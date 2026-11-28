# One frontmatter reader also reads openai.yaml

`scripts/check.sh` reads a skill's `agents/openai.yaml` with `scripts/frontmatter.awk`, the reader it uses for `SKILL.md`. It puts a `---` line in front of the file, so the reader sees the whole file as one frontmatter block (#442).

The check needs one key, `policy.allow_implicit_invocation`, to compare with `disable-model-invocation`. A second YAML reader for one key would be a second parser to keep in step with the first, and the repo has no YAML package in its checks. We keep one reader on purpose.
