#!/usr/bin/env bash
# Runs one self-test mod (headless unless --windowed) against the installed game, with this repo's
# mods freshly copied in, then removes the test mod again. Run it from Git Bash
# with a tool timeout above 180 s: a killed shell skips the cleanup below, and the
# next run removes what it left. --play has no time limit: run it in the background.
#
#   tools/run_selftest.sh <test_id> [--compat] [--no-overtime | --overtime=stock|fork|mp8] [--without=<id>] [--mods-from=<dir>] [--windowed] [--play] [--movie=<file.avi|file.png>] [--movie-fps=N] [--resolution=WxH] [extra mod dir...]
#
#   <test_id>      a folder in tools/selftest/ (gcs_selftest, cl_selftest, xc_selftest, mp8_selftest, xc_recon, xc_render, xc_screen, cl_recon, cl_render, cl_after, cl_hud, cl_portrait)
#   --compat       also install every mod in $MP_COMPAT_DIR (Offline Bots, FPV, MachineParty+)
#   --no-overtime  park <game>/mods/overtime outside the game for the run
#   --overtime=fork  park it and run the owner's fork build instead ($MP_OVERTIME_FORK); stock is the default
#   --overtime=mp8   park it and run 8 Player Support ($MP_MP8_BUILD, a extended/dist/<build>/mp8_support folder)
#                  It is installed under its own folder's name (a bundle's is machine_party_extended), and every
#                  installed folder whose mod.json id is mp8_support is parked in every run: it never mounts beside Overtime.
#                  So is an installed mods/local_glasses: Better Couch Lobby replaces it, and both would add a glasses row.
#   --without=<id> leave our mods/<id> out (refuses if the owner has it installed)
#   --mods-from=<dir>  a release zip extracted as-is (make_release.ps1 -Extract): each of our mods in <dir> is
#                  installed from there, the others from mods/ (--without=<id> leaves one out); refuses a <dir> with
#                  none of them. A bundle is one folder of id mp8_support with our mods inside, which its main.gd starts:
#                  it needs --overtime=mp8 and no MP_MP8_BUILD, and the owner's own copies of the mods it
#                  holds are parked for the run, since the bundle's stand down beside them.
#                  A mod the owner had stays installed as the zip's copy, with its README.txt and licence
#   --windowed     launch with a window (renders), on the screen left of the primary (tools/selftest/window_place;
#                  MP_WINDOW_SCREEN=primary keeps it there). Without --play it can't take focus back
#                  (MP_WINDOW_FOCUS=none); with --play it keeps focus (keep), unless MP_WINDOW_FOCUS says otherwise
#   --play         the owner plays (run_playtest.sh launch): no 180 s limit, the run ends when the game exits,
#                  and a save or config that changed is a NOTE, not a failure (play may save settings)
#   --movie=<file.avi>  windowed, recorded by Godot's Movie Maker at a fixed frame rate, with sound (run_playtest.sh
#                  launch --record), at 960x540: the game draws at that size and scales it up (stretch mode viewport).
#                  The game runs as fast as it can render, not in real time, so frame times are not real
#                  A .png path is Movie Maker's lossless writer instead: one PNG per frame beside a WAV of the sound
#                  (tools/trailer_pack.sh packs them); an .avi is MJPEG, lossy and capped at 4 GB
#   --movie-fps=N  Movie Maker's fixed frame rate (default 30)
#   --resolution=WxH  the window's size (windowed runs)
#   mod dir        installed for the run; one named like a mod of the compat set replaces that mod
#   MP_GAME_ARGS   extra arguments for the game itself, space-separated (8 Player Support's dev switches,
#                  such as mp8junkcouch=34,18,25, which only a -test build reads); run_playtest.sh launch passes it through
#
# Exits 0 only when the test printed "DONE fails=0" and no save or config changed (--play: whatever changed).
# Refuses while the game is open (the owner may be in a match), and refuses to
# replace a mod the owner already has installed under an extra's name.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Steam's default library. A game in another library: MP_GAME_DIR, or the same line in tools/local.env (gitignored).
[ -z "${MP_GAME_DIR:-}" ] && [ -f "$REPO/tools/local.env" ] && . "$REPO/tools/local.env"
# Notepad saves CRLF, which would leave a carriage return on the path.
[ -n "${MP_GAME_DIR:-}" ] && MP_GAME_DIR="${MP_GAME_DIR%$'\r'}"
GAME="${MP_GAME_DIR:-/c/Program Files (x86)/Steam/steamapps/common/party project/Machine Party_Windows}"
COMPAT="${MP_COMPAT_DIR:-$USERPROFILE/Documents/Modding/machine-party-compat}"
# No default: the fork's build script never overwrites a candidate, so each build has its own folder and a default goes stale.
FORK="${MP_OVERTIME_FORK:-}"
MP8="${MP_MP8_BUILD:-}"
SAVES="$APPDATA/Godot/app_userdata/Machine Party"
LOGS="${MP_LOG_DIR:-${TEMP:-/tmp}/machine-party-tests}"
# Next to mods/ on the same drive, so parking is a rename; the loader reads only mods/.
PARK="$GAME/mods_parked_by_selftest"
NAME='^[A-Za-z0-9_]+$'
# Extended's folder is found by its id: a build's is mp8_support, a bundle's machine_party_extended.
EXT_ID='"id": *"mp8_support"'
ext_folders() { local f; for f in "$1"/*/mod.json; do [ -f "$f" ] && grep -q "$EXT_ID" "$f" && basename "$(dirname "$f")"; done; }

die() { echo "$1" >&2; exit "${2:-2}"; }

# A tasklist that fails counts as "running": the check must fail closed.
game_running() {
  local out
  out="$(tasklist //NH //FO CSV //FI "IMAGENAME eq Machine Party.exe" 2>&1)" || return 0
  case "$out" in *'"Machine Party.exe"'*) return 0 ;; esac
  return 1
}

# Configs a run may write: Offline Bots' bot count.
CONFIGS=(offline_bots_config.json)
CONFIG_PENDING="$LOGS/selftest_configs"
# Puts each config back as the run found it (absent included), then drops the copies.
restore_config() {
  local c
  for c in "${CONFIGS[@]}"; do
    if [ -f "$CONFIG_PENDING/$c" ]; then
      cmp -s "$CONFIG_PENDING/$c" "$SAVES/$c" || { cp "$CONFIG_PENDING/$c" "$SAVES/$c" && echo "put back $c"; }
    elif [ -f "$CONFIG_PENDING/$c.absent" ] && [ -f "$SAVES/$c" ]; then
      rm -f "$SAVES/$c" && echo "removed the $c the run left"
    fi
  done
  rm -rf "$CONFIG_PENDING"
}

test_id="${1:-}"
[[ "$test_id" =~ $NAME ]] && [ -d "$REPO/tools/selftest/$test_id" ] || die "usage: $0 <test_id> [--compat] [--no-overtime | --overtime=stock|fork|mp8] [--without=<id>] [--windowed] [--play] [mod dir...]; tests: $(ls "$REPO/tools/selftest")"
shift
extras=()
compats=()
withouts=()
park_overtime=0
fork=0
mp8=0
stock=0
modes=0
play=0
headless=--headless
movie=()
movie_fps=30
res=()
from=""
for a in "$@"; do
  case "$a" in
    --compat)
      for d in "$COMPAT"/*/; do [ -f "$d/mod.json" ] && compats+=("${d%/}"); done
      [ "${#compats[@]}" -gt 0 ] || die "--compat: no mods in $COMPAT (set MP_COMPAT_DIR)" ;;
    --no-overtime) park_overtime=1; modes=$((modes + 1)) ;;
    --overtime=stock) stock=1; modes=$((modes + 1)) ;;
    --overtime=fork) fork=1; modes=$((modes + 1)) ;;
    --overtime=mp8) mp8=1; modes=$((modes + 1)) ;;
    --overtime=*) die "--overtime: stock, fork or mp8, not ${a#--overtime=}" ;;
    --without=*)
      w="${a#--without=}"
      [[ "$w" =~ $NAME ]] && [ -d "$REPO/mods/$w" ] || die "--without: not one of our mods: $w (mods/: $(cd "$REPO/mods" && ls -d */ | tr -d / | tr '\n' ' '))"
      withouts+=("$w") ;;
    --mods-from=*)
      from="${a#--mods-from=}"
      [ -d "$from" ] || die "--mods-from: not a folder: $from"
      from="$(cd "$from" && pwd)" ;;
    --windowed) headless= ;;
    --resolution=*)
      [[ "${a#--resolution=}" =~ ^[0-9]+x[0-9]+$ ]] || die "--resolution: WxH, not '${a#--resolution=}'"
      res=(--resolution "${a#--resolution=}") ;;
    --play) play=1 ;;
    --movie=*)
      m="${a#--movie=}"
      [[ "$m" == *.avi || "$m" == *.png ]] && [ -d "$(dirname "$m")" ] || die "--movie: an .avi or .png file in an existing folder, not '$m'"
      # The game starts in its own folder, so the movie path must be absolute, and Windows-style for Godot.
      movie=(--write-movie "$(cygpath -w "$(cd "$(dirname "$m")" && pwd)/$(basename "$m")")")
      headless= ;;
    --movie-fps=*)
      movie_fps="${a#--movie-fps=}"
      [[ "$movie_fps" =~ ^[1-9][0-9]*$ ]] || die "--movie-fps: frames a second, not '$movie_fps'" ;;
    *) [ -f "$a/mod.json" ] || die "not a mod folder: $a"; extras+=("${a%/}") ;;
  esac
done
[ ${#movie[@]} -gt 0 ] && movie+=(--fixed-fps "$movie_fps")
if [ -z "$headless" ]; then
  extras+=("$REPO/tools/selftest/window_place")
  [ ${#res[@]} -gt 0 ] && export MP_WINDOW_KEEP_SIZE=1
  [ "$play" = 1 ] && export MP_WINDOW_FOCUS="${MP_WINDOW_FOCUS:-keep}" || export MP_WINDOW_FOCUS="${MP_WINDOW_FOCUS:-none}"
fi
# Two folders of one name would be copied over each other; the one given by path is the one meant.
for c in "${compats[@]}"; do
  given=""
  for x in "${extras[@]}"; do [ "$(basename "$x")" = "$(basename "$c")" ] && given="$x"; done
  if [ -n "$given" ]; then
    echo "NOTE --compat: $(basename "$c") from $given, not the compat set's"
  else
    extras+=("$c")
  fi
done
for x in "${extras[@]}"; do
  [[ "$(basename "$x")" =~ $NAME ]] || die "bad mod folder name: $x"
done
[ "$modes" -le 1 ] || die "--no-overtime and --overtime=stock|fork|mp8: pick one"
if [ "$fork" = 1 ]; then
  [ -n "$FORK" ] || die "--overtime=fork: set MP_OVERTIME_FORK to the fork's MPML build (<fork>/dist/<candidate>/overtime)"
  [ -f "$FORK/mod.json" ] && [ -f "$FORK/overtime_overlay.zip" ] || die "no fork build at $FORK"
  park_overtime=1
fi
# Our mods inside a bundle's Extended folder, started by its main.gd rather than installed on their own.
hosted=()
if [ -n "$from" ]; then
  bundle="$(ext_folders "$from" | head -1)"
  found=0
  for m in "$REPO"/mods/*/; do
    b="$(basename "$m")"
    [ -f "$from/$b/mod.json" ] && found=1
    [ -n "$bundle" ] && [ -f "$from/$bundle/$b/mod.json" ] && found=1 && hosted+=("$b")
  done
  [ "$found" = 1 ] || die "--mods-from: $from holds none of our mods (an extracted zip's own folder, such as <dir>/BetterCouchLobby-<v>)"
  if [ ${#hosted[@]} -gt 0 ]; then
    [ "$mp8" = 1 ] || die "--mods-from: $from is a bundle ($bundle with ${hosted[*]} inside); pass --overtime=mp8"
    [ -z "$MP8" ] || die "--mods-from: $from is a bundle; unset MP_MP8_BUILD ($MP8), or its own $bundle and the mods inside it never run"
    for w in "${withouts[@]}"; do [[ " ${hosted[*]} " == *" $w "* ]] && die "--without=$w: the bundle holds $w inside $bundle"; done
    MP8="$from/$bundle"
  elif [ "$mp8" = 1 ] && [ -n "$bundle" ]; then
    if [ -z "$MP8" ]; then MP8="$from/$bundle"; else echo "NOTE --mods-from: MP_MP8_BUILD ($MP8) runs, not the bundle's own $bundle"; fi
  fi
fi
if [ "$mp8" = 1 ]; then
  [ -n "$MP8" ] || die "--overtime=mp8: set MP_MP8_BUILD to an 8 Player Support build (extended/dist/<build>/mp8_support)"
  [ -f "$MP8/mod.json" ] && [ -f "$MP8/mp8_support_overlay.zip" ] || die "no 8 Player Support build at $MP8"
  # A second Extended folder beside it is mp8_selftest's two-folder lane; only a clash of names is refused.
  for x in "${extras[@]}"; do
    grep -q "$EXT_ID" "$x/mod.json" || continue
    [ "$(basename "$x")" = "$(basename "$MP8")" ] && die "--overtime=mp8 and an extra Extended folder of the same name ($x): pick one"
    echo "NOTE two Extended folders: $(basename "$MP8") from $MP8 and $(basename "$x") from $x"
  done
  park_overtime=1
fi

[ -f "$GAME/Machine Party.exe" ] || die "game not found at $GAME (set MP_GAME_DIR, or put MP_GAME_DIR=\"<folder>\" in tools/local.env)"
echo "game: $GAME"
[ -d "$GAME/mods" ] || die "$GAME/mods missing: the mod loader isn't installed, or mods/ was renamed"
game_running && die "Machine Party is running (or tasklist failed); not touching it. Close the game first." 3
# A Steam verify or a game update puts back the vanilla pck: the loader is gone, no mod loads, and a run ends in NO RESULT.
record="$GAME/Machine Party.pck.modloader.json"
want="$(grep -o '"patched_size": *[0-9]*' "$record" 2>/dev/null | grep -o '[0-9]*$')"
have="$(stat -c %s "$GAME/Machine Party.pck")"
[ -n "$want" ] && [ "$have" = "$want" ] || die "Machine Party.pck is $have bytes, the loader's record says ${want:-nothing}: the loader isn't in the pck. Rerun MachinePartyModLoader.exe."

# The sweep below would take cl_playtest and leave its raised Offline Bots behind.
ls "$GAME"/mods/*/.installed_by_playtest >/dev/null 2>&1 && die "a bot playtest is installed; run tools/run_playtest.sh remove first"
# Leftovers from a run that was killed before its cleanup.
for d in "$REPO"/tools/selftest/*/ "$REPO/tools/joyprobe/lg_joyprobe/"; do
  b="$(basename "$d")"
  if [ -d "$GAME/mods/$b" ]; then
    mkdir -p "$LOGS"
    [ -f "$GAME/mods/$b/result.txt" ] && cp "$GAME/mods/$b/result.txt" "$LOGS/leftover_${b}_$(date +%Y%m%d-%H%M%S).txt" \
      && echo "saved the leftover $b/result.txt to $LOGS"
    rm -rf "${GAME:?}/mods/${b:?}" && echo "removed leftover dev mod: $b"
  fi
done
# Every mod a run installs carries this marker (ours, the fork build, extras such as the raised
# Offline Bots); the owner's own copies never do, so a killed run's leftovers go here.
for d in "$GAME"/mods/*/; do
  b="$(basename "$d")"
  [ -f "$GAME/mods/$b/.installed_by_selftest" ] && rm -rf "${GAME:?}/mods/${b:?}" && echo "removed leftover mod: $b"
done
# Offline Bots writes its config whenever bots are seated; a killed run's copies are put back here.
[ -e "$CONFIG_PENDING" ] && echo "a killed run kept copies of the configs:" && restore_config
# Overtime and 8 Player Support replace the same game scripts; a run parks whichever the lane doesn't want.
# Local Glasses, folded into Better Couch Lobby, is parked in every run, and a bundle run parks
# the owner's copies of the mods it holds.
for d in "$PARK"/*/; do
  ot="$(basename "$d")"
  if [ -d "$PARK/$ot" ]; then
    [ -e "$GAME/mods/$ot" ] && die "both $GAME/mods/$ot and a parked copy in $PARK/$ot exist; keep one and delete the other"
    mv "$PARK/$ot" "$GAME/mods/$ot" || die "could not restore $ot from $PARK"
    echo "restored $ot parked by an earlier run"
  fi
done
rmdir "$PARK" 2>/dev/null
if [ "$park_overtime" = 0 ] && [ ! -d "$GAME/mods/overtime" ]; then
  [ "$stock" = 1 ] && die "--overtime=stock: $GAME/mods/overtime is not installed"
  echo "NOTE no $GAME/mods/overtime: this run is without Overtime"
fi
# The fork may be installed for play; a "stock" run on it would pass under the wrong label.
if [ "$park_overtime" = 0 ] && [ -f "$GAME/mods/overtime/overtime_overlay.zip" ]; then
  have_ot="$(sha256sum < "$GAME/mods/overtime/overtime_overlay.zip" | cut -c1-64)"
  if [ -f "$COMPAT/overtime_mpml.zip" ]; then
    want_ot="$(unzip -p "$COMPAT/overtime_mpml.zip" overtime/overtime_overlay.zip | sha256sum | cut -c1-64)"
    [ "$have_ot" = "$want_ot" ] || die "$GAME/mods/overtime is not the stock release in $COMPAT/overtime_mpml.zip (overlay ${have_ot:0:12}); put stock back, or run --overtime=fork"
    echo "overtime: stock, as released"
  else
    echo "NOTE overtime overlay ${have_ot:0:12}: no $COMPAT/overtime_mpml.zip to tell whether it is stock"
  fi
fi
for x in "${extras[@]}"; do
  b="$(basename "$x")"
  # An installed Extended is always parked before extras go in, and so are a bundle's mods.
  grep -q "$EXT_ID" "$x/mod.json" && [ -n "$(ext_folders "$GAME/mods" | grep -x "$b")" ] && continue
  [[ " ${hosted[*]} " == *" $b "* ]] && continue
  [ -e "$GAME/mods/$b" ] && die "$GAME/mods/$b is already installed; a run would replace and then delete it. Move it out first."
done
for w in "${withouts[@]}"; do
  [ -e "$GAME/mods/$w" ] && die "--without=$w: $GAME/mods/$w is installed; move it out of mods/ first"
done

mkdir -p "$LOGS"
rm -rf "$CONFIG_PENDING" && mkdir -p "$CONFIG_PENDING" || die "could not make $CONFIG_PENDING"
for c in "${CONFIGS[@]}"; do
  if [ -f "$SAVES/$c" ]; then cp "$SAVES/$c" "$CONFIG_PENDING/$c" || die "could not keep a copy of $SAVES/$c"; else touch "$CONFIG_PENDING/$c.absent"; fi
done
before="$(md5sum "$SAVES"/*.save "$SAVES"/*.json 2>/dev/null)"
[ -n "$before" ] || die "no saves found in $SAVES"
for f in "$REPO"/.save-backup/*.save; do
  [ -f "$f" ] && ! cmp -s "$f" "$SAVES/$(basename "$f")" && echo "NOTE save differs from .save-backup before the run: $(basename "$f")"
done

installed=()
parked=()
launched=0
cleanup() {
  for m in "${installed[@]}"; do rm -rf "${GAME:?}/mods/${m:?}"; done
  # A run that died before the game started changed nothing; its copy would only revert later writes.
  [ "$launched" = 0 ] && rm -rf "$CONFIG_PENDING"
  for ot in "${parked[@]}"; do
    [ -d "$PARK/$ot" ] || continue
    if [ -e "$GAME/mods/$ot" ]; then
      echo "NOT restoring $ot: $GAME/mods/$ot exists; the parked copy is in $PARK" >&2
    elif mv "$PARK/$ot" "$GAME/mods/$ot"; then
      echo "$ot restored"
    else
      echo "could not restore $ot; it is in $PARK" >&2
    fi
  done
  rmdir "$PARK" 2>/dev/null
}
trap cleanup EXIT

# Parked before anything is installed, so a build passed as an extra mod dir is never parked.
to_park=(local_glasses "${hosted[@]}")
mapfile -t ext_installed < <(ext_folders "$GAME/mods")
to_park+=("${ext_installed[@]}")
[ "$park_overtime" = 1 ] && to_park+=(overtime)
for ot in "${to_park[@]}"; do
  [ -d "$GAME/mods/$ot" ] || continue
  [ -e "$PARK/$ot" ] && die "$PARK/$ot already exists; not parking over it"
  parked+=("$ot")
  mkdir -p "$PARK" && mv "$GAME/mods/$ot" "$PARK/$ot" || die "could not park $ot"
done

# Our own mods are replaced with the repo's copies. Those the owner already had
# stay installed afterwards; the others are removed with the test mod.
for m in "$REPO"/mods/*/; do
  m="$(basename "$m")"
  [[ " ${withouts[*]} " == *" $m "* ]] && continue
  if [[ " ${hosted[*]} " == *" $m "* ]]; then
    echo "$m: hosted in $MP8/$m"
    continue
  fi
  src="$REPO/mods/$m"
  if [ -n "$from" ]; then
    [ -f "$from/$m/mod.json" ] && src="$from/$m"
    echo "$m: from $src"
  fi
  if [ -d "$GAME/mods/$m" ]; then
    rm -rf "${GAME:?}/mods/${m:?}" && cp -r "$src" "$GAME/mods/$m" || die "could not install $m"
  else
    installed+=("$m")
    cp -r "$src" "$GAME/mods/$m" && touch "$GAME/mods/$m/.installed_by_selftest" || die "could not install $m"
  fi
done
# Tracked before the copy, so cleanup also removes a copy that failed halfway.
installed+=("$test_id")
cp -r "$REPO/tools/selftest/$test_id" "$GAME/mods/" || die "could not install $test_id"
for x in "${extras[@]}"; do
  b="$(basename "$x")"
  installed+=("$b")
  cp -r "$x" "$GAME/mods/" && touch "$GAME/mods/$b/.installed_by_selftest" || die "could not install $b"
done
if [ "$fork" = 1 ]; then
  installed+=(overtime)
  cp -r "$FORK" "$GAME/mods/overtime" && touch "$GAME/mods/overtime/.installed_by_selftest" || die "could not install the fork build"
  echo "overtime: the fork build from $FORK"
fi
if [ "$mp8" = 1 ]; then
  mp8_name="$(basename "$MP8")"
  installed+=("$mp8_name")
  cp -r "$MP8" "$GAME/mods/$mp8_name" && touch "$GAME/mods/$mp8_name/.installed_by_selftest" || die "could not install the 8 Player Support build"
  echo "$mp8_name: the 8 Player Support build from $MP8"
fi
for w in "${withouts[@]}"; do
  [ -e "$GAME/mods/$w" ] && die "--without=$w: $w is in $GAME/mods after install"
done
echo "mods: $(ls "$GAME/mods" | tr '\n' ' ')"

# The game sometimes segfaults on quit (exit 139) after the results are written.
limit=(timeout 180)
[ "$play" = 1 ] && limit=()
launched=1
read -r -a game_args <<< "${MP_GAME_ARGS:-}"
[ ${#game_args[@]} -gt 0 ] && echo "game args: ${game_args[*]}"
# A shipped Extended build reads none of its dev switches, so a render on one silently shows the defaults.
if [ "$mp8" = 1 ] && [[ " ${game_args[*]} " =~ \ (mp8[a-z]|-debug-tools|-trailer) ]] \
  && ! grep -q '"test_build": *true' "$MP8/BUILDINFO.json" 2>/dev/null; then
  echo "WARNING: $MP8 is not a test build: it ignores the dev switches in MP_GAME_ARGS (build_mpml_mod.ps1 -TestBuild)"
fi
(cd "$GAME" && "${limit[@]}" "./Machine Party.exe" $headless "${movie[@]}" "${res[@]}" "${game_args[@]}" > "$LOGS/stdout_$test_id.txt" 2>&1)
echo "exit=$?  log: $LOGS/stdout_$test_id.txt"
[ -z "$headless" ] && grep -E '^\[window_place\] (WARN|WINDOW)' "$LOGS/stdout_$test_id.txt" | awk '/WARN/ || !w++' | head -4
result="$GAME/mods/$test_id/result.txt"
if [ -f "$result" ]; then
  cp "$result" "$LOGS/result_$test_id.txt"
  grep -v "^PASS" "$result"
  echo "($(grep -c "^PASS" "$result") PASS lines hidden; full result: $LOGS/result_$test_id.txt)"
else
  echo "NO RESULT"
  grep -iE "SCRIPT ERROR|Parse Error|error" "$LOGS/stdout_$test_id.txt" | head -20
fi

after="$(md5sum "$SAVES"/*.save "$SAVES"/*.json 2>/dev/null)"
saves_ok=1
if [ "$before" != "$after" ]; then
  if [ "$play" = 1 ]; then
    echo "NOTE a save or config changed during play:"
  else
    saves_ok=0
    echo "WARN a save or config changed during the run:"
  fi
  diff <(echo "$before") <(echo "$after")
fi
if game_running; then
  echo "NOTE the game is open again; ${CONFIGS[*]} are left as they are, and the next run puts them back"
else
  restore_config
fi
grep -q "^DONE fails=0" "$result" 2>/dev/null && [ "$saves_ok" = 1 ]
