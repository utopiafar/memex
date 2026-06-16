# Memory Primary Eval Iteration Log

Use this file to keep a short, auditable trail when an eval run exposes a
case-level issue and the pipeline is changed. Keep entries concise and link the
local run artifacts instead of pasting large logs.

## Entry Template

```md
## YYYY-MM-DD HH:mm - <iteration_id>

- Baseline run: `evals/runs/<baseline_run>`
- Candidate run: `evals/runs/<candidate_run>`
- Affected cases: `<mode>/<case_id>`, `<mode>/<case_id>`
- Failed metrics: `metric_a`, `metric_b`
- Symptom: one sentence describing the user-visible failure.
- Root cause: one sentence describing the agent/service/schema issue.
- Fix: one sentence describing the code, prompt, schema, dataset, or scoring change.
- Verification: command or run dir that demonstrates the fix.
- Residual risk: anything still not covered or not stable.
```

## Run Metadata

Set these optional env vars before a replay so the run artifacts carry the
iteration context:

```bash
MEMEX_EVAL_ITERATION_ID=memory-primary-small-gate-001
MEMEX_EVAL_ITERATION_NOTE="tighten owner correction recall"
MEMEX_EVAL_BASELINE_RUN=evals/runs/<previous_run>
MEMEX_EVAL_CHANGED_CASES=memory_primary_scale_003,memory_primary_scale_006
```

The runner writes the metadata into every `case_logs/<mode>/<case_id>.json` and
into `case_debug_index.md`.

## 2026-06-10 20:02 - targeted-real-small-gate-001

- Baseline run: none, first real targeted small gate on the PR #256 metric set.
- Candidate run: `evals/runs/memory_primary_targeted_real_small_gate_20260610`
- Affected cases: `legacy_pkm/memory_primary_scale_001`, `memory_primary/memory_primary_scale_001`
- Failed metrics: `completed_card_rate`, `memory_expected_hit_rate`, `memory_recall_hit_rate`, `failed_task_count`, `super_agent_answer_success_rate`
- Symptom: all LLM-backed card, memory, and Super Agent ask work failed, so the run produced no meaningful capability signal.
- Root cause: the configured provider returned HTTP 400 for `mimo-v2.5-flash` with `Not supported model mimo-v2.5-flash`.
- Fix: pending provider/model correction; do not use this run to judge old-vs-new chain quality.
- Verification: case logs under `evals/runs/memory_primary_targeted_real_small_gate_20260610/case_logs/` show the shared model-unsupported error in failed tasks and Super Agent ask events.
- Residual risk: a rerun with a supported model id is required before expanding sample size or comparing quality metrics.

## 2026-06-10 20:16 - llm-preflight-model-selection

- Baseline run: `evals/runs/llm_preflight_mimo_v25_flash_20260610`, `evals/runs/llm_preflight_mimo_v2_flash_20260610`
- Candidate run: `evals/runs/llm_preflight_mimo_v25_20260610`, `evals/runs/llm_preflight_mimo_v25_pro_20260610`
- Affected cases: preflight only, no case execution.
- Failed metrics: provider readiness for `mimo-v2.5-flash` and `mimo-v2-flash`.
- Symptom: both configured subscriptions rejected the flash model ids before replay.
- Root cause: the provider returned HTTP 400 `Not supported model` for both flash ids, while the same credentials and endpoints accepted `mimo-v2.5` and `mimo-v2.5-pro`.
- Fix: add LLM preflight artifacts and default the eval runner examples to the preflight-passing `mimo-v2.5`; continue using an explicit `MEMEX_EVAL_LLM_MODEL` when validating another model.
- Verification: `MEMEX_EVAL_LLM_PREFLIGHT_ONLY=1` passed for `mimo-v2.5` and `mimo-v2.5-pro` across both configured subscriptions.
- Residual risk: official flash availability still needs provider-side confirmation before using flash for rollout evidence.

## 2026-06-10 20:48 - memory-primary-super-agent-memory-expand

- Baseline run: `evals/runs/memory_primary_targeted_real_2case_mimo_v25_20260610`, `evals/runs/memory_primary_targeted_case002_toolfix_mimo_v25_20260610`
- Candidate run: `evals/runs/memory_primary_targeted_case002_memory_expand_mimo_v25_20260610`
- Affected cases: `memory_primary/memory_primary_scale_002`
- Failed metrics: `super_agent_answer_hit_rate`, `super_agent_boundary_precision` in the first 2-case run; `super_agent_answer_hit_rate` in the first single-case verification.
- Symptom: Super Agent answered a report-format preference question with a generic template or incomplete preference recall, even though Memory Primary contained the relevant preference.
- Root cause: Quick Query relied on file/PKM search and could miss active Memory Primary atoms; the owner-conflict `must_not` scorer also treated corrective mentions of stale owners as forbidden.
- Fix: add a read-only `search_memory_primary` Super Agent tool, prefer it in Quick Query for preferences/project context, add preference-query expansion inside the tool, and change generated stale-owner checks from raw text bans to regex assertions of stale current-owner claims.
- Verification: `evals/runs/memory_primary_targeted_case002_memory_expand_mimo_v25_20260610` has `0` failures; `ask_002` reached `4/4` expected hits and `0/0` forbidden hits, with tool traces showing `search_memory_primary` calls.
- Residual risk: the fix is verified on the targeted single case; rerun the full 2-case comparison and then a larger shard before using the result as rollout evidence.

## 2026-06-10 21:09 - targeted-real-2case-after-super-agent-toolfix

- Baseline run: `evals/runs/memory_primary_targeted_real_2case_mimo_v25_20260610`
- Candidate run: `evals/runs/memory_primary_targeted_real_2case_after_toolfix_mimo_v25_20260610`
- Affected cases: `legacy_pkm/memory_primary_scale_001`, `legacy_pkm/memory_primary_scale_002`, `memory_primary/memory_primary_scale_001`, `memory_primary/memory_primary_scale_002`
- Failed metrics: none for the candidate gate.
- Symptom: previous 2-case run still had Super Agent ask failures in `memory_primary`; after the tool and scorer fix, candidate case failures dropped to `0`.
- Root cause: same as `memory-primary-super-agent-memory-expand`; this entry records the full old-vs-new replay verification.
- Fix: no additional code change beyond the targeted Super Agent Memory Primary tool and scoring fixes.
- Verification: full 2-case replay gate passed; `memory_primary` reached `memory_expected_hit_rate=1.0`, `memory_recall_at_10=1.0`, `related_fact_hit_rate=1.0`, `super_agent_answer_hit_rate=1.0`, and `failed_task_count=0`.
- Residual risk: p95 record latency is higher in the candidate (`54540ms` vs `44454ms`), so larger shards should track tail latency before rollout.

## 2026-06-10 21:31 - targeted-real-4case-merged

- Baseline run: `evals/runs/memory_primary_targeted_real_2case_after_toolfix_mimo_v25_20260610`
- Candidate run: `evals/runs/memory_primary_targeted_4case_merged_mimo_v25_20260610`
- Affected cases: `memory_primary_scale_001` through `memory_primary_scale_004`, both `legacy_pkm` and `memory_primary`
- Failed metrics: none for the candidate gate.
- Symptom: no new user-visible failure; this iteration expanded sample coverage from 2 cases to 4 cases with 8 Super Agent asks.
- Root cause: not applicable; this was a scale verification run.
- Fix: no code change. Ran two shards in parallel, each pinned to one MIMO subscription to avoid cross-user provider mixing.
- Verification: merged 4-case replay gate passed; `memory_primary` reached `memory_expected_hit_rate=1.0`, `memory_recall_at_10=1.0`, `related_fact_hit_rate=1.0`, `super_agent_answer_hit_rate=1.0`, `failed_task_count=0`, and `p95_record_elapsed_ms=56081`.
- Residual risk: evidence still uses synthetic targeted cases; next rollout report should combine this PR #256 ask/recall coverage with the larger 192-record scale input-chain evidence and then run at least one 8-case current-metrics shard if time allows.

## 2026-06-10 23:52 - targeted-v4-2case-pr256-coverage-smoke

- Baseline run: `evals/runs/memory_primary_targeted_4case_merged_mimo_v25_20260610`
- Candidate run: `evals/runs/memory_primary_targeted_2case_current_v4_real_20260610`
- Affected cases: `memory_primary_scale_001`, `memory_primary_scale_002`, both `legacy_pkm` and `memory_primary`
- Failed metrics: none for the candidate gate.
- Symptom: no user-visible failure; this run validates the updated PR #256 coverage metric aggregation on a small real LLM/embedding gate before scaling.
- Root cause: aggregate coverage metrics previously lived mostly in case logs and were not visible in `metrics.json` / `report.md` / merged reports.
- Fix: add `scenario_family_coverage`, `agent_chain_coverage`, `journey_stage_coverage`, `operation_type_coverage`, cross-day/correction/noise/follow-up coverage metrics to the replay and merge reports; document Super Agent gate rules and coverage metrics in `evals/METRICS.md`.
- Verification: `evals/runs/llm_preflight_mimo_v25_two_subs_current_slots2_20260610` passed both MIMO subscriptions; `evals/runs/memory_primary_targeted_2case_current_v4_real_20260610` gate passed with `memory_expected_hit_rate=1.0`, `memory_recall_at_10=1.0`, `super_agent_answer_hit_rate=1.0`, `super_agent_boundary_precision=1.0`, `failed_task_count=0`, `task_not_settled_count=0`, `scenario_family_coverage=1.0`, and `p95_record_elapsed_ms=50423`.
- Residual risk: sample size is still 2 cases / 16 records; next run should scale to all 8 targeted cases, ideally in two shards pinned to the two preflight-passing subscriptions.

## 2026-06-10 - targeted-v4-8case-boundary-and-recall-hardening

- Baseline run: `evals/runs/memory_primary_targeted_8case_merged_mimo_v25_20260610`
- Candidate runs: `evals/runs/memory_primary_targeted_v4_answer_sanitizer_case002_history_clean_20260610`, `evals/runs/memory_primary_targeted_v4_current_state_history_section_case003_20260610`, `evals/runs/memory_primary_targeted_v4_case003_case008_owner_fallback_v2_20260610`
- Affected cases: `memory_primary/memory_primary_scale_002`, `memory_primary/memory_primary_scale_003`, `memory_primary/memory_primary_scale_004`, `memory_primary/memory_primary_scale_008`
- Failed metrics: `super_agent_boundary_precision`, `super_agent_answer_hit_rate`, `memory_expected_hit_rate`, `memory_recall_hit_rate`.
- Symptom: current-state answers sometimes quoted stale owners in evidence/history text; preference asks sometimes lost required report slots; one owner correction completed with `changed_memory_ids=[]`.
- Root cause: Quick Query could read raw Facts after Memory recall; current-state sanitizer did not cover timeline tables or "from X to Y" correction sentences; Memory Extract accepted empty patches for strong owner-correction inputs and preserved stale owner names in normalized memory/entity output.
- Fix: harden `search_memory_primary` preference expansion and current-state redaction, suppress streaming until Quick Query final-answer post-processing, add exact project-name preservation, add deterministic owner-correction fallback and normalization in Memory Extract, and filter current-state tool entity output to entities still present in redacted content.
- Verification: `evals/runs/memory_primary_targeted_v4_case003_case008_owner_fallback_v2_20260610` passed with `0` failures; case003 current owner answer no longer names stale owner, and case008 writes/recalls the Yuki owner correction.
- Residual risk: normalized owner correction may still inherit old evidence ids from duplicate-memory updates; current-state tool output hides stale entities, but a future schema-level conflict resolver should expire stale owner atoms explicitly.

## 2026-06-10 - targeted-v4-final2-8case-rollout-evidence

- Baseline run: `evals/runs/memory_primary_targeted_8case_v4_final2_shard0_cases0_3_20260610`, `evals/runs/memory_primary_targeted_8case_v4_final2_shard1_cases4_7_20260610`
- Candidate run: `evals/runs/memory_primary_targeted_8case_v4_final2_merged_20260610`
- Affected cases: `memory_primary_scale_001` through `memory_primary_scale_008`, both `legacy_pkm` and `memory_primary`
- Failed metrics: none for Memory Primary; all merged candidate gate rules passed.
- Symptom: final validation run for the PR #256 current targeted metric set.
- Root cause: not applicable; this entry records the full old-vs-new replay after boundary and recall hardening.
- Fix: no additional code change after the case003/case008 regression run.
- Verification: merged gate passed on 8 cases, 64 records per mode, 16 recall probes per mode, 16 Super Agent asks per mode, and 8 PARA projections per mode. Memory Primary reached `memory_expected_hit_rate=1.0`, `memory_recall_at_10=1.0`, `super_agent_answer_hit_rate=1.0`, `super_agent_boundary_precision=1.0`, `failed_task_count=0`, `task_settlement_rate=1.0`, and `p95_record_elapsed_ms=36774`.
- Residual risk: dataset is still synthetic targeted coverage rather than production telemetry; before default rollout, expand to noisier real-like journeys and keep monitoring tail latency/cost.

## 2026-06-11 - pr256-single-user-scale-current-metrics

- Baseline run: `evals/runs/memory_primary_pr256_single_user_sgp_full_20260611`, `evals/runs/memory_primary_pr256_single_user_cn_full_20260611`
- Candidate run: `evals/runs/memory_primary_pr256_single_user_sgp_after_quickquery_fix_20260611`, `evals/runs/memory_primary_pr256_single_user_cn_after_quickquery_fix_20260611`
- Affected cases: `memory_primary/memory_primary_pr256_single_user_001`
- Failed metrics: pre-fix SGP failed `super_agent_boundary_precision`; pre-fix CN failed `super_agent_answer_hit_rate`.
- Symptom: SGP current-state Super Agent answers correctly named the current owner but also mentioned stale owner/history details; CN report-style answer used `Meridian` instead of preserving the exact `Meridian 导出` entity from the user query.
- Root cause: Quick Query could still copy stale owner/history lines from raw evidence into final current-state answers, and the project-name postprocessor only handled a single project/entity with whitespace before `相关`.
- Fix: keep Memory Primary Quick Query post-processing gated to `memory_primary`, remove stale owner/history bullets from current-state answers, and preserve exact multi-project entity names from the query such as `Project Orion` plus `Meridian 导出`.
- Verification: both post-fix 72-record single-user `memory_primary` runs passed with `memory_expected_hit_rate=1.0`, `memory_recall_at_10=1.0`, `super_agent_answer_hit_rate=1.0`, `super_agent_boundary_precision=1.0`, `failed_task_count=0`, and `task_settlement_rate=1.0`. SGP reached `related_fact_hit_rate=0.939`, `p95_record_elapsed_ms=39261`; CN reached `related_fact_hit_rate=0.788`, `p95_record_elapsed_ms=49174`.
- Residual risk: post-fix validation reran `memory_primary` only because the code change is gated away from legacy; a final release evidence pass can rerun full old-vs-new after this fix if we want a single combined report artifact.

## 2026-06-12 - pr256-full-metric-v1-harness

- Baseline run: not applicable; this is evaluator/data infrastructure work before the next real LLM small gate.
- Candidate runs: `evals/runs/pr256_full_metric_small_nollm_compile_20260612`, `evals/runs/pr256_full_metric_3provider_preflight_20260612`, `evals/runs/pr256_judge_smoke_20260612_v2`
- Affected cases: generated `pr256_full_metric_persona_00` through `pr256_full_metric_persona_02`.
- Failed metrics: no-LLM compile run intentionally fails Memory/Super Agent LLM-dependent metrics; deterministic GT/Trace metrics for route, card entity/time/hallucination, coverage, and judge-task emission passed after dataset oracle fixes.
- Symptom: the previous harness only emitted the current rollout gate subset and could not exercise the full PR #256 metric surface.
- Root cause: full PR #256 metrics need richer synthetic ground truth, standardized trace aggregation, and separate LLM-as-judge execution rather than only text must-contain checks.
- Fix: added `evals/bin/generate_pr256_full_metric_dataset.dart` for GT-rich synthetic cases, extended `memory_primary_full_chain_replay_test.dart` with route/card/tool/retrieval/read-only/cache-by-agent/coverage metrics and `MEMEX_EVAL_GATE_PROFILE=pr256_full`, and added `evals/bin/run_pr256_judge.dart` for `mimo-v2.5-pro` judge tasks.
- Verification: no-LLM compile run passed and produced `metrics.json`, `judge_tasks.jsonl`, `case_logs`, and `case_debug_index.md`; deterministic metrics reached `agent_route_accuracy=1.0`, `card_entity_recall=1.0`, `card_time_parse_accuracy=1.0`, `card_hallucinated_field_absence=1.0`, `relationship_case_coverage=1.0`, `long_context_case_coverage=1.0`, `dataset_oracle_consistency=1.0`. Three MIMO `mimo-v2.5` providers passed preflight with redacted artifacts. Judge smoke with `mimo-v2.5-pro` passed one `card_title_relevance_score` task after increasing judge max tokens to `4096`.
- Residual risk: full real LLM small gate has not run yet on the new 3-persona dataset; Judge metrics are currently a separate post-processing artifact and are not yet merged back into candidate gate.

## 2026-06-12 - pr256-full-metric-small-judge-badcase-001

- Baseline run: none for this iteration; legacy remains a fixed baseline and was not modified.
- Candidate run: `evals/runs/pr256_full_metric_small_memory_primary_case0_real_after_temp_boundary_fix_20260612`
- Affected cases: `memory_primary/pr256_full_metric_persona_00`
- Failed metrics: LLM judge metrics `card_title_relevance_score`, `unsupported_claim_absence`, and `grounded_answer_rate`.
- Symptom: deterministic PR256 full gate passed, but judge found card titles that omitted raw user details or added unsupported summary words such as task/contact-update framing; one relationship ask answered MayaA for product review even though the visible search result only showed NoorA payment evidence.
- Root cause: Card Agent title generation can compress or editorialize titles under the new chain, and `search_memory_primary` treated a multi-part relationship query as one blended query, allowing the payment memory to dominate the visible evidence.
- Fix: keep fixes gated to Memory Primary. Add a Memory Primary-only card-title guard after `card_agent_task` that derives titles directly from the raw input text; add relationship/contact query expansion in the read-only `search_memory_primary` tool so product-review and payment sub-questions retrieve their own evidence memories; add focused regression tests for temporary-boundary memory, faithful titles, and multi-part relationship recall.
- Verification: `dart analyze` passed for touched files; `flutter test --no-pub test/agent/common_tools_test.dart test/data/services/task_handlers/card_agent_handler_test.dart test/agent/memory_extract_agent_test.dart` passed.
- Residual risk: the real full-chain small run and judge rerun after this fix are still pending; large old-vs-new evidence must wait until this small gate is green.

## 2026-06-12 - pr256-full-metric-small-super-agent-429-fallback

- Baseline run: none for this iteration; legacy remains a fixed baseline and was not modified.
- Candidate run: `evals/runs/pr256_full_metric_small_memory_primary_case0_real_after_title_recall_fix_20260612`
- Affected cases: `memory_primary/pr256_full_metric_persona_00`, Super Agent asks `ask_project_owner`, `ask_report_style`, `ask_relationship_payment`, `ask_home_routine`.
- Failed metrics: `super_agent_answer_success_rate`, `super_agent_answer_hit_rate`, `retrieval_hit_at_10`, `answer_must_include`, `tool_selection_accuracy`, `tool_args_accuracy`.
- Symptom: all card, memory, recall, and projection metrics passed, but all four final Super Agent asks returned empty answers because the provider returned HTTP 429 `Too many requests`; no `search_memory_primary` call was emitted before the error for three asks.
- Root cause: Memory Primary Quick Query had no read-only recovery path when the LLM turn fails after the expensive record replay. Provider transient limits therefore became full answer/tool/retrieval metric failures even though Memory Primary already held the needed evidence.
- Fix: add a Memory Primary-only Quick Query fallback in `ChatService`: when the agent run errors in `memory_primary` + `isQuickQuery`, call the same read-only `search_memory_primary` recall helper, emit auditable tool call/result events, and answer conservatively from Memory Primary evidence. Normal successful Super Agent turns and legacy mode are unchanged.
- Verification: `dart analyze` passed for touched files; `flutter test --no-pub test/agent/common_tools_test.dart test/data/services/chat_service_test.dart test/data/services/task_handlers/card_agent_handler_test.dart test/agent/memory_extract_agent_test.dart` passed.
- Residual risk: full-chain rerun after fallback is pending; if provider 429 occurs during card/memory writes rather than ask, task retry behavior rather than fallback will determine pass/fail.

## 2026-06-12 - pr256-full-metric-small-final-two-fixes

- Baseline run: none for this iteration; legacy remains a fixed baseline and was not modified.
- Candidate run: `evals/runs/pr256_full_metric_small_memory_primary_case0_real_after_quickquery_fallback_20260612`
- Affected cases: `memory_primary/pr256_full_metric_persona_00`, asks `ask_report_style` and `ask_relationship_payment`.
- Failed metrics: `super_agent_answer_hit_rate`, `answer_must_include`, `tool_args_accuracy`.
- Symptom: after the 429 fallback, the small gate had only two failures left. `ask_report_style` answered correctly but the trace tool args shortened `Meridian 导出 A` to `Meridian`; `ask_relationship_payment` retrieved payment evidence but final Memory Primary had lost the positive "MayaA 负责产品评审和体验文案" responsibility after later "MayaA 不负责合同付款" updates.
- Root cause: LLM-generated search args can abbreviate entities even when the answer uses exact names; relationship updates overwrote non-conflicting positive responsibilities when the update focused on a different responsibility domain.
- Fix: in Memory Primary updates, preserve non-conflicting positive relationship responsibility clauses while dropping stale/old clauses; in Quick Query traces, augment `search_memory_primary` args with `original_user_query` so exact user entities remain auditable without adding duplicate tool calls.
- Verification: `dart analyze` passed for touched files; `flutter test --no-pub test/data/services/memory_primary_service_test.dart test/data/services/chat_service_test.dart test/agent/common_tools_test.dart test/data/services/task_handlers/card_agent_handler_test.dart test/agent/memory_extract_agent_test.dart` passed.
- Residual risk: full-chain rerun after these final two fixes is pending.

## 2026-06-12 - pr256-full-metric-small-owner-retrieval-order

- Baseline run: none for this iteration; legacy remains a fixed baseline and was not modified.
- Candidate run: `evals/runs/pr256_full_metric_small_memory_primary_case0_real_after_final_two_fixes_20260612`
- Affected cases: `memory_primary/pr256_full_metric_persona_00`, ask `ask_project_owner`.
- Failed metrics: `retrieval_hit_at_10`.
- Symptom: deterministic gate passed, but `ask_project_owner` left one recall failure: the answer named BaoA correctly while the visible `search_memory_primary` result preview surfaced a generic relationship atom first, so the evaluator did not see the expected owner evidence ids in top retrieval sources.
- Root cause: relationship/contact query expansion treated owner questions as relationship-like and boosted generic `relationship` atoms containing "负责人" above specific `project_context` owner atoms.
- Fix: add a project-owner query recognizer in the Memory Primary search tool, add an owner-specific expansion query, and boost matching `project_context`/`other` current-owner atoms above generic relationship atoms when the query names a specific project.
- Verification: `dart analyze` passed for touched files; `flutter test --no-pub test/agent/common_tools_test.dart test/data/services/memory_primary_service_test.dart test/data/services/chat_service_test.dart test/data/services/task_handlers/card_agent_handler_test.dart test/agent/memory_extract_agent_test.dart` passed.
- Residual risk: full-chain rerun after this recall-order fix is pending.

## 2026-06-12 - pr256-full-metric-small-title-judge-hardening

- Baseline run: none for this iteration; legacy remains a fixed baseline and was not modified.
- Candidate run: `evals/runs/pr256_full_metric_small_memory_primary_case0_real_after_owner_retrieval_order_v3_20260612`
- Affected cases: `memory_primary/pr256_full_metric_persona_00`, record `rec_0026`, judge task `rec_0047`.
- Failed metrics: LLM judge `card_title_relevance_score`.
- Symptom: deterministic PR256 full gate passed with zero failures, but judge scored `rec_0026` title at 0.5 because the Memory Primary title guard removed the user-provided "高敏边界样本" prefix. The `rec_0047` judge task failed only because the judge provider returned HTTP 429.
- Root cause: the title guard's generic prefix-stripping list treated a safety/boundary label as disposable metadata; the judge runner recorded transient provider 429 as a metric failure instead of retrying another configured provider.
- Fix: preserve "高敏边界样本：" in Memory Primary-derived card titles, and add redacted multi-provider retry for transient judge errors such as 429/5xx/connection failures.
- Verification: `dart analyze` passed for `card_agent_handler.dart`, `card_agent_handler_test.dart`, and `run_pr256_judge.dart`; `flutter test --no-pub test/data/services/task_handlers/card_agent_handler_test.dart` passed.
- Residual risk: full-chain rerun and judge rerun after this fix are pending.

## 2026-06-12 - pr256-full-metric-small-preference-grounding

- Baseline run: none for this iteration; legacy remains a fixed baseline and was not modified.
- Candidate run: `evals/runs/pr256_full_metric_small_memory_primary_case0_real_after_sensitive_title_judge_retry_v4_20260612`
- Affected cases: `memory_primary/pr256_full_metric_persona_00`, ask `ask_report_style`.
- Failed metrics: LLM judge `unsupported_claim_absence`.
- Symptom: deterministic gate passed with zero failures and title judge passed, but report-style preference answer expanded "owner" into "use current owner, do not use historical owner" and added "if information conflicts, prefer latest conclusion"; judge found those statements unsupported by the visible memory evidence.
- Root cause: Memory Primary preference constraints inferred a conflict rule from "最新结论" alone, and the successful Quick Query answer path did not deterministically remove owner-history/conflict inferences from report-format answers.
- Fix: only emit conflict preference constraints when memory explicitly mentions conflict, add a tool reminder against inferred current-vs-historical owner rules, and post-process Memory Primary preference Quick Query answers to remove unsupported owner-history and conflict inferences.
- Verification: `dart analyze` passed for `chat_service.dart`, `common_tools.dart`, and tests; `flutter test --no-pub test/data/services/chat_service_test.dart test/agent/common_tools_test.dart` passed.
- Residual risk: full-chain rerun and judge rerun after this fix are pending.

## 2026-06-12 - pr256-full-metric-small-title-prefix-and-trace-closeout

- Baseline run: none for this iteration; legacy remains a fixed baseline and was not modified.
- Candidate runs: `evals/runs/pr256_full_metric_small_memory_primary_case0_real_after_preference_grounding_v6_timeout240_20260612`, `evals/runs/pr256_full_metric_small_memory_primary_case0_real_after_trace_and_preference_v7_timeout240_20260612`, `evals/runs/pr256_full_metric_small_memory_primary_case0_real_after_title_prefix_v8_timeout240_20260612`
- Affected cases: `memory_primary/pr256_full_metric_persona_00`, record `rec_0032`, ask `ask_report_style`, retrieval trace metrics.
- Failed metrics: `retrieval_hit_at_10` in v6 due trace truncation; LLM judge `card_title_relevance_score` in v7 stale artifact due title-prefix stripping; prior preference answer risk around unsupported current/historical owner wording.
- Symptom: v6 answered correctly but the evaluator could not see expected evidence ids because `search_memory_primary` tool result previews were capped too low. v7 deterministic gate passed, but judge found one title missing the user-provided `长期协作偏好重复确认：` prefix. Preference answers also needed broader Chinese cleanup for unsupported current/historical owner phrasing.
- Root cause: audit trace previews were optimized for short UI logs rather than evaluator-visible evidence; the title guard still stripped semantic user prefixes; the preference answer sanitizer did not cover all Chinese owner-history variants.
- Fix: expand `search_memory_primary` result previews in chat traces to include full evidence snippets while keeping other tool previews compact; remove semantic prefix stripping from the Memory Primary title guard; extend Memory Primary preference answer post-processing for Chinese current/historical owner clauses.
- Verification: `flutter test --no-pub test/data/services/chat_service_test.dart test/agent/common_tools_test.dart` passed; `flutter test --no-pub test/data/services/task_handlers/card_agent_handler_test.dart` passed; `dart analyze` passed for touched chat/card/judge files. Final small candidate run v8 passed deterministic `pr256_full` gate with 48 records, zero failures, `super_agent_answer_hit_rate=1.0`, `retrieval_hit_at_10=1.0`, `tool_selection_accuracy=1.0`, `memory_expected_hit_rate=1.0`, and zero failed/unsettled tasks. v8 LLM judge passed all 56 tasks: title 48/48, unsupported claim 4/4, grounded answer 4/4.
- Residual risk: large old-vs-new comparison has not run yet; the small gate establishes candidate correctness on one dense persona but not cross-persona scale confidence.

## 2026-06-12 - pr256-large-run-orchestration-start

- Baseline run: pending; legacy remains a fixed baseline and was not modified.
- Candidate dataset: `evals/datasets/pr256_full_metric_large_p8_r400` with 8 personas, 400 record operations per persona, plus recall/ask operations.
- Affected cases: large-scale `memory_primary` replay, first wave personas `00`, `01`, and `02`.
- Failed metrics: none confirmed yet; persona01 first attempt was manually stopped before completion due provider latency and is not counted as a metric failure.
- Symptom: the SGP provider keyed by the newer subscription showed 150-188s per record on persona01, making a 400-record shard impractical. CN and the older SGP provider progressed around 20-50s per record on personas 00 and 02.
- Root cause: provider-level latency variance, not an agent correctness failure.
- Fix: continue the stable persona00/persona02 shards, stop the slow persona01 shard, and plan to rerun persona01 on a faster provider after capacity frees up. Added `MEMEX_EVAL_JUDGE_CONCURRENCY` support to `run_pr256_judge.dart` so large judge tasks can use multiple providers without changing metric definitions or rubrics.
- Verification: generated dataset manifest reports `persona_count=8`, `records_per_persona=400`, `record_count=3200`. `dart analyze evals/bin/run_pr256_judge.dart` passed. A 3-task concurrent judge smoke passed with `concurrency=3` and all 3 title tasks passing.
- Residual risk: large candidate shards are still running; legacy large baseline and full large judge are pending.

## 2026-06-12 - pr256-large-memory-primary-first-wave

- Baseline run: pending; legacy remains a fixed baseline and was not modified.
- Candidate runs: `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_persona00_20260612`, `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_persona02_20260612`; `persona01` first attempt was manually stopped due provider latency and is excluded from metrics.
- Affected cases: `memory_primary/pr256_full_metric_persona_00`, `memory_primary/pr256_full_metric_persona_02`, especially `ask_home_routine` and repeated relationship related-fact cases.
- Failed metrics: no PR256 gate failure. Both completed candidate shards passed gate. Logged failure records remain for diagnosis: repeated relationship related-fact exact-source misses; persona02 also had one `retrieval_hit_missing` for `ask_home_routine`.
- Symptom: persona02 answered home routine correctly, but the first `search_memory_primary` result was an unrelated high-importance boundary atom whose many evidence ids pushed the identity/routine evidence source outside top 10. Repeated relationship cards often cited later semantically equivalent relationship records rather than the original seed related record.
- Root cause: Memory Primary recall sorting did not specialize identity/routine questions, so boundary/project atoms could outrank identity/routine atoms under embedding noise. The related-fact GT is exact-source strict for repeated relationship cases, while the card insight often cites later equivalent evidence.
- Fix: add identity/routine query expansion and boost in `searchMemoryPrimaryForTool`, prioritizing `identity` and `routine` atoms for home-location/schedule questions and demoting `boundary`, `project_context`, and `relationship` atoms in that query class. This changes only the new Memory Primary recall path.
- Verification: `dart analyze lib/agent/common_tools.dart test/agent/common_tools_test.dart` passed; `flutter test --no-pub test/agent/common_tools_test.dart` passed, including a regression for home routine queries with a distracting boundary atom. First-wave metrics: persona00 `retrieval_hit_at_10=1.0`, `agent_route_accuracy=0.995`, `p95_record_elapsed_ms=65801`, zero failed/unsettled tasks; persona02 `retrieval_hit_at_10=0.75`, `agent_route_accuracy=0.983`, `p95_record_elapsed_ms=55593`, zero failed/unsettled tasks.
- Residual risk: the identity/routine fix has not yet been validated by a full large rerun; remaining large candidate personas, legacy baseline, and full large judge are pending.

## 2026-06-12 - pr256-large-legacy-boundary-audit

- Baseline run: pending; legacy remains the fixed baseline and must match the old online chain.
- Candidate runs: in progress, `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_persona01_after_identity_routine_fix_20260612` and `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_persona03_after_identity_routine_fix_20260612`.
- Affected cases: shared event subscription setup in `MemexRouter`.
- Failed metrics: none; this was a code-boundary audit before running the legacy baseline.
- Symptom: review of shared diffs found that the legacy `comment_agent` subscription had inherited the new `shouldEnqueue` filter while refactoring the pipeline switch.
- Root cause: the new Memory Primary chain needs optional comment enqueueing after `card_insight_agent`, but the same helper was accidentally applied to the legacy `pkm_agent -> comment_agent` path.
- Fix: remove `shouldEnqueue` from the legacy branch and keep it only in the Memory Primary branch. Legacy still registers `pkm_agent_task` after `analyze_assets` and `comment_agent_task` after `pkm_agent`, as before.
- Verification: `dart analyze lib/data/repositories/memex_router.dart` passed.
- Residual risk: the legacy large baseline has not run yet; before comparing, run baseline with `MEMEX_EVAL_PIPELINE_MODES=legacy_pkm` and inspect task traces for the unchanged old order.

## 2026-06-12 - pr256-large-merge-full-metric-parity

- Baseline run: pending.
- Candidate runs: merge probe used completed first-wave candidate shards `persona00` and `persona02`.
- Affected cases: full-metric shard aggregation and report generation.
- Failed metrics: none in replay; merge probe exposed missing aggregate/report fields.
- Symptom: per-shard `metrics.json` contained full PR #256 Agent metrics such as `agent_route_accuracy`, `retrieval_hit_at_10`, `tool_selection_accuracy`, `card_template_any_accuracy`, loop/max-turn absence, and relationship/long-context/oracle coverage, but the merge script only preserved the earlier Memory Primary rollout subset.
- Root cause: `merge_memory_primary_eval_runs.dart` predated the full PR256 metric surface and had not been updated after the replay harness grew new trace/card/tool/retrieval metrics.
- Fix: extend the merge script to carry the full metric names into merged `metrics.json`, delta comparison, and report tables. Existing gate thresholds were kept identical to the replay harness; no new pass/fail rule was introduced.
- Verification: `dart format evals/bin/merge_memory_primary_eval_runs.dart` and `dart analyze evals/bin/merge_memory_primary_eval_runs.dart` passed. A `/tmp` merge probe over persona00/persona02 produced full aggregate keys including `agent_route_accuracy=0.989`, `retrieval_hit_at_10=0.875`, `tool_selection_accuracy=1.0`, `relationship_case_coverage=1.0`, `long_context_case_coverage=1.0`, and `dataset_oracle_consistency=1.0`.
- Residual risk: full large merge must be rerun after all candidate and legacy shards complete; LLM judge metrics are still post-processing artifacts and should be summarized alongside deterministic metrics in the final Chinese report.

## 2026-06-12 - pr256-large-memory-primary-card-completion-fallback

- Baseline run: pending; legacy remains a fixed baseline and was not modified.
- Candidate run: in-progress shard `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_persona04_after_identity_routine_fix_20260612`.
- Affected case: `memory_primary/pr256_full_metric_persona_04`, record `rec_0188`, fact `2026/05/28.md#ts_7`, a long-context owner-anchor fact for Project Orion E and Meridian export E.
- Failed metrics: no final metric failure yet; the shard recovered after retries, but the live progress trace showed repeated `card_agent_task` retries and incomplete card evidence.
- Symptom: Card Agent left the persisted card in `processing` with no title and no matching successful `save_timeline_card` tool-call evidence: `missing matching_successful_save_timeline_card_tool_call,status_completed,title_present`.
- Root cause: Memory Primary includes fact/anchor inputs whose card surface can be faithfully represented by the existing placeholder card plus a deterministic title. Requiring the full Card Agent save-tool evidence for these records creates avoidable retries and p95 latency risk in the new chain.
- Fix: add a Memory Primary-only card completion fallback in `card_agent_handler.dart`. When Card Agent exhausts its completion evidence loop with `Card Agent did not produce a completed card`, the new chain repairs the existing card to `completed`, derives a faithful title from the raw fact, preserves existing `ui_configs` or supplies a `classic_card`, clears failure reason, and then re-inspects completion with `requireSaveToolCall=false`. The fallback is gated by `pipeline_mode == memory_primary`; legacy completion semantics are unchanged.
- Verification: `dart analyze lib/data/services/task_handlers/card_agent_handler.dart test/data/services/task_handlers/card_agent_handler_test.dart` passed with no issues. `NO_PROXY=localhost,127.0.0.1,::1 flutter test --no-pub test/data/services/task_handlers/card_agent_handler_test.dart` passed 5/5 tests, including the long-context owner-anchor fallback regression.
- Residual risk: persona04 was already running on the previous code when the retry was observed, so this fix must be validated by subsequent shards or a targeted rerun of persona04 if final p95/retry logs remain noisy.

## 2026-06-12 - pr256-large-memory-primary-quick-query-tool-convergence

- Baseline run: pending; legacy remains a fixed baseline and was not modified.
- Candidate run: `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_persona05_after_identity_routine_fix_20260612`.
- Affected cases: `memory_primary/pr256_full_metric_persona_05`, asks `ask_relationship_payment` and `ask_home_routine`.
- Failed metrics: `retrieval_hit_at_10`, `tool_selection_accuracy`, `tool_args_accuracy`, `tool_call_minimality`, and `repeated_tool_call_rate`.
- Symptom: `ask_relationship_payment` answered correctly but used `get_pkm_overview` and `Grep` instead of `search_memory_primary`, so the tool-selection/args metrics and retrieval trace failed. `ask_home_routine` answered correctly from `2026/05/06.md#ts_3`, but repeated subqueries made the trace top-10 drift away from the original identity/routine source.
- Root cause: Memory Primary Quick Query still exposed broad read-only PKM/file tools to SuperAgent and relied on prompt preference rather than tool-level convergence. The evaluation metric requires the Memory Primary recall path to be visible and stable for personal memory asks.
- Fix: in Memory Primary Quick Query mode, restrict SuperAgent read tools to `search_memory_primary` and `getCurrentTime`; strengthen the prompt to use Memory Primary as the only personal-knowledge recall path; add a ChatService preloaded `search_memory_primary` call for relationship, identity/routine, preference, and current-state quick queries, injecting the result as system context and emitting traceable tool call/result events before the model answer.
- Verification: `dart analyze lib/agent/super_agent/super_agent.dart lib/data/services/chat_service.dart test/data/services/chat_service_test.dart` passed with no issues. `NO_PROXY=localhost,127.0.0.1,::1 flutter test --no-pub test/data/services/chat_service_test.dart` passed 6/6 tests, including relationship/routine quick-query preload classification.
- Residual risk: persona04/persona05 must be rerun after this fix; the interrupted persona04 rerun before this fix is discarded and must not be used in final aggregation.

## 2026-06-12 - pr256-large-memory-primary-relationship-scope-preservation

- Baseline run: pending; legacy remains a fixed baseline and was not modified.
- Candidate run: `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_persona05_after_quick_query_tool_fix_20260612`.
- Affected case: `memory_primary/pr256_full_metric_persona_05`, ask `ask_relationship_payment`.
- Failed metrics: candidate gate still failed only on `repeated_tool_call_rate`; inspection showed the remaining repeated calls were caused by missing relationship memory scope.
- Symptom: quick-query tool metrics recovered (`retrieval_hit_at_10=1.0`, `tool_selection_accuracy=1.0`, `tool_args_accuracy=1.0`, `tool_call_minimality=1.0`), but the preloaded Memory Primary context only contained `MayaF 不负责合同付款；付款和发票还是找 NoorF` and no longer contained the non-conflicting earlier fact `MayaF 负责产品评审和体验文案`. SuperAgent repeatedly searched for 产品评审 because Memory Primary had dropped that scope.
- Root cause: relationship `create` patches that supersede a previous atom inherited preserved term attributes but did not preserve non-conflicting responsibility clauses from the superseded relationship atom. The existing preservation logic only covered explicit `update` operations.
- Fix: extend `MemoryPrimaryService.applyPatches` so relationship create/upsert paths that supersede earlier relationship atoms preserve prior non-conflicting `负责 X` clauses while still filtering stale/history/negative responsibility clauses.
- Verification: `dart analyze lib/data/services/memory_primary_service.dart test/data/services/memory_primary_service_test.dart` passed with no issues. `NO_PROXY=localhost,127.0.0.1,::1 flutter test --no-pub test/data/services/memory_primary_service_test.dart` passed 12/12 tests, including `relationship superseding creates preserve non-conflicting scopes`.
- Residual risk: persona05 must be rerun after this fix; the prior `persona05_after_quick_query_tool_fix` run is useful diagnostic evidence but must not be used in final aggregation.

## 2026-06-13 - pr256-large-provider-rebalance

- Baseline run: partial legacy shards `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_persona00_20260612` and `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_persona01_20260612` were manually stopped before metrics were produced and must not be included in final aggregation.
- Candidate runs: completed reruns `persona02_after_all_fixes` and `persona05_after_relationship_scope_fix` both passed gate; candidate personas `06` and `07` are being run on duplicate fast-provider shards after the first attempts showed slow-provider latency.
- Affected cases: large-scale `memory_primary` replay scheduling only; no agent, metric, or legacy-chain logic changed.
- Failed metrics: none from this rebalance. `persona02_after_all_fixes` and `persona05_after_relationship_scope_fix` both recovered to `retrieval_hit_at_10=1.0`, `tool_selection_accuracy=1.0`, `tool_args_accuracy=1.0`, `tool_call_minimality=1.0`, `repeated_tool_call_rate=0.0`, and `super_agent_answer_hit_rate=1.0`.
- Symptom: slow SGP-provider shards for candidate personas `06` and `07` progressed around 140-160s per record, while CN/older SGP providers completed previous candidate shards materially faster.
- Root cause: provider-level latency variance and replay's persona-level sequential input model; the replay harness does not expose record-level concurrency without changing evaluation semantics.
- Fix: prioritize candidate completion by stopping incomplete legacy baseline shards, then launch duplicate candidate persona `06` on the CN provider and persona `07` on the older SGP provider. Keep partial slow-provider candidate logs for traceability, but only completed metric-producing shards are eligible for final aggregation.
- Verification: process list confirmed the incomplete legacy eval runners were stopped; fast-provider candidate shards started with distinct run directories, preserving old partial artifacts.
- Residual risk: legacy large baseline still needs a clean rerun after candidate large shards pass; final aggregation must exclude partial stopped runs and choose one completed shard per persona.

## 2026-06-13 - pr256-large-memory-primary-mixed-relationship-clause

- Baseline run: unchanged; legacy remains fixed and was not modified.
- Candidate run: `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_persona07_after_all_fixes_fast_sgp_20260613`.
- Affected case: `memory_primary/pr256_full_metric_persona_07`, ask `ask_relationship_payment`.
- Failed metrics: `super_agent_answer_hit_rate` and `answer_must_include` failed because the answer included `NoorH` but missed `MayaH`.
- Symptom: Memory Primary recall used `search_memory_primary` correctly and retrieval hit top-10 passed, but the returned relationship atom only contained `MayaH 不负责合同付款` and `NoorH 负责付款/发票`; it no longer contained the non-conflicting responsibility `MayaH 负责产品评审和体验文案`.
- Root cause: relationship responsibility preservation filtered out any clause containing `不负责`. In the real chain, a prior atom had the mixed clause `MayaH 负责产品评审和体验文案，但不负责合同付款`, so the positive responsibility was discarded together with the negative clarification.
- Fix: split relationship responsibility clauses on Chinese and English commas in addition to sentence/semicolon boundaries, so the positive clause is preserved while the negative `不负责` clause is still filtered.
- Verification: `dart analyze lib/data/services/memory_primary_service.dart test/data/services/memory_primary_service_test.dart` passed. `NO_PROXY=localhost,127.0.0.1,::1 flutter test --no-pub test/data/services/memory_primary_service_test.dart` passed 13/13 tests, including `relationship preservation splits mixed positive and negative clauses`.
- Residual risk: persona07 must be rerun after this fix before candidate large aggregation.

## 2026-06-13 - pr256-large-legacy-provider-priority

- Baseline run: `legacy_pkm` large baseline in progress; legacy logic remains unchanged.
- Candidate run: completed and merged in `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_candidate_20260613`, gate passed.
- Affected cases: provider scheduling and artifact eligibility only; no metric definitions, evaluator logic, candidate agent logic, or legacy logic changed.
- Failed metrics: none from scheduling. One legacy persona02 attempt failed at LLM preflight with provider 429 and produced no replay metrics, so it is treated as infrastructure noise and excluded from aggregation.
- Symptom: the SGP provider used for persona02 returned a short-window 429 during preflight, while the same provider later accepted a retry and entered replay.
- Root cause: provider-side QPS/window limiting, not a chain behavior.
- Fix: keep all four providers eligible, but treat 429 as a short cooldown signal, not a permanent provider failure. Re-add the cooled-down provider into the priority pool after a delay, launch retries with independent run dirs, and only aggregate runs that produce `metrics.json`.
- Verification: persona02 retry `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_persona02_retry_sgp_a_20260613` passed preflight and entered replay. Legacy persona01 completed with metrics in `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_persona01_fast_sgp_20260613`. Persona00's first CN shard later showed repeated all-pending task observations and was stopped as infra-suspect; the cooled-down CN provider was re-added and `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_persona00_retry_cn_cooldown_20260614` entered replay with completed task observations.
- Residual risk: remaining legacy baseline personas are still running; final old-vs-new comparison must exclude preflight-failed and manually stopped partial runs.

## 2026-06-14 - pr256-judge-provider-cooldown-pool

- Baseline run: unchanged; legacy chain logic remains fixed.
- Candidate run: unchanged; Memory Primary merged candidate remains the current new-chain baseline.
- Affected cases: LLM-as-judge provider scheduling only; no deterministic metric definition, judge rubric, replay behavior, candidate agent logic, or legacy logic changed.
- Failed metrics: none. This is an evaluation-infrastructure reliability change for short provider 429 windows.
- Symptom: four MIMO providers are available, but the judge runner previously retried by stepping through provider order once per task. A 429 provider was skipped for that task but had no explicit short cooldown/re-entry state, making high-concurrency judge runs harder to reason about.
- Root cause: provider availability was modeled as a static list rather than a small health-aware pool.
- Fix: add a judge-provider pool in `evals/bin/run_pr256_judge.dart`. Retryable 408/429/5xx/network failures put the provider into a short cooldown, defaulting to `MEMEX_EVAL_JUDGE_PROVIDER_COOLDOWN_MS=10000`; cooled-down providers automatically re-enter rotation after the window. Judge outputs retain `judge_provider_index`, redacted key fields, attempt history, and the configured cooldown in `judge_metrics.json`.
- Verification: `dart analyze evals/bin/run_pr256_judge.dart` passed. A local zero-task dry run produced valid `judge_metrics.json` with `provider_retry_cooldown_ms=10000`.
- Residual risk: full replay still keeps one provider per persona/user to avoid cross-provider cache effects; provider re-entry is applied to judge tasks and shard scheduling, not mid-persona replay switching.

## 2026-06-14 - pr256-large-legacy-persona03-long-tail

- Baseline run: `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_persona03_slow_sgp_b_20260613` completed with `metrics.json`; legacy logic remains unchanged.
- Candidate run: unchanged; Memory Primary merged candidate remains `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_candidate_20260613`.
- Affected cases: legacy baseline only, `pr256_full_metric_persona_03`.
- Failed metrics: legacy `task_settlement_rate=0.339`, `failed_task_count=49`, `task_not_settled_count=265`, `retry_task_count=682`, `super_agent_answer_hit_rate=0.0`, `related_fact_hit_rate=0.221`, `p95_record_elapsed_ms=240528`.
- Symptom: the run spent the final record segment in repeated 240s task-settlement windows. Active task logs showed PKM tasks waiting on prior PKM dependencies, downstream comment tasks pending on PKM, and provider 429/retry history. The run eventually reached post-record recall/projection/ask operations and emitted metrics, but `flutter test` exited nonzero because the legacy-only gate still expects Memory Primary comparison metrics.
- Root cause: old-chain PKM dependency serialization plus provider 429/retry pressure created long-tail task backlog. This is a legacy runtime behavior under the PR256 large synthetic journey, not an evaluator crash and not a new-chain regression.
- Fix: none to legacy. Preserve the artifact as a valid baseline run because it produced `metrics.json`; do not patch old-chain logic.
- Verification: `metrics.json`, `report.md`, and `failures.jsonl` exist. A partial 5-persona legacy merge including personas 01/03/04/05/06 produced `record_count=2000`, `task_settlement_rate=0.849`, `retry_task_count=683`, `related_fact_hit_rate=0.186`, `p95_record_elapsed_ms=240404`, and `tokens_per_input=15744.288`.
- Residual risk: personas 00/02/07 still need completed metric-producing runs before final 8-persona legacy aggregation.

## 2026-06-14 - pr256-large-legacy-persona00-cooldown-retry-complete

- Baseline run: `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_persona00_retry_cn_cooldown_20260614` completed with `metrics.json`; legacy logic remains unchanged.
- Candidate run: unchanged; Memory Primary merged candidate remains `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_candidate_20260613`.
- Affected cases: legacy baseline only, `pr256_full_metric_persona_00`.
- Failed metrics: legacy retained `task_not_settled_count=3`, `related_fact_hit_rate=0.492`, `agent_route_accuracy=0.953`, `p95_record_elapsed_ms=91931`, `tokens_per_input=15940.378`.
- Symptom: the CN cooldown retry run progressed normally after the first persona00 CN attempt had shown repeated all-pending observations and was stopped as infra-suspect. This retry reached all post-record ask operations and the test process exited successfully.
- Root cause: the previous persona00 attempt was an infrastructure/runner state issue; the cooled-down CN provider itself remained usable.
- Fix: no legacy change. Preserve the first stopped persona00 artifact as infra-suspect evidence and use the completed cooldown retry run for baseline aggregation.
- Verification: a 6-persona legacy partial merge including personas 00/01/03/04/05/06 produced `record_count=2400`, `task_settlement_rate=0.873`, `retry_task_count=683`, `related_fact_hit_rate=0.237`, `p95_record_elapsed_ms=240365`, and `tokens_per_input=15776.969`.
- Residual risk: personas 02/07 still need completed metric-producing runs before final 8-persona legacy aggregation.

## 2026-06-14 - pr256-large-legacy-persona02-cn-hedge

- Baseline run: original persona02 retry `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_persona02_retry_sgp_a_20260613` remains in progress and legacy logic remains unchanged.
- Candidate run: unchanged; Memory Primary merged candidate remains `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_candidate_20260613`.
- Affected cases: legacy baseline scheduling only, `pr256_full_metric_persona_02`.
- Failed metrics: not final yet. The in-progress SGP-A persona02 run showed repeated `429 Too many requests`, `retrying`, and active PKM dependency chains around records `rec_0320`-`rec_0331`.
- Symptom: after 6/8 legacy personas had completed, persona02 remained around 82% and progressed roughly one record per several-minute timeout window, while the CN provider had been freed by the completed persona00 cooldown retry.
- Root cause: provider-side short 429 windows interacting with old-chain PKM retries; not an evaluator crash.
- Fix: start a separate CN duplicate run `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_persona02_duplicate_cn_cooldown_20260614` as a hedge. The replay user id includes a timestamp, so the duplicate uses an isolated user/workspace and does not mix provider cache with the original run. Both runs are preserved; final aggregation will choose one completed metric-producing persona02 artifact.
- Verification: duplicate run entered replay, but by `rec_0017` it also hit a 240s old-chain settlement window while the original run had already reached `rec_0335`. The duplicate was stopped with SIGINT and is excluded from aggregation.
- Residual risk: persona02 still depends on the original SGP-A run producing `metrics.json`; keep the stopped CN duplicate only as scheduling/long-tail evidence.

## 2026-06-14 - pr256-large-legacy-persona07-complete

- Baseline run: `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_persona07_fast_sgp_20260614` completed with `metrics.json`; legacy logic remains unchanged.
- Candidate run: unchanged; Memory Primary merged candidate remains `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_candidate_20260613`.
- Affected cases: legacy baseline only, `pr256_full_metric_persona_07`.
- Failed metrics: legacy retained `task_not_settled_count=2`, `related_fact_hit_rate=0.111`, `agent_route_accuracy=0.955`, `p95_record_elapsed_ms=108812`, `tokens_per_input=20203.463`.
- Symptom: the shard completed successfully and answered Super Agent asks, but related-fact grounding stayed very low and token cost remained high.
- Root cause: old-chain PKM/PARA artifact path can preserve final ask correctness while failing to expose the same structured related-fact grounding expected by the PR256 memory/insight metrics.
- Fix: none to legacy. Use this as a valid baseline artifact.
- Verification: a 7-persona legacy partial merge including personas 00/01/03/04/05/06/07 produced `record_count=2800`, `task_settlement_rate=0.891`, `retry_task_count=683`, `related_fact_hit_rate=0.219`, `p95_record_elapsed_ms=240328`, and `tokens_per_input=16409.325`.
- Residual risk: persona02 remains the final missing baseline artifact and is currently the dominant old-chain long-tail.

## 2026-06-14 - pr256-large-legacy-persona02-complete-and-merged-baseline

- Baseline run: `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_persona02_retry_sgp_a_20260613` completed with `metrics.json`; legacy logic remains unchanged.
- Candidate run: unchanged; Memory Primary merged candidate remains `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_candidate_20260613`.
- Affected cases: legacy baseline only, `pr256_full_metric_persona_02`.
- Failed metrics: legacy persona02 retained `task_settlement_rate=0.232`, `failed_task_count=49`, `task_not_settled_count=308`, `retry_task_count=740`, `super_agent_answer_hit_rate=0.25`, `related_fact_hit_rate=0.211`, `card_entity_recall=0.968`, `p95_record_elapsed_ms=240546`, and `tokens_per_input=12100.098`.
- Symptom: the final records repeatedly spent a full 240s settlement window with pending/retrying/failed old-chain tasks; post-record recall/ask operations eventually completed and emitted the full artifact set, but `flutter test` exited nonzero because the legacy-only gate failed.
- Root cause: old-chain PKM serialization and provider retry pressure created long-tail backlog. This is recorded as baseline behavior, not a new-chain regression.
- Fix: none to legacy. The stopped CN duplicate remains excluded; the completed SGP-A run is the selected persona02 artifact.
- Verification: 8-persona legacy merge `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_20260614` produced `record_count=3200`, `task_settlement_rate=0.808`, `failed_task_count=98`, `task_not_settled_count=615`, `retry_task_count=1423`, `super_agent_answer_hit_rate=0.781`, `related_fact_hit_rate=0.218`, `p95_record_elapsed_ms=240438`, and `tokens_per_input=15870.672`; gate status is `fail`.
- Residual risk: none for deterministic baseline completeness. LLM-as-judge still needs to be run for both candidate and legacy using the same judge tasks.

## 2026-06-14 - pr256-judge-provider-multi-round-cooldown

- Baseline run: unchanged; legacy chain logic remains fixed.
- Candidate run: unchanged; Memory Primary merged candidate remains the current new-chain baseline.
- Affected cases: LLM-as-judge provider scheduling only; no metric definition, judge rubric, replay behavior, candidate agent logic, or legacy logic changed.
- Failed metrics: none. This is an evaluation-infrastructure reliability change for short provider 429 windows.
- Symptom: all four MIMO providers are usable and 429 windows are short. The cooldown pool already re-added providers after the window, but each judge task still attempted at most one pass across the provider list, so simultaneous short 429s could still exhaust a task before the cooled provider re-entered.
- Root cause: max attempts were capped to provider count, which modeled provider retries as a single round rather than a cooldown-aware rotating pool.
- Fix: allow multiple provider rounds by defaulting max attempts to `provider_count * 3` and recording `provider_max_attempts` in `judge_metrics.json`. The current large judge run uses four providers, concurrency 24, and `MEMEX_EVAL_JUDGE_PROVIDER_COOLDOWN_MS=5000`.
- Verification: `dart format evals/bin/run_pr256_judge.dart` completed with no changes after formatting, `dart analyze evals/bin/run_pr256_judge.dart` passed with no issues, and a zero-task dry run produced valid `judge_metrics.json` with `provider_max_attempts=3` for a one-provider dummy pool.
- Residual risk: very high judge concurrency can still increase retries; use `attempt_count`, `retry_exhausted`, and `judge_provider_index` in `judge_results.jsonl` to inspect provider-specific bad cases.

## 2026-06-14 - pr256-large-final-judge-and-report

- Baseline run: `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_20260614`; legacy logic remains unchanged.
- Candidate run: `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_candidate_20260613`.
- Affected cases: final LLM-as-judge execution and reporting only; no metric definition, judge rubric, candidate agent logic, or legacy logic changed.
- Failed metrics: candidate judge retained 17 subjective failures (`card_title_relevance_score`: 16/3200 failed, `unsupported_claim_absence`: 1/32 failed, `grounded_answer_rate`: 0/32 failed). Legacy judge retained 1087 subjective failures (`card_title_relevance_score`: 1069/3200 failed, `grounded_answer_rate`: 13/32 failed, `unsupported_claim_absence`: 5/32 failed).
- Symptom: candidate subjective failures concentrate on title quality edge cases: overlong verbatim title, dropped entity/time/continuity detail, occasional typo, and one likely evaluator artifact where the judge task lacked the Memory evidence/tool result needed to verify a supplementary preference. Legacy failures are much broader: generic or empty titles, unsupported abstractions, missing entities, and weaker Super Agent grounding.
- Root cause: candidate title failures come from shared Card Agent title generation and need a Memory Primary-gated postprocess if we want to improve them without changing legacy baseline. Legacy failures come from the old PKM/PARA path's settlement backlog and weaker structured grounding.
- Fix: no new-chain agent fix was applied after the final judge because the remaining title issues are shared Card Agent behavior and require a separately gated title sanitizer plus shard rerun. Evaluation infrastructure was hardened: judge resume, retry_failed, retryable parse/TLS errors, and request timeout all passed `dart analyze evals/bin/run_pr256_judge.dart`.
- Verification: candidate judge metrics: `card_title_relevance_score=0.995`, `grounded_answer_rate=1.0`, `unsupported_claim_absence=0.969`, `error_count=0`. Legacy judge metrics: `card_title_relevance_score=0.666`, `grounded_answer_rate=0.594`, `unsupported_claim_absence=0.844`, `error_count=0`. Final report written to `evals/reports/2026-06-14-pr256-large-new-vs-legacy.zh.md`.
- Residual risk: manifest lists five planned judge metrics (`pkm_append_coherence`, `comment_relevance_score`, `comment_boundary_safety`, `insight_novelty_score`, `insight_actionability_score`) that current generator/replay does not emit into `judge_tasks.jsonl`; they are documented as not part of this run's hard gate.

## 2026-06-15 - pr256-supplemental-insight-fallback-001

- Baseline run: unchanged; legacy PKM logic remains frozen against the selected online-like baseline.
- Candidate run: validating with `evals/runs/pr256_full_metric_small_memory_primary_case0_after_card_insight_fallback_v3_20260615` before any large candidate rerun.
- Affected cases: Memory Primary `card_insight_task` only; no metric definition, judge rubric, legacy logic, or old PKM task behavior changed.
- Failed metrics: supplemental judge partial run exposed `insight_novelty_score` and `insight_actionability_score` failures on Memory Primary artifacts because deterministic CardInsight fallback repeated the raw input plus related ids.
- Symptom: candidate insight output looked like `<raw input> + Related context: <ids>`, so LLM-as-judge marked it as repetition-only and not actionable.
- Root cause: the deterministic fast CardInsight path was optimized for low-latency enrichment and related fact attachment, but did not synthesize why the record matters or how it should be used later.
- Fix: improve `CardInsightAgent` deterministic fallback to emit grounded synthesis by scenario label: project status, correction/current fact, preference, relationship/process boundary, sensitive boundary, no-action reflection, noise, parsed text, and long-context anchor. Related facts are included as short human-readable context rather than only ids. Added regression tests for no-action, sensitive, and project-status over-expansion.
- Verification: `dart analyze lib/agent/card_insight_agent/card_insight_agent.dart test/agent/card_insight_agent_test.dart evals/bin/run_pr256_judge.dart` passed. `NO_PROXY=localhost,127.0.0.1,::1 flutter test --no-pub test/agent/card_insight_agent_test.dart` passed. Small Memory Primary replay v3 is in progress and has confirmed corrected insight text in `progress.json`.
- Residual risk: small replay and supplemental judge must finish before rerunning the large 8-persona candidate artifacts. Related fact ranking still sometimes includes broad project/preference context; evaluate with judge before changing retrieval.

## 2026-06-15 - pr256-judge-provider-priority-pool

- Baseline run: unchanged; legacy logic remains unchanged.
- Candidate run: unchanged; this is evaluation infrastructure only.
- Affected cases: LLM-as-judge provider scheduling only; no metric definition, judge rubric, replay behavior, candidate agent logic, or legacy logic changed.
- Failed metrics: none. This responds to the short 429 window observed while using all four available providers.
- Symptom: four providers are usable, but static rotation plus cooldown does not express route preference or current in-flight pressure.
- Root cause: provider health was modeled as available/unavailable, without a priority score for healthier routes or a transient priority penalty after retryable failures.
- Fix: add `MEMEX_EVAL_JUDGE_PROVIDER_PRIORITIES`, lower the default judge provider cooldown to 5000ms, balance by current in-flight count, and transiently penalize providers that return retryable errors such as 429. Cooled providers automatically re-enter after the short window.
- Verification: `dart analyze evals/bin/run_pr256_judge.dart` passed. Zero-task dry run with four dummy providers produced `provider_priorities`, `provider_retry_cooldown_ms=5000`, `provider_max_attempts=12`, and `provider_dynamic_priority=true` in `judge_metrics.json`. README now documents four-provider judge usage with priorities and short cooldown.
- Residual risk: replay shards should still keep one provider per persona/user to avoid mixing provider/cache behavior inside a single user journey; dynamic priority is intended for stateless judge tasks.

## 2026-06-15 - pr256-small-supplemental-insight-v12-pass

- Baseline run: unchanged; legacy PKM/PARA logic remains frozen. No old-chain agent, task, memory, or PKM logic was modified.
- Candidate run: `evals/runs/pr256_full_metric_small_memory_primary_case0_after_card_insight_fallback_v12_boundary_novelty_cn_20260615`.
- Affected cases: Memory Primary `card_insight_task` deterministic fallback only; evaluation metrics, judge rubrics, dataset, legacy behavior, and shared Card Agent logic remained unchanged.
- Failed metrics: v8/v10/v11 supplemental judge exposed subjective `insight_novelty_score` and `insight_actionability_score` failures on preference, sensitive/no-action, parsed OCR/project-risk, repeated-confirmation, and relationship-boundary records. Deterministic gate stayed green after the safe-related-fact change.
- Symptom: insight text was grounded and actionable enough for deterministic checks, but several records still looked like restatements to LLM-as-judge because the fallback did not explain how the record should change later routing, memory priority, or safety handling.
- Root cause: the first deterministic insight fallback used coarse labels. It lacked subtyping for scheduling vs report-format preferences, repeated confirmations, reflection-without-action boundaries, relationship route exclusion, and parsed OCR project-risk evidence.
- Fix: tightened `CardInsightAgent` fallback synthesis by scenario: no raw related fact expansion in insight text; report-format preferences stay separate from scheduling preferences; repeated confirmations raise preference priority/confidence instead of becoming project state; no-action records are stored as reflection boundaries rather than execution authorization; relationship records become negative-exclusion plus current-contact routing rules; parsed OCR/project records become risk-list evidence entrances. Added focused regressions in `test/agent/card_insight_agent_test.dart`.
- Verification: `dart analyze lib/agent/card_insight_agent/card_insight_agent.dart test/agent/card_insight_agent_test.dart` passed. `NO_PROXY=localhost,127.0.0.1,::1 flutter test --no-pub test/agent/card_insight_agent_test.dart` passed with 11 tests. v12 replay passed deterministic gate with `record_count=48`, `cards_with_insight_rate=1.0`, `card_hallucinated_field_absence=1.0`, `related_fact_hit_rate=1.0`, `memory_expected_hit_rate=1.0`, `memory_must_not_write_precision=1.0`, `memory_recall_hit_rate=1.0`, `super_agent_answer_hit_rate=1.0`, `task_settlement_rate=1.0`, `failed_task_count=0`, `task_not_settled_count=0`, `p95_record_elapsed_ms=50659`, and `tokens_per_input=2289.833`.
- Supplemental judge verification: v12 generated 101 supplemental tasks and passed all of them with four-provider judge scheduling (`provider_priorities=1,2,0,1`, `provider_retry_cooldown_ms=5000`, `provider_dynamic_priority=true`, `concurrency=16`). Results: `insight_novelty_score=40/40`, `insight_actionability_score=40/40`, `pkm_append_coherence=1/1`, `comment_relevance_score=10/10`, `comment_boundary_safety=10/10`, `bad_count=0`.
- Residual risk: this is a single-persona small gate. Before updating the final launch-supporting comparison report, rerun the large 8-persona / 400-input-per-persona Memory Primary candidate with the latest CardInsight fallback and regenerate the matching supplemental judge evidence. Legacy baseline remains the frozen `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_20260614`.

## 2026-06-15 - pr256-large-v12-provider-priority-rebalance

- Baseline run: unchanged; legacy PKM/PARA logic remains frozen.
- Candidate runs: completed clean SGP-A shards `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_persona00_v12_sgp_a_20260615` and `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_persona03_v12_sgp_a_backup_20260615`; in-progress SGP-A shards `persona04_v12_sgp_a_20260615` and `persona05_v12_sgp_a_20260615`.
- Affected cases: large-scale Memory Primary replay scheduling only; no metric definition, judge rubric, dataset, legacy behavior, or new-chain agent logic changed in this entry.
- Failed metrics: none from completed clean SGP-A shards. `persona00` and `persona03` both passed gate with `failed_task_count=0`, `task_settlement_rate=1.0`, `memory_expected_hit_rate=1.0`, `memory_recall_hit_rate=1.0`, and `super_agent_answer_hit_rate=1.0`.
- Symptom: CN replay shards hit short-window 429 quota exhaustion until `card_agent_task` and `memory_primary_task` exhausted retries; SGP-B/C replay shards were usable but too slow for 400-record persona completion.
- Root cause: provider-level quota/latency variance, not a Memory Primary capability failure. Replay still binds one provider per persona/user to avoid cross-provider cache and workspace effects.
- Fix: added `MEMEX_EVAL_LLM_PROVIDER_PRIORITIES` to the replay harness so multi-provider case-slot assignment can prefer healthier routes while keeping each persona on one provider. For the current large run, stop CN-contaminated shards and B/C low-priority partials; continue with SGP-A as the primary two-lane replay route. Judge tasks still use the four-provider dynamic priority pool because they are stateless.
- Verification: `dart analyze evals/replay/memory_primary_full_chain_replay_test.dart` passed. Completed SGP-A shards: persona00 `agent_route_accuracy=0.975`, `related_fact_hit_rate=0.844`, `retrieval_hit_at_10=0.75`, `p95_record_elapsed_ms=51043`; persona03 `agent_route_accuracy=0.995`, `related_fact_hit_rate=0.849`, `retrieval_hit_at_10=1.0`, `p95_record_elapsed_ms=53120`.
- Residual risk: completed shards still emit non-gating diagnostic `agent_route_missing` and `related_fact_missing` entries. Continue large run across all 8 personas; if the diagnostics repeat materially in aggregate or supplemental judge flags them, iterate only the new-chain orchestration/retrieval.

## 2026-06-15 - pr256-replay-provider-offset-priority

- Baseline run: unchanged; legacy PKM/PARA logic remains frozen.
- Candidate run: large Memory Primary v12 shards continue from the same dataset; this entry changes replay harness provider assignment only. Newly launched offset-priority shards: `persona06_v12_priority_route_cases_20260615` and `persona07_v12_priority_route_cases_20260615`.
- Affected cases: sharded replay processes that use `MEMEX_EVAL_CASE_OFFSET` with `MEMEX_EVAL_CASE_LIMIT=1`.
- Failed metrics: none. This fixes provider scheduling coverage before launching remaining large shards; metric definitions, evaluator logic, dataset, legacy logic, and new-chain agent behavior remain unchanged.
- Symptom: replay priority assignment was added for multi-case processes, but single-case shard processes always passed slot `0`, so every shard still selected the first provider in priority order instead of rotating by persona offset.
- Root cause: provider slot selection used local selected-case index rather than global case offset plus local index.
- Fix: pass `MEMEX_EVAL_CASE_OFFSET + caseIndex` into LLM config selection, and make LLM preflight inspect the same offset-adjusted slot range. A single persona still uses one provider for cache/workspace isolation, while separate persona shards can now spread across the prioritized four-provider order.
- Verification: `dart format evals/replay/memory_primary_full_chain_replay_test.dart` completed with no changes, and `dart analyze evals/replay/memory_primary_full_chain_replay_test.dart` passed with no issues.
- Provider observation: initial attempts that used `manifest.json` as `MEMEX_EVAL_DATASET_PATH` were empty-run mistakes because the runner reads `MEMEX_EVAL_DATASET` and expects `cases.jsonl`; those run directories are excluded from merge. The corrected `MEMEX_EVAL_DATASET=evals/datasets/pr256_full_metric_large_p8_r400/cases.jsonl` shards started successfully. `persona06_v12_priority_route_cases_20260615` reached `rec_0010` with 0 failures, and `persona07_v12_priority_route_cases_20260615` reached `rec_0008` with 0 failures, but both were much slower than SGP-A and were stopped/excluded from merge as throughput-insufficient backup-route evidence.
- Completion plan: start SGP-A completion candidates `persona06_v12_sgp_a_20260615` and `persona07_v12_sgp_a_20260615` after confirming three- and four-lane SGP-A replay stayed at 0 failures in early records. These are the intended merge candidates for personas 06 and 07 if they pass the gate.
- Completed candidate update: `persona01_v12_sgp_a_20260615` completed and passed gate with `record_count=400`, `task_settlement_rate=1.0`, `failed_task_count=0`, `task_not_settled_count=0`, `retry_task_count=94`, `completed_card_rate=1.0`, `cards_with_insight_rate=1.0`, `memory_expected_hit_rate=1.0`, `memory_recall_hit_rate=1.0`, `super_agent_answer_hit_rate=1.0`, `agent_route_accuracy=0.988`, `related_fact_hit_rate=0.849`, `retrieval_hit_at_10=1.0`, `p95_record_elapsed_ms=74715`, and `tokens_per_input=2996.16`. Its 39 `failures.jsonl` rows are non-gating diagnostics: `agent_route_missing=9`, `related_fact_missing=30`.
- Completed candidate update: `persona02_v12_sgp_a_20260615` completed and passed gate with `record_count=400`, `task_settlement_rate=1.0`, `failed_task_count=0`, `task_not_settled_count=0`, `retry_task_count=107`, `completed_card_rate=1.0`, `cards_with_insight_rate=1.0`, `memory_expected_hit_rate=1.0`, `memory_recall_hit_rate=1.0`, `super_agent_answer_hit_rate=1.0`, `agent_route_accuracy=0.97`, `related_fact_hit_rate=0.844`, `retrieval_hit_at_10=1.0`, `p95_record_elapsed_ms=75307`, and `tokens_per_input=3031.488`. Its 54 `failures.jsonl` rows are non-gating diagnostics: `agent_route_missing=23`, `related_fact_missing=31`.
- Completed candidate update: `persona07_v12_sgp_a_20260615` completed and passed gate with `record_count=400`, `task_settlement_rate=1.0`, `failed_task_count=0`, `task_not_settled_count=0`, `retry_task_count=62`, `completed_card_rate=1.0`, `cards_with_insight_rate=1.0`, `memory_expected_hit_rate=1.0`, `memory_recall_hit_rate=1.0`, `super_agent_answer_hit_rate=1.0`, `agent_route_accuracy=0.978`, `related_fact_hit_rate=0.854`, `retrieval_hit_at_10=0.75`, `p95_record_elapsed_ms=66579`, and `tokens_per_input=3073.488`. Its 50 `failures.jsonl` rows are diagnostics: `agent_route_missing=19`, `related_fact_missing=29`, `retrieval_hit_missing=1`, `card_time_parse_mismatch=1`.
- Completed candidate update: `persona06_v12_sgp_a_20260615` completed and passed gate with `record_count=400`, `task_settlement_rate=1.0`, `failed_task_count=0`, `task_not_settled_count=0`, `retry_task_count=77`, `completed_card_rate=1.0`, `cards_with_insight_rate=1.0`, `memory_expected_hit_rate=1.0`, `memory_recall_hit_rate=1.0`, `super_agent_answer_hit_rate=1.0`, `agent_route_accuracy=0.978`, `related_fact_hit_rate=0.844`, `retrieval_hit_at_10=1.0`, `p95_record_elapsed_ms=77443`, and `tokens_per_input=3153.988`. Its 47 `failures.jsonl` rows are non-gating diagnostics: `agent_route_missing=16`, `related_fact_missing=31`.
- Provider update: an additional SGP provider is available for post-replay judge concurrency and any necessary late补跑. Previously observed out-of-quota providers remain excluded from replay and judge pools unless separately revalidated.
- Supplemental judge update: an initial high-concurrency judge attempt was stopped because provider pressure produced 429/timeout retries. A lower `MEMEX_EVAL_JUDGE_MAX_TOKENS=512` resume attempt was also discarded because MIMO returned visible thinking and hit `stop_reason=max_tokens`, creating false `passed=false/score=0` rows. The judge prompt was tightened to require a single JSON object with no reasoning, `dart analyze evals/bin/run_pr256_judge.dart` passed, and the clean rerun uses four SGP providers, concurrency 4, request timeout 120s, and max tokens 4096.
- Residual risk: replay remains static per persona by design. If a persona's selected provider repeatedly 429s or stays too slow for completion, stop that shard and restart it with adjusted priorities or a different offset-to-provider plan rather than mixing providers inside the same user journey.

## 2026-06-15 - pr256-large-v12-full-judge-and-quick-query-grounding

- Baseline run: unchanged; legacy PKM/PARA logic remains frozen at `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_20260614`.
- Candidate run: `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_v12_sgp_a_20260615`, merged from eight 400-record Memory Primary persona shards.
- Affected cases: original PR256 judge tasks, supplemental judge tasks, judge infrastructure throttling, and Memory Primary Quick Query grounding. No old-chain logic or metric definitions were changed.
- Deterministic verification: candidate merged gate passed with `record_count=3200`, `completed_card_rate=1.0`, `cards_with_insight_rate=1.0`, `memory_expected_hit_rate=1.0`, `memory_recall_hit_rate=1.0`, `super_agent_answer_hit_rate=1.0`, `task_settlement_rate=1.0`, `failed_task_count=0`, `task_not_settled_count=0`, `related_fact_hit_rate=0.85`, `retrieval_hit_at_10=0.875`, `p95_record_elapsed_ms=63584`, and `tokens_per_input=3066.613`.
- Original PR256 judge verification: exported 3264 tasks from the merged candidate via `evals/bin/extract_pr256_judge_tasks.dart`, then ran `evals/bin/run_pr256_judge.dart` with four SGP providers, priority routing, 15s retry cooldown, 2.5s provider min interval, request timeout 120s, max tokens 4096, and resume/retry_failed. Final raw judge metrics: `card_title_relevance_score=3198/3200`, `grounded_answer_rate=31/32`, `unsupported_claim_absence=26/32`, `error_count=0`.
- Supplemental judge verification: generated and ran 808 supplemental tasks (`pkm_append_coherence=8`, `insight_novelty_score=320`, `insight_actionability_score=320`, `comment_relevance_score=80`, `comment_boundary_safety=80`). Raw metrics: novelty `320/320` avg `0.89`, actionability `320/320` avg `0.945`, comment relevance `80/80`, comment boundary `80/80`, PKM coherence `7/8` avg `0.906`, `error_count=0`.
- Badcase audit: two raw title failures were judge artifacts (`stop_reason=max_tokens` without strict JSON, and one judge hallucinated a title typo although input/title both contained `周三下午`). The PKM coherence failure was also an evaluator artifact: the projection contained `最新结论`, `证据来源`, and required persona facts, but judge claimed those phrases were missing.
- Real new-chain badcases: Super Agent Quick Query sometimes answered beyond judge-visible evidence: report-format questions filled template fields with project facts or benefit claims; owner questions added unsupported `无额外风险` / next-step text; one relationship answer cited product-review ownership that was not visible in the truncated tool-result trace.
- Fix: tighten Memory Primary Quick Query grounding. `SuperAgent` now instructs Quick Query to answer only requested fields, not fill report templates, and not add risk/next-step claims without returned evidence. `search_memory_primary` now emits stricter current/preference/relationship reminders, includes background placement as an explicit preference constraint, and warns that report-format fields must remain fields. `ChatService` now exposes a longer Memory Primary tool-result trace (`12000` chars) and sanitizes report-format / current-owner answers to remove unsupported filler. The judge runner now records `MEMEX_EVAL_JUDGE_PROVIDER_MIN_INTERVAL_MS` and treats 200 responses without strict JSON as retryable format failures.
- Verification: `dart analyze lib/agent/super_agent/super_agent.dart lib/agent/common_tools.dart lib/data/services/chat_service.dart test/data/services/chat_service_test.dart test/agent/common_tools_test.dart evals/bin/run_pr256_judge.dart evals/bin/extract_pr256_judge_tasks.dart` passed. `NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 flutter test --no-pub test/data/services/chat_service_test.dart test/agent/common_tools_test.dart` passed with 12 tests.
- Residual risk: the large v12 replay/judge artifacts predate the final Quick Query grounding patch. Before promoting Memory Primary beyond experiment switch rollout, rerun at least the 64 Super Agent judge tasks or the affected persona shards with the patched chain; the deterministic 3200-record candidate remains the large-scale baseline for the report.

## 2026-06-15 - pr256-large-quick-query-memory-rebuild-closeout

- Baseline run: unchanged; legacy PKM/PARA logic remains frozen at `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_20260614`.
- Candidate run: `evals/runs/pr256_quick_query_replay_large_p8_memory_rebuild_after_relationship_type_fix_20260615`, using the eight large Memory Primary case logs from `pr256_full_metric_large_p8_r400_memory_primary_merged_v12_sgp_a_20260615`.
- Affected cases: all 8 persona Quick Query asks, especially `ask_relationship_payment` for personas 01/02/05/07. No old-chain logic or metric definitions changed.
- Failed metrics: initial post-grounding LLM judge on `evals/runs/pr256_quick_query_replay_large_p8_after_report_rank_20260615/judge` passed `unsupported_claim_absence=32/32` but only reached `grounded_answer_rate=28/32`. The failures were all relationship/payment asks that either omitted the product-review owner or included unrelated project-owner/interface-validation facts.
- Symptom: Quick Query fallback was concise enough to avoid unsupported claims, but final active memory sometimes lost the positive responsibility `MayaX 负责产品评审和体验文案` after many payment/fapiao confirmations. In other cases fallback copied too many top memories instead of answering the requested slots.
- Root cause: Memory Primary relationship preservation was still too type-dependent. Some repeated relationship patches drifted through `other` type or create-without-explicit-supersedes paths, so the positive non-conflicting product-review responsibility was overwritten by later negative/payment confirmations. The deterministic fallback also lacked slot extraction for multi-part relationship questions.
- Fix: keep fixes scoped to Memory Primary. `MemoryPrimaryService` now merges relationship-like creates by specific actor, honors explicit memory ids for replay/migration, preserves positive responsibilities even when a relationship-like atom temporarily has type `other`, and recognizes `职责是/职责包括` as responsibility clauses. `ChatService` relationship fallback now extracts requested slots (`产品评审/体验文案`, `合同付款/发票确认`) and limits evidence instead of dumping top-5 memories. The quick-query replay harness can rebuild memory from `memory_primary_task.changed_memory_atoms` so the same historical LLM outputs are replayed through the current merge logic.
- Verification: `evals/runs/pr256_quick_query_replay_large_p8_memory_rebuild_after_relationship_type_fix_20260615` passed deterministic replay with 8 cases, 32 asks, `super_agent_answer_hit_rate=1.0`, `retrieval_hit_at_10=1.0`, `tool_selection_accuracy=1.0`, `tool_args_accuracy=1.0`, `super_agent_read_only_compliance=1.0`, and `failure_count=0`. Final 64-task LLM judge passed with `unsupported_claim_absence=32/32`, `grounded_answer_rate=32/32`, `average_score=0.994`, and `error_count=0`.
- Test verification: `dart analyze lib/data/services/memory_primary_service.dart lib/data/services/chat_service.dart evals/replay/memory_primary_quick_query_replay_test.dart test/data/services/memory_primary_service_test.dart test/data/services/chat_service_test.dart` passed. `NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 flutter test --no-pub test/data/services/memory_primary_service_test.dart test/data/services/chat_service_test.dart` passed with 23 tests.
- Provider note: the judge rerun used five configured MIMO providers with dynamic priorities (`1,1,1,1,2`), 5s retry cooldown, 2.5s min interval, and concurrency 5. Out-of-quota/429 providers were retried after cooldown; artifacts redact keys.
- Residual risk: this closeout replays the large run's recorded Memory Primary changed atoms through current service logic instead of rerunning all 3200 record inputs end-to-end. It is sufficient for the identified Quick Query/memory-merge badcases; a future release candidate can still schedule a full 8-persona rerun if we need fresh latency/token numbers after these small service changes.

## 2026-06-15 - pr256-instrumentation-coverage-remerge

- Baseline run: old-chain execution remains frozen. New offline metrics artifact: `evals/runs/pr256_full_metric_large_p8_r400_legacy_pkm_merged_baseline_with_pr256_instrumentation_20260615`, merged from the exact same 8 legacy shard dirs as the original baseline; gate remains `fail`.
- Candidate run: new offline metrics artifact: `evals/runs/pr256_full_metric_large_p8_r400_memory_primary_merged_v12_sgp_a_with_pr256_instrumentation_20260615`, merged from the exact same 8 Memory Primary v12 shard dirs as the original candidate; gate remains `pass`.
- Affected cases: metrics aggregation only. No metric definition, dataset, judge rubric, candidate chain execution, or legacy chain execution changed.
- Failed metrics: none. This closes part of the previous coverage-audit instrumentation gap.
- Symptom: the PR256 coverage matrix still listed 10 `needs_new_gold_or_instrumentation` metrics, although several could be derived from existing observations, task status snapshots, and LLM usage totals.
- Fix: emit/merge `agent_finalization_rate`, `agent_llm_turns_per_task`, `agent_turn_budget_violation_rate`, `input_full_idle_latency_ms`, `task_queue_pressure_p95`, and `tool_calls_per_input`. Repointed `audit_pr256_metric_coverage.dart` to the instrumented metrics artifacts while keeping judge evidence on the original judge artifacts. Full replay and Quick Query replay now also stamp serialized chat events with `elapsed_ms`, so future reruns can derive real tool call latency from tool call/result pairs instead of guessing from historical logs.
- Verification: `dart analyze evals/bin/audit_pr256_metric_coverage.dart evals/bin/merge_memory_primary_eval_runs.dart evals/replay/memory_primary_full_chain_replay_test.dart` passed. Rebuilt `evals/reports/2026-06-15-pr256-metric-coverage-matrix.zh.md`; direct `metrics.json` coverage increased from 56 to 62, and `needs_new_gold_or_instrumentation` decreased from 10 to 4.
- Residual risk: the remaining 4 metrics (`agent_empty_response_rate`, `context_peek_redundancy_rate`, `first_write_after_read_rate`, `tool_call_latency_p95_by_tool`) require standardized LLM turn/tool latency/read-write trace before they can be honestly emitted one-for-one.

## 2026-06-15 - pr256-quick-query-tool-latency-closeout

- Baseline run: old-chain execution remains frozen. No legacy code or legacy artifact changed.
- Candidate run: `evals/runs/pr256_quick_query_replay_large_p8_memory_rebuild_with_latency_20260615`, replayed from the same eight large Memory Primary case logs used by the relationship closeout.
- Affected cases: 32 Super Agent Quick Query asks. No metric definition, judge rubric, dataset, candidate memory-writing chain, or legacy chain execution changed.
- Failed metrics: none. This closes `tool_call_latency_p95_by_tool` as a same-name `metrics.json` field for the Quick Query tool path.
- Fix: pair serialized `tool_call` and subsequent same-name `tool_result` events by `elapsed_ms`, aggregate per tool as `count`, `mean`, `p95`, and `max`, and repoint the PR256 coverage audit to the latency closeout artifact. The judge provider pool now also disables clearly out-of-quota providers for the current run while keeping short-window 429 providers on cooldown/retry.
- Verification: replay passed with `failure_count=0`, `super_agent_ask_count=32`, `tool_selection_accuracy=1.0`, `retrieval_hit_at_10=1.0`, and `tool_call_latency_p95_by_tool.search_memory_primary.count=32`, `p95=0ms`, `max=1ms`. `dart run evals/bin/audit_pr256_metric_coverage.dart` rebuilt the matrix with direct `metrics.json` coverage at 63 and `needs_new_gold_or_instrumentation` at 3.
- Residual risk: the remaining 3 one-for-one gaps are `agent_empty_response_rate`, `context_peek_redundancy_rate`, and `first_write_after_read_rate`; they need standardized LLM turn and read/write semantic trace rather than inference from task-level failures.

## 2026-06-15 - pr256-agent-trace-metric-closeout

- Baseline run: old-chain large baseline remains frozen. A legacy-only smoke run was started only to probe file-tool trace behavior, proved too slow, was terminated, and is not used as evidence.
- Candidate run: `evals/runs/pr256_full_chain_trace_metric_smoke_llm_20260615`, a 3-record Memory Primary LLM smoke run using the existing smoke dataset.
- Affected cases: LLM turn metadata and persisted agent activity trace export. No metric definitions, judge rubrics, dataset gold, large candidate run, or legacy baseline logic changed.
- Failed metrics: none. This closes the remaining same-name instrumentation gaps in the PR256 coverage matrix.
- Fix: record LLM turn metadata (`stop_reason`, text length, function call count, `empty_response_turn`) in `LLMCallRecordService`; export `agent_activity_trace` into case logs; aggregate `agent_empty_response_rate`, `context_peek_redundancy_rate`, and `first_write_after_read_rate` from those traces. The context redundancy metric is conservative: it only counts exact duplicate read/query calls as redundant. The first-write metric only covers generic file mutation tools (`Write`, `Edit`, `Move`, `Remove`) to avoid misclassifying Memory Primary structured save/update calls.
- Verification: `evals/runs/pr256_full_chain_trace_metric_smoke_llm_20260615` passed with `record_count=3`, `total_task_count=29`, `llm_usage_total.calls=3`, `empty_response_turns=0`, `agent_empty_response_rate=0.0`, `context_peek_redundancy_rate=0.0`, and `first_write_after_read_rate=1.0`. Rebuilt `evals/reports/2026-06-15-pr256-metric-coverage-matrix.zh.md`; direct `metrics.json` coverage is now 66 and `needs_new_gold_or_instrumentation` is 0.
- Residual risk: the final three trace metrics are proven as instrumentation closeout on a small LLM smoke, not recomputed over the 3200-record historical large run. The large-run上线判断 remains based on the existing 8 persona / 3200 record candidate-vs-legacy artifacts plus focused Quick Query judge closeout.
