#!/bin/sh
# render-compose.sh: print compose.yaml with the settings from .env filled in, for tools that take
# a single YAML file and no .env file, such as TrueNAS SCALE custom apps (docs/truenas.md).
#
#   (umask 077; sh tools/render-compose.sh [ENV_FILE [COMPOSE_FILE]] > compose.rendered.yaml)
#
# ENV_FILE defaults to .env and COMPOSE_FILE to compose.yaml, both next to this tools/ folder.
# It fills in ${VAR}, ${VAR:-default}, ${VAR-default}, ${VAR:?message} and ${VAR?message} the
# way Docker Compose does, and leaves "$$" alone. Values are escaped for the double-quoted YAML
# strings they land in ("$" becomes "$$"). ENV_FILE holds plain KEY=value lines; quotes around a
# value are removed, a " #" starts a comment in an unquoted value, references to other variables
# are not expanded; put a value with a backslash in single quotes. Nothing is printed when a
# setting is missing or malformed. The output holds your secrets: delete it after use.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
env_file=${1:-$top/.env}
compose_file=${2:-$top/compose.yaml}
[ -f "$env_file" ] || { echo "render-compose: no such file: $env_file" >&2; exit 2; }
[ -f "$compose_file" ] || { echo "render-compose: no such file: $compose_file" >&2; exit 2; }

awk -v env_file="$env_file" -v sq="'" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function yaml(s) { gsub(/\\/, "&&", s); gsub(/"/, "\\\"", s); gsub(/\$/, "$$", s); return s }
BEGIN {
  n = 0
  while ((getline line < env_file) > 0) {
    n++
    sub(/\r$/, "", line)
    if (line ~ /^[ \t]*(#|$)/) continue
    sub(/^[ \t]*export[ \t]+/, "", line)
    i = index(line, "=")
    if (i == 0) continue
    k = trim(substr(line, 1, i - 1))
    v = trim(substr(line, i + 1))
    q = substr(v, 1, 1)
    if (q == "\"" || q == sq) {
      if ((j = index(substr(v, 2), q)) == 0) { print "render-compose: " env_file " line " n ": " k ": the closing quote is missing" > "/dev/stderr"; err = 1; exit 1 }
      v = substr(v, 2, j - 1)
      if (q == "\"" && index(v, "\\") > 0) { print "render-compose: " env_file " line " n ": " k ": use single quotes for a value with a backslash" > "/dev/stderr"; err = 1; exit 1 }
    } else {
      if ((j = index(v, " #")) > 0) v = substr(v, 1, j - 1)
      v = trim(v)
    }
    val[k] = v
    has[k] = 1
  }
  close(env_file)
}
{
  s = $0
  out = ""
  while ((p = index(s, "$")) > 0) {
    out = out substr(s, 1, p - 1)
    s = substr(s, p)
    if (substr(s, 1, 2) == "$$") { out = out "$$"; s = substr(s, 3); continue }
    if (substr(s, 1, 2) != "${") { out = out "$"; s = substr(s, 2); continue }
    e = index(s, "}")
    if (e == 0) { print "render-compose: line " NR ": unclosed ${" > "/dev/stderr"; err = 1; exit 1 }
    expr = substr(s, 3, e - 3)
    s = substr(s, e + 1)
    if (!match(expr, /^[A-Za-z_][A-Za-z0-9_]*/)) { print "render-compose: line " NR ": bad variable ${" expr "}" > "/dev/stderr"; err = 1; exit 1 }
    name = substr(expr, 1, RLENGTH)
    op = substr(expr, RLENGTH + 1)
    set = (name in has)
    full = set && val[name] != ""
    if (op == "") {
      r = set ? val[name] : ""
      if (!set) print "render-compose: warning: " name " is not set, using an empty value" > "/dev/stderr"
    } else if (substr(op, 1, 2) == ":-") {
      r = full ? val[name] : substr(op, 3)
    } else if (substr(op, 1, 1) == "-") {
      r = set ? val[name] : substr(op, 2)
    } else if (substr(op, 1, 2) == ":?") {
      if (!full) { print "render-compose: " name ": " substr(op, 3) > "/dev/stderr"; err = 1; exit 1 }
      r = val[name]
    } else if (substr(op, 1, 1) == "?") {
      if (!set) { print "render-compose: " name ": " substr(op, 2) > "/dev/stderr"; err = 1; exit 1 }
      r = val[name]
    } else {
      print "render-compose: line " NR ": unsupported ${" expr "}" > "/dev/stderr"; err = 1; exit 1
    }
    out = out yaml(r)
  }
  lines[++count] = out s
}
END {
  if (err) exit 1
  for (i = 1; i <= count; i++) print lines[i]
}' "$compose_file"
