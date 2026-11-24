# The Standard is the only rules file

A repo had two rules files: the Standard for how code is written, and `REVIEW.md` for what a review checks. The repo rules in `REVIEW.md` repeated the Standard or belonged in it, and one rule could say two things in two files. We remove `REVIEW.md` and `set-review-rules`. A rule about a whole change, and a rule for one folder that comes from its fix history, are areas of the Standard. `review-pr` and `validate-pr-review` read the Standard, and `review-pr` still reads the general review rules from the shared core.

We considered a `REVIEW.md` that only points at the Standard. We rejected it because a second file can go out of date.
