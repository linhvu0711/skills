# copy.sh: the cases for the shared core's copy.sh, driven through fake
# clipboard tools. The repo's test.sh sources this file after test-lib.sh and
# runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# cp_setup: a fresh temp folder T with an empty $T/bin, the only folder on the
# PATH copy.sh sees, so a real pbcopy in /usr/bin stays out of reach. CAT is
# the real cat, kept for the fakes. WL is the WAYLAND_DISPLAY copy.sh sees.
cp_setup() {
  T="$(cd "$(mktemp -d)" && pwd -P)"; mkdir "$T/bin"
  CAT="$(command -v cat)"; WL=""
}

# fake <name> [<exit>]: a clipboard tool in $T/bin that writes its stdin to
# $T/<name>.in and its arguments to $T/<name>.args, then exits <exit> (0).
fake() {
  printf '#!/bin/sh\n%s > "%s/%s.in"\nprintf "%%s\\n" "$*" > "%s/%s.args"\nexit %s\n' \
    "$CAT" "$T" "$1" "$T" "$1" "${2:-0}" > "$T/bin/$1"
  chmod 755 "$T/bin/$1"
}

# cp_run: `printf x | copy.sh` with only $T/bin on PATH and WAYLAND_DISPLAY
# set when WL is not empty.
cp_run() {
  printf x > "$T/x"
  run env -i PATH="$T/bin" ${WL:+WAYLAND_DISPLAY="$WL"} "$BASH" "$here/../copy.sh" < "$T/x"
}

# none <name>...: no tool of these names was given any text.
none() { local n; for n in "$@"; do [ ! -e "$T/$n.in" ] || eq "$n.in" "missing" "$(cat "$T/$n.in")"; done; }

t_cp_pbcopy_first() {
  cp_setup; fake pbcopy; fake wl-copy; fake xclip; fake clip.exe; WL=wayland-0
  cp_run
  eq exit 0 "$code"
  eq pbcopy.in x "$(cat "$T/pbcopy.in")"
  none wl-copy xclip clip.exe
}

t_cp_wl_copy_with_wayland() {
  cp_setup; fake wl-copy; fake xclip; fake clip.exe; WL=wayland-0
  cp_run
  eq exit 0 "$code"
  eq wl-copy.in x "$(cat "$T/wl-copy.in")"
  none xclip
}

t_cp_skips_wl_copy_without_wayland() {
  cp_setup; fake wl-copy; fake xclip; fake clip.exe
  cp_run
  eq exit 0 "$code"
  eq xclip.in x "$(cat "$T/xclip.in")"
  eq xclip.args "-selection clipboard" "$(cat "$T/xclip.args")"
  none wl-copy
}

t_cp_clip_exe_last() {
  cp_setup; fake clip.exe
  cp_run
  eq exit 0 "$code"
  eq clip.exe.in x "$(cat "$T/clip.exe.in")"
}

t_cp_no_tool() {
  cp_setup; WL=wayland-0
  cp_run
  eq exit 1 "$code"
  eq stderr "copy.sh: no clipboard tool" "$err"
  eq stdout "" "$out"
  eq ".in files" "" "$(cd "$T" && ls -- *.in 2>/dev/null || true)"
}

t_cp_tool_fails() {
  cp_setup; fake xclip 1
  cp_run
  eq exit 1 "$code"
}

cases=(
  "copy uses pbcopy first|t_cp_pbcopy_first"
  "copy uses wl-copy when WAYLAND_DISPLAY is set|t_cp_wl_copy_with_wayland"
  "copy skips wl-copy when WAYLAND_DISPLAY is unset|t_cp_skips_wl_copy_without_wayland"
  "copy uses clip.exe last|t_cp_clip_exe_last"
  "copy fails with no clipboard tool|t_cp_no_tool"
  "copy passes on the tool's failure|t_cp_tool_fails"
)
