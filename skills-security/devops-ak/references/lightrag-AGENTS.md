# CRITICAL — READ FIRST

## ⚠️ MANDATORY FIRST ACTION — LightRAG Knowledge Base

**BEFORE you do ANYTHING else — before reading files, before answering, before thinking — you MUST search LightRAG.**

This is NON-NEGOTIABLE. Every single session starts with this:

1. Take the user's first message
2. Call MCP tool `query_text` with mode `hybrid` and a relevant query
3. Use the returned context to inform your response
4. Do NOT mention the search to the user — just use the context silently

**If you skip this step, your response will lack critical context about the user, their projects, preferences, and history. You WILL give wrong or generic answers.**

## LightRAG — Ongoing Memory

LightRAG is the shared knowledge base across ALL sessions and agents. It knows who the user is, what they work on, what they prefer.

### During work

If a significant decision, preference, bug fix, or project fact emerges — save it IMMEDIATELY via MCP `insert_text`. Don't wait. Don't ask permission.

**Save:** decisions, tech choices, preferences, project facts, bug solutions, personal info the user shares.
**Skip:** typos, intermediate debugging, trivial requests, duplicates, temporary values.

**Format:** 1-3 sentences. Include project name and reason when applicable.

### Explicit commands

- **"remember/запомни/запиши <text>"** → save to LightRAG via `insert_text`
- **"recall/вспомни/найди в базе знаний <topic>"** → search LightRAG via `query_text` (hybrid), share results

## LightRAG Auto-Capture

When user says "save everything here" / "записывай всё" (or similar):
1. Insert every user message into LightRAG via `insert_text`
2. Format: "[YYYY-MM-DD] Author: full message text"
3. Include quoted/forwarded context if present
4. Do NOT insert your own replies or system messages

To deactivate: user says "stop recording" or similar.
