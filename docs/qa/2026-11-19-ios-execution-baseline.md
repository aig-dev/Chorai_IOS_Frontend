# iOS execution measurements — 2026-11-19

Environment: Xcode simulator, iPhone 17 Pro / iOS 26.2, Debug Local, unsigned app-hosted XCTest. Synthetic content only. The T1/T3 timing tables use five warmups and 20 samples. These are observations, not new product thresholds or device-performance claims.

| Workload | p50 ms | p95 ms | Meaning |
| --- | ---: | ---: | --- |
| Original synchronous parser, 1000 blocks / 103781 bytes | 27.9595 | 28.2683 | Before T1; same simulator and build configuration |
| T1 direct parser, same document | 20.8329 | 21.1613 | Timing noise and implementation differ; not a claimed UI speedup |
| T1 cached 1000-block read | 0.00117 | 0.00129 | Cache lookup after warmup |
| T1 200 distinct cards, 20 blocks each | 108.4987 | 111.4496 | Total workload duration; not per-frame latency |

The cache tests directly assert non-main parsing and a maximum of two real simultaneous parses, including cancellation while synchronous work is still running. UI integration is verified separately.

Peak memory, physical-device frame latency, the 1000-note list are not measured yet. No before/after claim is made for these. An exploratory Instruments capture overlapped an app-test launch and the app exited; that capture is excluded from the evidence. Later task measurements will be appended here.

T3: synthetic solid-color 4000×3000 UIImage, JPEG quality 0.9, same Debug simulator, five warmups and 20 samples: direct encoding p50 10.1910 ms / p95 10.3083 ms; queued async encoding p50 10.2857 ms / p95 10.5096 ms end to end. This measures moving work off main, not faster encoding. The solid-color fixture is compressible and does not represent photographic entropy. Runtime tests assert non-main execution, unchanged encoded bytes and one actual concurrent encoder. Peak memory remains unmeasured.

T6: macOS Debug package test, 1000 real BlockNote blocks, 40 revisions plus four snapshot requests in one burst: 1090.4426 ms total, peak 47 mailbox items / 5,361,600 estimated queued payload bytes. All accepted revisions/snapshots drained, with zero queued payload after completion. This is one stress run, not a percentile or peak process-memory measurement. The fixture includes props/children/styles and validates stable generated IDs through the stateful adapter; an earlier incomplete fixture is excluded.

T7: macOS Debug package benchmark, 1000 card_doc blocks / 96,832 bytes, five warmups and 20 samples. Worker projection p50 41.0833 / p95 41.8717 ms; prepareDraft p50 54.8194 / p95 55.4888 ms. Remaining synchronous UserDefaultsMergeTaskStore.save: 2.8782 / 3.0060 ms. Remaining makeCleanDraft-equivalent direct codec decode: 36.6081 / 37.3215 ms. These are different workloads from T1 and must not be compared as a speed ratio. Store persistence and clean-draft decoding remain on MainActor; the latter is a specific follow-up hotspot.

Final diagnostic capture: a 15-second Local Debug long-Merge launch exported 1459 Time Profiler samples. Resource validation (11 samples), bridge worker apply (32) and Merge prepareDraft (8) appeared on other threads; remaining makeCleanDraft appeared on main (2). This is stack-placement evidence only: concurrent build load and one launch do not establish a latency ratio. The validation record identifies the trace and tool warning.
