#!/bin/sh
# build-compose.sh: write compose.yaml from src/: the template with the three scripts embedded
# ("$" becomes "$$" for Compose, indented for the YAML block).
#
#   sh tools/build-compose.sh           write compose.yaml
#   sh tools/build-compose.sh --check   exit 1 if compose.yaml is not up to date
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
src=$top/src
tmp=$(mktemp "$top/.compose.XXXXXX")
trap 'rm -f "$tmp" "$tmp.update"' EXIT
awk -v f="$src/craft-update.sh" '/^@@SCRIPT@@$/ { while ((getline l < f) > 0) print l; next } { print }' \
  "$src/update-loop.sh" > "$tmp.update"
awk -v w="$src/web-start.sh" -v u="$tmp.update" '
  function emit(f,   l) { while ((getline l < f) > 0) { gsub(/\$/, "$$", l); if (l == "") print ""; else print "        " l } close(f) }
  /^@@WEB@@$/ { emit(w); next }
  /^@@UPDATE@@$/ { emit(u); next }
  { print }' "$src/compose.template.yaml" > "$tmp"
if [ "${1:-}" = --check ]; then
  cmp -s "$tmp" "$top/compose.yaml" || { echo "compose.yaml is not up to date: run sh tools/build-compose.sh" >&2; exit 1; }
  exit 0
fi
cat "$tmp" > "$top/compose.yaml"
