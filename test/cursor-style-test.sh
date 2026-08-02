#!/bin/bash

set -euo pipefail

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "cursor-style-test: FAIL: $1${2:+: $2}" >&2
  exit 1
}
pass() {
  echo "ok - $1"
}

# If the Omarchy validator is available, gate the whole suite on it.
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate "$PLUGIN_DIR" || fail "omarchy-plugin-validate"
  pass "plugin folder passes omarchy-plugin-validate"
else
  echo "note - omarchy-plugin-validate not found; skipping validator gate"
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/home/.config/hypr" "$tmp_dir/home/.config/gtk-3.0"

cat >"$tmp_dir/bin/hyprctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
echo ok
EOF
chmod +x "$tmp_dir/bin/hyprctl"

cat >"$tmp_dir/bin/gsettings" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$GSETTINGS_LOG"
if [[ ${1:-} == "get" ]]; then
  printf "'%s'\n" "${3:-}"
fi
EOF
chmod +x "$tmp_dir/bin/gsettings"

cat >"$tmp_dir/bin/omarchy-notification-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
EOF
chmod +x "$tmp_dir/bin/omarchy-notification-send"

cat >"$tmp_dir/bin/omarchy-hook" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HOOK_LOG"
EOF
chmod +x "$tmp_dir/bin/omarchy-hook"

cat >"$tmp_dir/bin/omarchy-menu-input" <<'EOF'
#!/bin/bash
if [[ -z ${MENU_INPUT_VALUE+x} ]]; then
  exit 1
fi
printf '%s' "$MENU_INPUT_VALUE"
EOF
chmod +x "$tmp_dir/bin/omarchy-menu-input"

export PATH="$tmp_dir/bin:$PLUGIN_DIR/bin:$PATH"
export HOME="$tmp_dir/home"
export DBUS_SESSION_BUS_ADDRESS="test"
export HYPRCTL_LOG="$tmp_dir/hyprctl"
export GSETTINGS_LOG="$tmp_dir/gsettings"
export NOTIFY_LOG="$tmp_dir/notify"
export HOOK_LOG="$tmp_dir/hook"
unset HYPRCURSOR_SIZE XCURSOR_SIZE

# A fake theme so omarchy-cursor-set can validate against the list.
mkdir -p "$tmp_dir/home/.local/share/icons/Fake-Dark/cursors"
export XDG_DATA_HOME="$tmp_dir/home/.local/share"

[[ $(omarchy-cursor-size-list | tr '\n' ' ') == "16 20 24 28 32 36 40 44 48 56 64 " ]] ||
  fail "cursor size list emits standard sizes" "$(omarchy-cursor-size-list | tr '\n' ' ')"
pass "cursor size list emits standard sizes"

omarchy-cursor-list | rg -qx 'Fake-Dark' ||
  fail "cursor list finds the fake theme in HOME icons"
pass "cursor list finds the fake theme in HOME icons"

cat >"$HOME/.config/hypr/hyprland.lua" <<'EOF'
-- test config
hl.env("XCURSOR_THEME", "Fake-Dark")
hl.env("HYPRCURSOR_THEME", "Fake-Dark")
hl.env("XCURSOR_SIZE", "64")
hl.env("HYPRCURSOR_SIZE", "64")
EOF

[[ $(omarchy-cursor-size-current) == "64" ]] ||
  fail "cursor size current reads the Hyprland config"
pass "cursor size current reads the Hyprland config"

[[ $(omarchy-cursor-current) == "Fake-Dark" ]] ||
  fail "cursor theme current reads the Hyprland config"
pass "cursor theme current reads the Hyprland config"

omarchy-cursor-size-set 32

[[ $(tail -n 1 "$HYPRCTL_LOG") == "setcursor Fake-Dark 32" ]] ||
  fail "cursor size applies the theme at the requested size" "$(tail -n 1 "$HYPRCTL_LOG")"
pass "cursor size applies the theme at the requested size"

rg -q 'XCURSOR_SIZE", "32"' "$HOME/.config/hypr/hyprland.lua" &&
  rg -q 'HYPRCURSOR_SIZE", "32"' "$HOME/.config/hypr/hyprland.lua" ||
  fail "cursor size persists both env variables"
pass "cursor size persists both env variables"

[[ $(<"$HOME/.config/gtk-3.0/settings.ini") == $'[Settings]\ngtk-cursor-theme-name=Fake-Dark\ngtk-cursor-theme-size=32' ]] ||
  fail "cursor size writes GTK settings" "$(<"$HOME/.config/gtk-3.0/settings.ini")"
pass "cursor size writes GTK settings"

tail -n 2 "$GSETTINGS_LOG" | rg -q 'cursor-size 32' ||
  fail "cursor size syncs gsettings"
pass "cursor size syncs gsettings"

tail -n 1 "$NOTIFY_LOG" | rg -q '32' ||
  fail "cursor size notifies"
pass "cursor size notifies"

tail -n 1 "$HOOK_LOG" | rg -q 'cursor-size-set 32' ||
  fail "cursor size runs the size hook"
pass "cursor size runs the size hook"

if omarchy-cursor-size-set 0; then
  fail "cursor size rejects zero"
fi
pass "cursor size rejects zero"

if omarchy-cursor-size-set abc; then
  fail "cursor size rejects non-numeric sizes"
fi
pass "cursor size rejects non-numeric sizes"

MENU_INPUT_VALUE=55 omarchy-cursor-size-custom

[[ $(tail -n 1 "$HYPRCTL_LOG") == "setcursor Fake-Dark 55" ]] ||
  fail "custom size applies the typed value" "$(tail -n 1 "$HYPRCTL_LOG")"
pass "custom size applies the typed value"

rg -q 'XCURSOR_SIZE", "55"' "$HOME/.config/hypr/hyprland.lua" &&
  rg -q 'HYPRCURSOR_SIZE", "55"' "$HOME/.config/hypr/hyprland.lua" ||
  fail "custom size persists both env variables"
pass "custom size persists both env variables"

tail -n 2 "$GSETTINGS_LOG" | rg -q 'cursor-size 55' ||
  fail "custom size syncs gsettings"
pass "custom size syncs gsettings"

tail -n 1 "$HOOK_LOG" | rg -q 'cursor-size-set 55' ||
  fail "custom size runs the size hook"
pass "custom size runs the size hook"

if MENU_INPUT_VALUE=abc omarchy-cursor-size-custom; then
  fail "custom size rejects non-numeric input"
fi
pass "custom size rejects non-numeric input"

tail -n 1 "$NOTIFY_LOG" | rg -q 'Invalid cursor size' &&
  tail -n 1 "$NOTIFY_LOG" | rg -q 'abc' ||
  fail "custom size notifies on invalid input"
pass "custom size notifies on invalid input"

[[ $(tail -n 1 "$HYPRCTL_LOG") == "setcursor Fake-Dark 55" ]] ||
  fail "custom size leaves state unchanged on invalid input" "$(tail -n 1 "$HYPRCTL_LOG")"
pass "custom size leaves state unchanged on invalid input"

if MENU_INPUT_VALUE=0 omarchy-cursor-size-custom; then
  fail "custom size rejects zero"
fi
pass "custom size rejects zero"

unset MENU_INPUT_VALUE
if omarchy-cursor-size-custom; then
  fail "custom size aborts when the prompt is cancelled"
fi
pass "custom size aborts when the prompt is cancelled"

rg -q 'current: \$current' "$PLUGIN_DIR/bin/omarchy-cursor-size-custom" ||
  fail "custom size prompt hints at the current size"
pass "custom size prompt hints at the current size"

omarchy-cursor-set Fake-Dark

[[ $(tail -n 1 "$HYPRCTL_LOG") == "setcursor Fake-Dark 55" ]] ||
  fail "cursor theme applies the theme" "$(tail -n 1 "$HYPRCTL_LOG")"
pass "cursor theme applies the theme"

tail -n 1 "$NOTIFY_LOG" | rg -q 'Fake-Dark' ||
  fail "cursor theme notifies"
pass "cursor theme notifies"

tail -n 1 "$HOOK_LOG" | rg -q 'cursor-set Fake-Dark' ||
  fail "cursor theme runs the theme hook"
pass "cursor theme runs the theme hook"

if omarchy-cursor-set Not-Installed 2>/dev/null; then
  fail "cursor theme rejects unknown themes"
fi
pass "cursor theme rejects unknown themes"

# Sibling resolution: the set scripts must work with the repo bin dir alone on
# PATH (no core omarchy binaries). The launcher is content-checked only; the
# live toggle is the install proof step, not part of this standalone suite.
rg -q 'toggle taxin.cursor-style' "$PLUGIN_DIR/bin/omarchy-cursor-open" ||
  fail "cursor open launcher targets the plugin id"
pass "cursor open launcher toggles the plugin"

# The overlay entry point lives at manifest.entryPoints.overlay and the QML
# resolves its scripts from manifest.__sourceDir/bin.
jq -r '.entryPoints.overlay' "$PLUGIN_DIR/manifest.json" | rg -qx 'CursorStyle.qml' ||
  fail "manifest points the overlay at CursorStyle.qml"
pass "manifest points the overlay at CursorStyle.qml"

rg -q '__sourceDir' "$PLUGIN_DIR/CursorStyle.qml" &&
  rg -q 'pluginBin' "$PLUGIN_DIR/CursorStyle.qml" ||
  fail "overlay resolves its bundled scripts from manifest.__sourceDir"
pass "overlay resolves its bundled scripts from manifest.__sourceDir"

for script in \
  omarchy-cursor-list omarchy-cursor-current omarchy-cursor-set \
  omarchy-cursor-size-list omarchy-cursor-size-current omarchy-cursor-size-set \
  omarchy-cursor-size-custom omarchy-cursor-menu-install omarchy-cursor-open; do
  [[ -x "$PLUGIN_DIR/bin/$script" ]] ||
    fail "bundled script is executable: $script"
done
pass "all bundled scripts are executable"

# The size list feeds the picker; the custom entry is prepended by the overlay
# itself, so the list keeps emitting standard sizes only.
rg -q "Custom size" "$PLUGIN_DIR/CursorStyle.qml" &&
  rg -q "omarchy-cursor-size-custom" "$PLUGIN_DIR/CursorStyle.qml" ||
  fail "overlay adds a custom size entry that routes to the custom script"
pass "overlay adds a custom size entry"

# The custom entry is flagged as the active size when the current size is not
# a preset, and the picker surfaces the active size in its header.
rg -q 'grep -qx' "$PLUGIN_DIR/CursorStyle.qml" ||
  fail "size list flags the custom row when the active size is not a preset"
pass "size list flags the custom row when the active size is not a preset"

rg -q 'parts\[3\]' "$PLUGIN_DIR/CursorStyle.qml" ||
  fail "size list parser honours the custom-active flag"
pass "size list parser honours the custom-active flag"

rg -q 'Current: ' "$PLUGIN_DIR/CursorStyle.qml" ||
  fail "picker shows the active size in the header"
pass "picker shows the active size in the header"

rg -q 'markCurrent' "$PLUGIN_DIR/CursorStyle.qml" ||
  fail "picker moves the active-size marker instantly on selection"
pass "picker moves the active-size marker instantly on selection"

# The overlay self-installs its menu row so the picker survives core upgrades.
rg -q 'omarchy-cursor-menu-install' "$PLUGIN_DIR/CursorStyle.qml" &&
  rg -q 'onPluginBinChanged' "$PLUGIN_DIR/CursorStyle.qml" ||
  fail "overlay self-installs the menu row on load"
pass "overlay self-installs the menu row on load"

# The menu row installer writes into the user menu extension file.
EXT="$tmp_dir/home/.config/omarchy/extensions/omarchy-menu.jsonc"
mkdir -p "$(dirname "$EXT")"
export OMARCHY_MENU_EXTENSION="$EXT"
ENTRY="$(dirname "$EXT")/omarchy-cursor-menu-entry"

cat >"$EXT" <<'EOF'
{
  // pre-existing rows
  "personal": {"icon":"","label":"Personal"}
}
EOF
"$PLUGIN_DIR/bin/omarchy-cursor-menu-install"
jq -r '.["style.cursor-style"].action' <(sed -E 's@^\s*//.*@@' "$EXT") | rg -qx '.*omarchy-cursor-menu-entry' ||
  fail "menu installer adds the Cursor Style row"
[[ -f $ENTRY ]] && [[ -x $ENTRY ]] ||
  fail "menu installer copies the entry script into the user config"
jq -r '.["personal"].label' <(sed -E 's@^\s*//.*@@' "$EXT") | rg -qx 'Personal' ||
  fail "menu installer preserves existing rows"
pass "menu installer adds the row and keeps existing content"

"$PLUGIN_DIR/bin/omarchy-cursor-menu-install"
[[ $(rg -c '"style.cursor-style"' "$EXT") == "1" ]] ||
  fail "menu installer is idempotent"
pass "menu installer is idempotent"

cat >"$EXT" <<'EOF'
{
  "style.cursor-style": {"icon":"󰇀","label":"My Cursor","action":"echo custom"}
}
EOF
"$PLUGIN_DIR/bin/omarchy-cursor-menu-install"
jq -r '.["style.cursor-style"].action' "$EXT" | rg -qx 'echo custom' ||
  fail "menu installer never clobbers a user-defined row"
pass "menu installer keeps a user-defined row"

rm -f "$EXT"
"$PLUGIN_DIR/bin/omarchy-cursor-menu-install"
[[ -f $EXT ]] &&
  jq -r '.["style.cursor-style"].action' <(sed -E 's@^\s*//.*@@' "$EXT") | rg -qx '.*omarchy-cursor-menu-entry' ||
  fail "menu installer creates the file when missing"
pass "menu installer creates the extension file when missing"

# The overlay removes its menu row when it is unloaded, so disabling or
# deleting the plugin leaves no dead entry. Cleanup runs through the entry
# script copied into the user config so it survives plugin removal.
rg -q 'onDestruction' "$PLUGIN_DIR/CursorStyle.qml" &&
  rg -q 'omarchy-cursor-menu-entry' "$PLUGIN_DIR/CursorStyle.qml" &&
  rg -q -- '--remove' "$PLUGIN_DIR/bin/omarchy-cursor-menu-entry" ||
  fail "overlay removes its menu row via the persistent entry script"
pass "overlay removes its menu row when unloaded"

# --remove takes back the plugin's own row while keeping other rows and comments.
cat >"$EXT" <<'EOF'
{
  // pre-existing rows
  "personal": {"icon":"","label":"Personal"},
  "style.cursor-style": {"icon":"󰇀","label":"Cursor Style","action":"/home/taxin/.config/omarchy/extensions/omarchy-cursor-menu-entry"}
}
EOF
"$PLUGIN_DIR/bin/omarchy-cursor-menu-install" --remove
rg -q '"style.cursor-style"' "$EXT" &&
  fail "menu installer --remove takes back the plugin row"
jq -r '.["personal"].label' <(sed -E 's@^\s*//.*@@' "$EXT") | rg -qx 'Personal' ||
  fail "menu installer --remove preserves other rows"
pass "menu installer --remove takes back the row and keeps other content"

"$PLUGIN_DIR/bin/omarchy-cursor-menu-install" --remove
[[ -f $EXT ]] || fail "menu installer --remove is a no-op when already gone"
pass "menu installer --remove is idempotent"

# A user-redefined row (no plugin action) is left alone.
cat >"$EXT" <<'EOF'
{
  "style.cursor-style": {"icon":"󰇀","label":"My Cursor","action":"echo custom"}
}
EOF
"$PLUGIN_DIR/bin/omarchy-cursor-menu-install" --remove
jq -r '.["style.cursor-style"].action' "$EXT" | rg -qx 'echo custom' ||
  fail "menu installer --remove leaves a user-defined row"
pass "menu installer --remove leaves a user-defined row"

# Removing a middle row keeps the file valid JSON.
cat >"$EXT" <<'EOF'
{
  "personal": {"icon":"","label":"Personal"},
  "style.cursor-style": {"icon":"󰇀","label":"Cursor Style","action":"/home/taxin/.config/omarchy/extensions/omarchy-cursor-menu-entry"},
  "style.foo": {"icon":"󰇀","label":"Foo","action":"echo foo"}
}
EOF
"$PLUGIN_DIR/bin/omarchy-cursor-menu-install" --remove
jq -e '.personal and .["style.foo"] and (has("style.cursor-style") | not)' "$EXT" ||
  fail "menu installer --remove handles a middle row"
pass "menu installer --remove handles a middle row"

rm -f "$EXT"
"$PLUGIN_DIR/bin/omarchy-cursor-menu-install" --remove
[[ ! -e $EXT ]] || fail "menu installer --remove does not create the file"
pass "menu installer --remove is a no-op when the file is missing"

echo "all tests passed"
