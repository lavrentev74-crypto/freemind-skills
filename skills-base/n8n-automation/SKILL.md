---
name: n8n-automation
description: Manage n8n workflows via MCP tools or REST API. Use when creating, editing, activating, debugging, listing n8n workflows and executions. MCP tools (mcp__n8n__*) are the PRIMARY method — use REST API only as fallback when MCP unavailable. MAIN instance: https://n8n-lavrentev.ru (all active bots and automations). Reserve instance: https://n8n-lavrentev.store (empty, for experiments). Do NOT use for general HTTP requests unrelated to n8n.
---

# n8n Automation

**MAIN Instance: https://n8n-lavrentev.ru** | API: `https://n8n-lavrentev.ru/api/v1`
Reserve Instance: https://n8n-lavrentev.store (empty, experiments only)

## Priority: MCP Tools (use these first)

MCP tools are connected via `.mcp.json`. Use them directly:
- `mcp__n8n__n8n_list_workflows` — list all workflows
- `mcp__n8n__n8n_get_workflow` — get workflow by ID
- `mcp__n8n__n8n_create_workflow` — create new workflow
- `mcp__n8n__n8n_update_full_workflow` — update workflow
- `mcp__n8n__n8n_executions` — get execution history
- `mcp__n8n__n8n_health_check` — check instance health

## Fallback: REST API (when MCP unavailable)

```bash
export N8N_API_URL="https://n8n-lavrentev.ru/api/v1"
export N8N_API_KEY="<from 00_claude/CREDENTIALS.md>"
```

Generate API key: n8n Settings → n8n API → Create an API key.

## Quick Reference

All calls use header `X-N8N-API-KEY` for auth.

### List Workflows
```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/workflows" | jq '.data[] | {id, name, active}'
```

### Get Workflow Details
```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/workflows/{id}"
```

### Activate/Deactivate Workflow
```bash
# Activate
curl -s -X PATCH -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"active": true}' "$N8N_API_URL/workflows/{id}"

# Deactivate
curl -s -X PATCH -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"active": false}' "$N8N_API_URL/workflows/{id}"
```

### Trigger Workflow (via webhook)
```bash
# Production webhook
curl -s -X POST "$N8N_API_URL/../webhook/{webhook-path}" \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}'

# Test webhook
curl -s -X POST "$N8N_API_URL/../webhook-test/{webhook-path}" \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}'
```

### List Executions
```bash
# All recent executions
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/executions?limit=10" | jq '.data[] | {id, workflowId, status, startedAt}'

# Failed executions only
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/executions?status=error&limit=5"

# Executions for specific workflow
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/executions?workflowId={id}&limit=10"
```

### Get Execution Details
```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/executions/{id}"
```

### Create Workflow (from JSON)
```bash
curl -s -X POST -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H "Content-Type: application/json" \
  -d @workflow.json "$N8N_API_URL/workflows"
```

### Delete Workflow
```bash
curl -s -X DELETE -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/workflows/{id}"
```

## Common Patterns

### Health Check (run periodically)
List active workflows, check recent executions for errors, report status:
```bash
# Count active workflows
ACTIVE=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/workflows?active=true" | jq '.data | length')

# Count failed executions (last 24h)
FAILED=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/executions?status=error&limit=100" | jq '[.data[] | select(.startedAt > (now - 86400 | todate))] | length')

echo "Active workflows: $ACTIVE | Failed (24h): $FAILED"
```

### Debug Failed Execution
1. List failed executions → get execution ID
2. Fetch execution details → find the failing node
3. Check node parameters and input data
4. Suggest fix based on error message

### Workflow Summary
Parse workflow JSON to summarize: trigger type, node count, apps connected, schedule.

## API Endpoints Reference

See [references/api-endpoints.md](references/api-endpoints.md) for complete endpoint documentation.

## Tips
- API key has full access on non-enterprise plans
- Rate limits vary by plan (cloud) or are unlimited (self-hosted)
- Webhook URLs are separate from API URLs (no auth header needed)
- Use `?active=true` or `?active=false` to filter workflow listings
- Execution data may be pruned based on n8n retention settings
