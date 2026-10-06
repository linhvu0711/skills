# build-page.sh: Markdown in, the built page's DATA out.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

build() { run python3 "$here/../scripts/build-page.py" "$@"; }
page_data() { sed -n 's/^const DATA = \(.*\);$/\1/p' "$1" | jq -S .; }

t_build_ticket() {
  T="$(mktemp -d)"
  cp "$here/build-page/ticket.md" "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq stdout "page: $T/plan-acme-shop-42.html" "$out"
  eq DATA "$(jq -S . "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_run() {
  T="$(mktemp -d)"
  cp "$here/build-page/run.md" "$T/plan-acme-shop-71-run.md"
  build "$T/plan-acme-shop-71-run.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S . "$here/build-page/run.json")" "$(page_data "$T/plan-acme-shop-71-run.html")"
}

t_build_run_one() {
  T="$(mktemp -d)"
  cp "$here/build-page/run-one.md" "$T/plan-acme-shop-75-run.md"
  build "$T/plan-acme-shop-75-run.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S . "$here/build-page/run-one.json")" "$(page_data "$T/plan-acme-shop-75-run.html")"
}

t_build_none_map() {
  T="$(mktemp -d)"
  cp "$here/build-page/none-map.md" "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S . "$here/build-page/none-map.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

# chat_plan <file> [<brief>]: ticket.md with no issue number, and <brief>
# (default: a Task and two Done-when lines) as its last block.
chat_plan() {
  sed 's/^# Plan: #42 /# Plan: /' "$here/build-page/ticket.md" > "$1"
  printf '\n%s\n' "${2-$'## Brief\nTask: staff download the orders list as CSV\nDone when:\n- the Export menu offers CSV\n- a note with a newline stays in one field'}" >> "$1"
}

t_build_chat() {
  T="$(mktemp -d)"
  chat_plan "$T/plan-acme-shop-chat-orders-csv.md"
  build "$T/plan-acme-shop-chat-orders-csv.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S 'del(.issue.number, .issue.url, .layers[0].issue.number, .layers[0].issue.url)' "$here/build-page/ticket.json")" \
    "$(page_data "$T/plan-acme-shop-chat-orders-csv.html")"
}

bad_chat() {
  T="$(mktemp -d)"
  chat_plan "$T/plan-acme-shop-chat-orders-csv.md" "$1"
  build "$T/plan-acme-shop-chat-orders-csv.md"
  eq exit 1 "$code"
  eq stdout "$2" "$out"
  [ ! -e "$T/plan-acme-shop-chat-orders-csv.html" ]
}

t_build_chat_no_brief() {
  bad_chat '' 'brief: a chat plan needs a `## Brief` block'
}

t_build_chat_brief_gaps() {
  bad_chat $'## Brief\nTask:\nDone when:\n- ' "$(printf 'brief: no `Task:` line\nbrief: no `Done when:` list')"
}

bad_ticket() {
  T="$(mktemp -d)"
  sed "$1" "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 1 "$code"
  eq stdout "$2" "$out"
  eq stderr "" "$err"
  [ ! -e "$T/plan-acme-shop-42.html" ]
  [ ! -e "$T/plan-acme-shop-42.html.tmp" ]
}

t_build_no_review() {
  bad_ticket '/^## Review$/d' 'not a plan-up .md: plan-acme-shop-42.md'
}

t_build_no_schema() {
  bad_ticket '/^  Schema:/d' 'review: `Blast radius` has no `Schema` line'
}

t_build_name_limit() {
  bad_ticket 's/| Orders page |/| Orders page for staff |/' 'change map: M1 part name is 21 characters, the limit is 20'
}

t_build_no_summary() {
  bad_ticket '/^## Summary$/ { N; d; }' 'summary: layer 1 has no `## Summary` block'
}

t_build_blank_before() {
  bad_ticket 's/  Before:   none/  Before:/' 'walk 1: the .md `Before` line is blank'
}

t_build_no_proved_date() {
  bad_ticket 's/, 2026-10-04. Used by S1././' 'proved: P1 needs `, <YYYY-MM-DD>. Used by <refs>.` at its end'
}

t_build_odd_tick() {
  bad_ticket 's/- O1 orders export as PDF/&`/' 'DATA.layers[0].out[0]: odd number of backticks, one shows raw: orders export as PDF`'
}

t_build_no_date() {
  bad_ticket 's/Size: size\/M    Date: 2026-10-04/Size: size\/M/' 'head: no `Date: YYYY-MM-DD` line under `# Plan:`'
}

t_build_no_head() {
  bad_ticket '/^# Plan:/d' 'head: no `# Plan:` line'
}

t_build_no_size() {
  bad_ticket 's/Size: size\/M    //' 'head: a ticket needs `Size: size/<x>`'
}

t_build_summary_limit() {
  bad_ticket '/^## Summary$/a\
one\
two\
three' 'summary: layer 1 has 4 lines, the limit is 3'
}

t_build_no_before() {
  bad_ticket '/^  Before:/d' 'walk 1: the .md has no `Before` line'
}

t_build_later_before() {
  bad_ticket 's/Before:   none/Before:   as walk 2/' 'walk 1: `as walk 2` must name an earlier walk of its layer whose `Before` names steps'
}

t_build_no_at() {
  bad_ticket 's/`src\/web\/orders.tsx:12`//' 'change map: M1 has no files and no slice in `At`'
}

t_build_bad_grid() {
  bad_ticket 's/| 0,1 |/| -1,1 |/' 'change map: M1 grid `-1,1` is not `column,row` with both 0 or more'
}

t_build_same_grid() {
  bad_ticket 's/| 2,1 |/| 1,1 |/' 'change map: M3 and M2 share the grid cell 1,1'
}

t_build_job_limit() {
  bad_ticket 's/asks for an export/asks for an export with all rows/' 'change map: M1 job is 32 characters, the limit is 30'
}

t_build_label_limit() {
  bad_ticket 's/asks for CSV/asks for CSV with all rows/' 'change map: flow M1 → M2 label is 26 characters, the limit is 20'
}

t_build_bad_flow() {
  bad_ticket 's/- M1 → M2: asks for CSV (new)/- M1 sends CSV to M2/' 'change map: a flow line is not `- M1 → M2: what moves (change)`: - M1 sends CSV to M2
change map: M1 has no change and no changed flow touches it; leave it out'
}

t_build_unknown_ref() {
  bad_ticket 's/M2 → M3/M2 → M4/' 'change map: flow M2 → M4 names M4, which is not a part of this map
change map: M3 has no change and no changed flow touches it; leave it out'
}

t_build_run_one_review() {
  T="$(mktemp -d)"
  sed '/^## Layer /,$ { /^## Review$/,/^## Summary$/ { /^## Summary$/!d; }; }' "$here/build-page/run-one.md" > "$T/plan-acme-shop-75-run.md"
  build "$T/plan-acme-shop-75-run.md"
  eq exit 1 "$code"
  eq stdout 'review: the .md has 1 `## Review` block(s), a run of 1 layer needs 2' "$out"
  [ ! -e "$T/plan-acme-shop-75-run.html" ]
}

t_build_stack_count() {
  T="$(mktemp -d)"
  sed '/^| 2 | #73 /d' "$here/build-page/run.md" > "$T/plan-acme-shop-71-run.md"
  build "$T/plan-acme-shop-71-run.md"
  eq exit 1 "$code"
  eq stdout 'stack: 1 rows, 2 `## Layer` headings' "$out"
  [ ! -e "$T/plan-acme-shop-71-run.html" ]
}

t_build_preserves_old() {
  T="$(mktemp -d)"
  cp "$here/build-page/ticket.md" "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  cp "$T/plan-acme-shop-42.html" "$T/old.html"
  sed '/^  Schema:/d' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 1 "$code"
  eq stdout 'review: `Blast radius` has no `Schema` line' "$out"
  cmp "$T/old.html" "$T/plan-acme-shop-42.html"
  [ ! -e "$T/plan-acme-shop-42.html.tmp" ]
}

t_build_all_problems() {
  bad_ticket '/^  Schema:/d; s/- O1 orders export as PDF/&`/' 'review: `Blast radius` has no `Schema` line
DATA.layers[0].out[0]: odd number of backticks, one shows raw: orders export as PDF`'
}

t_build_wrapped_text() {
  T="$(mktemp -d)"
  sed 's/Run: pnpm dev          UI: web/Run: env URL=http:\/\/localhost:3000 pnpm dev          UI: web/;
    s/Standards: the code/Standards: the\n  code/;
    s/- P1 csv-stringify/- P1 CSV: csv-stringify/;
    s/streamed three rows in a temp folder, /streamed three rows in a temp folder,\n  /;
    s/orders export as CSV |/orders export as CSV \\| JSON |/;
    s/notes may contain newlines. If wrong:/notes may contain newlines.\n    If wrong:/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.facts.run = "env URL=http://localhost:3000 pnpm dev" |
    .proved[0].fact = "CSV: csv-stringify keeps a note with a newline whole" |
    .layers[0].proof[0].line = "orders export as CSV | JSON"' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_script_text() {
  T="$(mktemp -d)"
  sed 's/orders export as PDF/orders export as <\/script> PDF/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[0].out[0] = "orders export as </script> PDF"' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
  has escaped '<\/script>' "$(sed -n '/^const DATA = /p' "$T/plan-acme-shop-42.html")"
}

t_build_no_bend() {
  T="$(mktemp -d)"
  run grep -ci bend "$here/../assets/shell.html" "$here/../../../shared-skill-core/plan-page.md"
  eq stdout "$here/../assets/shell.html:0
$here/../../../shared-skill-core/plan-page.md:0" "$out"
}

t_build_earlier_seam() {
  T="$(mktemp -d)"
  sed 's/`src\/members.ts:10`, the public command/layer 1, slice 2, the public command/' "$here/build-page/run.md" > "$T/plan-acme-shop-71-run.md"
  build "$T/plan-acme-shop-71-run.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[1].seams[0].at = "layer 1, slice 2"' "$here/build-page/run.json")" "$(page_data "$T/plan-acme-shop-71-run.html")"
}

t_build_mixed_at() {
  T="$(mktemp -d)"
  sed 's/`src\/web\/orders.tsx:12` |/`src\/web\/orders.tsx:12`, src\/types.ts:7, S2 |/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.maps[0].parts[0].at = ["src/web/orders.tsx:12", "src/types.ts:7", "S2"]' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_multiple_proofs() {
  T="$(mktemp -d)"
  sed 's/Slice 1, proves #1:/Slice 1, proves #1 and #2:/;
    s/Walk 1, proves #1$/Walk 1, proves #1 and #2/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[0].slices[0].proves = [1, 2] |
    .layers[0].walks[0].proves = [1, 2]' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

t_build_at_comma() {
  T="$(mktemp -d)"
  sed 's/`src\/web\/orders.tsx:12` |/`src\/web\/orders,v2.tsx:12`, `src\/db\/orders,v2.ts:4`, src\/types.ts:7, S2 |/' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.maps[0].parts[0].at = ["src/web/orders,v2.tsx:12", "src/db/orders,v2.ts:4", "src/types.ts:7", "S2"]' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

bad_run() {
  T="$(mktemp -d)"
  sed "$1" "$here/build-page/run.md" > "$T/plan-acme-shop-71-run.md"
  build "$T/plan-acme-shop-71-run.md"
  eq exit 1 "$code"
  eq stdout "$2" "$out"
  eq stderr "" "$err"
  [ ! -e "$T/plan-acme-shop-71-run.html" ]
  [ ! -e "$T/plan-acme-shop-71-run.html.tmp" ]
}

t_build_stack_identity() {
  bad_run 's/## Layer 2 ·/## Layer 3 ·/' 'stack: layer heading 3 is not layer 2'
  bad_run 's/| 2 | #73 /| 3 | #73 /' 'stack: row 2 names layer 3, needs 2'
  bad_run 's/| 2 | #73 /| two | #73 /' 'stack: row 2 names layer two, needs 2'
  bad_run 's/| 2 | #73 /| 2 | #74 /' 'stack: row 2 issue `#74 Add a member` is not `#73 Add a member`'
  bad_run 's/| #73 Add a member |/| #73 Join a team |/' 'stack: row 2 issue `#73 Join a team` is not `#73 Add a member`'
  bad_run 's/| layer 1 | S | 2 |/| layer 1 | S |/' 'stack: row 2 has 4 cells, needs 5'
  bad_run 's/| layer 1 | S | 2 |/| | S | 2 |/' 'stack: row 2 has no base'
  bad_run 's/| layer 1 | S | 2 |/| layer 1 | tiny | 2 |/' 'stack: row 2 size `tiny` is not XS, S, M, L, or XL'
  bad_run 's/| layer 1 | S | 2 |/| layer 1 | S | two |/' 'stack: row 2 points `two` is not an integer'
}

t_build_bad_record_headings() {
  bad_ticket 's/Slice 2, proves/Slice two, proves/' 'slices: Slice two, proves #2: export route is not a `Slice <n>, proves #<n>: <seam>` heading'
  bad_ticket 's/Slice 1, proves #1:/Slice 1, proves #1 and two:/' 'slices: Slice 1, proves #1 and two: export route is not a `Slice <n>, proves #<n>: <seam>` heading'
  bad_ticket 's/Walk 1, proves/Walk one, proves/' 'UI walks: Walk one, proves #1 is not a `Walk <n>, proves #<n>` heading'
  bad_ticket 's/Video 1, Setup/Video one, Setup/' 'videos: Video one, Setup of walk 1, shows walks 1 is not a `Video <n>, Setup of walk <n>, shows walks <n>` heading'
  bad_ticket 's/Video 1, Setup of walk 1, shows walks 1/Video 1, Setup of walk 1, shows walks one/' 'videos: Video 1, Setup of walk 1, shows walks one is not a `Video <n>, Setup of walk <n>, shows walks <n>` heading'
}

t_build_video_step_semicolon() {
  bad_ticket 's/  2\. Click Export, pick CSV\./  2. Type `tally status; tally list`, press Return./' \
    'video 1 step 2: `tally status; tally list` joins commands with `;`; type one command per step'
}

t_build_walk_steps_and() {
  bad_ticket 's/  Steps:    click Export, pick CSV/  Steps:    type `tally status \&\& tally list`, press Return/' \
    'walk 1 steps: `tally status && tally list` joins commands with `&&`; type one command per step'
}

t_build_before_clear_and() {
  bad_ticket 's/  Before:   none/  Before:   type `clear \&\& tally status`, press Return/' \
    'walk 1 before: `clear && tally status` joins commands with `&&`; type one command per step
walk 1 before: `clear && tally status` starts with `clear`; never clear the screen in a walk'
}

t_build_video_step_clear() {
  bad_ticket 's/  2\. Click Export, pick CSV\./  2. Type `clear`, press Return./' \
    'video 1 step 2: `clear` starts with `clear`; never clear the screen in a walk'
}

t_build_quoted_semicolon() {
  T="$(mktemp -d)"
  sed "s/  2\\. Click Export, pick CSV\\./  2. Type \`tally list | awk '{print \$1; print \$2}'\`, press Return./;
    s/  Before:   none/  Before:   the list shows \`a; b\`/" "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq stdout "page: $T/plan-acme-shop-42.html" "$out"
}

t_build_video_step_two_commands() {
  bad_ticket 's/  2\. Click Export, pick CSV\./  2. Type `tally status`, press Return; type `tally list`, press Return./' \
    'video 1 step 2: types 2 commands; type one command per step'
}

t_build_escaped_semicolon() {
  T="$(mktemp -d)"
  sed 's/  2\. Click Export, pick CSV\./  2. Type `echo a\\;b "c\\"; d"`, press Return./' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq stdout "page: $T/plan-acme-shop-42.html" "$out"
}

t_build_task_protections() {
  T="$(mktemp -d)"
  sed 's/Task done: full suite green, lint green, build green./Task done: full suite green, and these existing tests untouched and green:\n  `src\/orders.test.ts` "exports JSON"./' "$here/build-page/ticket.md" > "$T/plan-acme-shop-42.md"
  build "$T/plan-acme-shop-42.md"
  eq exit 0 "$code"
  eq DATA "$(jq -S '.layers[0].gates.task = "full suite green, and these existing tests untouched and green: `src/orders.test.ts` \"exports JSON\"."' "$here/build-page/ticket.json")" "$(page_data "$T/plan-acme-shop-42.html")"
}

cases=(
  "build-page builds a ticket page from its .md|t_build_ticket"
  "build-page builds a run page from its .md|t_build_run"
  "build-page builds a one-layer run page from its .md|t_build_run_one"
  "build-page builds a None map page|t_build_none_map"
  "build-page builds a chat plan with no issue|t_build_chat"
  "build-page refuses a chat plan with no Brief|t_build_chat_no_brief"
  "build-page refuses a Brief with no Task or Done when|t_build_chat_brief_gaps"
  "build-page stops on a file with no Review|t_build_no_review"
  "build-page refuses a Review with no Schema line|t_build_no_schema"
  "build-page refuses a part name over its limit|t_build_name_limit"
  "build-page refuses a layer with no Summary|t_build_no_summary"
  "build-page refuses a blank Before|t_build_blank_before"
  "build-page refuses a Proved line with no date|t_build_no_proved_date"
  "build-page refuses an odd backtick|t_build_odd_tick"
  "build-page refuses a plan with no Date|t_build_no_date"
  "build-page refuses a plan with no head|t_build_no_head"
  "build-page refuses a ticket with no Size|t_build_no_size"
  "build-page refuses a Summary over three lines|t_build_summary_limit"
  "build-page refuses a walk with no Before|t_build_no_before"
  "build-page refuses a Before naming a later walk|t_build_later_before"
  "build-page refuses a part with no At|t_build_no_at"
  "build-page refuses a bad grid|t_build_bad_grid"
  "build-page refuses parts sharing a grid cell|t_build_same_grid"
  "build-page refuses a job over its limit|t_build_job_limit"
  "build-page refuses a label over its limit|t_build_label_limit"
  "build-page refuses a malformed flow|t_build_bad_flow"
  "build-page refuses a flow to an unknown part|t_build_unknown_ref"
  "build-page refuses a one-layer run with one Review|t_build_run_one_review"
  "build-page refuses a mismatched Stack|t_build_stack_count"
  "build-page keeps the old page when a block is bad|t_build_preserves_old"
  "build-page reports every problem before writing|t_build_all_problems"
  "build-page preserves wrapped text, colons and escaped pipes|t_build_wrapped_text"
  "build-page escapes script closing text|t_build_script_text"
  "the shell and plan-page.md hold no bend|t_build_no_bend"
  "build-page preserves earlier-layer seam locations|t_build_earlier_seam"
  "build-page keeps every mixed-format map location|t_build_mixed_at"
  "build-page accepts and-separated proof references|t_build_multiple_proofs"
  "build-page keeps commas inside quoted map locations|t_build_at_comma"
  "build-page refuses malformed or mismatched Stack rows|t_build_stack_identity"
  "build-page refuses malformed Slice Walk and Video headings|t_build_bad_record_headings"
  "build-page keeps existing test protections in Task done text|t_build_task_protections"
  "build-page refuses a video step that joins commands with a semicolon|t_build_video_step_semicolon"
  "build-page refuses walk steps that join commands with &&|t_build_walk_steps_and"
  "build-page refuses a Before that starts with clear and joins|t_build_before_clear_and"
  "build-page refuses a video step that types clear|t_build_video_step_clear"
  "build-page passes a semicolon inside quotes|t_build_quoted_semicolon"
  "build-page refuses a video step that types two commands|t_build_video_step_two_commands"
  "build-page passes an escaped semicolon|t_build_escaped_semicolon"
)
