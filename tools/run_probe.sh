#!/usr/bin/env bash
# Runs the controller probe (tools/joyprobe/lg_joyprobe) in the real, windowed
# game, with this repo's mods freshly copied in. Needs the owner at the pads:
# ask before running it. Run it from Git Bash with a tool timeout above 500 s
# (or in the background): a killed shell skips the cleanup below.
#
#   tools/run_probe.sh [--watch <seconds> | --play <seconds>] [--raw]
#
#   (default)  game mode: what the game receives, after gamecube_support's fixes
#   --watch N  log every trigger change and button press for N seconds instead of the steps
#   --play N   the game runs normally for N seconds while the probe logs pad events, action
#              edges, UI focus and the lobby's state; a save change is then the owner's play
#   --raw      raw mode: the adapter's own button numbers (SDL_GAMECONTROLLERCONFIG=RAW_SDL)
#
# Launches with SDL_JOYSTICK_HIDAPI_GAMECUBE=0, as the owner's PC has it set.
# Refuses while the game is open.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Steam's default library. A game in another library: MP_GAME_DIR, or the same line in tools/local.env (gitignored).
[ -z "${MP_GAME_DIR:-}" ] && [ -f "$REPO/tools/local.env" ] && . "$REPO/tools/local.env"
# Notepad saves CRLF, which would leave a carriage return on the path.
[ -n "${MP_GAME_DIR:-}" ] && MP_GAME_DIR="${MP_GAME_DIR%$'\r'}"
GAME="${MP_GAME_DIR:-/c/Program Files (x86)/Steam/steamapps/common/party project/Machine Party_Windows}"
SAVES="$APPDATA/Godot/app_userdata/Machine Party"
LOGS="${MP_LOG_DIR:-${TEMP:-/tmp}/machine-party-tests}"
PROBE="$REPO/tools/joyprobe/lg_joyprobe"
PARK="$GAME/mods_parked_by_selftest"

die() { echo "$1" >&2; exit "${2:-2}"; }

# A tasklist that fails counts as "running": the check must fail closed.
game_running() {
  local out
  out="$(tasklist //NH //FO CSV //FI "IMAGENAME eq Machine Party.exe" 2>&1)" || return 0
  case "$out" in *'"Machine Party.exe"'*) return 0 ;; esac
  return 1
}

watch=""
play=""
raw=0
while [ $# -gt 0 ]; do
  case "$1" in
    --watch) watch="${2:?--watch needs seconds}"; shift ;;
    --play) play="${2:?--play needs seconds}"; shift ;;
    --raw) raw=1 ;;
    *) die "usage: $0 [--watch <seconds> | --play <seconds>] [--raw]" ;;
  esac
  shift
done

[ -f "$GAME/Machine Party.exe" ] || die "game not found at $GAME (set MP_GAME_DIR, or put MP_GAME_DIR=\"<folder>\" in tools/local.env)"
echo "game: $GAME"
[ -d "$GAME/mods" ] || die "$GAME/mods missing: the mod loader isn't installed, or mods/ was renamed"
game_running && die "Machine Party is running (or tasklist failed); not touching it. Close the game first." 3

# Leftovers from a run that was killed before its cleanup.
for d in "$REPO"/tools/selftest/*/ "$PROBE/"; do
  b="$(basename "$d")"
  if [ -d "$GAME/mods/$b" ]; then
    mkdir -p "$LOGS"
    [ -f "$GAME/mods/$b/result.txt" ] && cp "$GAME/mods/$b/result.txt" "$LOGS/leftover_${b}_$(date +%Y%m%d-%H%M%S).txt" \
      && echo "saved the leftover $b/result.txt to $LOGS"
    rm -rf "${GAME:?}/mods/${b:?}" && echo "removed leftover dev mod: $b"
  fi
done
# A mod of ours that a killed run installed carries this marker; the owner's own copy never does.
for d in "$REPO"/mods/*/; do
  b="$(basename "$d")"
  [ -f "$GAME/mods/$b/.installed_by_selftest" ] && rm -rf "${GAME:?}/mods/${b:?}" && echo "removed leftover mod: $b"
done
for d in "$PARK"/*/; do
  [ -d "$d" ] && die "an earlier self-test left $(basename "$d") parked in $PARK; run tools/run_selftest.sh once to restore it"
done

mkdir -p "$LOGS"
before="$(md5sum "$SAVES"/*.save "$SAVES"/*.json 2>/dev/null)"
[ -n "$before" ] || die "no saves found in $SAVES"
installed=(lg_joyprobe window_place)
cleanup() { for m in "${installed[@]}"; do rm -rf "${GAME:?}/mods/${m:?}"; done; }
trap cleanup EXIT
# Our own mods are replaced with the repo's copies. Those the owner already had
# stay installed afterwards; the others are removed with the probe.
for m in "$REPO"/mods/*/; do
  m="$(basename "$m")"
  if [ -d "$GAME/mods/$m" ]; then
    rm -rf "${GAME:?}/mods/${m:?}" && cp -r "$REPO/mods/$m" "$GAME/mods/" || die "could not install $m"
  else
    installed+=("$m")
    cp -r "$REPO/mods/$m" "$GAME/mods/" && touch "$GAME/mods/$m/.installed_by_selftest" || die "could not install $m"
  fi
done
rm -rf "${GAME:?}/mods/lg_joyprobe" && cp -r "$PROBE" "$GAME/mods/" || die "could not install the probe"
# The owner plays it, so it opens on the screen left of the primary and keeps focus.
cp -r "$REPO/tools/selftest/window_place" "$GAME/mods/" || die "could not install window_place"

sdl_config=""
[ "$raw" = 1 ] && sdl_config="$(grep -o 'const RAW_SDL := "[^"]*"' "$PROBE/main.gd" | sed 's/^const RAW_SDL := "//; s/"$//')"
stamp="$(date +%Y%m%d-%H%M%S)"
(cd "$GAME" && SDL_JOYSTICK_HIDAPI_GAMECUBE=0 SDL_GAMECONTROLLERCONFIG="$sdl_config" JOYPROBE_WATCH="$watch" JOYPROBE_PLAY="$play" MP_WINDOW_FOCUS="${MP_WINDOW_FOCUS:-keep}" \
  timeout 500 "./Machine Party.exe" > "$LOGS/probe_stdout_$stamp.txt" 2>&1)
echo "exit=$?"
grep -E '^\[window_place\] (WARN|WINDOW)' "$LOGS/probe_stdout_$stamp.txt" | awk '/WARN/ || !w++' | head -4
if [ -f "$GAME/mods/lg_joyprobe/result.txt" ]; then
  cp "$GAME/mods/lg_joyprobe/result.txt" "$LOGS/probe_$stamp.txt"
  grep -vE "SEEN|FOCUS" "$LOGS/probe_$stamp.txt"
  echo "full result: $LOGS/probe_$stamp.txt"
else
  echo "NO RESULT (log: $LOGS/probe_stdout_$stamp.txt)"
fi

after="$(md5sum "$SAVES"/*.save "$SAVES"/*.json 2>/dev/null)"
[ "$before" = "$after" ] || { echo "WARN a save or config changed during the run:"; diff <(echo "$before") <(echo "$after"); exit 1; }
