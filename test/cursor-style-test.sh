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

omarchy-cursor-set Fake-Dark

[[ $(tail -n 1 "$HYPRCTL_LOG") == "setcursor Fake-Dark 32" ]] ||
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
  omarchy-cursor-open; do
  [[ -x "$PLUGIN_DIR/bin/$script" ]] ||
    fail "bundled script is executable: $script"
done
pass "all bundled scripts are executable"

echo "all tests passed"
