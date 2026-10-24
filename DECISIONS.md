# Decisions log (one line each)

- Build with SwiftPM via `scripts/swiftw`, which works around stale files in this machine's Command Line Tools (VFS overlay; no system files touched).
- Tests use Swift Testing (`import Testing`); XCTest is not shipped with the Command Line Tools.
- `ClaudeClient` lives in LookoutCore (Foundation only) so fixture mode and the benchmark can call Claude without any TCC permissions.
- Raw HTTP to the Messages API (no official Swift SDK); `anthropic-version: 2026-10-21`; model `claude-sonnet-5-5` set in `LookoutConfig.model` (override `LOOKOUT_MODEL`).
- Sonnet 5.5 calls omit `thinking` (adaptive by default) and send `output_config.effort` (`low` for scam checks, `medium` for help) to keep latency demo-friendly; no `temperature` (rejected by the API).
- Server-side refusal fallbacks enabled (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`); client retries once without them if the API rejects the field.
- Scam confirmation uses structured outputs (`output_config.format` json_schema) so the verdict is always parseable.
- RiskEngine remembers the strongest instance of each signal kind with a 120 s half-life; repeats of an unchanged screen don't inflate risk; benign context is screen-local.
- ActionPolicy = argmin expected cost with explicit false-alarm vs. missed-scam cost tables; "block" is only allowed when payment entry or remote access is active.
- Hard rules set a minimum action but are switched off on screens with strong benign context (articles, "this is not a bill").
- Scam vocabulary inside advice sentences ("we will never ask for gift cards") is ignored and counts as mild benign evidence.
- Free-mail sender domains (gmail, outlook…) never count as "official".
- Benchmark "alarm" = policy action ≥ interrupt; tuned only on the `dev` split; `test` split reported untouched.
- Claude confirmation threshold lowered to p ≥ 0.10 so heuristic near-misses still get a vision check.
- Demo scenario pages carry `<meta name="lookout-*">` tags and `data-lookout-threat/target/sensitive` attributes so fixture mode can read label, URL, app and sensitive fields.
- Family server: zero-dependency Node; SMS only if all Twilio vars are set AND `LOOKOUT_SMS_ENABLED=1`, otherwise logged as `[sms:mock]`.
