# The readiness module only reads

The readiness module reads a PR, waits for Devin Review, counts open threads, and returns a readiness verdict. It does not push, force-push, or restack. That round stays with the agent and `restack.sh`, because a force-push rewrites history on GitHub and a clash with a child PR needs a person to look at it. A read-only module is also safe to run at any time, and a fake `gh` is all its tests need.
