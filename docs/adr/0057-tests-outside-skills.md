# Tests live outside skills and guard only silent harm

Tests sat in each skill folder, and `scripts/link.sh` links the whole folder into every harness, so each agent got the tests with the skill. They grew to about half of the repo. All tests now live in the top-level `tests/` folder. A script gets a test only when a break would go unseen and do harm. A break a person sees at once gets no test. A repo's own test rule wins over the plan and review rules, so plan-up and review-pr add or ask for no test that this rule leaves out.
