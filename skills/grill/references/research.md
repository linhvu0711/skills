# Research

A research note is a **cache**, a dated copy of a lookup that was expensive to make. It exists so the next agent, in a fresh context window, reads one file instead of repeating the dig. Like any cache it goes stale, so every claim in it carries the source it came from and the note carries the date it was made.

## Dispatch

Send the question to an Explore agent with web search on. In Claude Code, put the token `SEARCH=on` in the agent's prompt above the brief. The brief carries the question, the claims to verify, and the instruction to cite the URL or repo path that owns each claim. The agent's answer file is the raw material for the note.

## Sources

Cite the source that owns the claim: the official docs, the spec, the source code, the first-party API. Follow every claim back to its owner. A blog post or a summary is a lead to the owner, never the citation itself.

Prefer a doc tool that serves the library's own docs over a general web search. When the claim is about behaviour, the library's source or test suite is the owner.

The research is done when every claim in the note cites its owner and every open question the brief asked is answered or marked as unanswerable with the reason.

## Writing the note

One Markdown file per research question. The header carries the question, the date, and the feature or sprint it serves. Each finding is one claim with one citation.

```md
# {The research question}

Date: {YYYY-MM-DD}
For: {feature or sprint this serves}

## Findings

- {Claim}. Source: {URL or repo path, with version or commit where it matters}.
- {Claim}. Source: {...}.

## Open

- {Question the sources did not settle, and why}.
```

## Where it lives

Match the repo's convention for such notes if one exists. If there is none, use `docs/research/<slug>.md`. Say where you put it when you report back.

## Using an existing note

Compare the note's date to the source before you lean on a claim. If the source has moved (a new major version, a changed spec), re-fetch that claim and update the note.

An ADR cites the primary source, never the research note. Notes are removed when the feature ships; ADRs outlive them.
