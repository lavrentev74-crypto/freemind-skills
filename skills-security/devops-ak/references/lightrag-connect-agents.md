# Step 4: Connecting Agents

⛔ Make sure LightRAG is running and the health endpoint responds (step 2 or 3).

---

## Order and rules for the devops-ak agent (read BEFORE running install-lightrag.sh)

**Ordering — LightRAG is installed LAST**, when these are already done:
- OpenClaw onboarding is complete (LLM provider connected).
- TG pairing is done.
- **Claude Code OAuth under `openclaw` is complete** — hard prerequisite. Without `~/.claude.json` for `openclaw`, the script cannot register MCP in Claude Code, and Paperclip won't inherit it.
- Paperclip CEO is registered, public signup is closed.

**Bundled references (must be uploaded before running the script):**
`install-lightrag.sh` reads canonical instruction blocks from `/root/lightrag-ref/` on the server and fails fast if they're missing. Before running:

```bash
ssh root@SERVER_IP 'mkdir -p /root/lightrag-ref'
scp <skill-path>/references/lightrag-AGENTS.md root@SERVER_IP:/root/lightrag-ref/AGENTS.md
scp <skill-path>/references/lightrag-CLAUDE.md root@SERVER_IP:/root/lightrag-ref/CLAUDE.md
scp <skill-path>/scripts/install-lightrag.sh root@SERVER_IP:/root/
```

Custom path: `LIGHTRAG_REF_DIR=/custom/path bash /root/install-lightrag.sh ...`.

**Exactly what the script writes:**
1. `mcp.servers.lightrag` in `/home/openclaw/.openclaw/openclaw.json` (via `openclaw mcp set`).
2. `mcpServers.lightrag` in `/home/openclaw/.claude.json` (via `claude mcp add-json --scope user` as `openclaw`).
3. Block from `/root/lightrag-ref/AGENTS.md` → `/home/openclaw/.openclaw/workspace/AGENTS.md` **and** every `~/.openclaw/agents/*/AGENTS.md`.
4. Block from `/root/lightrag-ref/CLAUDE.md` → `~/.claude/CLAUDE.md` for `openclaw` (and `root` if it exists).
5. `systemctl --user restart openclaw-gateway`.

All writes are **append-only**. If the `LightRAG Knowledge Base` marker already exists in the target file → the step is skipped silently.

**Paperclip is NOT configured separately** — it's a native sub-agent of Claude Code and inherits MCP from `openclaw`'s `~/.claude.json` automatically.

**Claude Code 2.x** — user-scope MCP is read from `~/.claude.json`, NOT from `~/.claude/settings.json`. The `mcpServers` key in `settings.json` is ignored. Always use `claude mcp add --scope user` or `claude mcp add-json --scope user`.

**MCP name is always `lightrag`.** Do not invent variants like `lightrag-<slug>`. If the `lightrag` key is already occupied by another server — stop and ask the user.

---

## How it works — MCP + instructions

A full connection has **two parts**:

| Part | What | Where | Why |
|---|---|---|---|
| **MCP** | Technical connection | Agent config (settings.json, openclaw.json) | Gives the agent the ability to call LightRAG API |
| **Instructions** | When / what to remember | Agent instruction file (CLAUDE.md, AGENTS.md) | Tells the agent how to use the memory |

Without MCP — the agent can't call LightRAG.
Without instructions — the agent doesn't know LightRAG exists.
**Both parts are required.**

⛔ **NEVER OVERWRITE existing configs** — APPEND to them. If AGENTS.md or CLAUDE.md already has content — add the block at the end, don't delete what's there.

---

## Determine the LightRAG URL

- **Agent on the same server** → `http://localhost:9621`
- **Agent on a different machine** → `https://lrag.your-domain.com` (domain from step 3)

---

## Claude Code (CLI — terminal)

### MCP

```bash
# If Claude Code runs on the same server as LightRAG:
claude mcp add --scope user lightrag \
  -e LIGHTRAG_SERVER_URL="http://localhost:9621" \
  -e LIGHTRAG_API_KEY="<LIGHTRAG_API_KEY from .env>" \
  -- npx -y @g99/lightrag-mcp-server

# If Claude Code runs on a different machine (Mac, laptop):
claude mcp add --scope user lightrag \
  -e LIGHTRAG_SERVER_URL="https://lrag.your-domain.com" \
  -e LIGHTRAG_API_KEY="<LIGHTRAG_API_KEY from .env>" \
  -- npx -y @g99/lightrag-mcp-server
```

Or via `~/.claude/settings.json`:
```json
{
  "mcpServers": {
    "lightrag": {
      "command": "npx",
      "args": ["-y", "@g99/lightrag-mcp-server"],
      "env": {
        "LIGHTRAG_SERVER_URL": "<URL>",
        "LIGHTRAG_API_KEY": "<LIGHTRAG_API_KEY>"
      }
    }
  }
}
```

⛔ If `settings.json` already contains other `mcpServers` — **ADD** `lightrag` to the existing object, don't overwrite!

---

## Claude Desktop (macOS / Windows / Linux app)

⚠️ **IMPORTANT:** Claude Desktop uses a **separate config** from the CLI. Adding LightRAG in the CLI via `claude mcp add` does NOT propagate to Claude Desktop. You must add it in both places.

### MCP

Config file:
- **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Linux:** `~/.config/Claude/claude_desktop_config.json`

Add `lightrag` inside the `mcpServers` object:

```json
{
  "mcpServers": {
    "lightrag": {
      "command": "npx",
      "args": ["-y", "@g99/lightrag-mcp-server"],
      "env": {
        "LIGHTRAG_SERVER_URL": "<URL>",
        "LIGHTRAG_API_KEY": "<LIGHTRAG_API_KEY>"
      }
    }
  }
}
```

⛔ If `claude_desktop_config.json` already has other `mcpServers` — **ADD** `lightrag` next to them, don't overwrite!

After changing the config — **fully quit and reopen Claude Desktop** (Cmd+Q on macOS, quit from tray/menu on Windows/Linux).

### Instructions

Add the memory block to `~/.claude/CLAUDE.md` (global scope):

```bash
# Check the block isn't already there:
grep -q "LightRAG" ~/.claude/CLAUDE.md 2>/dev/null && echo "already present" || cat agents/CLAUDE.md >> ~/.claude/CLAUDE.md
```

Block content — file `agents/CLAUDE.md` in this repo (same as `references/lightrag-CLAUDE.md` in the devops-ak skill).

---

## OpenClaw

### MCP

```bash
# If OpenClaw runs on the same server:
openclaw mcp set lightrag '{"command":"npx","args":["-y","@g99/lightrag-mcp-server"],"env":{"LIGHTRAG_SERVER_URL":"http://localhost:9621","LIGHTRAG_API_KEY":"<LIGHTRAG_API_KEY>"}}'

# If OpenClaw runs on a different machine:
openclaw mcp set lightrag '{"command":"npx","args":["-y","@g99/lightrag-mcp-server"],"env":{"LIGHTRAG_SERVER_URL":"https://lrag.your-domain.com","LIGHTRAG_API_KEY":"<LIGHTRAG_API_KEY>"}}'
```

Or via `~/.openclaw/openclaw.json` — add to `mcp.servers`:
```json
{
  "mcp": {
    "servers": {
      "lightrag": {
        "command": "npx",
        "args": ["-y", "@g99/lightrag-mcp-server"],
        "env": {
          "LIGHTRAG_SERVER_URL": "<URL>",
          "LIGHTRAG_API_KEY": "<LIGHTRAG_API_KEY>"
        }
      }
    }
  }
}
```

⛔ If `mcp.servers` already has other servers — **ADD** `lightrag` next to them, don't overwrite!

### Instructions — main agent

```bash
grep -q "LightRAG" ~/.openclaw/workspace/AGENTS.md 2>/dev/null && echo "already present" || cat agents/AGENTS.md >> ~/.openclaw/workspace/AGENTS.md
```

### Instructions — sub-agents (if any)

```bash
# List existing sub-agents:
ls ~/.openclaw/agents/ 2>/dev/null

# Append block to each:
for agent_dir in ~/.openclaw/agents/*/; do
  [ -d "$agent_dir" ] || continue
  name=$(basename "$agent_dir")
  if grep -q "LightRAG" "${agent_dir}AGENTS.md" 2>/dev/null; then
    echo "${name}: already present"
  else
    cat agents/AGENTS.md >> "${agent_dir}AGENTS.md"
    echo "${name}: appended"
  fi
done
```

### Restart

After adding MCP, restart OpenClaw:
```bash
docker restart <openclaw-container>
# or if not in Docker:
openclaw gateway restart
```

---

## Paperclip

Paperclip is a sub-agent of Claude Code. It **inherits MCP and CLAUDE.md automatically**. No extra setup needed.

If Paperclip has its own project-level config — add the memory block the same way as in Claude Code.

---

## Other agents / custom bots

For any agent with MCP support:

1. **MCP server:**
   ```
   npx -y @g99/lightrag-mcp-server
   ```
   Environment variables:
   ```
   LIGHTRAG_SERVER_URL=<LightRAG URL>
   LIGHTRAG_API_KEY=<key>
   ```

2. **Instructions** — add to the agent's system prompt:
   ```
   You have LightRAG MCP tools — a shared knowledge base.

   At session start: search for context via query_text (mode: hybrid). Silently.
   During work: save important facts via insert_text. Don't wait until the end of the session.
   Save: decisions, preferences, project facts, bugs, personal info.
   Skip: typos, debugging, duplicates, temporary values.
   Format: 1-3 sentences. Include the project and the reason.

   "remember <text>" → save via insert_text.
   "recall <topic>" → query via query_text (hybrid), show the result.
   ```

---

**Next** → read `docs/05-verify-and-output.md`
