# Examples

**User:** `/build-and-prove ~/.agents/artifacts/plan/plan-acme-shop-42.md`
on Sonnet; the plan has `UI: web`, three walks, two videos.

Plan read, slug `acme-shop-42`. Worktree
`~/development/worktrees/acme/shop/feat-42-export-orders-csv` from
`main`. `.env.example` has `PORT=3000` and an empty `STRIPE_KEY=`:
`SECRETS` is `STRIPE_KEY`. The proof prompt is written, and `cursor.sh
start` prints `bc-7f3a`; `agent.env` holds it. This session builds four
slices, each test red then green on the local machine. After slice 2,
`poll` shows run 1 ended: `BEFORE 1/1`, walk 1's before shot taken on
`main`. After slice 4: push, then the round 1 note with `Videos: 1, 2`.
While the agent films, the local checks run: CI's workflow names
`pnpm test` and `pnpm build`, so their lines say `not run: CI runs it`;
`pnpm lint` is green on `1a2b3c4` on the local machine. Walk 3 fails,
its screenshot shows the `Export` button disabled with rows on screen:
an app bug, a follow-up, slice 4's code fixed, pushed. Round 2 films
video 2 again and runs `pnpm lint` again: all pass. `proof.md`
written, `down`, report, whose `Walk notes:` copies walk 3's round 1
FAIL.

**No UI.** The plan of `acme-shop-57`, a fix with `UI: none`.

Step 3 is `3. Proof agent. skip: no UI`: no key, credit, or secret is
checked. Coding, push, then round 1 runs only the local checks:
`pnpm lint` green on the local machine, `pnpm test` left to CI. Step 8
is skipped. The report says `Walks: none (no UI)` and `Proof agent:
none (no UI)`.

**Missing secret.** Run 1 ends `MISSING SECRETS: STRIPE_KEY` while slice
2 is being built.

One message: `The Proof agent lacks STRIPE_KEY. Add them to this repo's
environment on cursor.com (Cloud Agents, Secrets).` Coding goes on. The
round 1 note has `Check secrets: STRIPE_KEY`; the user added it, so the
run goes on to the videos.

**No credit.** `cursor.sh start` prints `cursor.sh: HTTP 402 on POST
/agents: payment_required (Add credit to run agents)`.

Show it, stop. No Coding yet; the worktree stays.

**Proof agent** reports walk 2 failed: step 3 says click `Save`, the
screen shows `Save changes`, and after it the saved row is there.

The Done-when line holds; only the label in the plan was wrong. Small
fork: walk 2's step fixed in the plan, a `Decided` line, one line to the
user, round 2 films walk 2's video again.

**Setup fault.** Round 1 ends `SETUP FAULT: ffmpeg not found`.

The round 1 note again, with `Install: ffmpeg (apt-get install -y
ffmpeg)`. It does not count as a round.
