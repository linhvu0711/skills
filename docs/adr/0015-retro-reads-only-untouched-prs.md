# Retro reads a PR only when no session touched it

Retro reads GitHub PRs, their issues, reviews, and failed CI runs only when no session in scope names the PR. A session that worked on a PR already holds its reviews and fixes, so reading the PR as well would count the same moment twice and make patterns look stronger than they are. PRs no session touched (teammates' work, work done by hand) are the only record of that work on this machine, so those are read.
