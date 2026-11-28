# A skill obeys the repo rules

Skills carry their own rules, and the repos they run in carry theirs, so the two clashed: a plan added tests that a repo's Standard ruled out. A skill now follows the repo rules, what the repo's agent files say, the files they point to, and the Standard, where they differ from its own, and its own rules fill only what the repo leaves unsaid. This amends ADR 0036: the Standard stays the file the clean-codebase skills write code rules into, but it is not the only file a skill obeys.

**Considered options**: the Standard alone as the rule source, rejected because a rule written in `AGENTS.md` would not reach the skills until someone moved it; a fixed list of skill rules no repo can switch off, such as merge only on the user's go, rejected to keep one plain rule.
