# MCP конфиги

MCP (Model Context Protocol) — подключает внешние сервисы прямо в Claude Code.

## Установка

1. Скопируй `.mcp.json.example` в корень проекта как `.mcp.json`
2. Замени токены и пути на свои
3. Перезапусти Claude Code

## Доступные серверы

| Сервер | Что даёт |
|--------|---------|
| `postgres` | Claude читает и пишет в твою БД через SQL |
| `github` | Claude работает с репо: PR, issues, файлы |
| `playwright` | Claude управляет браузером |
| `filesystem` | Claude читает файлы проекта |

## Где взять токены

- **GitHub PAT:** github.com → Settings → Developer Settings → Personal Access Tokens
- **PostgreSQL:** строка подключения от хостера или локальная БД

## Дополнительные серверы

Полный каталог MCP-серверов: [modelcontextprotocol.io/servers](https://modelcontextprotocol.io/servers)
