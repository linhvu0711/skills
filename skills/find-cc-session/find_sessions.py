#!/usr/bin/env python3
"""Find Claude Code sessions in the current project that match a description.

Claude Code stores every conversation as a JSONL transcript at
    ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
where <encoded-cwd> is the absolute working directory with every
non-alphanumeric character replaced by '-'.

This script lists the sessions for one project (default: the current working
directory) with enough metadata — title, first/last human prompt, age, size —
for a model to judge which ones match a natural-language description. When a
query is given it also scores each session by keyword overlap and surfaces the
best-matching snippet, so the obvious matches float to the top. It does NOT
decide the final match or touch the clipboard — that judgment is left to the
caller, which is better at fuzzy/semantic matching than keyword counting.

Read-only: never modifies any .jsonl.

Usage:
    find_sessions.py "rewrite the landing page hero"   # score + rank by the query
    find_sessions.py --all                              # list everything, newest first
    find_sessions.py "..." --json                       # machine-readable output
    find_sessions.py "..." --project-dir /path/to/proj  # a different project
    find_sessions.py "..." --limit 12                   # show more candidates
"""
import argparse
import json
import os
import re
import sys
import time

WRAP_PREFIXES = (
    "<local-command-caveat>",
    "<command-name>",
    "<command-message>",
    "<command-args>",
    "<command-stdout>",
    "<local-command-stdout>",
    "<task-notification>",  # harness re-invocation when background work finishes — not a human prompt
)
PROMPT_DISPLAY_CAP = 500  # cap stored first/last prompt so a pasted wall-of-text can't flood output
BODY_CAP = 200_000  # cap chars indexed per session for scoring (keeps big files fast)
SNIPPET_LEN = 180


def encode_cwd(path):
    """Mirror Claude Code's project-dir encoding: every non-alphanumeric -> '-'."""
    return re.sub(r"[^a-zA-Z0-9]", "-", path)


def project_session_dir(project_dir):
    home = os.path.expanduser("~")
    return os.path.join(home, ".claude", "projects", encode_cwd(os.path.abspath(project_dir)))


def text_of(message):
    """Extract human-readable text from a message's content (str or block list)."""
    content = message.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
        return "\n".join(parts)
    return ""


def strip_wrappers(text):
    """Drop slash-command/caveat/system-reminder scaffolding, return real text or ''."""
    if not text:
        return ""
    stripped = text.strip()
    # Whole message is just command/caveat/reminder scaffolding -> not a human prompt.
    if stripped.startswith(WRAP_PREFIXES):
        # A slash-command invocation: pull the command name out so it's still searchable.
        m = re.search(r"<command-name>([^<]+)</command-name>", text)
        return m.group(1).strip() if m else ""
    if stripped.startswith("<system-reminder>") and stripped.endswith("</system-reminder>"):
        return ""
    # Remove any embedded reminder/caveat blocks but keep surrounding prose.
    cleaned = re.sub(r"<system-reminder>.*?</system-reminder>", " ", text, flags=re.S)
    cleaned = re.sub(r"<local-command-caveat>.*?</local-command-caveat>", " ", cleaned, flags=re.S)
    return cleaned.strip()


def is_bare_command(text):
    """True for a prompt that is just a slash-command token like '/clear' (no real prose)."""
    return bool(re.fullmatch(r"/[\w:-]+", text.strip()))


def parse_session(path):
    """Return a dict of metadata for one .jsonl transcript, or None if unreadable.

    Scoring leans on what the *human* steered the session toward (title + prompts);
    the assistant's output (``body``) is kept only for snippet display, because its
    sheer volume would otherwise let incidental word hits drown out the real topic.
    """
    sid = os.path.basename(path)[: -len(".jsonl")]
    title = None
    created = None
    first_prompt = None      # first prompt of any kind (may be a bare slash command)
    first_substantive = None  # first prompt with real prose, for display
    last_prompt = None
    n_prompts = 0
    prompt_parts = []
    prompt_len = 0
    body_parts = []
    body_len = 0
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                t = d.get("type")
                if t in ("ai-title", "summary"):
                    # Current Claude Code writes {"type":"ai-title","aiTitle":...};
                    # older transcripts used {"type":"summary","summary":...}.
                    s = d.get("aiTitle") or d.get("summary")
                    if s:
                        title = s  # keep the latest one as the title
                    continue
                if t == "last-prompt":
                    lp = d.get("lastPrompt")
                    if isinstance(lp, str) and lp.strip():
                        last_prompt = strip_wrappers(lp) or last_prompt
                    continue
                ts = d.get("timestamp")
                if ts and created is None:
                    created = ts
                if t == "user":
                    if d.get("isMeta") or d.get("isSidechain"):
                        continue
                    human = strip_wrappers(text_of(d.get("message", {})))
                    if human:
                        n_prompts += 1
                        if first_prompt is None:
                            first_prompt = human
                        if first_substantive is None and not is_bare_command(human):
                            first_substantive = human
                        last_prompt = human
                        if prompt_len < BODY_CAP:
                            prompt_parts.append(human)
                            prompt_len += len(human)
                elif t == "assistant":
                    if d.get("isSidechain"):
                        continue
                    txt = text_of(d.get("message", {}))
                    if txt and body_len < BODY_CAP:
                        body_parts.append(txt)
                        body_len += len(txt)
    except OSError:
        return None

    def cap(text):
        if not text:
            return text
        text = text.strip()
        return text[:PROMPT_DISPLAY_CAP] + ("…" if len(text) > PROMPT_DISPLAY_CAP else "")

    return {
        "id": sid,
        "title": title,
        # Display fields are capped; the full text still lives in ``prompts`` for scoring.
        "first_prompt": cap(first_substantive or first_prompt),
        "last_prompt": cap(last_prompt),
        "n_prompts": n_prompts,
        "modified": os.path.getmtime(path),
        "created": created,
        "prompts": "\n".join(prompt_parts),
        "body": "\n".join(body_parts),
    }


def score_session(sess, tokens, phrase):
    """Relevance by how well the query overlaps the session's *topic*.

    Topic lives in the title (summary) and the human prompts — those are what the
    user steered toward. We score by token *presence* there (not raw frequency) so a
    short, on-topic session isn't beaten by a long, sprawling one that mentions the
    words in passing. The assistant body counts only as a faint tiebreaker, by
    distinct tokens present, so volume can't dominate. Returns (score, snippet).
    """
    if not tokens:
        return 0, ""
    title = (sess["title"] or "").lower()
    prompts = sess["prompts"].lower()
    body = sess["body"].lower()

    score = 0
    matched = set()
    for tok in tokens:
        hit = False
        if tok in title:
            score += 6
            hit = True
        if tok in prompts:
            # presence is the main signal; a little extra for repeated emphasis
            score += 4 + min(prompts.count(tok) - 1, 3)
            hit = True
        if tok in body:
            score += 1  # distinct-token presence only — no frequency multiplier
            hit = True
        if hit:
            matched.add(tok)
    # Reward breadth: matching many distinct query words beats hammering one.
    score += len(matched) * len(matched)
    # Exact phrase is a strong signal of a real match.
    if phrase and len(phrase) > 3:
        if phrase in title:
            score += 40
        elif phrase in prompts:
            score += 20
        elif phrase in body:
            score += 6
    return score, best_snippet(sess, tokens)


def best_snippet(sess, tokens):
    """Pick the most query-dense line from the prompts/title/body for display."""
    candidates = []
    if sess["title"]:
        candidates.append(sess["title"])
    for key in ("first_prompt", "last_prompt"):
        if sess[key]:
            candidates.extend(sess[key].splitlines())
    candidates.extend(sess["body"].splitlines())
    best, best_hits = "", 0
    for line in candidates:
        line = line.strip()
        if not line:
            continue
        low = line.lower()
        hits = sum(1 for tok in tokens if tok in low)
        if hits > best_hits:
            best, best_hits = line, hits
            if best_hits == len(tokens):
                break
    snippet = best or (sess["first_prompt"] or sess["title"] or "")
    snippet = re.sub(r"\s+", " ", snippet).strip()
    return snippet[:SNIPPET_LEN] + ("…" if len(snippet) > SNIPPET_LEN else "")


def humanize_age(mtime):
    delta = max(0, time.time() - mtime)
    mins = delta / 60
    if mins < 60:
        return f"{int(mins)}m ago"
    hours = mins / 60
    if hours < 24:
        return f"{int(hours)}h ago"
    days = hours / 24
    if days < 14:
        return f"{int(days)}d ago"
    return f"{int(days / 7)}w ago"


def tokenize(query):
    toks = [w for w in re.findall(r"[a-z0-9]+", query.lower()) if len(w) >= 2]
    # Drop a few ultra-common words that add noise to keyword scoring.
    stop = {"the", "and", "for", "with", "that", "this", "from", "was", "were",
            "where", "when", "about", "into", "your", "you", "our", "are", "can"}
    return [t for t in toks if t not in stop]


def main():
    ap = argparse.ArgumentParser(description="Find Claude Code sessions in a project by description.")
    ap.add_argument("query", nargs="?", default="", help="natural-language description to match")
    ap.add_argument("--project-dir", default=os.getcwd(), help="project working dir (default: cwd)")
    ap.add_argument("--all", action="store_true", help="list every session (newest first), ignore scoring")
    ap.add_argument("--limit", type=int, default=8, help="max candidates to show (default 8)")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of text")
    args = ap.parse_args()

    sess_dir = project_session_dir(args.project_dir)
    if not os.path.isdir(sess_dir):
        msg = (f"No session history found for this project.\n"
               f"Looked in: {sess_dir}\n"
               f"(Derived from project dir: {os.path.abspath(args.project_dir)})")
        if args.json:
            print(json.dumps({"error": "no_project_dir", "session_dir": sess_dir, "sessions": []}))
        else:
            print(msg)
        return

    current_id = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    files = [os.path.join(sess_dir, f) for f in os.listdir(sess_dir) if f.endswith(".jsonl")]
    sessions = [s for s in (parse_session(p) for p in files) if s]

    tokens = tokenize(args.query)
    phrase = args.query.strip().lower()
    use_query = bool(tokens) and not args.all

    for s in sessions:
        s["is_current"] = (s["id"] == current_id)
        if use_query:
            s["score"], s["snippet"] = score_session(s, tokens, phrase)
        else:
            s["score"], s["snippet"] = 0, best_snippet(s, [])

    if use_query:
        ranked = [s for s in sessions if s["score"] > 0]
        ranked.sort(key=lambda s: (s["score"], s["modified"]), reverse=True)
    else:
        ranked = sorted(sessions, key=lambda s: s["modified"], reverse=True)

    shown = ranked[: args.limit]

    if args.json:
        out = {
            "session_dir": sess_dir,
            "query": args.query,
            "current_session_id": current_id,
            "total_sessions": len(sessions),
            "matched": len(ranked) if use_query else len(sessions),
            "sessions": [
                {k: s[k] for k in ("id", "title", "first_prompt", "last_prompt",
                                   "n_prompts", "score", "snippet", "is_current")}
                | {"age": humanize_age(s["modified"]), "modified": s["modified"]}
                for s in shown
            ],
        }
        print(json.dumps(out, indent=2, ensure_ascii=False))
        return

    # Pretty text output
    print(f"Project session dir: {sess_dir}")
    print(f"Total sessions in project: {len(sessions)}")
    if use_query:
        print(f'Query: "{args.query}"  →  {len(ranked)} with keyword overlap '
              f'(showing top {len(shown)})')
    else:
        print(f"Listing {len(shown)} most recent (no query / --all)")
    if not shown:
        print("\nNo candidates. Try --all to list everything, or a broader description.")
        return
    print()
    for i, s in enumerate(shown, 1):
        flag = "  ← current session" if s["is_current"] else ""
        score = f"  [score {s['score']}]" if use_query else ""
        print(f"{i}. {s['id']}{flag}")
        print(f"   {humanize_age(s['modified'])} · {s['n_prompts']} prompts{score}")
        if s["title"]:
            print(f"   title:  {s['title']}")
        if s["first_prompt"]:
            fp = re.sub(r"\s+", " ", s["first_prompt"]).strip()
            print(f"   opened: {fp[:160]}{'…' if len(fp) > 160 else ''}")
        if s["snippet"] and s["snippet"] not in (s["title"] or ""):
            print(f"   match:  {s['snippet']}")
        print()


if __name__ == "__main__":
    main()
