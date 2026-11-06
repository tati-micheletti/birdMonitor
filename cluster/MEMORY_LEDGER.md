# EVE memory ledger (what failed, with how much memory, and what worked)

Started 2026-11-06 at the request of the project lead: **every time a job runs out of memory, record here where it failed, how much memory it had, and what worked afterwards, so that nobody goes back to a setting that already failed.**

## Rules
1. Before changing a `--mem-per-cpu` / `--cpus-per-task`, read this file and the real numbers: `python3 cluster/mem_history.py 2026-10-29` on EVE (read-only; `sacct` history: end states, requested GB, peak used GB, wait after the job became eligible).
2. Never request less than **1.25 x the peak of a COMPLETED run** of that job family, and never go back to a setting listed under *Failures*.
3. After any `OUT_OF_MEMORY` (e-mail from the watcher, or `sacct ... | grep OUT_OF_MEMORY`): add a row to *Failures* (date, job family, task, memory requested, peak used if known, cause) and, when it works, a row to *What worked*, in the same commit as the fix.
4. A higher request is not free: above about 8 GB per core the job can land in the small high-memory pool and wait (see the observations below).

## Failures (each one: where, with how much, cause, what fixed it)
| Date | Job (family) | Memory it had | What happened | Fix that worked |
|---|---|---|---|---|
| 2026-10-09 | `unc-prepare` of the first big-5 uncertainty chain | 64 GB (8 cpus x 8 GB) | 3 tasks out of memory (5 tasks failed after 8-22 min: a failed GAM refit killed the batch of its core) | 128 GB (8 cpus x 16 GB), robust GAM refit ladder; later peak 72 GB, all 14 tasks completed |
| 2026-10-29 | prep, completeness check (`checkNoNAInsideStudyArea`) | 64 GB job | killed: terra sized its memory from the whole node and the masks of hundreds of files piled up | `terraOptions(memmax = 8)` and `rm()`/`gc()` per file; the check has run since in 5.3 GB peak |
| 2026-10-31 | `birdmon-habitat` (BRT habitat array), first v2 chain | 12 GB (1 cpu); earlier attempts at 13, 20 and 24 GB also died | all 14 tasks OUT_OF_MEMORY (peak 12.0 GB): each task built the 200 m covariate stacks of every year in memory | `covcache` job builds the stacks once (24 GB, peak 17.7 GB) and the habitat array waits for it; then 14 tasks completed at 12 GB, peak 9.3 GB |

## What worked (completed runs, accounting since 2026-10-29, read 2026-11-06; all v2, 14 species unless noted)
Peak = highest `MaxRSS` over the tasks of the family; margin = requested / peak.

| Job family | Tasks | Requested (cpus x GB/cpu) | Peak used | Margin |
|---|---|---|---|---|
| `birdmon-covcache` | 1 | 24 GB (1 x 24) | 17.7 GB | 1.36 |
| `birdmon-europe` (BRT climate) | 14 | 13 GB (1 x 13) | 1.5 GB | 8.7 |
| `birdmon-habitat` (BRT, after covcache) | 14 | 12 GB (1 x 12) | 9.3 GB | 1.29 |
| `birdmon-landscape` (BRT) | 14 | 13 GB (1 x 13) | 9.3 GB | 1.40 |
| `ens-habitat-glm` / `-gam` / `-nn` | 14 each | 12 GB (1 x 12) | 6.7 / 8.3 / 6.8 GB | 1.8 / 1.45 / 1.8 |
| `ens-habitat-rf` | 14 | 32 GB (4 x 8) | **30.4 GB** | **1.05 (tight, worked)** |
| `ens-landscape-glm` / `-gam` / `-nn` | 14 each | 8 GB (1 x 8) | 4.1 / 4.0 / 3.9 GB | 2.0 |
| `ens-landscape-rf` | 14 | 16 GB (4 x 4) | 9.5 GB | 1.7 |
| `ens-climate-*` (glm, gam, nn, rf) | 14 each | 8 GB (rf: 2 x 4) | 1.5-1.6 GB | 5 |
| `ens-mean-climate` / `-landscape` / `-habitat` | 14 each | 12 GB (1 x 12) | 1.8 / 5.5 / 3.7 GB | 6.7 / 2.2 / 3.2 |
| `ens-meta` | 14 | 13 GB (1 x 13) | 8.3 GB | 1.57 |
| `ens-index` | 1 | 32 GB (4 x 8) | 25.4 GB | 1.26 |
| `unc-covcache` | 1 | 16 GB | 0.8 GB | 20 |
| `unc-prepare` | 14 | 128 GB (8 x 16) | **72.0 GB** | 1.78 |
| `unc-band` | 672 | 52 GB (4 x 13) | 34.3 GB | 1.52 |
| `unc-summarize` | 672 | 24 GB (2 x 12) | 1.9 GB | 12 |
| `unc-assemble` / `-assembleall` | 14 / 2 | 16 GB (1 x 16) | 2.1 / 2.0 GB | 7.6 |
| `unc-community` | 48 | 32 GB (2 x 16) | 5.3 GB | 6 |
| `unc-regionband` / `-regionassemble` / `-regionindex` | 672 / 14 / 1 | 16 GB / 16 GB / 24 GB | 1.0 / 0.7 / 1.2 GB | 16 / 23 / 20 |
| `unc-maskmaps` | 15 | 16 GB (2 x 8) | 12.5 GB | 1.28 |
| prep (`birdmon-prep`) | - | 64 GB (8 x 8) | about 5.3 GB at the completeness check (the highest peak was never read) | - |

## Observations about waiting (not about failing)
- Same moment, same user, different memory: after the BRT arrays finished, `ens-landscape-*` (8 GB, 1 cpu) started after 3-12 min, but `ens-habitat-glm/-gam/-nn` (12 GB, 1 cpu) waited 300-350 min. The 12 GB BRT habitat array had waited 0 min at another time, so memory is not the whole story, but the comparison at one moment points to the high-memory pool being slower.
- `unc-band` waited up to 23 h, but it is an array with a throttle of 100 running tasks (672 tasks): that wait is the throttle, not memory.
- Everything else waited 0-18 min.

## Decided for the NEXT run (project lead, 2026-11-06; NOT applied: the v3 chain of 2026-11-06 uses the settings above, which worked)
Every value keeps at least 1.25 x the peak of the completed run (rule 2).

| Job family | Now | Next run | Peak used | Margin | Note |
|---|---|---|---|---|---|
| `birdmon-europe` (BRT climate) | 13 GB (1 x 13) | **3 GB** (1 x 3) | 1.5 GB | 2.0 | project lead's cap |
| `unc-prepare` | 128 GB (8 x 16) | **96 GB** (8 x 12) | 72.0 GB | 1.33 | 64 GB failed (2026-10-09) |
| `unc-band` | 52 GB (4 x 13) | **44 GB** (4 x 11) | 34.3 GB | 1.28 | |
| `unc-community` | 32 GB (2 x 16) | **12 GB** (2 x 6) | 5.3 GB | 2.3 | |
| `unc-summarize` | 24 GB (2 x 12) | **6 GB** (2 x 3) | 1.9 GB | 3.2 | |
| `unc-assemble`, `unc-assembleall` | 16 GB (1 x 16) | **6 GB** (1 x 6) | 2.1 / 2.0 GB | 2.9 | |
| `unc-regionband` | 16 GB (2 x 8) | **4 GB** (2 x 2) | 1.0 GB | 4 | |
| `unc-regionassemble` | 16 GB (1 x 16) | **4 GB** (1 x 4) | 0.7 GB | 5.7 | |
| `unc-regionindex` | 24 GB (1 x 24) | **4 GB** (1 x 4) | 1.2 GB | 3.3 | |
| `unc-covcache` | 16 GB (1 x 16) | **4 GB** (1 x 4) | 0.8 GB | 5 | |

Decided to KEEP: `birdmon-landscape` 13 GB (peak 9.3), `ens-meta` 13 GB (peak 8.3), `birdmon-habitat` 12 GB (peak 9.3; 13, 20 and 24 GB failed before the covcache job), `covcache` 24 GB (peak 17.7).

**Watch item: `ens-habitat-rf`, 32 GB (4 cpus x 8 GB/core), peak 30.4 GB, margin 1.05, worked 14 of 14.** Not changed. 34 GB on 4 cpus would be 8.5 GB per core, above the ~8 GB per core line of the UFZ onboarding note (the job could be routed to the small high-memory pool and wait). If a task is ever killed at 32 GB, record it under *Failures* and try 5 cpus x 7 GB = 35 GB (stays at <= 8 GB per core; check that the random forest does not take more memory with the extra thread).

Proposed but NOT decided yet (ask the project lead): `ens-climate-*` 8 -> 4 GB; `ens-mean-climate` / `-landscape` / `-habitat` 12 -> 4 / 8 / 6 GB; `ens-habitat-glm` / `-gam` / `-nn` 12 GB x 1 cpu -> 2 cpus x 5 GB (10 GB; the 12 GB tasks waited 5 h at one moment while the 8 GB ones waited minutes; peak 6.7-8.3 GB).
