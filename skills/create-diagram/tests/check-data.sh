# check-data.sh: a diagram page in, the DATA check's verdict out.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

cd_check() { run python3 "$here/../scripts/check-data.py" "$T/diagram-t.html"; }

# cd_page <fixture> <jq filter>: the shell at $T/diagram-t.html, its DATA the
# fixture check-data/<fixture>.json changed by the filter.
cd_page() {
  T="$(mktemp -d)"
  jq -c "$2" "$here/check-data/$1.json" > "$T/data.json"
  python3 -c 'import sys; shell, data = open(sys.argv[1]).read(), open(sys.argv[2]).read().strip(); print(shell.replace("const DATA = {};", "const DATA = " + data + ";"), end="")' \
    "$here/../assets/shell.html" "$T/data.json" > "$T/diagram-t.html"
}

t_cd_good_graph() {
  # Given: a flowchart of three nodes, two edges, and one group
  cd_page graph .
  # When
  cd_check
  # Then
  eq exit 0 "$code"
  eq stdout "ok: flowchart, 3 nodes, 2 edges" "$out"
}

t_cd_good_sequence() {
  # Given: a sequence of three participants and three steps, one frame, one note
  cd_page sequence .
  # When
  cd_check
  # Then
  eq exit 0 "$code"
  eq stdout "ok: sequence, 3 participants, 3 steps" "$out"
}

t_cd_unknown_edge_end() {
  # Given: the second edge goes to "cache", which is no node
  cd_page graph '.edges[1].to = "cache"'
  # When
  cd_check
  # Then
  eq exit 1 "$code"
  eq stdout 'edges[1]: to "cache" is not a node' "$out"
}

t_cd_unknown_group_member() {
  # Given: group svc lists "queue", which is no node or group
  cd_page graph '.groups[0].members += ["queue"]'
  # When
  cd_check
  # Then
  eq exit 1 "$code"
  eq stdout 'group "svc": member "queue" is not a node or group' "$out"
}

t_cd_unknown_step_participant() {
  # Given: the second step goes to "queue", which is no participant
  cd_page sequence '.steps[1].to = "queue"'
  # When
  cd_check
  # Then
  eq exit 1 "$code"
  eq stdout 'steps[1]: to "queue" is not a participant' "$out"
}

t_cd_unknown_frame_participant() {
  # Given: the frame spans "queue", which is no participant
  cd_page sequence '.frames[0].participants = ["api","queue"]'
  # When
  cd_check
  # Then
  eq exit 1 "$code"
  eq stdout 'frames[0]: participant "queue" is not a participant' "$out"
}

t_cd_unknown_note_participant() {
  # Given: the note sits on "queue", which is no participant
  cd_page sequence '.notes[0].at = "queue"'
  # When
  cd_check
  # Then
  eq exit 1 "$code"
  eq stdout 'notes[0]: at "queue" is not a participant' "$out"
}

t_cd_not_json() {
  # Given: DATA written as a JavaScript object with a bare key
  cd_page graph .
  python3 -c 'import sys,re; p=sys.argv[1]; s=open(p).read(); open(p,"w").write(re.sub(r"const DATA = .*;\n", "const DATA = { nodes: [] };\n", s, count=1))' "$T/diagram-t.html"
  # When
  cd_check
  # Then
  eq exit 1 "$code"
  has stdout "DATA is not JSON: Expecting property name enclosed in double quotes" "$out"
}

t_cd_missing_node_label() {
  # Given: node db has no label key
  cd_page graph 'del(.nodes[2].label)'
  # When
  cd_check
  # Then
  eq exit 1 "$code"
  eq stdout 'node "db": no label' "$out"
}

t_cd_missing_step_label() {
  # Given: the first step has no label key
  cd_page sequence 'del(.steps[0].label)'
  # When
  cd_check
  # Then
  eq exit 1 "$code"
  eq stdout 'steps[0]: no label' "$out"
}

cases=(
  "passes a good graph page|t_cd_good_graph"
  "passes a good sequence page|t_cd_good_sequence"
  "names an unknown edge end|t_cd_unknown_edge_end"
  "names an unknown group member|t_cd_unknown_group_member"
  "names an unknown step participant|t_cd_unknown_step_participant"
  "names an unknown frame participant|t_cd_unknown_frame_participant"
  "names an unknown note participant|t_cd_unknown_note_participant"
  "refuses DATA that is not JSON|t_cd_not_json"
  "names a missing node label|t_cd_missing_node_label"
  "names a missing step label|t_cd_missing_step_label"
)
