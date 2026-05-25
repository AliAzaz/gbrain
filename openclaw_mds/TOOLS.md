# TOOLS.md — PureClaw Connect (Founder Edition)

Environment-specific notes (SSH hosts, device names) also belong here.

You have **curl** — no extra plugins for connected apps. Every app speaks one shape.

## Bootstrap once per session

```bash
GATEWAY_TOKEN=$(cat ~/.openclaw/openclaw.json | python3 -c "import sys,json;print(json.load(sys.stdin)['gateway']['auth']['token'])")
BACKEND_URL="https://be.paioclaw.ai"

# List connected accounts
curl -s -H "Authorization: Bearer $GATEWAY_TOKEN" "$BACKEND_URL/api/v1/connectors/accounts"

# Universal proxy — ANY connected app
curl -s -X POST -H "Authorization: Bearer $GATEWAY_TOKEN" -H "Content-Type: application/json" \
  "$BACKEND_URL/api/v1/connectors/proxy" \
  -d '{"app":"<slug>","method":"<GET|POST|PUT|DELETE>","path":"<api-path>","params":{},"body":{}}'

# OAuth link for a new connector
curl -s -X POST -H "Authorization: Bearer $GATEWAY_TOKEN" -H "Content-Type: application/json" \
  "$BACKEND_URL/api/v1/connectors/token" -d '{"app_slug":"<slug>"}'
```

**App slugs (examples):** `gmail`, `google_calendar`, `slack`, `notion`, `github`, `google_sheets`, `trello`, `asana`, `jira`, `hubspot`, `discord`, `twitter`, `linkedin`, `dropbox`, `microsoft_outlook`, `microsoft_teams`, `zoom`, and 3,000+ others.

## Rules

- Token **401** → re-read `openclaw.json` silently; don't bother the founder.
- **App not connected** → fetch OAuth link, hand it over, say what you'll do once connected.
- **Any data you pull → save to GBrain** via `skills/pureclaw-gbrain/SKILL.md` §11 (every connector flow ends at `gbrain put <dir>/<slug>`). Next turn, hit the brain not the API.
- Never say "I don't have access." You have curl. Use it.
- **Brain first:** `gbrain search` before Connect when the answer may already be ingested (`AGENTS.md` Search Order).

## Connector auto-behaviors

When a connector goes live, run the initial sweep and maintain behaviors in the background — full playbooks in **`skills/pureclaw-gbrain/SKILL.md` §11**. Trigger-driven routines (morning brief, weekly review) are in **`SKILL.md` §9** (not OpenClaw heartbeat).

All durable writes: `gbrain put` — never workspace `MEMORY.md` or `memory/*.md`.
