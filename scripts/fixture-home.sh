#!/usr/bin/env bash
# Creates a fake home with junk folders of known sizes, for manual tests (launch Mopster with `--fixture-home <dir>`).
# Usage: scripts/fixture-home.sh <dir>. Prints the total size in bytes of the junk it created (the fixture's own Trash excluded).
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 <dir>" >&2; exit 2; }
existed_nonempty=false
[[ -d "$1" && -n "$(ls -A "$1")" ]] && existed_nonempty=true
mkdir -p "$1"
HOME_DIR="$(cd "$1" && pwd -P)"
REAL_HOME="$(cd "$HOME" && pwd -P)"
if [[ "$HOME_DIR" == "/" || "$HOME_DIR" == "$REAL_HOME" || "$existed_nonempty" == true ]]; then
  echo "refusing: $HOME_DIR is the root, your home, or a non-empty directory; pass a new or empty directory" >&2
  exit 2
fi
total=0

# make_junk <relative path> <file count> <bytes per file>
make_junk() {
  local dir="$HOME_DIR/$1" count="$2" size="$3"
  mkdir -p "$dir"
  for i in $(seq 1 "$count"); do
    head -c "$size" /dev/zero > "$dir/file-$i.bin"
  done
  total=$((total + count * size))
}

make_file() {
  mkdir -p "$(dirname "$HOME_DIR/$1")"
  head -c "$2" /dev/zero > "$HOME_DIR/$1"
  total=$((total + $2))
}

make_junk "Library/Caches/mopster-fixture-alpha" 3 20480
make_junk "Library/Caches/mopster-fixture-beta" 2 40960
make_junk "Library/Caches/mopster-fixture-gamma" 1 81920
make_junk "Library/Caches/Homebrew/downloads/mopster-fixture-brew" 2 30720
make_junk "Library/Logs/mopster-fixture-logs" 4 10240
make_junk "Library/Logs/mopster-fixture-helper" 2 20480
make_junk "Library/Developer/Xcode/DerivedData/mopster-fixture-App-abcdef" 5 16384
make_junk "Library/Developer/Xcode/DerivedData/mopster-fixture-Lib-ghijkl" 3 16384
make_junk "Library/Saved Application State/mopster.fixture.app.savedState" 2 8192
make_file "Downloads/mopster-fixture-installer.dmg" 61440
make_file "Downloads/mopster-fixture-tool.pkg" 40960

trash_bytes=4096
make_junk ".Trash/mopster-fixture-already-trashed" 1 "$trash_bytes"
total=$((total - trash_bytes))

echo "$total"
