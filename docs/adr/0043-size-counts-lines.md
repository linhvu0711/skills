---
status: replaces the facts table in shared/size.md
---

# Size counts changed lines

Size is the count of changed lines: XS 0–9, S 10–29, M 30–99, L 100–499, XL 500–999, XXL 1,000 or more. A script counts a PR's lines, and every skill that pushes to an open PR runs it again, so the label stays right. A ticket's Size is a guess on the same scale. XL is a normal ticket; XXL is never a ticket and goes to file-epic. Size alone sets a `/ship` thread's effort.

We used to judge Size from files, seams, and packages, "never by lines", and XL meant over the ceiling. Models now fit more in one window, and a count needs no judgment. We considered lines for PRs and the old facts for tickets, but then a ticket's Size and its PR's Size could disagree. We also considered a second label for how hard the decisions are; the user chose Size alone.
