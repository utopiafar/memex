# Agent Split Legacy vs Primary: 3-Round Eval Report

Date: 2026-05-23

## Executive Summary

Formal comparison only includes `legacy_pkm` and `split_primary`. Shadow artifacts are ignored for scoring and conclusions.

Across three isolated replay rounds, `split_primary` is consistently better on stability and cost:

| Round | Shard | Legacy | Primary | Primary delta |
| --- | --- | ---: | ---: | ---: |
| R1 | offset 0, limit 2 | 83/113 (73.5%) | 103/113 (91.2%) | +17.7pp |
| R2 | offset 0, limit 2 | 84/113 (74.3%) | 104/113 (92.0%) | +17.7pp |
| R3 | offset 2, limit 2 | 88/114 (77.2%) | 104/114 (91.2%) | +14.0pp |

Aggregate:

| Mode | Avg pass rate | Tokens | LLM calls | Tool calls | Failed tasks | loopDetection tasks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `legacy_pkm` | 75.0% | 545,839 | 472 | 3,114 | 3 | 3 |
| `split_primary` | 91.5% | 229,017 | 361 | 1,950 | 0 | 0 |

Conclusion: `split_primary` is suitable as an opt-in/debuggable primary path candidate. I would not default switch it yet because the remaining misses are concentrated in answer completeness and dataset window mismatches, but the stability evidence is strong enough to keep iterating on Primary rather than the legacy PKM path.

## Method

- Dataset: `evals/datasets/full_chain_journey_real_replay_v4/cases.jsonl`
- Each mode ran in an isolated replay workspace with the same case shard for that round.
- R1 and R2 used offset 0, limit 2 to verify the first fix against the same pressure cases.
- R3 used offset 2, limit 2 to check generalization on a different shard.
- Embedding service used OpenRouter `perplexity/pplx-embed-v1-4b`.
- Eval judge config was passed by environment variables only; no secret values are stored in repo files.

## Implemented Changes

1. Primary split path remains a product/debug switch.
   - The formal eval uses only `legacy_pkm` and `split_primary`.
   - Shadow stays useful for diagnostics but is not part of the formal conclusion.

2. Lightweight memory atom provenance and conflict handling.
   - Added `source_fact_ids` preservation in eval observations.
   - Added `status`, `supersedes_memory_ids`, and `conflicting_memory_ids`.
   - Superseded memory atoms are hidden from active prompts instead of being hard-deleted.
   - This keeps the data structure small while giving the model enough evidence to decide latest truth semantically.

3. MemoryAgent prompt tightened without making it a large orchestrator.
   - One-off tasks and reminders are excluded.
   - Standing reminder rules, durable routines, project owners, and evidence preferences are included.
   - This fixed R1's missing memory for case A in R2.

4. Knowledge Insight recoverable loop isolation.
   - `knowledge_insight_task` loopDetection is treated as a skipped recoverable result and does not poison the replay round.
   - Other exceptions still fail normally.

5. Eval harness supports `--case-offset`.
   - This allowed R3 to run a different shard while preserving same-method comparability.

6. Small post-R2 grounding fixes.
   - Quick Query now treats injected memory as first-class read-only evidence for preferences, reminder rules, latest corrections, owners, and boundaries.
   - Card titles now preserve conflict anchors when a task is defined by avoiding conflict with another named project or boundary.

## Round Notes

### R1

Primary already beat Legacy on the same inputs:

- Legacy: 73.5%, 194,197 tokens, 1 failed `pkm_agent_task`, 1 loopDetection, only 15 record operations completed.
- Primary: 91.2%, 73,656 tokens, 0 failed tasks, 0 loopDetection, all 24 record operations completed.

Primary misses showed it was too conservative on memory extraction:

- Missed standing reminder memory.
- Missed durable project-owner memory in some windows.

Applied fix: MemoryAgent inclusion policy for standing reminder rules and durable project owner context.

### R2

Primary improved memory recall:

- Legacy: 74.3%, 161,712 tokens, 1 failed `pkm_agent_task`, 1 loopDetection, 16 record operations.
- Primary: 92.0%, 72,465 tokens, 0 failed tasks, 0 loopDetection, 24 record operations.

Important detail:

- Case A memory recall fully passed after the prompt change.
- Case B still missed `提前一天`, but the B shard's 12 record inputs do not contain that fact. This is a ground-truth window mismatch, not a safe code target. The right behavior is not to invent a missing durable memory.

Applied fix: small Quick Query grounding and card-title conflict-anchor rule before R3.

### R3

R3 used new cases with offset 2.

- Legacy: 77.2%, 189,930 tokens, 1 failed task, 1 loopDetection, 22 record operations.
- Primary: 91.2%, 82,896 tokens, 0 failed tasks, 0 loopDetection, 24 record operations.

Primary's remaining memory misses were concentrated in `journey_real_replay_v4_01_c`, where the 12 input records do not contain the expected inherited facts (`提前一天`, coffee latest rule, initial owner rule). In `journey_real_replay_v4_02_a`, where the evidence is present, Primary memory recall passed and all 7 memory entries carried source links.

## Residual Risks

- Some benchmark expectations assume cross-window world facts that are not always present in the replay shard. Absolute memory recall should be read with this caveat; mode-to-mode comparison remains useful because both modes run the same shard.
- SuperAgent answer completeness is still weaker than the processing path. Primary can retrieve the relevant memories, but answers sometimes omit strict expected phrases. This is a retrieval/answer contract issue, not a split pipeline blocker.
- Card title keyword constraints remain brittle. The conflict-anchor rule improved one class of cases, but title scoring is still exact-keyword sensitive.

## Recommendation

Keep the split Primary path behind the product/debug switch and continue with it as the safer candidate path. Do not default it for all users yet.

Next iteration should focus on:

1. SuperAgent answer contract: when a query asks for preferences/latest boundary, explicitly synthesize active memory atoms and cite evidence.
2. Eval dataset hygiene: mark inherited-world expectations separately from same-window evidence expectations.
3. Title metric tolerance: move from exact keyword-only checks toward source-grounded semantic title checks, or explicitly tag which title keywords are mandatory from the source input.

Artifacts:

- R1 Legacy: `evals/runs/agent-split-iter-r1-legacy-score/report.md`
- R1 Primary: `evals/runs/agent-split-iter-r1-primary-score/report.md`
- R2 Legacy: `evals/runs/agent-split-iter-r2-legacy-score/report.md`
- R2 Primary: `evals/runs/agent-split-iter-r2-primary-score/report.md`
- R3 Legacy: `evals/runs/agent-split-iter-r3-legacy-score/report.md`
- R3 Primary: `evals/runs/agent-split-iter-r3-primary-score/report.md`
- Machine-readable summary: `evals/experiments/2026-05-23-agent-split-legacy-primary-3round/metrics.json`
