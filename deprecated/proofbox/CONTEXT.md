Terms of the proofbox route, replaced by the Proof agent (ADR 0019).

**Walker**:
The subagent that does a plan's UI walks on a proofbox Sandbox the way a test user would. It gets the walks and the pass rule for each, never reads or changes the code, and reports what passed and what broke, with videos and screenshots.
_Avoid_: tester, verifier, QA agent

**Sandbox fault**:
A failed walk whose screen shows the Sandbox, not the app, is wrong: a missing tool, or a mark drawn as other bytes for want of a UTF-8 locale. The setup script is fixed and the round runs again, and it does not count as a round.
_Avoid_: flaky walk, env failure
