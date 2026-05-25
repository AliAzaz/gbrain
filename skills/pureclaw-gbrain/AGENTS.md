# AGENTS.md — PureClaw GBrain (workspace fragment)

Merge this into your workspace root **`AGENTS.md`** next to your existing **First Run**, **Every Session**, and **Tools** sections. **There is no separate "Memory" section in this design** — GBrain is the only memory store, so anything that used to live in a `## Memory` section about `MEMORY.md` / `memory/YYYY-MM-DD.md` should be deleted or replaced with the rules below.

**Skillpack note:** If you use `gbrain skillpack install`, routing rows live inside the managed fence only:

`<!-- gbrain:skillpack:begin -->` … `<!-- gbrain:skillpack:end -->`

Do not edit between those markers. Everything below is **yours** to paste outside that fence.

---

## Every Session — wake order

GBrain is the **only** persistent memory. Do not read `MEMORY.md`, `USER.md` (as a private user-truths file), or `memory/YYYY-MM-DD.md` from the agent workspace — those are legacy. If they exist on disk from an older install, the first run after upgrade should be a one-time migration into GBrain pages (`personal/profile`, `daily/YYYY-MM-DD`), after which the filesystem copies are ignored forever.

**Do not read `HEARTBEAT.md` on normal user turns** — it is for OpenClaw heartbeat only (already injected when `lightContext: true`). Founder trigger routines (morning brief, weekly review, etc.) live in **`skills/pureclaw-gbrain/SKILL.md` §9**, not in heartbeat ticks.

Before answering the first message of a session, run this in order — silently, without narrating to the human:

1. **Read `skills/pureclaw-gbrain/SKILL.md` end-to-end.** Re-read whenever the human mentions a **person, company, deal, meeting, project, decision,** or any entity worth remembering — weak recall here is the main failure mode.
2. **Read `SOUL.md`** from the workspace if you maintain one — your agent persona is host-managed identity, not GBrain content.
3. **Main session only — `gbrain get personal/profile`.** This replaces the legacy `MEMORY.md` + `USER.md` private truths. Never call this in group chats, shared sessions, or any context with more than one human.
4. **`gbrain get daily/$(date +%Y-%m-%d)`** and the same call for yesterday — today + yesterday raw stream.
5. **`gbrain get _dream/last-dream`** if it exists (overnight consolidation / briefing drafts).
6. **`gbrain doctor --fast` and `gbrain stats`** — brain must be reachable and embed/tag health must be known before semantic queries (`SKILL.md` §8). Fix connectivity drift first.
7. **If the human has a calendar event in the next ~2 hours** — `gbrain search "<attendee names>"` silently for dossiers (`SKILL.md` §8).

Don't narrate the checklist. Just load context.

---

## Tools — PureClaw GBrain (the only persistent brain)

You have the **`pureclaw-gbrain`** skill for treating **GBrain** as durable memory. Your chat context window is not memory. Local markdown files in the agent workspace are not memory. **GBrain is memory.** Anything important not written through this protocol is gone next session.

### When to use it

- **Every inbound message** — run the signal detector in parallel with your reply (`SKILL.md` §3): entities, decisions, dates, preferences, wins, connector-derived facts worth keeping.
- **Explicit memory language:** `gbrain`, `g-brain`, `your brain`, `the brain`, `your memory`, `remember`, `recall`, `what do you know`, `your records`, `your archive`, `your knowledge`, `search your memory`, `do you have`, `what have you got on`, `save`, `log this`, `store this`, `note this`, `track this`.
- **Any message that names** a person, company, deal, meeting, or project — notability gate and filing rules are in **`SKILL.md`** §13 + the resolver docs (`RESOLVER.md` / `AGENTS.md` at the brain repo root).
- **Before web search or external APIs** — `gbrain search` / `gbrain query` first (**brain first**, `SKILL.md` §5).
- **After PureClaw Connect pulls data** — land structured facts in the brain with `gbrain put` per **`SKILL.md` §11** (connector → brain, not "mental notes" and not local files).
- **Scheduled routines** (morning brief, weekly review, EOD recap) — **`SKILL.md` §9** (cron/minions or first user message), not `HEARTBEAT.md`.

### How to use it

1. **Read `skills/pureclaw-gbrain/SKILL.md`** — Iron Laws, canonical `gbrain put` heredoc pattern, command cheat sheet (§7), founder routines (§9), dream cycle (§10), connector playbooks (§11).
2. **Read before external lookup:** `gbrain search "<keywords>"` then escalate if empty. **And actually call the tool — do not narrate "let me check the brain" without invoking it in the same turn.**
3. **Write durable entity pages with:** `gbrain put <dir>/<slug>` — never rely on raw `echo > ...` for pages that must be searchable (`SKILL.md` §4).
4. **Daily stream:** append meaningful inbound signals to `gbrain put daily/YYYY-MM-DD` (NOT to a local `memory/` file). Promote distilled truths to `gbrain put personal/profile` only when appropriate (**main session only**).
5. **When the human invokes "the brain" / memory** — name **GBrain**, run the lookup in the same turn, show receipts (§6). No vague "I remember."

### Hard rules (non-negotiable)

- **Do not ask permission to write brain pages** — capture first, report second (`SKILL.md` §2 / §6). Banned phrases include "Want me to save this?" / "Confirm and I'll write it."
- **Do not narrate retrieval without performing it.** Phrases like "let me check the brain," "I'll search gbrain now," or "pulling that from memory…" without a tool call in the same turn are violations.
- **`personal/*` is main-session only** — never call `gbrain get personal/profile` (or any sibling) in group, shared, or multi-human contexts.
- **No API keys in chat** — never paste embedding or provider secrets into replies or brain pages.

### Works with PureClaw Connect

**PureClaw Connect** is for OAuth'd apps and HTTP proxies; **PureClaw GBrain** is for what survives sessions. Pull with Connect → **store** with `gbrain put` so the next turn hits `gbrain search`, not the network and not a local file.
