# Data, Stats, Leaderboards, and Privacy Spec (iPad v1)

## Product direction (confirmed)
- Architecture should be **cloud-ready**.
- v1 shipping mode is **local-only persistence**.

## Data policy summary
Keep only summary-level data needed for product value:
- users
- runs summary
- leaderboard entries
- lightweight aggregate stats

Do **not** retain full raw session event logs long-term.

## Data entities (local)

## User
- `user_id` (alphanumeric)
- `display_name`
- `dominant_hand` (`left`/`right`, default `right`)
- `created_at`, `updated_at`

## RunSummary
- `run_id`
- `user_id`
- `task_id`
- `mode`
- `started_at`, `ended_at`
- `duration_ms`
- `score`
- `completed_targets`
- `total_targets`
- `accuracy_pct` (if available)
- `handx_used` bool
- `summary_payload` (small JSON for task-specific rollups)

## LeaderboardEntry (can be derived)
- `task_id`
- `mode`
- `user_id`
- `primary_metric` (time / score / count)
- `rank_context` metadata

## Session transient data
During a live run, app can keep in-memory/transient buffers for:
- detections
- state transitions
- BLE samples
- timing traces

After run finalization:
1. compute `RunSummary`
2. persist summary + derived stats
3. delete transient raw payload

## Local storage recommendation
- SwiftData or SQLite-based repository layer (team choice)
- explicit repositories:
  - `UserRepository`
  - `RunSummaryRepository`
  - `LeaderboardRepository`

## Leaderboard semantics
- Sprint: lower time is better
- Timer/Survival-like count modes: higher count is better
- Score modes: higher score is better

Implementation must avoid the old ambiguity where count/time share the same unnamed metric field.

## Basic stats to keep
- recent runs list
- per-user averages by task/mode
- completion trend (simple)
- best score/time per task/mode

## Cloud-ready contract (future)
Define protocol interfaces now, with local implementation in v1:
```swift
protocol SyncGateway {
  func pushSummaries(_ summaries: [RunSummaryDTO]) async throws
  func pullUpdates(since: Date?) async throws -> SyncDelta
}
```

v1 can ship with `NoopSyncGateway`.

## Privacy and retention rules
- No video recording in v1.
- No long-term raw BLE or frame-level detection logs.
- Only keep summary-level and qualitative insights needed for reports/leaderboards.
- Add manual “Delete user data” capability in User Management.
