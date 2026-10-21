# Examples

**User:** `/build-and-prove ~/.agents/artifacts/plan/plan-acme-shop-42.md`
on Sonnet; the plan has `UI: web`, three walks, two videos.

Plan read, slug `acme-shop-42`. proofbox found. Worktree
`~/development/worktrees/acme/shop/feat-42-export-orders-csv` from
`main`. No setup script yet: written from `.nvmrc` and `pnpm-lock.yaml`;
`app.env` gets `PORT=3000` and an empty `STRIPE_KEY=`; the user fills it
in. Prompt written, this session builds four slices, each test red
then green on the local machine. After the fourth, `box.sh up` prints
`SANDBOX=ns:us:abc`. Walk 1's `Before` names steps: app started from
the base, walker in `before` mode, `before-1.png`. Gates green on
`1a2b3c4` in the Sandbox. Round 1: walk 3 fails,
its screenshot shows the `Export` button disabled with rows on screen:
an app bug, a follow-up, slice 4's code fixed, Gates again. Round 2: all
pass. `proof.md` written, `box.sh down`, report.

**`box.sh auth`** at step 2 prints `stop: log in first: proofbox auth login namespace`.

Show it, copy it with `copy.sh`, stop. No worktree, no Coding, and no Sandbox yet.

**Walker** reports walk 2 failed: step 3 says click `Save`, the screen
shows `Save changes`, and after it the saved row is there.

The Done-when line holds; only the label in the plan was wrong. Small
fork: walk 2's step fixed in the plan, a `Decided` line, one line to the
user, round 2.
