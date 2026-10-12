#!/bin/sh
# craft-update: keeps the Craft web apps (storytold) up to date from their GitHub releases.
# Per app and release: verify, unpack, add the nextcloud-craftsuite-layer translator, compress,
# switch in one step (the previous version stays for a rollback). Writes the start page.
#   craft-update                  check all apps and update where a release is due
#   craft-update --status         installed, previous and blocked versions, translator state
#   craft-update --rollback APP   back to the previous version; the current one is blocked
set -u
umask 022

APPS=${CRAFT_APPS:-"pdfcraft photocraft vectorcraft designcraft wordcraft gridcraft deckcraft cadcraft lightcraft filmcraft effectcraft"}
BASE=${CRAFT_BASE:-/craft}
LANGUAGE=${CRAFT_LANGUAGE:-en}
LAYER_VERSION=${CRAFTSUITE_LAYER_VERSION:-}
LAYER_SHA256=${CRAFTSUITE_LAYER_SHA256:-}
LAYER_REPO=${CRAFTSUITE_LAYER_REPO:-hozwei/nextcloud-craftsuite-layer}
CANARY=${CRAFTSUITE_CANARY:-on}
STARTUP_TIMEOUTS=${CRAFTSUITE_STARTUP_TIMEOUTS-"lightcraft=180000 effectcraft=180000"}
API=https://api.github.com/repos
RAW=https://raw.githubusercontent.com/storytold
WWW=$BASE/www
REL=$WWW/releases
STATE=$BASE/state
LAYERS=$BASE/layer
# The layer's canary is its workflow canary.yml (daily, or started by hand), which tests the
# newest release of each app. When its newest run that tested something started longer ago than
# this (seconds), the canary has stopped, and new releases would wait for it without a word.
CANARY_STALE=259200
INJ=
HOLD=
RUNS='[]'
ISSUES='[]'
OPEN=
FAILED=
STALE=

log() { echo "$(date '+%F %T') $*"; }

hours=${CRAFT_MIN_AGE_HOURS:-24}
case $hours in
  '' | *[!0-9]*) log "ERROR - CRAFT_MIN_AGE_HOURS must be a whole number of hours"; exit 2 ;;
esac
hours=$(printf '%s' "$hours" | sed 's/^0*//')
MIN_AGE=$(( ${hours:-0} * 3600 ))
case $LANGUAGE in
  de | en) ;;
  *) LANGUAGE=en ;;
esac
case ${CRAFT_UPDATE_TIME:-} in
  [0-9]:[0-5][0-9] | [01][0-9]:[0-5][0-9] | 2[0-3]:[0-5][0-9]) ;;
  *) CRAFT_UPDATE_TIME=07:00 ;;
esac

# Removes a folder even if it holds read-only parts.
drop() { [ -e "$1" ] || return 0; chmod -R u+rwX "$1" 2>/dev/null; rm -rf "$1"; }

esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

app_info() {
  name=$1 short=$(printf '%.2s' "$1") text=""
  case $1 in
    pdfcraft) name=PdfCraft short=Pd ;;
    photocraft) name=PhotoCraft short=Ph ;;
    vectorcraft) name=VectorCraft short=Vc ;;
    designcraft) name=DesignCraft short=Dc ;;
    wordcraft) name=WordCraft short=Wd ;;
    gridcraft) name=GridCraft short=Gr ;;
    deckcraft) name=DeckCraft short=Dk ;;
    cadcraft) name=CADCraft short=Cd ;;
    lightcraft) name=LightCraft short=Lt ;;
    filmcraft) name=FilmCraft short=Fm ;;
    effectcraft) name=EffectCraft short=Fx ;;
  esac
  case $LANGUAGE:$1 in
    de:pdfcraft) text="PDFs ansehen, kommentieren und bearbeiten" ;;
    de:photocraft) text="Fotos und Ebenen bearbeiten, auch PSD" ;;
    de:vectorcraft) text="Vektorgrafiken und Logos zeichnen, auch SVG" ;;
    de:designcraft) text="Layouts und Drucksachen setzen" ;;
    de:wordcraft) text="Texte schreiben und gestalten, auch DOCX" ;;
    de:gridcraft) text="Tabellen berechnen und auswerten, auch XLSX" ;;
    de:deckcraft) text="Präsentationen gestalten, auch aus PPTX" ;;
    de:cadcraft) text="2D-Zeichnungen konstruieren, im DXF-Format" ;;
    de:lightcraft) text="Fotos und Kamera-RAWs entwickeln und exportieren" ;;
    de:filmcraft) text="Videos und Filmprojekte schneiden" ;;
    de:effectcraft) text="Animationen und visuelle Effekte gestalten" ;;
    en:pdfcraft) text="View, annotate and edit PDFs" ;;
    en:photocraft) text="Edit photos and layers, PSD included" ;;
    en:vectorcraft) text="Draw vector graphics and logos, SVG included" ;;
    en:designcraft) text="Lay out pages and print matter" ;;
    en:wordcraft) text="Write and format documents, DOCX included" ;;
    en:gridcraft) text="Calculate and analyse spreadsheets, XLSX included" ;;
    en:deckcraft) text="Build presentations, also from PPTX" ;;
    en:cadcraft) text="Draft 2D drawings in DXF" ;;
    en:lightcraft) text="Develop and export photos and camera raws" ;;
    en:filmcraft) text="Edit videos and film projects" ;;
    en:effectcraft) text="Create animations and visual effects" ;;
  esac
}

version_of() {
  z=$(readlink "$WWW/$1" 2>/dev/null) || return 0
  case $z in
    "releases/$1-"?*) echo "${z#releases/"$1"-}" ;;
  esac
}

switch_to() {
  rm -f "$WWW/.$1.new"
  ln -s "releases/$1-$2" "$WWW/.$1.new" && mv -T "$WWW/.$1.new" "$WWW/$1"
}

# App icon (256 px, MIT/Apache-2.0) from the app's repository at the version's tag. Cosmetic
# only: without it the start page shows a tile with two letters.
fetch_icon() {
  [ -s "$3/app-icon.png" ] && return 0
  if curl -fsSL --retry 2 --connect-timeout 20 --max-time 60 --max-filesize 1048576 -o "$3/.app-icon.new" \
       "$RAW/$1/v$2/assets/app-icon/hicolor/256x256/apps/ai.storyteller.$1.png" 2>/dev/null &&
     [ "$(head -c 8 "$3/.app-icon.new" | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a ] &&
     mv -f "$3/.app-icon.new" "$3/app-icon.png"; then
    return 0
  fi
  rm -f "$3/.app-icon.new"
  return 1
}

# The hosting bundle of nextcloud-craftsuite-layer, pinned by version and SHA-256. Downloaded
# once into layer/craftsuite-layer-hosting-<version>/; sets INJ to its inject-translator.sh.
# Without CRAFTSUITE_LAYER_VERSION the apps are served without the Nextcloud integration.
layer_ready() {
  INJ=
  [ -n "$LAYER_VERSION" ] || return 0
  case $LAYER_VERSION in
    *[!0-9A-Za-z.+-]* | [!0-9]*) log "layer: ERROR - invalid CRAFTSUITE_LAYER_VERSION '$LAYER_VERSION'"; return 1 ;;
  esac
  if [ "${#LAYER_SHA256}" -ne 64 ] || [ -n "$(printf '%s' "$LAYER_SHA256" | tr -d '0-9a-f')" ]; then
    log "layer: ERROR - CRAFTSUITE_LAYER_SHA256 must be the 64 lowercase hex digits of the bundle"
    return 1
  fi
  case $LAYER_REPO in
    */*/* | *[!A-Za-z0-9._/-]*) log "layer: ERROR - invalid CRAFTSUITE_LAYER_REPO '$LAYER_REPO'"; return 1 ;;
    ?*/?*) ;;
    *) log "layer: ERROR - invalid CRAFTSUITE_LAYER_REPO '$LAYER_REPO'"; return 1 ;;
  esac
  if [ -z "${CRAFTSUITE_ALLOWED_ORIGINS:-}" ]; then
    log "layer: ERROR - CRAFTSUITE_ALLOWED_ORIGINS is empty: name the Nextcloud origins that may frame the apps"
    return 1
  fi
  # shellcheck disable=SC2086 # one entry per line; the injector takes 1 to 2147483647 ms
  if printf '%s\n' $STARTUP_TIMEOUTS | awk -F= 'NF && !(NF == 2 && $1 ~ /^[a-z0-9_-]+$/ &&
       $2 ~ /^[1-9][0-9]*$/ && length($2) <= 10 && $2 + 0 <= 2147483647) { bad = 1 } END { exit !bad }'; then
    log "layer: ERROR - CRAFTSUITE_STARTUP_TIMEOUTS takes entries such as lightcraft=180000 (milliseconds, at most 2147483647), separated by spaces"
    return 1
  fi
  bundle=craftsuite-layer-hosting-$LAYER_VERSION
  dir=$LAYERS/$bundle
  if [ ! -f "$dir/hosting/inject-translator.sh" ] ||
     [ "$(cat "$LAYERS/.$bundle.verified" 2>/dev/null)" != "$LAYER_REPO $LAYER_SHA256" ]; then
    url=https://github.com/$LAYER_REPO/releases/download/v$LAYER_VERSION
    mkdir -p "$LAYERS"
    t=$(mktemp -d "$LAYERS/.tmp.XXXXXX") || { log "layer: ERROR - no working folder"; return 1; }
    if ! curl -fsSL --retry 3 --connect-timeout 20 --max-time 300 -o "$t/$bundle.tar.gz" "$url/$bundle.tar.gz" ||
       ! curl -fsSL --retry 3 --connect-timeout 20 --max-time 60 -o "$t/SHA256SUMS" "$url/SHA256SUMS"; then
      rm -rf "$t"
      log "layer: ERROR - download of $bundle failed"
      return 1
    fi
    is=$(sha256sum "$t/$bundle.tar.gz" | cut -d' ' -f1)
    listed=$(awk -v n="$bundle.tar.gz" '$2 == n || $2 == "*" n { print $1 }' "$t/SHA256SUMS" | sort -u)
    if [ "$is" != "$LAYER_SHA256" ] || [ "$is" != "$listed" ]; then
      rm -rf "$t"
      log "layer: ERROR - checksum of $bundle.tar.gz does not match CRAFTSUITE_LAYER_SHA256 and SHA256SUMS"
      return 1
    fi
    mkdir "$t/x"
    if ! tar -tzf "$t/$bundle.tar.gz" > "$t/names" ||
       ! awk -v p="$bundle/" 'index($0, p) != 1 || /(^|\/)\.\.(\/|$)/ { bad = 1 } END { exit bad }' "$t/names" ||
       ! tar -xzf "$t/$bundle.tar.gz" -C "$t/x" ||
       [ "$(ls -A "$t/x")" != "$bundle" ] ||
       [ -n "$(find "$t/x" ! -type f ! -type d | head -n 1)" ] ||
       [ ! -f "$t/x/$bundle/hosting/inject-translator.sh" ]; then
      rm -rf "$t"
      log "layer: ERROR - unexpected content in $bundle.tar.gz"
      return 1
    fi
    chmod -R u+rwX,a+rX,go-w "$t/x/$bundle"
    rm -rf "$dir" "$LAYERS/.$bundle.verified"
    if [ -e "$dir" ] || ! mv -T "$t/x/$bundle" "$dir" ||
       ! echo "$LAYER_REPO $LAYER_SHA256" > "$LAYERS/.$bundle.verified"; then
      rm -rf "$t"
      log "layer: ERROR - could not store $bundle"
      return 1
    fi
    rm -rf "$t"
    for d in "$LAYERS"/craftsuite-layer-hosting-*; do
      [ "$d" = "$dir" ] || rm -rf "$d" "$LAYERS/.${d##*/}.verified"
    done
    log "layer: $LAYER_VERSION downloaded and verified"
  fi
  INJ=$dir/hosting/inject-translator.sh
}

# The startup timeout of app $1 from CRAFTSUITE_STARTUP_TIMEOUTS ("lightcraft=180000 ..."), as
# an option for inject-translator.sh in TIMEOUT (empty: the translator's default). The injector
# writes it into its block, so every run passes it, --check included. The injector of layers
# before 0.2.0 has no such option and gets none.
timeout_of() {
  TIMEOUT=
  grep -q -e '--startup-timeout' "$INJ" 2>/dev/null || return 0
  for t in $STARTUP_TIMEOUTS; do
    case $t in "$1="*) TIMEOUT=--startup-timeout=${t#*=} ;; esac
  done
}

# Adds the translator to the web build in $3 (app $1, version $2), with the origins from
# CRAFTSUITE_ALLOWED_ORIGINS. Returns 1 if the build must not be switched to.
add_translator() {
  [ -n "$INJ" ] || return 0
  timeout_of "$1"
  # shellcheck disable=SC2086 # TIMEOUT is empty or one word
  sh "$INJ" -c -q --app "$1" --app-version "$2" $TIMEOUT "$3" >/dev/null 2>&1 && return 0
  # shellcheck disable=SC2086
  sh "$INJ" -q --app "$1" --app-version "$2" $TIMEOUT "$3"
  rc=$?
  case $rc in
    0)
      find "$3/craftsuite-layer" -type f -name '*.js' -exec gzip -9 -k -f {} \;
      log "$1: Nextcloud integration added to $2"
      ;;
    6)
      sh "$INJ" -q --remove --app "$1" "$3" >/dev/null 2>&1
      log "$1: layer $LAYER_VERSION has no adapter for $1, $2 is served without the Nextcloud integration"
      ;;
    *) log "$1: ERROR - translator not added to $2 (inject-translator.sh exit code $rc)"; return 1 ;;
  esac
  return 0
}

# jq definitions for the canary runs in RUNS and the issues in $issues. A run passed if no canary
# issue was open at its check time (at): the run opens or closes its issue in its last job, just
# before it ends. A re-run passed only if no canary issue was open at any time from its creation
# to then: its first attempt may have failed, and a re-run of failed jobs keeps the canary job's
# earlier result.
# shellcheck disable=SC2016 # jq variables, not the shell's
CANARY_JQ='def open_during($from; $to): any($issues[]; (.created_at | fromdateiso8601) <= $to
    and (.closed_at == null or (.closed_at | fromdateiso8601) > $from));
  def passed($r): open_during(if $r.rerun then $r.start else $r.at end; $r.at) | not;'

# Reads the layer's canary: its runs into RUNS and its issues into ISSUES, for the release choice,
# and sets OPEN (an open canary issue), FAILED (the newest canary failure since the current layer
# version came into use) and STALE (when the newest run is older than CANARY_STALE). A run of
# canary.yml on main fetches the newest release of each app and tests the translators of the
# layer's main branch against it; a failing run opens an issue labelled canary (or comments on the
# open one), the next passing run closes it. Only runs that ended with success or failure count: a
# cancelled one (a timeout, for example) tested nothing. RUNS holds them oldest first, in seconds:
# start (the run's creation: every attempt and every job of a re-run started after it), end, the
# check time at (a minute after the end, but not after the next run's start), and whether it is a
# re-run. Whether a run passed is told by the issues, since a run also fails when only the
# layer's look at the next Nextcloud release does.
# state/canary-since keeps one line "<layer version> <time>" per version that came into use;
# removing the file confirms that earlier failures do not concern the layer. A failure is a
# canary issue opened after that time, or one the first run after it did not pass (a failing run
# comments on the open issue instead of opening a new one). The canary tests the layer's main
# branch, so after a failure a later passing run does not show that the pinned layer handles the
# new releases: they wait until another layer version is in use or the failure is confirmed, and
# a failure once found counts until then (state/canary-failed: the issue, then the version and
# time it belongs to). Returns 1 if the runs or the issues could not be read (CANARY_PART says
# which).
canary_check() {
  since=$(awk -v v="$LAYER_VERSION" '$1 == v && $2 ~ /^[0-9]+$/ { s = $2 } END { print s }' "$STATE/canary-since" 2>/dev/null)
  if [ -z "$since" ]; then
    since=$(date +%s)
    echo "$LAYER_VERSION $since" >> "$STATE/canary-since"
    rm -f "$STATE/canary-failed"
    log "layer: canary failures count from now on (layer $LAYER_VERSION)"
  fi
  CANARY_PART=runs
  json=$(curl -fsS --retry 3 --connect-timeout 20 --max-time 60 -A craft-update \
    -H 'Accept: application/vnd.github+json' \
    "$API/$LAYER_REPO/actions/workflows/canary.yml/runs?branch=main&status=completed&exclude_pull_requests=true&per_page=100") || return 1
  RUNS=$(printf '%s' "$json" | jq -c 'if (.workflow_runs | type) == "array" then
      [ .workflow_runs[] | select(.head_branch == "main" and .status == "completed"
          and (.conclusion == "success" or .conclusion == "failure")
          and (.created_at | type) == "string" and (.updated_at | type) == "string")
        | {start: (.created_at | fromdateiso8601), end: (.updated_at | fromdateiso8601), conclusion,
           rerun: ((.run_attempt // 1) > 1)} ]
      | sort_by(.start)
      | . as $r | [ range(length) as $i | $r[$i]
          + {at: ([ $r[$i].end, ([ $r[$i].end + 60, ($r[$i + 1].start // ($r[$i].end + 60)) ] | min) ] | max)} ]
    else error("not a list") end') && [ -n "$RUNS" ] || {
    RUNS='[]'
    return 1
  }
  CANARY_PART=issues
  json=$(curl -fsS --retry 3 --connect-timeout 20 --max-time 60 -A craft-update \
    -H 'Accept: application/vnd.github+json' "$API/$LAYER_REPO/issues?labels=canary&state=all&per_page=100") || return 1
  ISSUES=$(printf '%s' "$json" | jq -c 'if type == "array" then [ .[] | select(.pull_request == null) | {state, html_url, created_at, closed_at} ] else error("not a list") end') &&
    [ -n "$ISSUES" ] || {
    ISSUES='[]'
    return 1
  }
  OPEN=$(printf '%s' "$ISSUES" | jq -r '[ .[] | select(.state == "open") | .html_url ] | first // empty')
  FAILED=$(jq -nr --argjson since "$since" --argjson runs "$RUNS" --argjson issues "$ISSUES" "$CANARY_JQ"'
    ([ $runs[] | select(.start > $since) ] | first) as $r
    | [ $issues[] | select((.created_at | fromdateiso8601) > $since
        or ($r != null and (.created_at | fromdateiso8601) <= $r.at
            and (.closed_at == null or (.closed_at | fromdateiso8601) > (if $r.rerun then $r.start else $r.at end)))) ]
    | sort_by(.created_at) | last | .html_url // empty')
  if [ -z "$FAILED" ] && [ "$(sed -n 2p "$STATE/canary-failed" 2>/dev/null)" = "$LAYER_VERSION $since" ]; then
    FAILED=$(head -n 1 "$STATE/canary-failed")
  fi
  newest=$(jq -nr --argjson runs "$RUNS" --argjson issues "$ISSUES" "$CANARY_JQ"'
    $runs | last // empty | "\(.start) \(.conclusion)" + (if .rerun then ", re-run" else "" end)
      + (if passed(.) | not then ", canary issue open" elif .conclusion == "failure" then ", no canary issue" else "" end)')
  if [ -z "$newest" ]; then
    STALE=none
    return 0
  fi
  if [ $(( $(date +%s) - ${newest%% *} )) -gt "$CANARY_STALE" ]; then
    STALE=$(date -d "@${newest%% *}" '+%F %T')
  else
    log "layer: newest canary run started $(date -d "@${newest%% *}" '+%F %T') (${newest#* })"
  fi
}

# shellcheck disable=SC1111 # typographic quotes in the texts of the start page
start_page() {
  if [ "$LANGUAGE" = de ]; then
    when=$(date -r "$STATE/status" '+%d.%m.%Y um %H:%M' 2>/dev/null) || when="?"
    tagline="Büro, Grafik, Foto, Video und PDF – direkt im Browser"
    open="Öffnen"
    err="Die letzte Update-Prüfung hatte Fehler. Die Apps laufen in ihrer bisherigen Version weiter, Einzelheiten stehen im Log von craft-update."
    none="Noch ist keine App installiert; warum, steht im Log von craft-update."
    held="Neue App-Versionen werden zurückgehalten, weil der Canary-Test von nextcloud-craftsuite-layer fehlgeschlagen ist:"
    tips="So landet die Datei wieder in Nextcloud"
    intro="Speichern ist immer ein Download. Im Speichern-Dialog die Originaldatei im synchronisierten Ordner wählen und ersetzen; in Nextcloud bleibt die vorige Fassung unter „Versionen“."
    nc="Direkt aus Nextcloud: im Menü einer Datei „In … öffnen“ wählen. Speichern legt die Datei dann ohne Download in Nextcloud ab."
    firefox="Einstellungen → Allgemein → Dateien und Anwendungen → „Jedes Mal nachfragen, wo eine Datei gespeichert werden soll“. Unter „Anwendungen“ PDF, SVG, WebP und AVIF auf „Datei speichern“ stellen."
    chrome="Einstellungen → Downloads → „Vor dem Download nach dem Speicherort der einzelnen Dateien fragen“. Schlägt Chrome „Name (1).ext“ vor, das Original anklicken."
    edge="„Fragen, was mit jedem Download geschehen soll“, dann „Speichern unter“."
    ipad="Der Download landet in „Downloads“. Danach in der Dateien-App in den gewünschten Ordner verschieben."
    warn="Kein automatisches Speichern – vor dem Schließen des Tabs speichern."
    footer="Updates täglich um $(esc "${CRAFT_UPDATE_TIME:-07:00}") Uhr · zuletzt geprüft am $when Uhr"
  else
    when=$(date -r "$STATE/status" '+%Y-%m-%d %H:%M' 2>/dev/null) || when="?"
    tagline="Office, graphics, photo, video and PDF – right in the browser"
    open="Open"
    err="The last update check had errors. The apps keep running in their current version; the log of craft-update has the details."
    none="No app is installed yet; the log of craft-update says why."
    held="New app versions are held back because the canary test of nextcloud-craftsuite-layer failed:"
    tips="Getting the file back into your folder"
    intro="Saving is always a download. In the save dialog, choose the original file in your synced folder and replace it; a synced cloud folder usually keeps the previous version."
    nc="Straight from Nextcloud: choose “Open in …” in a file's menu. Saving then stores the file in Nextcloud, without a download."
    firefox="Settings → General → Files and Applications → “Always ask you where to save files”. Under “Applications”, set PDF, SVG, WebP and AVIF to “Save File”."
    chrome="Settings → Downloads → “Ask where to save each file before downloading”. If Chrome suggests “name (1).ext”, click the original."
    edge="“Ask me what to do with each download”, then “Save as”."
    ipad="The download goes to “Downloads”. Move it to the folder you want in the Files app."
    warn="No autosave – save before you close the tab."
    footer="Updates daily at $(esc "${CRAFT_UPDATE_TIME:-07:00}") · last checked $when"
  fi
  link=
  if [ -n "${CRAFT_LINK_URL:-}" ]; then
    case $CRAFT_LINK_URL in
      https://* | http://*) link="<a class=\"nc\" href=\"$(esc "$CRAFT_LINK_URL")\">$(esc "${CRAFT_LINK_LABEL:-Nextcloud}") ↗</a>" ;;
    esac
  fi
  {
    printf '<!DOCTYPE html>\n<html lang="%s">\n' "$LANGUAGE"
    cat <<'HTML'
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>Craft</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='14' height='14' rx='4' fill='%2312a58a'/%3E%3Crect x='18' width='14' height='14' rx='4' fill='%232f7bf5'/%3E%3Crect y='18' width='14' height='14' rx='4' fill='%23e8573f'/%3E%3Crect x='18' y='18' width='14' height='14' rx='4' fill='%237bb51c'/%3E%3C/svg%3E">
<style>
:root{--bg:#f2f3f6;--fg:#15171c;--mut:#5d636e;--card:#fff;--line:rgba(20,24,32,.09);--sh:0 1px 2px rgba(16,24,40,.06),0 12px 32px -14px rgba(16,24,40,.22);--art:#fff;--mix:20%;--glow:.16;--c:#8a8f98}
@media (prefers-color-scheme:dark){:root{--bg:#0d0f13;--fg:#eceef2;--mut:#9ea5b0;--card:#171a20;--line:rgba(255,255,255,.08);--sh:0 1px 2px rgba(0,0,0,.5),0 16px 40px -16px rgba(0,0,0,.8);--art:#0d0f13;--mix:26%;--glow:.22}}
*{box-sizing:border-box}
html{background:var(--bg)}
body{margin:0;min-height:100vh;color:var(--fg);font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,Ubuntu,Cantarell,"Noto Sans",sans-serif;-webkit-font-smoothing:antialiased;background:radial-gradient(48rem 30rem at 8% -8%,rgb(47 123 245/var(--glow)),transparent 70%),radial-gradient(44rem 28rem at 96% 0,rgb(232 87 63/var(--glow)),transparent 70%),radial-gradient(60rem 30rem at 50% 112%,rgb(18 165 138/var(--glow)),transparent 70%) fixed}
.wrap{max-width:1180px;margin:0 auto;padding:clamp(28px,6vw,72px) 16px 36px}
header{display:flex;align-items:center;justify-content:space-between;gap:16px 20px;flex-wrap:wrap;margin-bottom:clamp(24px,4vw,44px)}
.brand{display:flex;align-items:center;gap:16px;min-width:0}
.mark{width:48px;height:48px;flex:none}
h1{margin:0;font-size:clamp(2.1rem,4.8vw,3rem);line-height:1;font-weight:800;letter-spacing:-.035em}
header p{margin:6px 0 0;color:var(--mut);font-size:clamp(1rem,2vw,1.15rem)}
.nc{padding:9px 16px;border:1px solid var(--line);border-radius:99px;background:var(--card);box-shadow:var(--sh);color:inherit;font-weight:600;font-size:.9375rem;text-decoration:none;white-space:nowrap}
.nc:hover{border-color:color-mix(in srgb,#2f7bf5 45%,var(--line))}
.apps{list-style:none;margin:0;padding:0;display:grid;gap:18px}
.pdfcraft{--c:#12a58a}.photocraft{--c:#2f7bf5}.vectorcraft{--c:#e8573f}.designcraft{--c:#7bb51c}
.wordcraft{--c:#3d5bd9}.gridcraft{--c:#1e9e57}.deckcraft{--c:#f0761e}.cadcraft{--c:#1a9fd5}
.lightcraft{--c:#eca312}.filmcraft{--c:#8b5cf6}.effectcraft{--c:#e0409a}
.app{display:flex;align-items:center;gap:16px;height:100%;padding:12px;border:1px solid var(--line);border-radius:22px;background:var(--card);box-shadow:var(--sh);color:inherit;text-decoration:none;-webkit-tap-highlight-color:transparent;transition:transform .2s ease,box-shadow .2s ease,border-color .2s ease}
.art{flex:none;display:grid;place-items:center;width:96px;height:96px;border-radius:16px;background:radial-gradient(circle at 50% 38%,color-mix(in srgb,var(--c) 34%,var(--art)),color-mix(in srgb,var(--c) var(--mix),var(--art)) 70%)}
.ico{display:block;width:72px;height:72px;border-radius:22%;filter:drop-shadow(0 10px 16px color-mix(in srgb,var(--c) 45%,transparent));transition:transform .25s cubic-bezier(.2,.8,.2,1.2)}
.ico rect{fill:color-mix(in srgb,var(--c) 18%,#0b0c0f);stroke:color-mix(in srgb,var(--c) 70%,transparent);stroke-width:1.5}
.ico text{fill:color-mix(in srgb,var(--c) 75%,#fff);font:700 27px system-ui,sans-serif;text-anchor:middle}
.body{display:flex;flex-direction:column;gap:2px;min-width:0;flex:1}
.top{display:flex;align-items:center;gap:10px}
.name{font-size:1.2rem;font-weight:750;letter-spacing:-.015em}
.ver{margin-left:auto;padding:1px 9px;border-radius:99px;background:color-mix(in srgb,var(--c) 13%,transparent);color:color-mix(in srgb,var(--c) 70%,var(--fg));font-size:.75rem;font-weight:600;font-variant-numeric:tabular-nums}
.desc{color:var(--mut);font-size:.9375rem;line-height:1.4}
.go{display:none;margin-top:auto;padding-top:14px;color:color-mix(in srgb,var(--c) 75%,var(--fg));font-weight:650}
.go i{display:inline-block;font-style:normal;transition:transform .2s ease}
@media (min-width:640px){
.apps{grid-template-columns:1fr 1fr}
.app{flex-direction:column;align-items:stretch;gap:0;padding:10px}
.art{width:auto;height:156px;border-radius:15px}
.ico{width:112px;height:112px}
.body{padding:16px 10px 10px}
.go{display:block}
}
@media (min-width:1060px){.apps{grid-template-columns:repeat(4,1fr)}}
@media (hover:hover){
.app:hover{transform:translateY(-4px);border-color:color-mix(in srgb,var(--c) 45%,var(--line));box-shadow:var(--sh),0 26px 50px -26px color-mix(in srgb,var(--c) 90%,transparent)}
.app:hover .ico{transform:scale(1.07) rotate(-2.5deg)}
.app:hover .go i{transform:translateX(5px)}
}
.app:active{transform:scale(.985)}
.app:focus-visible,.nc:focus-visible,.tips summary:focus-visible{outline:3px solid color-mix(in srgb,var(--c) 80%,var(--fg));outline-offset:3px}
.tips{margin-top:26px;border:1px solid var(--line);border-radius:22px;background:var(--card);box-shadow:var(--sh)}
.tips summary{display:flex;align-items:center;gap:12px;padding:16px 20px;border-radius:22px;font-weight:650;cursor:pointer;list-style:none}
.tips summary::-webkit-details-marker{display:none}
.tips summary svg{flex:none;width:22px;height:22px;fill:none;stroke:var(--mut);stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.tips summary::after{content:"";margin-left:auto;width:9px;height:9px;border:solid var(--mut);border-width:0 2px 2px 0;transform:translateY(-2px) rotate(45deg);transition:transform .2s ease}
.tips[open] summary::after{transform:translateY(2px) rotate(-135deg)}
.tb{padding:0 20px 20px;color:var(--mut)}
.tb p{margin:0 0 14px}
.tb dl{display:grid;gap:2px 24px;margin:0}
.tb dt{color:var(--fg);font-weight:650}
.tb dd{margin:0 0 10px}
@media (min-width:720px){.tb dl{grid-template-columns:max-content 1fr;row-gap:10px}.tb dd{margin:0}}
.warn{margin:16px 0 0;padding:10px 14px;border-left:3px solid #f0a020;border-radius:10px;background:rgb(240 160 32/.13);color:var(--fg)}
.err{margin:0 0 18px;padding:12px 16px;border-left:3px solid #e8573f;border-radius:12px;background:rgb(232 87 63/.12)}
footer{margin-top:30px;color:var(--mut);font-size:.8125rem;text-align:center}
@media (prefers-reduced-motion:reduce){*{transition:none!important}.app:hover,.app:active{transform:none}}
</style>
</head>
<body>
<div class="wrap">
<header>
<div class="brand"><svg class="mark" viewBox="0 0 32 32" aria-hidden="true"><rect width="14" height="14" rx="4" fill="#12a58a"/><rect x="18" width="14" height="14" rx="4" fill="#2f7bf5"/><rect y="18" width="14" height="14" rx="4" fill="#e8573f"/><rect x="18" y="18" width="14" height="14" rx="4" fill="#7bb51c"/></svg>
HTML
    printf '<div><h1>Craft</h1><p>%s</p></div></div>\n%s\n</header>\n<main>\n' "$tagline" "$link"
    any=
    for a in $APPS; do any=$any$(version_of "$a"); done
    if [ -z "$any" ]; then
      printf '<p class="err">%s</p>\n' "$none"
    elif grep -q '^ERROR' "$STATE/status" 2>/dev/null; then
      printf '<p class="err">%s</p>\n' "$err"
    fi
    if [ -n "$INJ" ] && [ "$CANARY" != off ] && [ -s "$STATE/canary-failed" ]; then
      read -r hurl < "$STATE/canary-failed"
      printf '<p class="err">%s <a href="%s">%s</a></p>\n' "$held" "$(esc "$hurl")" "$(esc "$hurl")"
    fi
    echo '<ul class="apps">'
    for a in $APPS; do
      v=$(version_of "$a")
      [ -n "$v" ] || continue
      app_info "$a"
      if [ -s "$WWW/$a/app-icon.png" ]; then
        ico="<img class=\"ico\" src=\"$a/app-icon.png\" alt=\"\">"
      else
        ico="<svg class=\"ico\" viewBox=\"0 0 64 64\" aria-hidden=\"true\"><rect x=\".75\" y=\".75\" width=\"62.5\" height=\"62.5\" rx=\"14\"/><text x=\"32\" y=\"41.5\">$short</text></svg>"
      fi
      printf '<li><a class="app %s" href="%s/"><span class="art">%s</span><span class="body"><span class="top"><span class="name">%s</span><span class="ver">%s</span></span><span class="desc">%s</span><span class="go">%s <i>→</i></span></span></a></li>\n' \
        "$a" "$a" "$ico" "$name" "$v" "$text" "$open"
    done
    echo '</ul>'
    printf '<details class="tips">\n<summary><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12m-5-5 5 5 5-5M4 20h16"/></svg>%s</summary>\n<div class="tb">\n' "$tips"
    [ -z "$INJ" ] || printf '<p>%s</p>\n' "$nc"
    printf '<p>%s</p>\n<dl>\n<dt>Firefox</dt>\n<dd>%s</dd>\n<dt>Chrome/Chromium</dt>\n<dd>%s</dd>\n<dt>Edge</dt>\n<dd>%s</dd>\n<dt>iPad</dt>\n<dd>%s</dd>\n</dl>\n' \
      "$intro" "$firefox" "$chrome" "$edge" "$ipad"
    printf '<p class="warn">%s</p>\n</div>\n</details>\n</main>\n' "$warn"
    printf '<footer>%s</footer>\n</div>\n</body>\n</html>\n' "$footer"
  } > "$WWW/.index.html.new" && mv -f "$WWW/.index.html.new" "$WWW/index.html"
}

update_app() {
  app=$1
  old=$(version_of "$app")
  json=$(curl -fsS --retry 3 --connect-timeout 20 --max-time 120 -A craft-update \
    -H 'Accept: application/vnd.github+json' "$API/storytold/$app/releases?per_page=30") || {
    log "$app: ERROR - cannot list the releases of storytold/$app (GitHub not reachable, rate limit reached, or no such repository)"
    return 1
  }
  now=$(date +%s)
  blocked=
  [ -f "$STATE/$app.blocked" ] && blocked=$(tr -d ' \t\r\n' < "$STATE/$app.blocked")
  blocked=${blocked#v}
  case $blocked in
    '') ;;
    *[!0-9.]* | .* | *. | *..* | *.*.*.*) log "$app: ERROR - state/$app.blocked holds '$blocked', not a version such as 0.7.0"; return 1 ;;
    *.*.*) ;;
    *) log "$app: ERROR - state/$app.blocked holds '$blocked', not a version such as 0.7.0"; return 1 ;;
  esac
  canary=off
  [ -n "$INJ" ] && [ "$CANARY" != off ] && canary=on
  # Without the runs no release counts as tested; the hold keeps them all back, and the choice
  # without the canary only names the release that waits.
  [ "$HOLD" = "canary runs not readable" ] && canary=off
  # The newest release (by version) that is MIN_AGE old (counted from its last upload), newer than
  # the installed and the blocked version, and has a web build. With the canary check on, also:
  # the first canary run created after its last upload has ended, no release of the app came out
  # before that run ended (so the run tested this one), and the run passed. A release that was not
  # the newest during its first run is never taken, and neither is one whose first run did not
  # pass: later runs test the layer's main branch, not the pinned layer. The app's next release
  # that passes its own first run is taken.
  pick=$(printf '%s' "$json" | jq -r --arg app "$app" --argjson now "$now" --argjson minage "$MIN_AGE" \
      --arg old "$old" --arg blocked "$blocked" --arg canary "$canary" \
      --argjson runs "$RUNS" --argjson issues "$ISSUES" "$CANARY_JQ"'
    def sv: split(".") | map(tonumber);
    [ .[] | select(.draft == false and .prerelease == false and .published_at != null) ] as $all
    | [ $all[] | .published_at | fromdateiso8601 ] as $times
    | [ $all[]
      | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
      | (.tag_name | ltrimstr("v")) as $v
      | (.published_at | fromdateiso8601) as $pub
      | select($old == "" or ($v | sv) > ($old | sv))
      | select($blocked == "" or ($v | sv) > ($blocked | sv))
      | (.assets | map(select(.name == ($app + "-web-" + $v + ".zip"))) | first) as $z
      | (.assets | map(select(.name == "SHA256SUMS.txt")) | first) as $s
      | select($z != null and $s != null)
      | ([.published_at, $z.updated_at, $s.updated_at] | map(select(. != null) | fromdateiso8601) | max) as $p
      | select($p <= $now - $minage)
      | ([ $times[] | select(. > $pub) ] | min) as $next
      | ([ $runs[] | select(.start > $p) ] | first) as $r
      | select($canary != "on" or ($r != null and ($next == null or $next > $r.end) and passed($r)))
      | [$v, $z.name, $z.browser_download_url, ($z.digest // "-"), $s.browser_download_url] ]
    | max_by(.[0] | sv) // empty | join("|")') || {
    log "$app: ERROR - unreadable answer from GitHub"
    return 1
  }
  if [ -z "$pick" ]; then
    if [ -n "$old" ]; then
      fetch_icon "$app" "$old" "$REL/$app-$old" || log "$app: no icon for $old, the start page shows a letter tile"
      log "$app: $old stays, no newer release qualifies yet"
      return 0
    fi
    some=$(printf '%s' "$json" | jq --arg app "$app" '[ .[] | select(.draft == false and (.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))) | (.tag_name | ltrimstr("v")) as $v | select(any(.assets[]; .name == ($app + "-web-" + $v + ".zip")) and any(.assets[]; .name == "SHA256SUMS.txt")) ] | length') || some=0
    if [ "${some:-0}" -gt 0 ]; then
      log "$app: not installed yet, no release qualifies yet; a later run takes one"
      return 0
    fi
    log "$app: ERROR - no release v<version> with $app-web-<version>.zip and SHA256SUMS.txt found"
    return 1
  fi
  IFS='|' read -r ver name url digest sums <<EOF
$pick
EOF
  case $ver in
    '' | *[!0-9A-Za-z.+-]*) log "$app: ERROR - unexpected version '$ver'"; return 1 ;;
  esac
  if [ -n "$HOLD" ]; then
    if [ -z "$old" ]; then
      log "$app: ERROR - $ver not installed: $HOLD"
      return 1
    fi
    log "$app: $ver held back ($HOLD), $old stays"
    return 0
  fi
  base="https://github.com/storytold/$app/releases/download/v$ver/"
  if [ "$url" != "$base$name" ] || [ "$sums" != "${base}SHA256SUMS.txt" ]; then
    log "$app: ERROR - unexpected download address for $ver"
    return 1
  fi
  case $digest in
    sha256:*) ;;
    *) log "$app: ERROR - GitHub gives no checksum for $name"; return 1 ;;
  esac
  mkdir -p "$REL"
  tmp=$(mktemp -d "$REL/.tmp-$app.XXXXXX") || { log "$app: ERROR - no working folder"; return 1; }
  if ! curl -fsSL --retry 3 --connect-timeout 20 --max-time 900 -o "$tmp/$name" "$url" ||
     ! curl -fsSL --retry 3 --connect-timeout 20 --max-time 120 -o "$tmp/SHA256SUMS.txt" "$sums"; then
    drop "$tmp"
    log "$app: ERROR - download of $ver failed"
    return 1
  fi
  is=$(sha256sum "$tmp/$name" | cut -d' ' -f1)
  should=$(awk -v n="$name" '$2 == n || $2 == "*" n { print $1 }' "$tmp/SHA256SUMS.txt" | sort -u)
  if [ "${#should}" -ne 64 ] || [ "$is" != "$should" ] || [ "sha256:$is" != "$digest" ]; then
    drop "$tmp"
    log "$app: ERROR - checksum of $name does not match, nothing changed"
    return 1
  fi
  if ! unzip -Z1 "$tmp/$name" > "$tmp/names" 2>/dev/null ||
     ! awk -v p="$app-web-$ver/" 'index($0, p) != 1 || /(^|\/)\.\.(\/|$)/ { bad = 1 } END { exit bad }' "$tmp/names" ||
     unzip -Z "$tmp/$name" 2>/dev/null | grep -q '^l'; then
    drop "$tmp"
    log "$app: ERROR - $name has links or paths outside $app-web-$ver/, nothing changed"
    return 1
  fi
  mkdir "$tmp/x"
  if ! unzip -q "$tmp/$name" -d "$tmp/x"; then
    drop "$tmp"
    log "$app: ERROR - unpacking $name failed"
    return 1
  fi
  chmod -R u+rwX "$tmp/x"
  src=$tmp/x/$app-web-$ver
  if [ -n "$(find "$tmp/x" ! -type f ! -type d | head -n 1)" ] ||
     [ "$(ls -A "$tmp/x")" != "$app-web-$ver" ] ||
     [ ! -f "$src/index.html" ] ||
     [ -z "$(find "$src" -maxdepth 1 -type f -name '*.wasm' | head -n 1)" ]; then
    drop "$tmp"
    log "$app: ERROR - unexpected content in $name, nothing changed"
    return 1
  fi
  rm -f "$src/README.md" "$src/HOSTING.md" "$src/_headers" "$src/.htaccess"
  # The leftovers of a Cargo build next to the site (LightCraft's release ships build/, deps/,
  # .fingerprint/ and more): the page never loads them, so they are not served. Brotli copies
  # go too; the web server serves the .gz copies written below.
  if [ -d "$src/.fingerprint" ] || [ -f "$src/.cargo-lock" ]; then
    for d in build deps examples incremental .fingerprint; do drop "$src/$d"; done
    rm -f "$src"/.cargo-*lock
    log "$app: Cargo build leftovers removed from $ver"
  fi
  find "$src" -type f -name '*.br' -exec rm -f {} +
  fetch_icon "$app" "$ver" "$src" || log "$app: no icon for $ver, the start page shows a letter tile"
  if ! add_translator "$app" "$ver" "$src"; then
    drop "$tmp"
    log "$app: $ver not switched to, ${old:-nothing} stays"
    return 1
  fi
  find "$src" -type f \( -name '*.wasm' -o -name '*.js' -o -name '*.mjs' -o -name '*.html' -o -name '*.otf' \) -exec gzip -9 -k -f {} \;
  chmod -R a+rX "$src"
  dest=$REL/$app-$ver
  drop "$dest"
  if [ -e "$dest" ] || ! mv -T "$src" "$dest"; then
    drop "$tmp"
    log "$app: ERROR - storing $ver failed, ${old:-nothing} stays"
    return 1
  fi
  drop "$tmp"
  if ! switch_to "$app" "$ver"; then
    log "$app: ERROR - switching to $ver failed"
    return 1
  fi
  [ -n "$old" ] && echo "$old" > "$STATE/$app.previous"
  for d in "$REL/$app"-*; do
    [ -d "$d" ] || continue
    case ${d##*/} in
      "$app-$ver" | "$app-$old") ;;
      *) drop "$d" ;;
    esac
  done
  log "$app: ${old:-new} -> $ver"
}

rollback() {
  app=$1
  now=$(version_of "$app")
  prev=$(cat "$STATE/$app.previous" 2>/dev/null || true)
  if [ -z "$now" ] || [ -z "$prev" ] || [ ! -d "$REL/$app-$prev" ]; then
    log "$app: ERROR - no previous version to go back to"
    return 1
  fi
  layer_ready || log "$app: layer not available, $prev keeps the translator it has"
  add_translator "$app" "$prev" "$REL/$app-$prev" || log "$app: $prev runs without an up-to-date translator"
  switch_to "$app" "$prev" || { log "$app: ERROR - switching failed"; return 1; }
  echo "$now" > "$STATE/$app.blocked"
  rm -f "$STATE/$app.previous"
  log "$app: back to $prev, $now blocked"
}

case ${1:-} in
  "") ;;
  --status)
    dir=$LAYERS/craftsuite-layer-hosting-$LAYER_VERSION
    [ -n "$LAYER_VERSION" ] && [ -f "$dir/hosting/inject-translator.sh" ] && INJ=$dir/hosting/inject-translator.sh
    for a in $APPS; do
      v=$(version_of "$a")
      nc=-
      if [ -n "$v" ] && [ -n "$INJ" ]; then
        timeout_of "$a"
        # shellcheck disable=SC2086 # TIMEOUT is empty or one word
        if sh "$INJ" -c -q --app "$a" --app-version "$v" $TIMEOUT "$REL/$a-$v" >/dev/null 2>&1; then nc=yes; else nc=no; fi
      fi
      echo "$a: ${v:--} (previous $(cat "$STATE/$a.previous" 2>/dev/null || echo -), blocked $(cat "$STATE/$a.blocked" 2>/dev/null || echo -), Nextcloud $nc)"
    done
    if [ -z "$LAYER_VERSION" ]; then
      echo "layer: off"
    elif [ -n "$INJ" ]; then
      echo "layer: $LAYER_VERSION"
    else
      echo "layer: $LAYER_VERSION (not downloaded yet)"
    fi
    if [ -n "$LAYER_VERSION" ] && [ "$CANARY" != off ] && [ -s "$STATE/canary-failed" ]; then
      read -r hurl < "$STATE/canary-failed"
      echo "canary hold: the canary failed ($hurl) since layer $LAYER_VERSION came into use; new releases wait"
    fi
    cat "$STATE/status" 2>/dev/null
    exit 0
    ;;
  --rollback)
    # shellcheck disable=SC2086 # the list is split on purpose
    case " $APPS " in
      *" ${2:-} "*) [ -n "${2:-}" ] || { echo "Usage: craft-update --rollback APP" >&2; exit 2; } ;;
      *) echo "Usage: craft-update --rollback <$(echo $APPS | tr ' ' '|')>" >&2; exit 2 ;;
    esac
    ;;
  *) echo "Usage: craft-update [--status | --rollback APP]" >&2; exit 2 ;;
esac

if ! mkdir -p "$REL" "$STATE" || [ ! -w "$WWW" ] || [ ! -w "$REL" ] || [ ! -w "$STATE" ] || [ ! -w "$BASE" ]; then
  log "ERROR - $BASE (and www, www/releases, state in it) must be writable for user $(id -u):$(id -g)"
  exit 1
fi
chmod a+rx "$BASE" "$WWW" "$REL" 2>/dev/null || true
if ! mkdir "$STATE/.lock" 2>/dev/null; then
  log "craft-update is already running (remove $STATE/.lock if it is not)"
  exit 1
fi
trap 'rmdir "$STATE/.lock"' EXIT
trap 'exit 1' HUP INT PIPE TERM

if [ "${1:-}" = "--rollback" ]; then
  rollback "$2"
  rc=$?
  start_page
  exit $rc
fi

errors=0
# state/canary-failed changes only when the canary could be read.
FAILED=keep
if ! layer_ready; then
  errors=$((errors + 1))
  HOLD="layer not available"
elif [ -n "$INJ" ] && [ "$CANARY" != off ]; then
  if ! canary_check; then
    errors=$((errors + 1))
    log "layer: ERROR - cannot read the canary $CANARY_PART of $LAYER_REPO, new releases wait"
    HOLD="canary $CANARY_PART not readable"
  else
    case $STALE in
      '') ;;
      none)
        errors=$((errors + 1))
        log "layer: ERROR - the canary of $LAYER_REPO has no finished run: new releases wait for one (how-it-works.md, The canary)"
        ;;
      *)
        errors=$((errors + 1))
        log "layer: ERROR - the newest canary run of $LAYER_REPO started $STALE, more than three days ago: releases that came out since wait for a run (how-it-works.md, The canary)"
        ;;
    esac
    if [ -n "$FAILED" ]; then
      errors=$((errors + 1))
      log "layer: ERROR - the canary failed ($FAILED) since layer $LAYER_VERSION came into use: new releases wait until another layer version is in use, or you confirm that the failure does not concern it (operations.md, The canary hold)"
      HOLD="canary failure"
    elif [ -n "$OPEN" ]; then
      log "layer: the canary reports a failure ($OPEN), new releases wait while the issue is open"
      HOLD="open canary issue"
    fi
  fi
fi
case $FAILED in
  keep) ;;
  '') rm -f "$STATE/canary-failed" ;;
  *) printf '%s\n%s\n' "$FAILED" "$LAYER_VERSION $since" > "$STATE/canary-failed" ;;
esac
for a in $APPS; do
  update_app "$a" || errors=$((errors + 1))
  v=$(version_of "$a")
  if [ -n "$v" ] && ! add_translator "$a" "$v" "$REL/$a-$v"; then
    errors=$((errors + 1))
  fi
done
if [ "$errors" -eq 0 ]; then
  echo "OK $(date '+%F %T')" > "$STATE/status"
else
  echo "ERROR $errors $(date '+%F %T')" > "$STATE/status"
fi
start_page
[ "$errors" -eq 0 ]
