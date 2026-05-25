# HEARTBEAT.md — periodic checks only

OpenClaw heartbeat turn only. **Do not use the `read` tool on this file** — with `lightContext: true` it is already in context.

Morning brief, weekly review, dream, and connector sweeps run on **user messages or cron/minions** (`skills/pureclaw-gbrain/SKILL.md` §9–§11), not on heartbeat.

On this heartbeat turn, only if cheap and warranted:

- If `gbrain get _dream/briefing-$(date +%Y-%m-%d)` exists and was never delivered to the founder → note internally; do not DM unless `target` is not `none`.
- If a calendar event starts within ~2 hours → `gbrain search` attendee dossiers silently; no user-visible spam.
- If nothing needs attention → reply **`HEARTBEAT_OK`** only (no tools, no narration).
