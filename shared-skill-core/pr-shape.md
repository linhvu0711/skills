<!-- template: the PR shape, one source. make-pr reads it, grill through make-pr; render.sh pastes it into the handoff rules under ## The pull request. Keep it free of executor blocks and of links to other files: the include pastes it raw. Edit here only. -->
Every pull request has this shape: a branch, a title, a body, a label.

### Branch

`type/<issue>-<words>`, as in `feat/42-undo-delete`. With no issue,
`type/<words>`, as in `refactor/rename-create-pr`. `type` is a commit
type: `feat`, `fix`, `test`, `refactor`, `chore`, `docs`, `perf`, `ci`,
or `build`. Two to four words that name the change. Lower case, words
joined by `-`, no spaces, no other punctuation.

### Title

The shape of a commit summary, `type(scope): summary`, naming the whole
change, as in `feat(todos): undo delete, clear done, due badges`.
Imperative, lower case, no period, 72 characters at most. A change that
breaks a caller, a config, or a deploy puts `!` before the colon, as in
`feat(cli)!: rename --out to --output`, and its body has
`## Breaking changes`.

### Body

The body is for a reader who never saw the plan or the chat. Plan words
such as `slice 2`, `walk 1`, or `step 3` mean nothing to them, so the
body names behavior, tests, and what is on screen.

The parts, in this order. `Summary` and `Proof` are always there. Every
other part is there only when it has something to say; with nothing to
say, the heading goes too.

1. **The issue line**, first line of the body. `Closes #<n>` when the
   PR finishes the issue. `Refs #<n>` when it is part of the issue and
   another PR finishes it. No issue: no line.
2. **`## Summary`**: what the change does, why, and how to try it, in a
   few plain sentences.
3. **`## Where to look`**: one to three bullets that tell the reviewer
   where to spend their time:
   - the core change, as `file:line`;
   - what they can skim: wiring, renames, moved code, generated files;
   - a choice they may question, with its reason: a decision made
     during the work, or a surprise that changed what the code does
     (the code was not what the plan or the issue said, and the change
     went another way).

   The diff already lists the files; this part points. A PR whose diff
   is one place that the Summary already names leaves it out.
4. **`## Breaking changes`**: what else must happen for the change to
   work. Who it breaks and what they do now; a migration to run; an env
   var or a config to set; the order to deploy in. Undo steps only when
   a revert of the PR does not undo it, as with a data migration. This
   part and the `!` in the title go together: one is there exactly when
   the other is.
5. **`## Proof`**: the evidence that the change does what it says.
   - The issue or the plan has Done-when lines: one table, one row per
     Done-when line, in order. Columns: `#`, `Behavior`, `Test`.
     `Behavior` is the Done-when line verbatim. `Test` is the case name,
     linked to the test on the branch; or the command and its output in
     a fenced block, run on the head commit; or the URL of the CI run on
     the head commit. The words `see the Actions run` with no URL are
     not proof.
   - No Done-when lines: a list of the checks that ran on the head
     commit. Each item is the command, the short SHA, and the result,
     or a test the PR added or changed, linked. The list holds only
     checks that ran.

   ```markdown
   ## Proof

   | # | Behavior | Test |
   |---|---|---|
   | 1 | `uninstall` removes the launch agent and says so. | [`apps/cli/src/uninstall.test.ts` "removes the launch agent"](link to the test case on the branch) |
   | 2 | `bun test` passes. | `bun test` on `9e18c16`: `116 pass, 0 fail` |
   ```

   ```markdown
   ## Proof

   - `scripts/check.sh` on `9e18c16`: `check: clean`
   - `bun test` on `9e18c16`: `116 pass, 0 fail`
   - Added [`src/export.test.ts` "writes ISO dates"](link to the test case on the branch)
   ```
6. **`## Follow-ups`**: every issue filed during the work or the
   review, one line each, `#<n>: <what it is>`. Each line is an issue
   that exists. When an issue is filed after the PR opens, this part is
   updated then.

Write the body to a file kept out of every commit, and pass it with
`--body-file`.
`gh pr edit --body-file` replaces the whole body, so write the file
whole each time.

### Label

One size label: size the PR's own diff against its base with the size
table, and put on the repo's label for that size. A repo with no size
labels gets none, and no label is created.

### A repo's own PR template

A repo with a PR template (`.github/pull_request_template.md`, or a
file under `.github/PULL_REQUEST_TEMPLATE/`) keeps its structure. Each
part above goes under the template heading that matches it best; a part
with no match goes at the end under its own heading. A template heading
with nothing to say is left out. A checkbox stays, ticked only when it
is true. The branch, the title, and the label follow this shape as
written.
