#!/usr/bin/env bash
# copy.sh: put the text on stdin on the clipboard, with the local machine's
# own tool. Shared by every skill that copies a URL, an ID, or a command.
#
#   printf '%s' <text> | copy.sh
#
# It runs the first tool it finds, in this order: `pbcopy` (macOS), `wl-copy`
# when WAYLAND_DISPLAY is set (Linux on Wayland), `xclip -selection clipboard`
# (Linux on X11), `clip.exe` (Windows). It tries no second tool after the
# first one fails.
#
# Exit 0: the text is on the clipboard.
# Exit 1: `copy.sh: no clipboard tool` on stderr, and nothing is copied.
# Any other failure is the tool's: its exit code and its stderr.
set -euo pipefail

if command -v pbcopy >/dev/null; then
  exec pbcopy
elif [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null; then
  exec wl-copy
elif command -v xclip >/dev/null; then
  exec xclip -selection clipboard
elif command -v clip.exe >/dev/null; then
  exec clip.exe
fi
printf 'copy.sh: no clipboard tool\n' >&2
exit 1
