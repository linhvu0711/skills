#!/usr/bin/env bash
# The Cursor adapter of the handoff module (scripts/handoff.sh): the shared
# Cursor client, ../../shared/cursor/cursor.sh (from the skill folder), which /build-and-prove
# runs too. Its header lists the verbs.
set -euo pipefail
exec bash "$(cd "$(dirname "$0")" && pwd -P)/../../../../shared/cursor/cursor.sh" "$@"
