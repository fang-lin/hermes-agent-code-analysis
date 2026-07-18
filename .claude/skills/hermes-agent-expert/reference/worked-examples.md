# Worked Examples — the ladder in action / 实战范例:阶梯怎么走

Two end-to-end traces showing how to climb Tier 0 → Tier 3 and land at the real hermes source. **Both were validated against the actual v0.18.2 checkout** — the anchors below resolved to real code. Imitate the *pattern*: climb only as far as the problem needs, and confirm the final answer in the source, not from memory.
两个从 Tier 0 走到"读真源码"的完整轨迹,均已对 v0.18.2 真源码验证过。学的是**方法**:按需逐层深入,最终答案落在源码上。

---

## Example A — Debugging: "cron `last_status=ok` but I never got the message"

**Tier 0 (orient, offline).** Routing table → cron = subsystem ch11. Silent-failure instinct: "ran fine but no output" is almost always a **delivery** problem, not an execution problem — don't start editing the prompt.

**Tier 1 (`reference/debugging.md`).** The silent-failure catalog says it directly:
> `last_status=ok` but no message → execution succeeded, **delivery** failed — separate field `last_delivery_error`.
> Also: the dead-target registry may have marked the target dead on a prior failure (self-heals on success).

Action it prescribes: `hermes cron list --all` → read `last_delivery_error` (there is no `cron get` subcommand).

**Tier 3 (confirm in real source — reached in ~2 greps).** To be sure the two fields are truly independent (and give a fix you can stand behind), go to ground truth:
- `grep -n last_delivery_error cron/jobs.py` → `:1073` (initialized `None`) and `:1351` (`job["last_delivery_error"] = delivery_error`) — a field written **separately** from `last_status`.
- `grep -n _deliver_result cron/scheduler.py` → defined `:1308`, called at `:3355` as `delivery_error = _deliver_result(...)`; the comment at `:3080` even notes `last_status` is set to "ok" independently of delivery.

**Resolution.** The job executed; delivery failed. Read `last_delivery_error` — it names the cause (bad `deliver:` target syntax / platform not connected / target marked dead). Fix the target or start the gateway; a success re-arms the dead-target registry. *No prompt changes, no guessing — the fix is grounded in the two-field design.*

---

## Example B — Customizing: "add a custom messaging platform"

**Tier 0 (orient).** Routing → platforms = ch05/ch08. Invariant #7/#8: platforms are **plugins** now — write a plugin, do **not** edit `gateway/` core.

**Tier 1 (`reference/extending.md` §4).** Implement `BasePlatformAdapter`'s abstract methods; register via `ctx.register_platform()` in a plugin under `plugins/platforms/`; copy `plugins/platforms/telegram/` as a template; watch the deferred-load gotcha.

**Tier 3 (read the real contract — and a real lesson).** The interface is the contract, so grep the ABC in the actual checkout:
- `grep -rn "class BasePlatformAdapter" gateway/platforms/` → `gateway/platforms/base.py:2253`.
- Naive move: `awk 'NR>=2253 && NR<=3200 && /@abstractmethod/'` → shows **3** methods: `connect`/`disconnect`/`send`. **This is the trap.** The class is ~3,375 lines; scanning only the first ~1,000 lines misses the 4th.
- Correct move: `grep -n "@abstractmethod" gateway/platforms/base.py` (whole file) → **4** methods; the 4th, `get_chat_info()`, is at `:5475` — ~2,600 lines below the other three. Ship without it and the subclass won't instantiate.

**Resolution.** Subclass `BasePlatformAdapter`, implement all **4** abstract methods (`connect`/`disconnect`/`send`/`get_chat_info`), override optional capability methods (`send_image`, `edit_message`, …) only for what your platform supports, add a `register(ctx)` calling `ctx.register_platform(...)`, and structure it like `plugins/platforms/telegram/` (`adapter.py` + `plugin.yaml`). *The skill got you to the right file in one grep; the "scan the whole definition" discipline caught the far-flung 4th method.*

---

## The transferable lesson / 可迁移的教训
This is exactly why the skill pins to a version but tells you to **read the real source**: a hardcoded "N methods" or a partial grep can mislead. The reliable procedure at Tier 3 is always: **grep the symbol across the whole definition → read it in full → confirm before you rely on it.** 别信"N 个方法"这种硬编码,也别信截断的 grep——在真源码里把整个定义读全,确认后再动手。
