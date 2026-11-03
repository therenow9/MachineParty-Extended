#!/usr/bin/env bash
# Sets up the owner's bot playtest: humans and up to 7 Offline Bots in the lobby's items, each with
# a split-screen tile, in a local match that plays each custom-game minigame once (tools/selftest/cl_playtest).
# The owner launches and plays through Steam; `remove` takes it all out again. Refuses while the game is open.
#
#   tools/run_playtest.sh install [minigame ...]
#                                      copy cl_playtest, and the playtest's Offline Bots (below); names such as
#                                      DiscoDodge GreenPea limit the match to those minigames (default: all 15)
#   tools/run_playtest.sh remove       remove both, then report what changed in the saves folder
#   tools/run_playtest.sh copy <dir> [--local]
#                                      only make the playtest's Offline Bots in <dir>/offline_bots, for the headless check
#   tools/run_playtest.sh launch <Minigame> [--split | --local] [--bots N] [--overtime=fork|stock|mp8|none] [--compat] [--auto N [--drop S] [--stall S] [--grace S]] [--record <file.avi|file.png> [--fps N]] [--resolution WxH] [--look hi] [--difficulty easy|normal|hard] [--extra <mod dir>]... [--shot <id>]
#                                      start the game windowed straight into <Minigame> (a Globals.MinigameIdentifier
#                                      name, any case): the first pad to press A in the lobby is the owner, bots fill
#                                      the other seats, everyone in a random outfit with no hat twice, the minigame
#                                      repeats until the owner quits; then prints tools/perf_summary.py for its frame log.
#                                      CutsceneTest (the wheat field) is a normal session instead: one round of its first
#                                      minigame, the wheat field, then the rest; --auto moves the fake pad's character to
#                                      the house 10 s in (--auto 3 ends after the minigame that follows it).
#                                      Defaults: --split, 7 bots, --overtime=fork (the newest ../MachineParty-Overtime
#                                      dist/mpml-fork-b<N> build, or $MP_OVERTIME_FORK); stock is <game>/overtime_stock_1.7;
#                                      mp8 is the newest extended/dist/mp8-b<N>/mp8_support build, or
#                                      $MP_MP8_BUILD; none is vanilla's 4 seats, so 3 bots at most. --compat adds the compat set.
#                                      --auto N: unattended, a fake pad in the owner's seat, played by Offline Bots' AI;
#                                      ends 20 s after the Nth load, or records a stall after 10 minutes without a new load.
#                                      --drop S: with --auto, that fake pad disconnects S seconds into the match.
#                                      --stall S: with --auto, a stall is S seconds without a new load instead of 600.
#                                      --grace S: with --auto, end S seconds after the Nth load instead of 20; --auto 2
#                                      --grace 0 is exactly one round, its results included.
#                                      --record <file.avi>: Godot's Movie Maker records the run (30 fps, 960x540, sound);
#                                      the game runs as fast as it renders, so its frame log is not real frame times.
#                                      A .png path records losslessly instead (a PNG per frame and a WAV; tools/trailer_pack.sh).
#                                      --fps N: with --record, Movie Maker's frame rate instead of 30.
#                                      --resolution WxH: the window's size (the game still draws 3D at 960x540 and scales).
#                                      --look hi: 3D drawn at the window's size instead (cl_playtest's look=hi; the trailer's look test).
#                                      Movie Maker can't record it (it keeps a 960x540 corner), so it takes no --record:
#                                      MP_LOOK_STILLS=<existing dir> in the environment saves a still every 30 frames instead.
#                                      --difficulty easy|normal|hard: the bots' level for this launch only; the saved
#                                      Offline Bots config is neither read for it nor changed.
#                                      --extra <mod dir>: also install that mod for the run (repeatable), such as
#                                      tools/selftest/perf_probe (PERF_PROBE=inventory|ablate in the environment).
#                                      --shot <id>: a trailer take (docs/plans/2026-10-31-trailer.md): installs
#                                      tools/trailer_cast with that shot of its trailer.json, so every seat is the cast,
#                                      the music bus is muted and the shot's camera, HUD and choreography run; its event
#                                      log goes beside --record's frames (events.csv), or to %TEMP%/machine-party-tests/trailer.
#
# The playtest's Offline Bots is the owner's copy from $MP_COMPAT_DIR with its caps raised to 8 seats / 7 bots
# and without its three split-screen handler overrides, so bots keep their tiles (--local keeps the overrides:
# bots play off-screen, as Offline Bots means them to). It never enters the repo.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Steam's default library. A game in another library: MP_GAME_DIR, or the same line in tools/local.env (gitignored).
[ -z "${MP_GAME_DIR:-}" ] && [ -f "$REPO/tools/local.env" ] && . "$REPO/tools/local.env"
# Notepad saves CRLF, which would leave a carriage return on the path.
[ -n "${MP_GAME_DIR:-}" ] && MP_GAME_DIR="${MP_GAME_DIR%$'\r'}"
GAME="${MP_GAME_DIR:-/c/Program Files (x86)/Steam/steamapps/common/party project/Machine Party_Windows}"
SAVES="$APPDATA/Godot/app_userdata/Machine Party"
COMPAT="${MP_COMPAT_DIR:-$USERPROFILE/Documents/Modding/machine-party-compat}"
LOGS="${MP_LOG_DIR:-${TEMP:-/tmp}/machine-party-tests}"
MARK=".installed_by_playtest"
BEFORE="$LOGS/playtest_saves_before.txt"
# Offline Bots saves its bot count here whenever bots are seated; install keeps what was there, remove puts it back.
CONFIG="$SAVES/offline_bots_config.json"
CONFIG_KEPT="$LOGS/playtest_offline_bots_config.json"
CONFIG_ABSENT="$LOGS/playtest_offline_bots_config.absent"

die() { echo "$1" >&2; exit "${2:-2}"; }

# A tasklist that fails counts as "running": the check must fail closed.
game_running() {
  local out
  out="$(tasklist //NH //FO CSV //FI "IMAGENAME eq Machine Party.exe" 2>&1)" || return 0
  case "$out" in *'"Machine Party.exe"'*) return 0 ;; esac
  return 1
}

# Git Bash's python is often the Store's stub; the installer's copy is under LOCALAPPDATA.
find_python() {
  local p
  for p in "$LOCALAPPDATA"/Programs/Python/Python3*/python.exe; do [ -x "$p" ] && echo "$p" && return; done
  command -v py >/dev/null && echo py && return
  command -v python
}

saves_list() { (cd "$SAVES" && find . -maxdepth 1 -type f ! -name 'modloader.log' -exec sha256sum {} + | sort -k2); }

# Offline Bots' entry calls override_script_rel(MOD_ID, <game path>, <file>) over three lines per call.
# With keep (launch --local) its overrides stay: the lobby's and the three split-screen handlers'.
make_bots() {
  local dest="$1/offline_bots" keep="${2:-}"
  [ -f "$COMPAT/offline_bots/bot_manager.gd" ] || die "no Offline Bots in $COMPAT/offline_bots"
  [ -e "$dest" ] && die "$dest already exists"
  cp -r "$COMPAT/offline_bots" "$dest" || return 1
  sed -i -e 's/^const MAX_SEATS: int = 4$/const MAX_SEATS: int = 8/' -e 's/^const MAX_BOTS: int = 3$/const MAX_BOTS: int = 7/' "$dest/bot_manager.gd"
  grep -q '^const MAX_SEATS: int = 8$' "$dest/bot_manager.gd" && grep -q '^const MAX_BOTS: int = 7$' "$dest/bot_manager.gd" || return 1
  if [ "$keep" = keep ]; then
    [ "$(grep -c 'override_script_rel' "$dest/main.gd")" = 4 ] && [ "$(grep -c '_local_handler.*\.gd",$' "$dest/main.gd")" = 3 ]
    return
  fi
  sed -i '/override_script_rel(MOD_ID,$/{N;/_local_handler\.gd",$/{N;d}}' "$dest/main.gd"
  [ "$(grep -c 'override_script_rel' "$dest/main.gd")" = 1 ] && ! grep -q '_local_handler' "$dest/main.gd"
}

if [ "${1:-}" = copy ]; then
  [ -d "${2:-}" ] || die "usage: $0 copy <existing dir> [--local]"
  [ "$(cd "$2" && pwd -P)" = "$(cd "$GAME/mods" 2>/dev/null && pwd -P)" ] && die "copy is for a scratch folder; use install for the game"
  case "${3:-}" in "") keep= ;; --local) keep=keep ;; *) die "usage: $0 copy <existing dir> [--local]" ;; esac
  make_bots "$2" $keep || die "Offline Bots' caps or overrides were not where expected; $2/offline_bots is incomplete"
  echo "made $2/offline_bots${keep:+ (overrides kept)}"
  exit 0
fi

game_running && die "Machine Party is running; close it first"
[ -d "$GAME/mods" ] || die "$GAME/mods missing: the mod loader isn't installed, or the game is elsewhere (set MP_GAME_DIR, or put MP_GAME_DIR=\"<folder>\" in tools/local.env)"
mkdir -p "$LOGS"

case "${1:-}" in
  install)
    for m in cl_playtest offline_bots; do
      [ -f "$GAME/mods/$m/.installed_by_selftest" ] && die "$GAME/mods/$m is left from a killed self-test or launch; any tools/run_selftest.sh run removes it"
      [ -e "$GAME/mods/$m" ] && die "$GAME/mods/$m already exists; run '$0 remove' or move it aside first"
    done
    [ -f "$COMPAT/offline_bots/bot_manager.gd" ] || die "no Offline Bots in $COMPAT/offline_bots"
    [ -e "$CONFIG_KEPT" ] || [ -e "$CONFIG_ABSENT" ] \
      && die "a previous playtest's Offline Bots config was never put back; run '$0 remove' first"
    if [ -f "$CONFIG" ]; then
      cp "$CONFIG" "$CONFIG_KEPT" || die "could not keep a copy of $CONFIG"
    else
      touch "$CONFIG_ABSENT" || die "could not write to $LOGS"
    fi
    saves_list > "$BEFORE" || die "could not read $SAVES"
    if ! cp -r "$REPO/tools/selftest/cl_playtest" "$GAME/mods/cl_playtest"; then
      [ -d "$GAME/mods/cl_playtest" ] && touch "$GAME/mods/cl_playtest/$MARK"
      echo "could not install cl_playtest; removing the playtest" >&2
      "$0" remove
      exit 2
    fi
    touch "$GAME/mods/cl_playtest/$MARK"
    shift
    if [ $# -gt 0 ]; then
      if ! printf '%s\n' "$@" > "$GAME/mods/cl_playtest/playlist.txt"; then
        echo "could not write the playlist; removing the playtest" >&2
        "$0" remove
        exit 2
      fi
      echo "playlist: $*"
    fi
    if make_bots "$GAME/mods"; then
      touch "$GAME/mods/offline_bots/$MARK"
    else
      touch "$GAME/mods/offline_bots/$MARK" 2>/dev/null
      echo "Offline Bots' caps or overrides were not where expected; removing the playtest" >&2
      "$0" remove
      exit 2
    fi
    echo "installed: cl_playtest, offline_bots (8 seats / 7 bots, bots keep their split-screen tiles)"
    echo "mods: $(ls "$GAME/mods" | tr '\n' ' ')"
    echo "Play: join with only your pad, pick your outfit, ready up; bots fill the free seats. Afterwards: $0 remove"
    ;;
  remove)
    removed=0
    for m in cl_playtest offline_bots; do
      if [ -f "$GAME/mods/$m/$MARK" ]; then
        rm -rf "${GAME:?}/mods/${m:?}" && echo "removed $m" && removed=1
      elif [ -e "$GAME/mods/$m" ]; then
        echo "kept $GAME/mods/$m: not installed by this script"
      fi
    done
    if [ -f "$CONFIG_KEPT" ]; then
      cp "$CONFIG_KEPT" "$CONFIG" && rm -f "$CONFIG_KEPT" && echo "put back offline_bots_config.json as it was before the playtest"
    elif [ -f "$CONFIG_ABSENT" ]; then
      rm -f "$CONFIG" "$CONFIG_ABSENT" && echo "offline_bots_config.json: none before the playtest, none now"
    fi
    if [ -f "$BEFORE" ]; then
      after="$(saves_list)"
      if [ "$(cat "$BEFORE")" = "$after" ]; then
        echo "saves folder unchanged"
      else
        echo "saves folder changed during the playtest (before | after):"
        diff <(cat "$BEFORE") <(echo "$after")
      fi
      rm -f "$BEFORE"
    fi
    [ "$removed" = 1 ] || echo "nothing of the playtest was installed"
    echo "mods: $(ls "$GAME/mods" | tr '\n' ' ')"
    ;;
  launch)
    shift
    minigame="${1:-}"
    [[ "$minigame" =~ ^[A-Za-z0-9_]+$ ]] || die "usage: $0 launch <Minigame> [--split | --local] [--bots N] [--overtime=fork|stock|mp8|none] [--compat] [--auto N [--drop S] [--stall S] [--grace S]] [--record <file.avi|file.png> [--fps N]] [--resolution WxH] [--look hi] [--difficulty easy|normal|hard] [--extra <mod dir>]... [--shot <id>]"
    shift
    mode=split bots=7 ot=fork mp8= compat=() extra=() res=() auto= drop= stall= grace= auto_set= drop_set= stall_set= grace_set= record= fps= look= difficulty= shot= shot_log=
    while [ $# -gt 0 ]; do
      case "$1" in
        --split) mode=split ;;
        --local) mode=local ;;
        --bots) bots="${2:-}"; shift ;;
        --bots=*) bots="${1#--bots=}" ;;
        --overtime=fork|--overtime=stock|--overtime=mp8|--overtime=none) ot="${1#--overtime=}" ;;
        --compat) compat=(--compat) ;;
        --auto) auto="${2:-}"; auto_set=1; [ $# -gt 1 ] && shift ;;
        --drop) drop="${2:-}"; drop_set=1; [ $# -gt 1 ] && shift ;;
        --stall) stall="${2:-}"; stall_set=1; [ $# -gt 1 ] && shift ;;
        --grace) grace="${2:-}"; grace_set=1; [ $# -gt 1 ] && shift ;;
        --record) record="${2:-}"; [ $# -gt 1 ] && shift; [ -n "$record" ] || die "--record: an .avi or .png file" ;;
        --look) look="${2:-}"; [ $# -gt 1 ] && shift; [ "$look" = hi ] || die "--look: hi, not '$look'" ;;
        --fps) fps="${2:-}"; [ $# -gt 1 ] && shift; [[ "$fps" =~ ^[1-9][0-9]*$ ]] || die "--fps: frames a second, not '$fps'" ;;
        --resolution) [[ "${2:-}" =~ ^[0-9]+x[0-9]+$ ]] || die "--resolution: WxH, not '${2:-}'"; res=("--resolution=$2"); shift ;;
        --extra) [ -f "${2:-}/mod.json" ] || die "--extra: not a mod folder: '${2:-}'"; extra+=("$2"); shift ;;
        --difficulty) difficulty="${2:-}"; [ $# -gt 1 ] && shift; [[ "$difficulty" =~ ^(easy|normal|hard)$ ]] || die "--difficulty: easy, normal or hard, not '$difficulty'" ;;
        --shot) shot="${2:-}"; [ $# -gt 1 ] && shift; [ -n "$shot" ] || die "--shot: a shot id from tools/trailer_cast/trailer.json" ;;
        *) die "launch: unknown option $1" ;;
      esac
      shift
    done
    [ -z "$auto_set" ] || [[ "$auto" =~ ^[1-9][0-9]*$ ]] || die "--auto: a number of minigame loads, not '$auto'"
    [ -z "$drop_set" ] || [[ "$drop" =~ ^[1-9][0-9]*$ ]] || die "--drop: seconds into the match, not '$drop'"
    [ -z "$drop_set" ] || [ -n "$auto_set" ] || die "--drop works only with --auto"
    [ -z "$stall_set" ] || [[ "$stall" =~ ^[1-9][0-9]*$ ]] || die "--stall: seconds without a new load, not '$stall'"
    [ -z "$stall_set" ] || [ -n "$auto_set" ] || die "--stall works only with --auto"
    [ -z "$grace_set" ] || [[ "$grace" =~ ^[0-9]+$ ]] || die "--grace: seconds after the last load, not '$grace'"
    [ -z "$grace_set" ] || [ -n "$auto_set" ] || die "--grace works only with --auto"
    [ -z "$fps" ] || [ -n "$record" ] || die "--fps works only with --record"
    if [ -n "$shot" ]; then
      [ -f "$REPO/tools/trailer_cast/trailer.json" ] || die "--shot: tools/trailer_cast is not in this clone (the trailer's tools are not published)"
      # A shot for another minigame would record a whole take with no camera, choreography or hiding.
      shot_for="$("$(find_python)" -c 'import json,sys; s=json.load(open(sys.argv[1]))["shots"].get(sys.argv[2]); print(s.get("minigame","") if isinstance(s,dict) else "")' "$(cygpath -w "$REPO/tools/trailer_cast/trailer.json")" "$shot")"
      [ -n "$shot_for" ] || die "--shot: no shot '$shot' under \"shots\" in tools/trailer_cast/trailer.json"
      [ "${shot_for,,}" = "${minigame,,}" ] || die "--shot $shot is for $shot_for, not $minigame"
      extra+=("$REPO/tools/trailer_cast")
      [ -z "$record" ] || shot_log="$(cygpath -w "$(cd "$(dirname "$record")" && pwd)")\events.csv"
    fi
    [ -z "$look" ] || [ -z "$record" ] || die "--look hi can't be recorded (Movie Maker keeps a 960x540 corner); set MP_LOOK_STILLS=<dir> instead"
    [[ "$bots" =~ ^[1-7]$ ]] || die "--bots: 1 to 7 (a session of one ends at once), not '$bots'"
    case "$ot" in
      fork)
        fork="${MP_OVERTIME_FORK:-}"
        if [ -z "$fork" ]; then
          best=-1
          for d in "$REPO"/../MachineParty-Overtime/dist/mpml-fork-b*/overtime; do
            n="${d%/overtime}"; n="${n##*mpml-fork-b}"
            [[ "$n" =~ ^[0-9]+$ ]] && [ -f "$d/mod.json" ] && [ "$n" -gt "$best" ] && best="$n" && fork="$(cd "$d" && pwd)"
          done
        fi
        [ -n "$fork" ] || die "--overtime=fork: no ../MachineParty-Overtime/dist/mpml-fork-b<N>/overtime build; set MP_OVERTIME_FORK"
        ot_flags=(--overtime=fork) ;;
      stock)
        fork="$GAME/overtime_stock_1.7"
        [ -f "$fork/overtime_overlay.zip" ] || die "--overtime=stock: no parked stock Overtime at $fork"
        [ -f "$COMPAT/overtime_mpml.zip" ] || die "--overtime=stock: no $COMPAT/overtime_mpml.zip to tell whether $fork is stock"
        have_ot="$(sha256sum < "$fork/overtime_overlay.zip" | cut -c1-64)"
        want_ot="$(unzip -p "$COMPAT/overtime_mpml.zip" overtime/overtime_overlay.zip | sha256sum | cut -c1-64)"
        [ "$have_ot" = "$want_ot" ] || die "$fork is not the stock release in $COMPAT/overtime_mpml.zip (overlay ${have_ot:0:12})"
        ot_flags=(--overtime=fork) ;;
      mp8)
        mp8="${MP_MP8_BUILD:-}"
        if [ -z "$mp8" ]; then
          best=-1
          for d in "$REPO"/extended/dist/mp8-b*/mp8_support; do
            n="${d%/mp8_support}"; n="${n##*mp8-b}"
            [[ "$n" =~ ^[0-9]+$ ]] && [ -f "$d/mod.json" ] && [ "$n" -gt "$best" ] && best="$n" && mp8="$(cd "$d" && pwd)"
          done
        fi
        [ -n "$mp8" ] || die "--overtime=mp8: no extended/dist/mp8-b<N>/mp8_support build; set MP_MP8_BUILD"
        fork=""
        ot_flags=(--overtime=mp8) ;;
      none)
        fork=""
        ot_flags=(--no-overtime)
        [ "$bots" -gt 3 ] && echo "without Overtime the lobby has 4 seats: 3 bots, not $bots" && bots=3 ;;
    esac
    scratch="$LOGS/launch-bots-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$scratch" || die "could not make $scratch"
    keep=
    [ "$mode" = local ] && keep=keep
    make_bots "$scratch" $keep || die "Offline Bots' caps or overrides were not where expected; $scratch/offline_bots is incomplete"
    perf_dir="${TEMP:-/tmp}/machine-party-tests/launch"
    mkdir -p "$perf_dir"
    touch "$scratch/started"
    echo "launch: $minigame, $mode, $bots bots${difficulty:+ ($difficulty)}, overtime $ot${fork:+ ($fork)}${mp8:+ ($mp8)}${compat[*]:+, compat set}"
    MP_LAUNCH="minigame=$minigame;mode=$mode;bots=$bots${auto:+;auto=$auto}${drop:+;drop=$drop}${stall:+;stall=$stall}${grace:+;grace=$grace}${look:+;look=$look}${difficulty:+;difficulty=$difficulty}" MP_OVERTIME_FORK="$fork" MP_MP8_BUILD="$mp8" \
      MP_TRAILER_SHOT="$shot" MP_TRAILER_LOG="$shot_log" \
      bash "$REPO/tools/run_selftest.sh" cl_playtest --windowed --play ${record:+"--movie=$record"} ${fps:+"--movie-fps=$fps"} "${res[@]}" "${ot_flags[@]}" "${compat[@]}" "$scratch/offline_bots" "${extra[@]}"
    rc=$?
    csv="$(find "$perf_dir" -maxdepth 1 -name '*.csv' -newer "$scratch/started" | sort | tail -1)"
    if [ -n "$csv" ] && [ -f "$REPO/tools/perf_summary.py" ]; then
      "$(find_python)" "$REPO/tools/perf_summary.py" "$csv"
    elif [ -n "$csv" ]; then
      echo "frame log: $csv"
    else
      echo "no frame log in $perf_dir from this run"
    fi
    exit "$rc"
    ;;
  *) die "usage: $0 install [minigame ...] | remove | copy <dir> [--local] | launch <Minigame> [options]" ;;
esac
