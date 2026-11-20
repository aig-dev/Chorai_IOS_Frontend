# Chat execution and launch follow-up

Date: 2026-11-20. iOS base `5166db1`, Go source base `67de388b`.
Task 4 of the [first-launch plan](../superpowers/plans/2026-11-20-post-swift6-integration.md)
is in progress; this record does not close the production synchronization,
ordinary-account, Merge, import or signed-release gates.

Evidence directory: `.superpowers/sdd/2026-11-20-post-swift6-integration/`.
Dedicated simulator `EBACA372-C94A-4A14-9947-634DF3918495`, iPhone 17 Pro / iOS 26.2,
Xcode 27.2. User Xcode state is excluded from the change.

## Behavior evidence

- `task-4-red.log`: 12 events created 13 reads; old messages/detail/error/loading
  contaminated the new conversation; a retired read replaced current messages.
  All five read/pagination cases then passed in `task-4-green-reads.log`.
- `task-4-red-events.log`: duplicate IDs repeated reads and restored an old failure;
  old-source failure hid a new wait; account retirement was not synchronous.
  Ten hosted cases then passed in `task-4-green-events.log`.
- `task-4-red-recovery-baseline.log`: send ACK advanced past unconsumed events;
  late retry acceptance reopened a reply already completed by SSE.
  Thirteen hosted cases then passed in `task-4-green-recovery.log`.
- `task-4-green-stream.log`: 27 hosted Chat/network cases passed, including ordered
  delivery of 500 SSE frames on main and real transport cancellation. The new
  time-zone regression was added afterward and passed in the full hosted run.
- `task-4-core-chat.log`: 23 selected CoreFlow Chat cases passed.
- `Chat-UI.xcresult`: all five requested UI cases passed without skips: actor-scoped
  history clear, fallback avatar, header-only typing, retry action and restored
  latest message with compact attachment. Exported retry/typing screenshots were
  inspected; controls and existing layout remain visible.
- `full-gate/`: complete concurrency gate passed. All three configurations built;
  18 runner checks, 1,070 CoreFlow cases (six explicit live API skips), 76 editor
  cases, 97 hosted cases and all six exact editor UI cases completed with zero
  failures. The six live API skips remain open under Tasks 2–3.

## Synthetic timing observations

These are single-run simulator samples with synthetic messages, including debug
instrumentation; they are not device p95 or a product latency guarantee.

| Sample | Before: ten display preparations | After: one input publication | After: ten cache reads |
| --- | --- | --- | --- |
| Current 20-message page | 723.216 ms | 1.294 ms | 0.010 ms |
| Independent 500-message stress input | 2,826.567 ms | 24.839 ms | 0.007 ms |

The UI no longer sorts or parses on each body evaluation. Normal 20-message
preparation remains inline; the larger stress input does not change pagination.
SSE parser plus reducer took about 0.232 ms for 20 events and 11.812 ms for 500
events / 48,890 bytes. Framing now uses the existing background response queue;
ordered delivery and small state reduction remain on MainActor.

## Real-runtime and remaining acceptance

Rebuilt the current Go source through `go run -exec` without launching a second
server. Its binary SHA-256 exactly matches the process listening on local port
8180: `e28bccdeb45a1e21752fee791adce4def5f8d5be2a8a530fdc6cce610b304f9b`.
This establishes the local build source without assuming repository HEAD equals
the running binary. The isolated dev/test media-sync configuration remains in
use; it is not production protocol acceptance.

`Chat-Go-Run.xcresult` passed actual UI send and server message persistence. Its
recipient was the isolated Merge execution Agent, so it proves message transport
but not Agent reply delivery. The account's actual ACTIVE Chora binding was then
resolved through `/api/agent/profile`.
`Chat-Bound-Go.xcresult` then passed sending to that binding. The user message
`msg_5a2a4a32-3adc-4a` produced reply `msg_79b4ed8d-cd9a-49`. After the UI stream
disconnected, a new connection with `Last-Event-ID: 7` replayed thinking (8), reply
creation (9) and successful delivery (10), preserving the exact source ID. The
history contains one copy of the input and one new reply. This single local
provider run took about 35 seconds from input persistence to reply persistence;
it is not a latency target or device performance result.

These runtime checks use the isolated administrator account. Normal-account
reconnect/switch-account validation remains coupled to Task 3, so Task 4's final
integration checkbox remains open despite its verified implementation batch.
No signing, TestFlight, oldest-OS or physical-device performance result is claimed.
