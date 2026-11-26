---
status: superseded by ADR-0041
---

# An Antigravity helper takes the main agent's model

An Antigravity agent file cannot name an exact model or a reasoning effort. Its `model` key takes only `inherit`, `flash`, `pro`, or `flash_lite`. agy 1.5.12 refuses any other model with "unsupported model: %q, must be one of 'inherit', 'flash', 'pro', 'flash_lite'", and the Antigravity subagent docs list no effort key (checked 2026-11-20). So each skill agent's Antigravity backup is `inherit`. The helper runs on the main agent's model and effort, which is Gemini 4 Neon when the main agent runs on Neon. Issue #196 wanted Neon at a set effort for each helper. The home models still give that, because T3 starts them with an exact model and thought level. The backup loses the per-helper effort. That happens in T3 when a home model cannot run, and every time in plain `agy`. We considered `pro`, Google's large-model tier, which looks like Neon today. We dropped it because Google decides what `pro` means and can change it. We also considered keeping `gemini-4-neon <effort>` in the file and writing `pro` into the plugin. We dropped that because the file would name an effort that never runs. Look at this again when Antigravity lets an agent file name a model or an effort, or when an Antigravity backup must differ from the main agent's model.
