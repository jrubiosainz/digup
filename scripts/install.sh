#!/bin/bash
# Installs build.noindex/Biblo.app as /Applications/Biblo.app (DEST=…/Name.app for another place) and opens it, so the
# Dock, Spotlight and Launch Services know the copy in use. Run it after each ./build.sh. The Biblo that's running quits
# first, whichever folder it runs from (only one copy runs at a time), and so does its indexer, which would otherwise
# finish the batch in hand (minutes, for a long video) next to the new copy's; dev and test runs (`-defaultsSuite`)
# keep going.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="build.noindex/Biblo.app"
DEST="${DEST:-/Applications/Biblo.app}"
[[ -d "$SRC" ]] || { echo "No $SRC: run ./build.sh first." >&2; exit 1; }
[[ "$DEST" == *.app ]] || { echo "DEST must end in .app: $DEST" >&2; exit 1; }

stopped=()
for pid in $(pgrep -x Biblo || true); do
  [[ "$(ps -o args= -p "$pid")" == *" -defaultsSuite "* ]] && continue
  helpers=($(pgrep -P "$pid" -x digup || true))   # before the app goes: then they're nobody's children
  kill "$pid" && stopped+=("$pid")
  for helper in ${helpers[@]+"${helpers[@]}"}; do
    kill "$helper" 2>/dev/null && stopped+=("$helper") || true
  done
done
for pid in ${stopped[@]+"${stopped[@]}"}; do
  for _ in {1..50}; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
done

rm -rf "$DEST"
ditto "$SRC" "$DEST"
open "$DEST"
echo "Installed $DEST"
