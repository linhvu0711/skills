# sessions-rank.sh: the cases for the shared core's sessions/rank.py. The
# repo's test.sh sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
R="$here/../sessions/rank.py"

# rank_order <query> <json docs>: the doc names, best first, then each score
# above 0 as 1 and 0 as 0. Each doc is {"name", "prompts", "body"}.
rank_order() {
  python3 -I - "$R" "$1" "$2" <<'EOF'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("rank", sys.argv[1])
rank = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rank)
docs = json.loads(sys.argv[3])
marks = rank.scores(docs, sys.argv[2], {"prompts": 2.0, "body": 1.0})
order = sorted(range(len(docs)), key=lambda i: -marks[i])
print(" ".join(docs[i]["name"] for i in order), " ".join(str(int(marks[i] > 0)) for i in order))
EOF
}

t_rank_whole_words() {
  # Given: "stall" sits only inside "install"
  # When / Then: no match, so the score is 0
  eq order "a 0" "$(rank_order "stall" '[{"name":"a","prompts":"install the app","body":""}]')"
}

t_rank_rare_word_wins() {
  # Given: every session says "skill"; only b says "gates"
  docs='[{"name":"a","prompts":"skill skill skill","body":""},
         {"name":"b","prompts":"skill gates","body":""},
         {"name":"c","prompts":"skill","body":""}]'
  # When / Then: the rare word decides
  eq order "b a c 1 1 1" "$(rank_order "skill gates" "$docs")"
}

t_rank_long_session_no_edge() {
  # Given: both name the topic once; a also holds 3000 other words
  filler="$(python3 -c 'print(" ".join(f"w{i}" for i in range(3000)))')"
  docs="[{\"name\":\"a\",\"prompts\":\"box gates $filler\",\"body\":\"\"},
         {\"name\":\"b\",\"prompts\":\"box gates\",\"body\":\"\"},
         {\"name\":\"c\",\"prompts\":\"other\",\"body\":\"\"}]"
  # When / Then: the short one wins
  eq order "b a c 1 1 0" "$(rank_order "box gates" "$docs")"
}

t_rank_prompt_beats_reply() {
  # Given: a has the word in a prompt, b only in the agent's reply
  docs='[{"name":"b","prompts":"go","body":"walker fix"},
         {"name":"a","prompts":"walker fix","body":"go"},
         {"name":"c","prompts":"other","body":"other"}]'
  # When / Then
  eq order "a b c 1 1 0" "$(rank_order "walker" "$docs")"
}

t_rank_word_forms() {
  # Given: the session says "gate", "run", and "make"
  # When / Then: "gates", "running", and "making" still find it
  eq order "a 1" "$(rank_order "running gates" '[{"name":"a","prompts":"run the gate","body":""}]')"
  eq order "a 1" "$(rank_order "making" '[{"name":"a","prompts":"make the plan","body":""}]')"
}

t_rank_look_alike_words() {
  # Given: "not" and "plan" only, never "note" or "plane"
  # When / Then: no match
  eq order "a 0" "$(rank_order "note plane" '[{"name":"a","prompts":"not the plan","body":""}]')"
}

t_rank_filler_only() {
  # Given / When: a search of only filler words
  # Then: nothing scores
  eq order "a 0" "$(rank_order "the chat where we" '[{"name":"a","prompts":"the chat where we","body":""}]')"
}

cases=(
  "rank matches whole words only|t_rank_whole_words"
  "rank counts a rare word above a common one|t_rank_rare_word_wins"
  "rank gives a long session no edge for its length|t_rank_long_session_no_edge"
  "rank counts a word the user typed above one the agent wrote|t_rank_prompt_beats_reply"
  "rank finds other forms of a word|t_rank_word_forms"
  "rank keeps look-alike words apart|t_rank_look_alike_words"
  "rank scores a search of only filler words 0|t_rank_filler_only"
)
