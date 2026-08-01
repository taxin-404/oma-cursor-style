#!/bin/bash

# Validate the plugin folder. Uses the Omarchy validator when available, and
# falls back to the same core checks via jq so plugin authors without Omarchy
# can still gate their work.

set -euo pipefail

PLUGIN_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  exec omarchy-plugin-validate "$PLUGIN_DIR"
fi

fail() {
  echo "validate: $*" >&2
  exit 1
}

MANIFEST="$PLUGIN_DIR/manifest.json"
[[ -f $MANIFEST ]] || fail "missing manifest.json in $PLUGIN_DIR"
jq -e . "$MANIFEST" >/dev/null 2>&1 || fail "manifest.json is not valid JSON"

jq -e '.schemaVersion == 1' "$MANIFEST" >/dev/null 2>&1 || fail "unsupported or missing schemaVersion"

for field in id name version kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' "$MANIFEST" >/dev/null 2>&1 || fail "manifest missing required field '$field'"
done

ID=$(jq -r '.id // ""' "$MANIFEST")
[[ $ID =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid plugin id '$ID'"
[[ $ID != *".."* ]] || fail "invalid plugin id '$ID'"
[[ $ID != omarchy.* ]] || fail "plugin id '$ID' uses the reserved omarchy.* namespace"

jq -e '(.kinds | type) == "array" and (.kinds | length) > 0' "$MANIFEST" >/dev/null 2>&1 ||
  fail "'kinds' must be a non-empty array"
jq -e '(.entryPoints | type) == "object"' "$MANIFEST" >/dev/null 2>&1 ||
  fail "'entryPoints' must be an object"

jq -e '(.kinds | index("overlay")) != null' "$MANIFEST" >/dev/null 2>&1 &&
  jq -e '.entryPoints | has("overlay")' "$MANIFEST" >/dev/null 2>&1 ||
  fail "kind 'overlay' requires an 'entryPoints.overlay' to load"

EP=$(jq -r '.entryPoints.overlay // ""' "$MANIFEST")
[[ -n $EP && $EP != /* && $EP != *".."* ]] || fail "invalid entry point: '$EP'"
[[ -f "$PLUGIN_DIR/$EP" ]] || fail "entry point file not found: '$EP'"

link=$(find "$PLUGIN_DIR" -name .git -prune -o -type l -print -quit 2>/dev/null)
[[ -z $link ]] || fail "symlinks are not allowed inside a plugin folder: $link"

echo "validate: $PLUGIN_DIR looks valid"
