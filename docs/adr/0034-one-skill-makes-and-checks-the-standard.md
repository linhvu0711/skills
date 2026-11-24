# One skill makes and checks the Standard

ADR 0005 split two skills by when they run. `set-coding-standards` made the Standard the first time, and `audit-coding-standards` checked it after that. Their steps were the same except for the first gate, and the user had to know which one a repo needed. `audit-coding-standards` now does both. In a repo with no Standard it makes one, and in a repo with a Standard it checks it. We remove `set-coding-standards`. This replaces ADR 0005.

We considered the name `coding-standards` for the one skill. We kept `audit-coding-standards` because the first run does the same checks against an empty Standard.
