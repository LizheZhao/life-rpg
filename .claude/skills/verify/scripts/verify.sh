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
# One simulator per checkout (main repo and each git worktree): two sessions driving one shared
# simulator reinstall the app and reset each other's store mid-run.
NAME="LifeRPG-Verify-$(printf %s "$ROOT" | shasum | cut -c1-6)"
BUNDLE="com.lizhezhao.LifeRPG"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
MODEL="iPhone 17 Pro Max"
DERIVED="$ROOT/build/verify-derived"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/LifeRPG.app"
EVIDENCE="$ROOT/build/verify-evidence"
STATE="$ROOT/build/verify-state"          # holds "we-booted" when `up` booted the sim
LOCK="$ROOT/build/verify-up.lock"         # one `up` at a time: two of them fight over the derived data and the sim

# run_to <seconds> <label> <command...>: runs the command, and if it is still going after <seconds> kills its whole
# process group and says which step hung (exit 124). Nothing here may wait forever: a stuck `simctl` or `xcodebuild`
# used to hang `up` for good and leave processes behind that hung the next run too. RUN_TO_QUIET=1 drops the
# command's own stderr (not the timeout message).
run_to() {
  local secs="$1" label="$2"; shift 2
  perl -e '
    use POSIX ":sys_wait_h";
    my ($secs, $label, @cmd) = @ARGV;
    my $pid = fork(); die "fork: $!" unless defined $pid;
    if (!$pid) { setpgrp(0, 0); open(STDERR, ">/dev/null") if $ENV{RUN_TO_QUIET}; exec { $cmd[0] } @cmd or die "exec $cmd[0]: $!"; }
    my $deadline = time + $secs;
    while (1) {
      my $r = waitpid($pid, WNOHANG);
      if ($r == $pid) { exit(($? & 127) ? 128 + ($? & 127) : $? >> 8); }
      if (time >= $deadline) {
        kill "TERM", -$pid; select(undef, undef, undef, 2); kill "KILL", -$pid; waitpid($pid, 0);
        print STDERR "verify.sh: step \"$label\" did not finish in ${secs}s and was killed\n";
        exit 124;
      }
      select(undef, undef, undef, 0.2);
    }
  ' "$secs" "$label" "$@"
}

say() { echo "[verify] $*" >&2; }

# Only one `up` at a time; a lock whose process is gone is taken over.
take_up_lock() {
  mkdir -p "$ROOT/build"
  if ! mkdir "$LOCK" 2>/dev/null; then
    local old; old="$(cat "$LOCK/pid" 2>/dev/null || true)"
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
      echo "verify.sh: another 'up' is already running (pid $old). Wait for it, or kill it, then retry." >&2; exit 3
    fi
    say "taking over a stale lock (pid ${old:-unknown} is gone)"
    rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null || true
    mkdir "$LOCK"
  fi
  echo $$ > "$LOCK/pid"
  trap 'rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null || true' EXIT
}

udid() { run_to 30 "simctl list" xcrun simctl list devices | awk -v n="$NAME" '$0 ~ n" \\(" { match($0, /[0-9A-F-]{36}/); print substr($0, RSTART, RLENGTH); exit }'; }
sim_state() { run_to 30 "simctl list" xcrun simctl list devices | grep "$NAME (" | grep -o -E "\((Booted|Shutdown|Booting)\)" | tr -d '()' | head -1; }
store() { echo "$(run_to 20 get_app_container xcrun simctl get_app_container "$(udid)" "$BUNDLE" data)/Library/Application Support/default.store"; }
# The app's own writes (Debug → Advance one day) land in its container plist, and that value beats
# anything `simctl spawn … defaults write` sets (a device-level layer). So read and write the
# container plist itself, with the app terminated, then restart the sim's cfprefsd, which otherwise
# keeps serving the value the app last wrote from its memory.
prefs() { echo "$(run_to 20 get_app_container xcrun simctl get_app_container "$(udid)" "$BUNDLE" data)/Library/Preferences/$BUNDLE.plist"; }
# A fresh install has no preferences file yet, and PlistBuddy prints a notice to stdout for a missing one.
offset() { local f; f="$(prefs)"; { [ -f "$f" ] && /usr/libexec/PlistBuddy -c "Print :debugDayOffset" "$f" 2>/dev/null; } || echo 0; }
set_offset() {
  local f; f="$(prefs)"
  [ -f "$f" ] || { mkdir -p "$(dirname "$f")"; /usr/libexec/PlistBuddy -c "Save" "$f" >/dev/null 2>&1 || true; }
  /usr/libexec/PlistBuddy -c "Set :debugDayOffset $1" "$f" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Add :debugDayOffset integer $1" "$f" >/dev/null
}
need_sim() { [ -n "$(udid)" ] || { echo "no $NAME simulator — run: verify.sh up" >&2; exit 1; }; }

# Day generation runs after launch and can take 10s+ on a freshly booted sim; ready means today's quests exist.
wait_for_day() {
  local i s
  for i in $(seq 1 120); do
    s="$(store 2>/dev/null)" || s=""
    if [ -f "$s" ] && [ "$(sqlite3 -readonly -cmd '.timeout 3000' "$s" 'select count(*) from ZDAILYQUEST' 2>/dev/null || echo 0)" -gt 0 ]; then return 0; fi
    sleep 0.5
  done
  echo "timed out (60s) waiting for today to be generated: the app launched but wrote no day (is it running? try: verify.sh doctor)" >&2; return 1
}

cmd_up() {
  take_up_lock
  mkdir -p "$ROOT/build" "$EVIDENCE"
  [ -n "$(udid)" ] || run_to 120 "create simulator" xcrun simctl create "$NAME" "$MODEL" "$RUNTIME" >/dev/null
  local u; u="$(udid)"
  if [ "$(sim_state)" != "Booted" ]; then
    say "booting the simulator"
    run_to 120 "boot simulator" xcrun simctl boot "$u"; echo we-booted > "$STATE"
  fi
  run_to 180 "wait for the simulator to finish booting" xcrun simctl bootstatus "$u" -b >/dev/null 2>&1 || {
    [ $? -eq 124 ] && exit 124; true; }
  # The full build log is kept, so a slow or stuck build can be looked at; 20 minutes is a cold build with room to spare.
  say "building (full log: build/verify-build.log)"
  (cd "$ROOT" && run_to 1200 "xcodebuild" xcodebuild -scheme LifeRPG -destination "platform=iOS Simulator,id=$u" \
      -derivedDataPath "$DERIVED" build 2>&1 | tee "$ROOT/build/verify-build.log" | tail -3)
  [ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }
  if [ "${1:-}" = "--fresh" ]; then
    say "removing the installed app (fresh)"
    local rc=0
    RUN_TO_QUIET=1 run_to 90 "uninstall app" xcrun simctl uninstall "$u" "$BUNDLE" >/dev/null || rc=$?
    # "not installed" is fine; a hang is not (installing over the old data would defeat --fresh)
    [ "$rc" -eq 124 ] && exit 124
  fi
  RUN_TO_QUIET=1 run_to 30 "terminate app" xcrun simctl terminate "$u" "$BUNDLE" || true
  say "installing"
  run_to 120 "install app" xcrun simctl install "$u" "$APP"
  say "launching"
  run_to 60 "launch app" xcrun simctl launch "$u" "$BUNDLE"
  say "waiting for today to be generated"
  wait_for_day
  echo "ready: $u"
}

cmd_doctor() {
  need_sim
  local u; u="$(udid)"
  echo "sim:       $NAME $u $(sim_state)"
  [ "$(sim_state)" = "Booted" ] || { echo "FAIL: sim not booted"; exit 1; }
  run_to 20 get_app_container xcrun simctl get_app_container "$u" "$BUNDLE" >/dev/null 2>&1 || { echo "FAIL: app not installed (or the simulator is not answering)"; exit 1; }
  local newest built
  newest=$(find "$ROOT/LifeRPG" "$ROOT/LifeRPGCore/Sources" -name '*.swift' -print0 | xargs -0 stat -f '%m' | sort -n | tail -1)
  built=$(stat -f '%m' "$APP/LifeRPG" 2>/dev/null || echo 0)
  if [ "$newest" -gt "$built" ]; then echo "STALE: sources are newer than the built app — run: verify.sh up"; else echo "build:     up to date"; fi
  echo "running:   $(run_to 20 "launchctl list" xcrun simctl spawn "$u" launchctl list | grep -c "UIKitApplication:$BUNDLE" | sed 's/0/no/;s/1/yes/')"
  echo "offset:    $(offset) day(s)"
  local s; s="$(store)"
  [ -f "$s" ] || { echo "FAIL: no store at $s"; exit 1; }
  sqlite3 -readonly -cmd '.timeout 3000' "$s" "select 'rows:      ledger='||(select count(*) from ZLEDGERENTRY)||' dailyQuest='||(select count(*) from ZDAILYQUEST)||' templates='||(select count(*) from ZQUESTTEMPLATE)||' routines='||(select count(*) from ZROUTINETASK)"
  local off; off="$(offset)"
  echo "app day:   $(date -v-5H -v+"${off}"d '+%Y-%m-%d')  (host: $(date '+%Y-%m-%d %H:%M'); the app's day ends at 05:00; offset applied)"
  echo "generated: up to $(sqlite3 -readonly -cmd '.timeout 3000' "$s" 'select max(ZDAYKEY) from ZDAILYCONTEXT')  (time travel leaves future days behind)"
}

cmd_sql() { need_sim; sqlite3 -readonly -cmd '.timeout 5000' -header -column "$(store)" "$1"; }
cmd_ledger() { need_sim; cmd_sql "select ZDAYKEY day, ZKIND kind, ZPOINTS points, ZNOTE note from ZLEDGERENTRY order by ZTIMESTAMP, Z_PK; select 'balance' as '', sum(ZPOINTS) from ZLEDGERENTRY;"; }

cmd_day() {
  need_sim; local u before i cur; u="$(udid)"
  cur="$(offset)"
  before="$(sqlite3 -readonly -cmd '.timeout 3000' "$(store)" 'select count(*) from ZDAILYCONTEXT')"
  RUN_TO_QUIET=1 run_to 30 "terminate app" xcrun simctl terminate "$u" "$BUNDLE" || true
  set_offset "$1"
  RUN_TO_QUIET=1 run_to 30 "restart cfprefsd" xcrun simctl spawn "$u" launchctl kickstart -k system/com.apple.cfprefsd.xpc.daemon >/dev/null || true
  sleep 1
  run_to 60 "launch app" xcrun simctl launch "$u" "$BUNDLE" >/dev/null
  # Only going forward generates a new day (a new DailyContext row); otherwise just let the refresh settle.
  for i in $(seq 1 120); do
    [ "$(sqlite3 -readonly -cmd '.timeout 3000' "$(store)" 'select count(*) from ZDAILYCONTEXT')" -gt "$before" ] && break
    [ "$1" -le "$cur" ] && [ "$i" -ge 8 ] && break
    sleep 0.5
  done
  echo "offset=$1; latest generated day $(sqlite3 -readonly -cmd '.timeout 3000' "$(store)" 'select max(ZDAYKEY) from ZDAILYCONTEXT')"
}

cmd_shot() { need_sim; mkdir -p "$EVIDENCE"; run_to 30 "screenshot" xcrun simctl io "$(udid)" screenshot "$EVIDENCE/$1.png" >/dev/null 2>&1; echo "$EVIDENCE/$1.png"; }
cmd_relaunch() { need_sim; local u; u="$(udid)"; RUN_TO_QUIET=1 run_to 30 "terminate app" xcrun simctl terminate "$u" "$BUNDLE" || true; run_to 60 "launch app" xcrun simctl launch "$u" "$BUNDLE" >/dev/null; sleep 2; }

cmd_down() {
  [ -n "$(udid)" ] || exit 0
  local u; u="$(udid)"
  RUN_TO_QUIET=1 run_to 30 "terminate app" xcrun simctl terminate "$u" "$BUNDLE" || true
  if [ -f "$STATE" ] && [ "$(sim_state)" = "Booted" ]; then run_to 90 "shut the simulator down" xcrun simctl shutdown "$u"; rm "$STATE"; fi
}
cmd_destroy() { cmd_down; [ -z "$(udid)" ] || { RUN_TO_QUIET=1 run_to 90 "shut the simulator down" xcrun simctl shutdown "$(udid)" || true; run_to 90 "delete simulator" xcrun simctl delete "$(udid)"; }; }

c="${1:-}"; shift || true
case "$c" in
  up) cmd_up "$@";; udid) udid;; doctor) cmd_doctor;; sql) cmd_sql "$@";; ledger) cmd_ledger;; day) cmd_day "$@";;
  shot) cmd_shot "$@";; relaunch) cmd_relaunch;; down) cmd_down;; destroy) cmd_destroy;;
  *) sed -n "2,12p" "${BASH_SOURCE[0]}"; exit 2;;
esac
