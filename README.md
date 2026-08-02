# oma-cursor-style

A self-contained [Omarchy](https://github.com/basecamp/omarchy) plugin that
picks the cursor **theme** and **size** from a single overlay picker.

Everything the picker needs is bundled in this plugin: the QML overlay, the
cursor discovery/apply scripts under `bin/`, and the tests under `test/`. There
is no dependency on Omarchy source — any Omarchy user can install it.

## Features

- Searchable overlay (themed like the menu) with `Theme` / `Size` modes (Tab to
  switch).
- Lists Hyprcursor and legacy X11 cursor themes from system and user icon dirs,
  and standard sizes — plus a **Custom size** entry that prompts for any value
  in pixels.
- Applies instantly via `hyprctl setcursor`, persists `hl.env` in
  `hyprland.lua`, and keeps GTK `settings.ini` / `gsettings` in sync.
- Falls back gracefully on systems without the Omarchy runtime (no
  notification/hook, no crash).

## Installation

```sh
omarchy plugin add https://github.com/taxin-404/oma-cursor-style.git
omarchy plugin enable taxin.cursor-style
```

Enabling the plugin self-installs a **Style › Cursor Style** row into
`~/.config/omarchy/extensions/omarchy-menu.jsonc`, so the picker is reachable
from the Omarchy menu with no manual config. The row lives in your user config
(not the shipped defaults), so it survives Omarchy upgrades. Disabling the
plugin leaves the row behind; delete it from that file to remove the entry.

## Usage

Summon the picker:

```sh
omarchy-shell shell toggle taxin.cursor-style
```

Bind a key in `~/.config/hypr/hyprland.lua`:

```lua
bind = $mainMod, C, exec, omarchy-shell shell toggle taxin.cursor-style
```

## Standalone scripts

The `bin/` scripts work without the plugin or the Omarchy CLI. They resolve
their sibling helpers by script location, so the repo can be cloned anywhere:

```sh
bin/omarchy-cursor-list              # installed themes
bin/omarchy-cursor-current           # current theme
bin/omarchy-cursor-set <name>        # apply + persist a theme
bin/omarchy-cursor-size-list         # standard sizes
bin/omarchy-cursor-size-current      # current size
bin/omarchy-cursor-size-set <px>     # apply + persist a size
bin/omarchy-cursor-size-custom       # prompt for any size and apply it
bin/omarchy-cursor-menu-install      # ensure the Style > Cursor Style menu row
bin/omarchy-cursor-open              # open the picker (needs the plugin)
```

## Layout

```
manifest.json       plugin manifest (id taxin.cursor-style, overlay)
CursorStyle.qml     overlay entry point
bin/                cursor scripts (self-contained)
test/               standalone test suite
```

## Development

Validate the plugin folder with the Omarchy validator (or inspect
`test/validate.sh`):

```sh
omarchy plugin validate .
./test/cursor-style-test.sh
```
