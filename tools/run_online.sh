#!/usr/bin/env bash
# Plays one online match between several game instances on this PC, over the game's own ENet debug lobby,
# headless, driven by the dev mod tools/selftest/net_peer. Each peer runs from its own folder beside the game
# (the exe, DLLs and pck hard-linked, so a peer costs no disk) with its own mods/ and its own user dir
# (override.cfg), so the owner's install, mods and saves are only read. Run it from Git Bash; a full
# playlist takes longer than a tool call allows, so run it in the background.
#
#   tools/run_online.sh <roles> [--minigames=A,B|all] [--cap=S] [--limit=S] [--spoof=<tag>] [--last=joined|spectator|refused:<Reason>]
#                       [--cast] [--window=<i> [--record=ddagrab:<file.mkv>|movie:<dir>/frame.png]]
#
#   <roles>      the peers, host first, comma-separated: ext (Machine Party: Extended, $MP_MP8_BUILD, plus the
#                driver) or van (the driver alone: the game's own scripts and wire). E.g. ext,van or van,van,van
#   --minigames  the playlist, by Globals.MinigameIdentifier name, 1 round each; all = the custom-game list.
#                The game picks their order at random
#   --cap        end the run this many seconds into a minigame that hasn't ended (players who press at random
#                never finish some, Firearm Factory among them); the run then passes as "capped"
#   --limit      seconds each peer may run before it gives up (default 1200)
#   --spoof=TAG  van peers send game_version+TAG, as Extended before 0.22 did (an old Extended joiner)
#   --last       what the last joiner should see (default joined); every other joiner must join. A reason
#                past the peer's own list (a vanilla peer refused with MP8RoomFull) reads reason_<n>
#   --cast       a trailer take (docs/plans/2026-10-31-trailer.md, D125): each seat is tools/trailer_cast/trailer.json's
#                cast, long name and outfit, and every peer gets mods/more_cosmetics (most of the cast's items)
#   --window=I   peer I (0 = host) runs windowed, borderless and on top, 960x540 at the desktop's (WIN_X, WIN_Y),
#                with the music bus muted; the rest stay headless
#   --record     the windowed peer's take, never overwriting one: ddagrab (real time, ffmpeg's Desktop
#                Duplication of the window into Ut Video, the game's sound recorded by the peer beside it as
#                <file>.wav) or movie (Movie Maker's PNGs and WAV at a fixed 60 fps; pack with tools/trailer_pack.sh)
#
# Pass: every expected join happened; no peer logged a multiplayer error outside the known vanilla ones
# (KNOWN below); every joined peer saw the same minigames load and the same scores at each briefing, and
# reached the session's end or the cap; no save of the owner's changed. Exits 0 on a pass.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Steam's default library. A game in another library: MP_GAME_DIR, or the same line in tools/local.env (gitignored).
[ -z "${MP_GAME_DIR:-}" ] && [ -f "$REPO/tools/local.env" ] && . "$REPO/tools/local.env"
# Notepad saves CRLF, which would leave a carriage return on the path.
[ -n "${MP_GAME_DIR:-}" ] && MP_GAME_DIR="${MP_GAME_DIR%$'\r'}"
GAME="${MP_GAME_DIR:-/c/Program Files (x86)/Steam/steamapps/common/party project/Machine Party_Windows}"
MP8="${MP_MP8_BUILD:-}"
SAVES="$APPDATA/Godot/app_userdata/Machine Party"
LOGS="${MP_LOG_DIR:-${TEMP:-/tmp}/machine-party-tests}/online"
# Beside the game on its drive: hard links can't cross drives. The loader reads mods/ beside the exe.
PEERS="$(dirname "$GAME")/mp_online_peers"
LINKED=("Machine Party.exe" "Machine Party.pck" libaudio_gate.windows.release.x86_64.dll
  libgodotsteam.windows.template_release.x86_64.dll steam-multiplayer-peer.windows.template_release.x86_64.dll steam_api64.dll)
# Multiplayer errors the game logs with no mod at all (van,van, 2026-10-29): a minigame node's path
# reaching a peer before it loads or after it leaves, a despawn of a node this peer never spawned (a
# minigame's teardown), and minigame_end_state.gd:28 sending update_playlist_state_rpc 1 of its 3 arguments.
# Extended's relay (mp8_net.gd) logs the first of these its own way; any other relay error fails.
KNOWN='\[MP8\] relay: no node Game/Minigame/|Node not found: "Game/Minigame/|Parameter "node" is null\.|Failed to get path from RPC: Game/Minigame/|Failed to get cached node from peer|Invalid packet received\. Requested node was not found\.|Condition "!pinfo\.recv_nodes\.has\(net_id\)" is true|update_playlist_state_rpc.: Method expected 3 argument\(s\), but called with 1'

die() { echo "$1" >&2; exit "${2:-2}"; }

# A tasklist that fails counts as "running": the check must fail closed.
game_running() {
  local out
  out="$(tasklist //NH //FO CSV //FI "IMAGENAME eq Machine Party.exe" 2>&1)" || return 0
  case "$out" in *'"Machine Party.exe"'*) return 0 ;; esac
  return 1
}

roles_arg="${1:-}"
[[ "$roles_arg" =~ ^(ext|van)(,(ext|van))+$ ]] || die "usage: $0 <roles: ext|van, host first, at least two> [--minigames=A,B|all] [--limit=S] [--spoof=<tag>] [--last=joined|spectator|refused:<Reason>]"
shift
IFS=, read -r -a roles <<< "$roles_arg"
[ "${#roles[@]}" -le 8 ] || die "at most 8 peers, not ${#roles[@]}"
minigames=all
cap=""
limit=1200
spoof=""
last=joined
cast=""
window=""
take=""
for a in "$@"; do
  case "$a" in
    --minigames=*) minigames="${a#--minigames=}" ;;
    --cap=*) cap="${a#--cap=}"; [[ "$cap" =~ ^[0-9]+$ ]] || die "--cap: seconds, not '$cap'" ;;
    --limit=*) limit="${a#--limit=}"; [[ "$limit" =~ ^[0-9]+$ ]] || die "--limit: seconds, not '$limit'" ;;
    --spoof=*) spoof="${a#--spoof=}"; [[ "$spoof" =~ ^[A-Za-z0-9.+-]+$ ]] || die "--spoof: a tag such as mp8-0.21, not '$spoof'" ;;
    --last=joined|--last=spectator|--last=refused:*) last="${a#--last=}" ;;
    --cast) cast=1 ;;
    --window=*) window="${a#--window=}"; [[ "$window" =~ ^[0-7]$ ]] || die "--window: a peer index 0-7, not '$window'" ;;
    --record=ddagrab:*.mkv|--record=movie:*/frame.png) take="${a#--record=}" ;;
    --record=*) die "--record: ddagrab:<file.mkv> or movie:<dir>/frame.png, not '${a#--record=}'" ;;
    *) die "unknown option: $a" ;;
  esac
done

[ -z "$window" ] || [ "$window" -lt "${#roles[@]}" ] || die "--window=$window: there are only ${#roles[@]} peers"
[ -z "$take" ] || [ -n "$window" ] || die "--record needs --window: only the windowed peer is recorded"
rec_kind="${take%%:*}"
rec_file="${take#*:}"
if [ -n "$take" ]; then
  # Absolute: the peer runs from its own folder, which the cleanup deletes.
  rec_file="$(cygpath -am "$rec_file")"
  [ ! -e "$rec_file" ] && [ ! -e "${rec_file%.mkv}.wav" ] || die "$rec_file (or its WAV) exists; a take is never overwritten"
  [ "$rec_kind" = movie ] && [ -n "$(ls "$(dirname "$rec_file")" 2>/dev/null)" ] && die "$(dirname "$rec_file") is not empty; Movie Maker writes frame00000000.png onward into it"
  mkdir -p "$(dirname "$rec_file")" || die "could not make $(dirname "$rec_file")"
fi
# Physical desktop pixels on the primary display, the same for the window and ddagrab's crop.
WIN_X="${WIN_X:-64}"
WIN_Y="${WIN_Y:-64}"

# Git Bash's python is often the Store's stub; the installer's copy is under LOCALAPPDATA.
find_python() {
  local p
  for p in "$LOCALAPPDATA"/Programs/Python/Python3*/python.exe; do [ -x "$p" ] && echo "$p" && return; done
  command -v py >/dev/null && echo py && return
  command -v python
}
# A WINDOW line from net_peer, against the primary screen's origin (Godot puts the desktop's top-left screen
# at 0, 0): the window must be 960x540 at (WIN_X, WIN_Y) on it, where ddagrab crops.
window_in_place() {
  [[ "$1" =~ at\ \(([-0-9]+),\ ([-0-9]+)\)\ pos=\(([-0-9]+),\ ([-0-9]+)\)\ size=\(960,\ 540\) ]] \
    && [ $((BASH_REMATCH[3] - BASH_REMATCH[1])) = "$WIN_X" ] && [ $((BASH_REMATCH[4] - BASH_REMATCH[2])) = "$WIN_Y" ]
}
names=() outfits=()
if [ -n "$cast" ]; then
  [ -f "$REPO/tools/trailer_cast/trailer.json" ] || die "--cast: tools/trailer_cast is not in this clone (the trailer's tools are not published)"
  # One "name|hat,glasses,suit" line a seat; the cast's "none" is the game's empty id.
  mapfile -t cast_rows < <("$(find_python)" -c 'import json,sys
for c in json.load(open(sys.argv[1]))["cast"]:
    g = "" if c["glasses"] == "none" else c["glasses"]
    print("%s|%s,%s,%s" % (c["long"], c["hat"], g, c["suit"]))' "$(cygpath -w "$REPO/tools/trailer_cast/trailer.json")" | tr -d '\r')
  [ "${#cast_rows[@]}" -ge "${#roles[@]}" ] || die "--cast: trailer.json has ${#cast_rows[@]} cast rows for ${#roles[@]} peers"
  for r in "${cast_rows[@]}"; do names+=("${r%%|*}"); outfits+=("${r#*|}"); done
  [ -f "$REPO/mods/more_cosmetics/mod.json" ] || die "--cast: mods/more_cosmetics not found"
fi

[ -f "$GAME/Machine Party.exe" ] || die "game not found at $GAME (set MP_GAME_DIR, or put MP_GAME_DIR=\"<folder>\" in tools/local.env)"
echo "game: $GAME"
game_running && die "Machine Party is running (or tasklist failed); not touching it. Close the game first." 3
record="$GAME/Machine Party.pck.modloader.json"
want="$(grep -o '"patched_size": *[0-9]*' "$record" 2>/dev/null | grep -o '[0-9]*$')"
have="$(stat -c %s "$GAME/Machine Party.pck")"
[ -n "$want" ] && [ "$have" = "$want" ] || die "Machine Party.pck is $have bytes, the loader's record says ${want:-nothing}: the loader isn't in the pck. Rerun MachinePartyModLoader.exe."
tag=""
if [[ " ${roles[*]} " == *" ext "* ]]; then
  [ -n "$MP8" ] && [ -f "$MP8/mod.json" ] && [ -f "$MP8/mp8_support_overlay.zip" ] || die "ext peers: set MP_MP8_BUILD to a build (extended/dist/<build>/mp8_support)"
  tag="$(grep -o '"mod_tag": *"[^"]*"' "$MP8/BUILDINFO.json" | grep -o 'mp8-[0-9.]*')"
  [ -n "$tag" ] || die "no mod_tag in $MP8/BUILDINFO.json"
fi

# Only peers this runner started: matched by their folder, never by the image name the owner's game shares.
stop_peers() {
  pwsh -NoProfile -Command "Get-Process 'Machine Party' -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like '$(cygpath -w "$PEERS")\\*' } | Stop-Process -Force" 2>/dev/null
}
remove_peers() {
  [ -d "$PEERS" ] && rm -rf "${PEERS:?}"
  for n in 1 2 3 4 5 6 7 8; do
    [ -d "$APPDATA/MachinePartyNetPeer$n" ] && rm -rf "${APPDATA:?}/MachinePartyNetPeer${n:?}"
  done
}
# A killed run's peers and user dirs are removed first (its processes would have failed game_running above).
[ -d "$PEERS" ] && echo "removing leftover peers in $PEERS"
remove_peers
run_id="$(date +%Y%m%d-%H%M%S)_${roles_arg//,/-}"
out="$LOGS/$run_id"
mkdir -p "$out" || die "could not make $out"
before="$(md5sum "$SAVES"/*.save "$SAVES"/*.json 2>/dev/null)"
[ -n "$before" ] || die "no saves found in $SAVES"

cleanup() {
  [ -n "$rec_pid" ] && { touch "$out/stop_rec"; wait "$rec_pid" 2>/dev/null; }
  rec_pid=""
  stop_peers
  remove_peers
}
rec_pid=""
trap cleanup EXIT

for i in "${!roles[@]}"; do
  d="$PEERS/p$i"
  mkdir -p "$d/mods" || die "could not make $d"
  for f in "${LINKED[@]}"; do ln "$GAME/$f" "$d/$f" || die "could not link $f into $d (same drive as the game?)"; done
  n=$((i + 1))
  printf '[application]\n\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="MachinePartyNetPeer%s"\n' "$n" > "$d/override.cfg"
  if [ "$i" = "$window" ]; then
    # Its fresh settings save says windowed, since the game's default is exclusive fullscreen over the whole
    # display (globals.gd load_settings, read key by key). The game still activates the window once at
    # startup, before any mod runs; no_focus keeps it from taking focus again once the owner clicks away.
    printf '\n[display]\n\nwindow/size/no_focus=true\nwindow/size/borderless=true\nwindow/size/always_on_top=true\n' >> "$d/override.cfg"
    mkdir -p "$APPDATA/MachinePartyNetPeer$n" && echo '{"fullscreen":false}' > "$APPDATA/MachinePartyNetPeer$n/machine_party_settings.save" \
      || die "could not write p$i's settings"
  fi
  # The user dir is fresh (remove_peers above): settings or a playlist saved by an earlier run would change this one.
  cp -r "$REPO/tools/selftest/net_peer" "$d/mods/" || die "could not install net_peer in $d"
  [ "${roles[$i]}" = ext ] && { cp -r "$MP8" "$d/mods/$(basename "$MP8")" || die "could not install $MP8 in $d"; }
  [ -n "$cast" ] && { cp -r "$REPO/mods/more_cosmetics" "$d/mods/" || die "could not install more_cosmetics in $d"; }
done
echo "peers: ${roles[*]} (host first) in $PEERS; playlist: $minigames; ${tag:+tag $tag; }${cast:+cast; }${window:+windowed p$window; }${take:+recording $take; }logs: $out"

seats=${#roles[@]}
hold=0
# A last joiner meant to be refused or seated as a spectator isn't waited for, but the lobby stays open
# long enough for it to try.
[ "$last" = joined ] || { seats=$((seats - 1)); hold=8; }
pids=()
for i in "${!roles[@]}"; do
  name="P$((i + 1))"
  [ -n "$cast" ] && name="${names[$i]}"
  if [ "$i" = 0 ]; then
    net="role=host;name=$name;seats=$seats;hold=$hold;minigames=$minigames;limit=$limit"
  else
    # Joiners go in seat order, a second and a half apart, so the last one really is last.
    net="role=join;name=$name;delay=$((3 + i * 3 / 2));limit=$limit"
  fi
  [ -n "$spoof" ] && [ "${roles[$i]}" = van ] && net="$net;spoof_tag=$spoof"
  [ -n "$cap" ] && net="$net;cap=$cap"
  [ -n "$cast" ] && net="$net;outfit=${outfits[$i]}"
  args=(--headless)
  if [ "$i" = "$window" ]; then
    args=()
    net="$net;window=$WIN_X,$WIN_Y;mute_music"
    [ "$rec_kind" = ddagrab ] && net="$net;audio_rec=$(cygpath -m "${rec_file%.mkv}.wav")"
    [ "$rec_kind" = movie ] && args=(--write-movie "$(cygpath -m "$rec_file")" --fixed-fps 60)
  fi
  (cd "$PEERS/p$i" && MP_NET="$net" timeout $((limit + 60)) "./Machine Party.exe" "${args[@]}" > "$out/p${i}_stdout.txt" 2>&1) &
  pids+=($!)
done
if [ "$rec_kind" = ddagrab ]; then
  # ddagrab crops the desktop, so it records only while the peer's window is there: from the lobby's WINDOW
  # line, if it has the window in place, until the peer logs END (it waits a second before quitting), goes
  # back to the main menu, or is gone. ffmpeg quits cleanly on the loop's 'q'; timeout bounds it if this
  # runner is killed. Its start is logged against the peer's u= times, which align the WAV.
  res="$PEERS/p$window/mods/net_peer/result.txt"
  wpid="${pids[$window]}"
  for _ in $(seq 120); do [ "$(grep -c ' WINDOW ' "$res" 2>/dev/null)" -ge 2 ] && break; sleep 0.5; done
  if ! window_in_place "$(grep ' WINDOW ' "$res" 2>/dev/null | sed -n 2p)"; then
    echo "p$window's window was not in place in the lobby; not recording: $(grep ' WINDOW ' "$res" 2>/dev/null | sed -n 2p)" > "$out/ffmpeg.txt"
  else
    date +%s.%N > "$out/rec_start_unix.txt"
    { while [ ! -e "$out/stop_rec" ] && kill -0 "$wpid" 2>/dev/null && ! grep -qE ' (END |SCENE MainMenu)' "$res" 2>/dev/null; do sleep 0.2; done; echo q; } \
      | timeout $((limit + 90)) ffmpeg -hide_banner -loglevel warning \
      -f lavfi -i "ddagrab=output_idx=0:draw_mouse=0:framerate=60:offset_x=$WIN_X:offset_y=$WIN_Y:video_size=960x540,hwdownload,format=bgra" \
      -c:v utvideo -pix_fmt gbrp "$rec_file" > "$out/ffmpeg.txt" 2>&1 &
    rec_pid=$!
  fi
fi
for p in "${pids[@]}"; do wait "$p" 2>/dev/null; done
if [ -n "$rec_pid" ]; then
  touch "$out/stop_rec"
  wait "$rec_pid" 2>/dev/null
  rec_pid=""
fi

fails=0
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
if [ -n "$window" ]; then
  win_line="$(grep ' WINDOW ' "$PEERS/p$window/mods/net_peer/result.txt" 2>/dev/null | tail -1)"
  if window_in_place "$win_line"; then
    echo "PASS p$window's window at ($WIN_X, $WIN_Y) on the primary screen, 960x540"
  else
    fail "p$window's window was not at ($WIN_X, $WIN_Y) 960x540 on the primary screen: ${win_line:-no WINDOW line}${rec_kind:+ (nothing was recorded unless the lobby's line was in place; check the take's frames)}"
  fi
fi
if [ "$rec_kind" = ddagrab ]; then
  [ -s "$rec_file" ] && echo "PASS recorded $rec_file (ffmpeg's log: $out/ffmpeg.txt)" || { fail "ddagrab wrote no take; $out/ffmpeg.txt:"; cat "$out/ffmpeg.txt"; }
  [ -s "${rec_file%.mkv}.wav" ] && echo "PASS the peer's sound in ${rec_file%.mkv}.wav" || fail "no ${rec_file%.mkv}.wav from the peer"
elif [ "$rec_kind" = movie ]; then
  [ -s "$(dirname "$rec_file")/frame00000000.png" ] && echo "PASS Movie Maker's take in $(dirname "$rec_file") (pack it with tools/trailer_pack.sh)" || fail "Movie Maker wrote no frames in $(dirname "$rec_file")"
fi
joined=()
for i in "${!roles[@]}"; do
  r="$PEERS/p$i/mods/net_peer/result.txt"
  if [ -f "$r" ]; then cp "$r" "$out/p${i}_result.txt"; else fail "p$i (${roles[$i]}) wrote no result"; continue; fi
  if [ "$i" -gt 0 ]; then
    want_join=joined
    [ "$i" = $(( ${#roles[@]} - 1 )) ] && want_join="$last"
    if grep -q " JOINED SPECTATOR" "$r"; then saw=spectator
    elif grep -q " JOINED" "$r"; then saw=joined
    elif grep -q " REFUSED" "$r"; then saw="refused:$(grep -o ' REFUSED [A-Za-z0-9_]*' "$r" | head -1 | cut -d' ' -f3)"
    else saw=nothing; fi
    [ "$saw" = "$want_join" ] && echo "PASS p$i (${roles[$i]}) join: $saw" || fail "p$i (${roles[$i]}) join: $saw, expected $want_join"
  fi
  # The game's teardown logs errors of its own, so each log is cut at the first sign: the end, the host
  # leaving, this peer's refusal, or a peer leaving once a minigame has loaded (a refused joiner leaves
  # before any load, so the match after it is still checked). Refused and spectating peers are checked
  # too: a call sent before the refusal lands on the refused vanilla peer.
  log="$(awk '{ print } /\[NETPEER\].* LOAD / { loaded = 1 } /\[NETPEER\].* (SCENE MainMenu|END |HOST_GONE|REFUSED )/ { exit } loaded && /\[NETPEER\].* PEER- / { exit }' "$out/p${i}_stdout.txt")"
  errs="$( { echo "$log" | grep -A1 '^ERROR' | grep -B1 'modules/multiplayer/' | grep '^ERROR'; echo "$log" | grep '^ERROR: \[MP8\] relay'; } )"
  bad="$(echo "$errs" | grep -v '^$' | grep -vE "$KNOWN")"
  [ -z "$bad" ] && echo "PASS p$i no multiplayer errors beyond the known ones ($(echo "$errs" | grep -c '^ERROR') known)" \
    || { fail "p$i multiplayer errors:"; echo "$bad" | sort | uniq -c | sort -rn | head -20; }
  [ "$i" -gt 0 ] && [ "$saw" != joined ] && continue
  joined+=("$i")
  # Peers cap a moment apart, so a client may see the host leave first.
  end="$(grep -o ' END .*' "$r" | head -1)"
  case "$end" in
    " END session over") echo "PASS p$i reached the session's end" ;;
    " END capped "*) echo "PASS p$i ran to the cap (${end# END })" ;;
    # A host whose only joiner was meant to be refused has no match to play.
    " END alone") [ "$i" = 0 ] && [ "$last" != joined ] && [ "${#roles[@]}" = 2 ] && echo "PASS p0 left alone, as expected" || fail "p$i was left alone" ;;
    " END host gone") grep -q " END capped " "$out/p${joined[0]}_result.txt" 2>/dev/null && echo "PASS p$i ran until the host's cap" || fail "p$i: the host left" ;;
    *) fail "p$i did not reach the session's end or the cap (${end:- no END})" ;;
  esac
done
if [ "${#joined[@]}" -ge 2 ]; then
  h="${joined[0]}"
  loads_h="$(grep -o ' LOAD .*' "$out/p${h}_result.txt")"
  scores_h="$(grep -o ' SCORES .*' "$out/p${h}_result.txt")"
  [ -n "$loads_h" ] || fail "the host loaded no minigame"
  for i in "${joined[@]:1}"; do
    [ "$(grep -o ' LOAD .*' "$out/p${i}_result.txt")" = "$loads_h" ] && echo "PASS p$i loaded what the host loaded ($(echo "$loads_h" | grep -c LOAD))" || fail "p$i loads differ from the host's"
    [ "$(grep -o ' SCORES .*' "$out/p${i}_result.txt")" = "$scores_h" ] && echo "PASS p$i scores match the host's at every briefing ($(echo "$scores_h" | grep -c SCORES); the last minigame's are not compared)" || fail "p$i scores differ from the host's"
  done
  # Each peer changes its own copy of Firearm Factory's bench room (zz_mp8v_bench_room_rpc): every Extended peer
  # that joined logs the same, the host too: its own relay calls run inside a client's RPC (PD19).
  room="$(grep -ho '\[MP8\] Firearm Factory 8p: room for .*' "$out"/p*_stdout.txt | sort -u)"
  all_ext=1; for i in "${joined[@]}"; do [ "${roles[$i]}" = ext ] || all_ext=0; done
  if [ -z "$room" ] && [ "$all_ext" = 1 ] && [ "${#joined[@]}" -ge 5 ] && grep -q ' LOAD ManufactureGun ' "$out/p${h}_result.txt"; then
    fail "Firearm Factory at ${#joined[@]} Extended peers, but no peer logged its room"
  fi
  if [ -n "$room" ]; then
    for i in "${joined[@]}"; do
      [ "${roles[$i]}" = ext ] || continue
      [ "$(grep -o '\[MP8\] Firearm Factory 8p: room for .*' "$out/p${i}_stdout.txt" | sort -u)" = "$room" ] && echo "PASS p$i changed its own Firearm Factory room" || fail "p$i did not change its Firearm Factory room as the others did: $room"
    done
  fi
  # net_peer's PROBE lines: each Extended peer's own copy of the minigame after its start, the host's included.
  if [ "${roles[$h]}" = ext ]; then
    probe_h="$(grep -o ' PROBE .*' "$out/p${h}_result.txt")"
    # A release build prints nothing for a script error, so a host with no PROBE line fails rather than passing unread.
    if [ -z "$probe_h" ] && grep -qE ' LOAD (ManufactureGun|SpineBreaker) ' "$out/p${h}_result.txt"; then
      fail "the host loaded Firearm Factory or Spine Breaker but logged no PROBE"
    fi
    for i in "${joined[@]:1}"; do
      [ "${roles[$i]}" = ext ] && [ -n "$probe_h" ] || continue
      [ "$(grep -o ' PROBE .*' "$out/p${i}_result.txt")" = "$probe_h" ] && echo "PASS p$i's minigame state matches the host's ($(echo "$probe_h" | grep -c PROBE) probes)" || fail "p$i's minigame state differs from the host's: $(grep -o ' PROBE .*' "$out/p${i}_result.txt" | tr '\n' '|') host: $(echo "$probe_h" | tr '\n' '|')"
    done
    # Spine Breaker's devices: each spot the host logs placing one at is where its own device stands.
    while read -r spot; do
      [ -n "$spot" ] || continue
      echo "$probe_h" | grep -qF "$spot" && echo "PASS the host's Spine Breaker device stands where it was placed, $spot" || fail "the host placed a Spine Breaker device at $spot, but its device is not there: $(echo "$probe_h" | grep SpineBreaker | tr '\n' '|')"
    done < <(grep -o 'Spine Breaker: device [0-9]* placed at ([^)]*)' "$out/p${h}_stdout.txt" | grep -o '([^)]*)')
  fi
fi

after="$(md5sum "$SAVES"/*.save "$SAVES"/*.json 2>/dev/null)"
[ "$before" = "$after" ] || { fail "a save of the owner's changed:"; diff <(echo "$before") <(echo "$after"); }
echo "DONE fails=$fails  logs: $out"
[ "$fails" = 0 ]
