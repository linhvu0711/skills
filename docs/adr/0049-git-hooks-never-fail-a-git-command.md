# The link hooks never fail a git command

The post-commit, post-checkout, post-merge, and post-rewrite hooks run `scripts/link.sh`, and each one ends in `|| true` (#187). A hook runs after git has done its work, so it cannot undo the commit or the checkout. But the post-checkout hook's exit code becomes the exit code of `git checkout` and `git switch`, so a failed link would make a good checkout look failed to any script that runs it.

`link.sh` prints its own `skip:` and error lines, and `scripts/link.sh --status` shows each link that is `missing` or `stale`, so a failed link is still seen.
