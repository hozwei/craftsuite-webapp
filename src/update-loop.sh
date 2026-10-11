set -u
mkdir -p /tmp/bin
cat > /tmp/bin/craft-update <<'SCRIPT'
@@SCRIPT@@
SCRIPT
chmod 755 /tmp/bin/craft-update
case $CRAFT_UPDATE_TIME in
  [0-9]:[0-5][0-9] | [01][0-9]:[0-5][0-9] | 2[0-3]:[0-5][0-9]) ;;
  *)
    echo "$(date '+%F %T') CRAFT_UPDATE_TIME '$CRAFT_UPDATE_TIME' is not HH:MM, using 07:00"
    CRAFT_UPDATE_TIME=07:00
    export CRAFT_UPDATE_TIME
    ;;
esac
rmdir /craft/state/.lock 2>/dev/null
rm -rf /craft/www/releases/.tmp-* /craft/layer/.tmp.*
trap 'echo "craft-update stopped"; exit 0' TERM
echo "$(date '+%F %T') craft-update started: one run now, then daily at ${CRAFT_UPDATE_TIME}"
craft-update
rc=$?
retries=0
while true; do
  now=$(date +%s)
  next=$(date -d "today ${CRAFT_UPDATE_TIME}" +%s 2>/dev/null) || next=0
  if [ "$next" -le "$now" ]; then
    next=$(date -d "tomorrow ${CRAFT_UPDATE_TIME}" +%s 2>/dev/null) || next=$(( now + 86400 ))
  fi
  if [ "$rc" -ne 0 ] && [ "$retries" -lt 3 ] && [ $(( now + 3600 )) -lt "$next" ]; then
    next=$(( now + 3600 ))
    retries=$(( retries + 1 ))
    echo "$(date '+%F %T') craft-update had errors, next try in an hour ($retries of 3)"
  else
    retries=0
  fi
  sleep $(( next - now )) & wait $!
  craft-update
  rc=$?
done
