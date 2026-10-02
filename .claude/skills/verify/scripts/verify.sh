#!/usr/bin/env bash
# Driver for LifeRPG verification on a dedicated iOS Simulator. Usage: verify.sh <command> [args]
#   up [--fresh]   create/boot the sim, build, install, launch (--fresh wipes the app's data first)
#   udid           print the dedicated sim's UDID (pass it as `device` to the simulator control tool)
#   doctor         read-only health check; run it first whenever something looks off
#   sql "<query>"  read-only query against the app's SwiftData store
#   ledger         balance (sum of ledger) and every ledger row
#   day <N>        set the debug time-travel offset to N days, relaunch (0 = real date)
#   shot <name>    screenshot into build/verify-evidence/<name>.png
#   relaunch       terminate and launch the app again (re-runs the foreground refresh)
#   down           terminate the app; shut the sim down if `up` booted it
#   destroy        delete the dedicated sim (evidence and derived data are kept)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
NAME="LifeRPG-Verify"
BUNDLE="com.lizhezhao.LifeRPG"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
MODEL="iPhone 17 Pro Max"
DERIVED="$ROOT/build/verify-derived"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/LifeRPG.app"
EVIDENCE="$ROOT/build/verify-evidence"
STATE="$ROOT/build/verify-state"          # holds "we-booted" when `up` booted the sim

udid() { xcrun simctl list devices | awk -v n="$NAME" '$0 ~ n" \\(" { match($0, /[0-9A-F-]{36}/); print substr($0, RSTART, RLENGTH); exit }'; }
sim_state() { xcrun simctl list devices | grep "$NAME (" | grep -o -E "\((Booted|Shutdown|Booting)\)" | tr -d '()' | head -1; }
store() { echo "$(xcrun simctl get_app_container "$(udid)" "$BUNDLE" data)/Library/Application Support/default.store"; }
need_sim() { [ -n "$(udid)" ] || { echo "no $NAME simulator — run: verify.sh up" >&2; exit 1; }; }

# Day generation runs after launch and can take 10s+ on a freshly booted sim; ready means today's quests exist.
wait_for_day() {
  local i s
  for i in $(seq 1 120); do
    s="$(store 2>/dev/null)" || s=""
    if [ -f "$s" ] && [ "$(sqlite3 -readonly "$s" 'select count(*) from ZDAILYQUEST' 2>/dev/null || echo 0)" -gt 0 ]; then return 0; fi
    sleep 0.5
  done
  echo "timed out (60s) waiting for today to be generated" >&2; return 1
}

cmd_up() {
  mkdir -p "$ROOT/build" "$EVIDENCE"
  [ -n "$(udid)" ] || xcrun simctl create "$NAME" "$MODEL" "$RUNTIME" >/dev/null
  local u; u="$(udid)"
  if [ "$(sim_state)" != "Booted" ]; then
    xcrun simctl boot "$u"; echo we-booted > "$STATE"
  fi
  xcrun simctl bootstatus "$u" -b >/dev/null 2>&1
  (cd "$ROOT" && xcodebuild -scheme LifeRPG -destination "platform=iOS Simulator,id=$u" \
      -derivedDataPath "$DERIVED" build 2>&1 | tail -3)
  [ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }
  if [ "${1:-}" = "--fresh" ]; then xcrun simctl uninstall "$u" "$BUNDLE" 2>/dev/null || true; fi
  xcrun simctl terminate "$u" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$u" "$APP"
  xcrun simctl launch "$u" "$BUNDLE"
  wait_for_day
  echo "ready: $u"
}

cmd_doctor() {
  need_sim
  local u; u="$(udid)"
  echo "sim:       $NAME $u $(sim_state)"
  [ "$(sim_state)" = "Booted" ] || { echo "FAIL: sim not booted"; exit 1; }
  xcrun simctl get_app_container "$u" "$BUNDLE" >/dev/null 2>&1 || { echo "FAIL: app not installed"; exit 1; }
  local newest built
  newest=$(find "$ROOT/LifeRPG" "$ROOT/LifeRPGCore/Sources" -name '*.swift' -print0 | xargs -0 stat -f '%m' | sort -n | tail -1)
  built=$(stat -f '%m' "$APP/LifeRPG" 2>/dev/null || echo 0)
  if [ "$newest" -gt "$built" ]; then echo "STALE: sources are newer than the built app — run: verify.sh up"; else echo "build:     up to date"; fi
  echo "running:   $(xcrun simctl spawn "$u" launchctl list | grep -c "UIKitApplication:$BUNDLE" | sed 's/0/no/;s/1/yes/')"
  echo "offset:    $(xcrun simctl spawn "$u" defaults read "$BUNDLE" debugDayOffset 2>/dev/null || echo 0) day(s)"
  local s; s="$(store)"
  [ -f "$s" ] || { echo "FAIL: no store at $s"; exit 1; }
  sqlite3 -readonly "$s" "select 'rows:      ledger='||(select count(*) from ZLEDGERENTRY)||' dailyQuest='||(select count(*) from ZDAILYQUEST)||' templates='||(select count(*) from ZQUESTTEMPLATE)||' routines='||(select count(*) from ZROUTINETASK)"
  echo "app day:   $(sqlite3 -readonly "$s" 'select max(ZDAYKEY) from ZDAILYCONTEXT')  (host: $(date '+%Y-%m-%d %H:%M'); the app's day ends at 05:00)"
}

cmd_sql() { need_sim; sqlite3 -readonly -header -column "$(store)" "$1"; }
cmd_ledger() { need_sim; cmd_sql "select ZDAYKEY day, ZKIND kind, ZPOINTS points, ZNOTE note from ZLEDGERENTRY order by ZTIMESTAMP, Z_PK; select 'balance' as '', sum(ZPOINTS) from ZLEDGERENTRY;"; }

cmd_day() {
  need_sim; local u before i cur; u="$(udid)"
  cur="$(xcrun simctl spawn "$u" defaults read "$BUNDLE" debugDayOffset 2>/dev/null || echo 0)"
  before="$(sqlite3 -readonly "$(store)" 'select count(*) from ZDAILYCONTEXT')"
  xcrun simctl terminate "$u" "$BUNDLE" 2>/dev/null || true
  xcrun simctl spawn "$u" defaults write "$BUNDLE" debugDayOffset -int "$1"
  xcrun simctl launch "$u" "$BUNDLE" >/dev/null
  # Only going forward generates a new day (a new DailyContext row); otherwise just let the refresh settle.
  for i in $(seq 1 120); do
    [ "$(sqlite3 -readonly "$(store)" 'select count(*) from ZDAILYCONTEXT')" -gt "$before" ] && break
    [ "$1" -le "$cur" ] && [ "$i" -ge 8 ] && break
    sleep 0.5
  done
  echo "offset=$1; latest generated day $(sqlite3 -readonly "$(store)" 'select max(ZDAYKEY) from ZDAILYCONTEXT')"
}

cmd_shot() { need_sim; mkdir -p "$EVIDENCE"; xcrun simctl io "$(udid)" screenshot "$EVIDENCE/$1.png" >/dev/null 2>&1; echo "$EVIDENCE/$1.png"; }
cmd_relaunch() { need_sim; local u; u="$(udid)"; xcrun simctl terminate "$u" "$BUNDLE" 2>/dev/null || true; xcrun simctl launch "$u" "$BUNDLE" >/dev/null; sleep 2; }

cmd_down() {
  [ -n "$(udid)" ] || exit 0
  local u; u="$(udid)"
  xcrun simctl terminate "$u" "$BUNDLE" 2>/dev/null || true
  if [ -f "$STATE" ] && [ "$(sim_state)" = "Booted" ]; then xcrun simctl shutdown "$u"; rm "$STATE"; fi
}
cmd_destroy() { cmd_down; [ -z "$(udid)" ] || { xcrun simctl shutdown "$(udid)" 2>/dev/null || true; xcrun simctl delete "$(udid)"; }; }

c="${1:-}"; shift || true
case "$c" in
  up) cmd_up "$@";; udid) udid;; doctor) cmd_doctor;; sql) cmd_sql "$@";; ledger) cmd_ledger;; day) cmd_day "$@";;
  shot) cmd_shot "$@";; relaunch) cmd_relaunch;; down) cmd_down;; destroy) cmd_destroy;;
  *) sed -n "2,12p" "${BASH_SOURCE[0]}"; exit 2;;
esac
