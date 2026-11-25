# issue-conventions.sh: the cases for the shared core's issue-conventions.py.
# The repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# ic_setup: a fresh temp folder T, holding the HOME every command runs with,
# and the paths of the three stores under it.
ic_setup() {
  T="$(cd "$(mktemp -d)" && pwd -P)"
  ISS="$T/home/.config/gh-issues/issue-conventions.json"
  PRI="$T/home/.config/gh-issues/priority-labels.json"
  SEED="$T/home/.config/capture/conventions.json"
}

# conv <cmd> <args...>: the conventions command, with HOME in $T and the store
# env vars unset, so every case reads and writes the default paths.
conv() {
  run env -u GH_ISSUE_STORE -u GH_PRIORITY_STORE -u CAPTURE_STORE HOME="$T/home" python3 "$here/../issue-conventions.py" "$@"
}

set_types() { conv set O/R --style colon --xs size/XS --s size/S --m size/M --l size/L --word fix=bug --sampled 12; }
set_prio() { conv priority-set o/r --p0 p0 --p1 p1 --p2 p2 --p3 p3; }

t_ic_get_miss() {
  # Given
  ic_setup; set_types
  # When
  conv get o/other
  # Then
  eq exit 3 "$code"
  eq stdout MISS "$out"
}

t_ic_set_get() {
  # Given
  ic_setup; set_types
  # When
  conv get o/r
  # Then
  eq exit 0 "$code"
  eq entry '{"sampled":12,"size":{"L":"size/L","M":"size/M","S":"size/S","XS":"size/XS"},"style":"colon","words":{"fix":"bug"}}' \
    "$(jq -c 'del(.learned_at)' <<<"$out")"
}

t_ic_set_twice() {
  # Given
  ic_setup; set_types
  conv set o/r --style bracket --xs XS --s S --m M --l L
  # When
  conv get o/r
  # Then
  eq exit 0 "$code"
  eq entry '{"sampled":0,"size":{"L":"L","M":"M","S":"S","XS":"XS"},"style":"bracket","words":{}}' \
    "$(jq -c 'del(.learned_at)' <<<"$out")"
}

t_ic_get_priority() {
  # Given
  ic_setup; set_types; set_prio
  # When
  conv get o/r
  # Then
  eq priority '{"p0":"p0","p1":"p1","p2":"p2","p3":"p3"}' "$(jq -c .priority <<<"$out")"
}

t_ic_priority_set_get() {
  # Given
  ic_setup
  conv priority-set o/r --p0 "priority: critical" --p1 "priority: high" --p2 "priority: medium" --p3 "priority: low"
  # When
  conv priority-get o/r
  # Then
  eq exit 0 "$code"
  eq labels '{"p0":"priority: critical","p1":"priority: high","p2":"priority: medium","p3":"priority: low"}' \
    "$(jq -c . <<<"$out")"
}

t_ic_seed_set_get() {
  # Given
  ic_setup
  conv seed-set o/r --prefix "[seed] " --seed-label seed --bug-label defect --p0 p0 --p1 p1 --p2 p2 --p3 p3 --sampled 7
  # When
  conv seed-get o/r
  # Then
  eq exit 0 "$code"
  eq entry '{"bug_label":"defect","prefix":"[seed] ","priority":{"p0":"p0","p1":"p1","p2":"p2","p3":"p3"},"sampled":7,"seed_label":"seed"}' \
    "$(jq -c 'del(.learned_at)' <<<"$out")"
}

t_ic_seed_old_bug_label() {
  # Given
  ic_setup; mkdir -p "$(dirname "$SEED")"
  printf '%s\n' '{"o/r":{"prefix":"seed: ","seed_label":"Seed","sampled":5,"learned_at":"2026-01-02"}}' > "$SEED"
  # When
  conv seed-get o/r
  # Then
  eq entry '{"bug_label":"bug","learned_at":"2026-01-02","prefix":"seed: ","sampled":5,"seed_label":"Seed"}' \
    "$(jq -c . <<<"$out")"
}

t_ic_old_stores() {
  # Given
  ic_setup; mkdir -p "$(dirname "$ISS")"
  printf '%s\n' '{"o/r":{"style":"bracket","words":{},"size":{"XS":"XS","S":"S","M":"M","L":"L"},"sampled":30,"learned_at":"2026-01-02"}}' > "$ISS"
  printf '%s\n' '{"o/r":{"p0":"P0","p1":"P1","p2":"P2","p3":"P3"}}' > "$PRI"
  # When
  conv get o/r
  # Then
  eq exit 0 "$code"
  eq entry '{"learned_at":"2026-01-02","priority":{"p0":"P0","p1":"P1","p2":"P2","p3":"P3"},"sampled":30,"size":{"L":"L","M":"M","S":"S","XS":"XS"},"style":"bracket","words":{}}' \
    "$(jq -c . <<<"$out")"
}

t_ic_corrupt() {
  # Given
  ic_setup; mkdir -p "$(dirname "$ISS")"
  printf 'not json\n' > "$ISS"
  # When
  conv get o/r
  # Then
  eq exit 3 "$code"
  eq stdout MISS "$out"
  has stderr "warning: store was corrupt" "$err"
  [ ! -e "$ISS" ] || { echo "store still there: $ISS" >&2; exit 1; }
  ls "$(dirname "$ISS")" | grep -qxE 'issue-conventions\.json\.bak-[0-9]+' \
    || { echo "no backup in: $(ls "$(dirname "$ISS")")" >&2; exit 1; }
  eq "files left" 1 "$(ls "$(dirname "$ISS")" | wc -l | tr -d ' ')"
}

t_ic_forget() {
  # Given
  ic_setup; set_types; set_prio
  conv forget o/r
  # When
  conv get o/r; get_code="$code" get_out="$out"
  conv priority-get o/r
  # Then
  eq "get exit" 3 "$get_code"
  eq "get stdout" MISS "$get_out"
  eq "priority-get exit" 0 "$code"
  eq labels '{"p0":"p0","p1":"p1","p2":"p2","p3":"p3"}' "$(jq -c . <<<"$out")"
}

t_ic_seed_forget() {
  # Given
  ic_setup
  conv seed-set o/r --prefix "[seed] " --seed-label seed --p0 p0 --p1 p1 --p2 p2 --p3 p3
  conv seed-forget o/r
  # When
  conv seed-get o/r; seed_code="$code" seed_out="$out"
  conv priority-get o/r
  # Then
  eq "seed-get exit" 3 "$seed_code"
  eq "seed-get stdout" MISS "$seed_out"
  eq "priority-get exit" 3 "$code"
  eq "priority-get stdout" MISS "$out"
}

cases=(
  "conventions: get on a repo never learned prints MISS|t_ic_get_miss"
  "conventions: set saves style, words, and sizes, and get reads them back|t_ic_set_get"
  "conventions: a second set replaces the first|t_ic_set_twice"
  "conventions: get merges the repo's priority labels|t_ic_get_priority"
  "conventions: priority-set saves the labels and priority-get reads them|t_ic_priority_set_get"
  "conventions: seed-set saves the seed and priority labels and seed-get reads them|t_ic_seed_set_get"
  "conventions: a seed saved before bug_label reads back with bug|t_ic_seed_old_bug_label"
  "conventions: stores written before the move read back unchanged|t_ic_old_stores"
  "conventions: a corrupt store is moved aside and read as empty|t_ic_corrupt"
  "conventions: forget drops the issue types and keeps the priority labels|t_ic_forget"
  "conventions: seed-forget drops the seed and the priority labels|t_ic_seed_forget"
)
