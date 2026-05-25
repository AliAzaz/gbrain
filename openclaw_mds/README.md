# OpenClaw workspace templates (Founder Edition)

Source-of-truth for `$OPENCLAW_HOME` workspace files. **Ship these files directly** — they already use OpenClaw names (`AGENTS.md`, `TOOLS.md`, `HEARTBEAT.md`, `BOOTSTRAP.md`). Not installed by `gbrain` or `pureclaw-gbrain`.

Keep **`AGENTS.md`** under ~12k characters for OpenClaw bootstrap. Do **not** deploy **`AGENTS.full.md`** (~22k reference monolith — causes `[Bootstrap truncation warning]`).

**Ship to workspace:**

```bash
export OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "$PACK_DIR/AGENTS.md"    "$OPENCLAW_HOME/AGENTS.md"
cp "$PACK_DIR/TOOLS.md"     "$OPENCLAW_HOME/TOOLS.md"
cp "$PACK_DIR/HEARTBEAT.md" "$OPENCLAW_HOME/HEARTBEAT.md"
[[ -f "$OPENCLAW_HOME/BOOTSTRAP.md" ]] || cp "$PACK_DIR/BOOTSTRAP.md" "$OPENCLAW_HOME/BOOTSTRAP.md"
```

Then from your gbrain install:

```bash
gbrain skillpack install pureclaw-gbrain --workspace "${OPENCLAW_WORKSPACE:-$OPENCLAW_HOME}"
gbrain doctor --fast
```

Memory protocol: [`skills/pureclaw-gbrain/SKILL.md`](../skills/pureclaw-gbrain/SKILL.md). Install flow: [`skills/pureclaw-gbrain/INSTALL.md`](../skills/pureclaw-gbrain/INSTALL.md).

**Verify:** `wc -c "$OPENCLAW_HOME/AGENTS.md"` — expect under 12_000 characters. `wc -c "$OPENCLAW_HOME/HEARTBEAT.md"` — expect under ~1_000 (small heartbeat checklist only).

## OpenClaw heartbeat (silent)

Founder routines (morning brief, weekly review, dream) live in **`skills/pureclaw-gbrain/SKILL.md` §9–§10**, not in a large `HEARTBEAT.md`. The shipped `HEARTBEAT.md` is a **short periodic checklist** only.

Set `lightContext` and `isolatedSession` in **`openclaw.json`** (not inside `HEARTBEAT.md`):

```json5
{
  agents: {
    defaults: {
      heartbeat: {
        every: "30m",
        target: "none",
        lightContext: true,
        isolatedSession: true,
        skipWhenBusy: true,
        ackMaxChars: 300,
        prompt: "Use workspace HEARTBEAT.md context already loaded. Do not read HEARTBEAT.md with tools. If nothing needs attention, reply HEARTBEAT_OK only.",
      },
    },
  },
}
```

- **`target: "none"`** — no heartbeat messages in the UI/DM (stops chat spam).
- **`lightContext: true`** — inject only `HEARTBEAT.md`, not full `AGENTS.md` each tick.
- **`isolatedSession: true`** — no main conversation history on each heartbeat.
- **Custom `prompt`** — avoids the default “Read HEARTBEAT.md…” line that triggers visible `read` tool calls.

Use `every: "1h"` or `activeHours` if you want fewer ticks. Set `every: "0m"` to disable heartbeats entirely.
