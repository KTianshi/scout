# Benchmark results

154 labeled text fixtures (79 scam / 75 benign; 89 dev / 65 held-out test) in `bench/fixtures.jsonl`,
plus the 10 demo scenario pages. "Alarm" = the policy would interrupt (or block). Heuristics were tuned
only on `dev`; `test` was evaluated untouched.

| configuration | split | recall | precision | false-alarm rate |
|---|---|---|---|---|
| on-device heuristics only | dev | 89.4% | 100% | 0.0% |
| on-device heuristics only | **test** | **65.6%** | 91.3% | 6.1% |
| on-device heuristics only | demo pages | 100% (6/6) | 100% | 0% (0/4) |
| heuristics + Claude confirm (p ≥ 0.10, default) | dev | 97.9% | 100% | 0.0% |
| heuristics + Claude confirm (p ≥ 0.10, default) | **test** | **84.4%** | **100%** | **0.0%** |
| heuristics + Claude confirm (p ≥ 0.025) | test | 87.5% | 100% | 0.0% |

Claude confirmation here is text-only (`claude-sonnet-5-5`, effort `low`); the live app also sends a screenshot.

**Known gap:** the 4 test scams missed in every configuration (`scam-crypto-002`, `scam-crypto-005`,
`scam-romance-003`, `scam-charity-003`) are early-stage relationship messages with no scam vocabulary at all
("wrong number" chit-chat, a friendly stranger). The heuristic gate never fires, so Claude never sees them.
Catching these needs conversation-level memory or periodic model review of messaging apps.

Reproduce:

```bash
scripts/swiftw build
.build/debug/lookout-bench --demo demo/scenarios            # heuristics
.build/debug/lookout-bench --model                          # + Claude (needs ANTHROPIC_API_KEY)
LOOKOUT_CONFIRM_THRESHOLD=0.025 .build/debug/lookout-bench --model
```

Full per-fixture reports: `RESULTS-heuristics.md`, `RESULTS-model.md`, `RESULTS-model-lowthreshold.md`.
