# NoopLocalAccess

`noop-local-access` exposes bounded, read-only NOOP health data locally. It has no network or
write/control path.

Use MCP over stdio with `noop-local-access mcp`, or query one tool directly as JSON:

```sh
noop-local-access query health_snapshot --days 14
noop-local-access query metric_series --key hrv --days 90
noop-local-access query data_freshness
noop-local-access query sleep_summary --days 30
noop-local-access query workout_summary --days 90
noop-local-access query heart_rate_series --from 2026-10-09T07:00 --hours 2 --bucket-minutes 1
```

Set `NOOP_DB_PATH` to select a database, or pass `--db-path PATH`. Query results are written to
stdout; diagnostics are written to stderr. Query usage errors exit 64 and runtime/database errors
exit 1.

Arguments reuse the MCP defaults and bounds:

- `health_snapshot`: optional `--days` (default 14, clamped to 1...120).
- `metric_series`: required `--key`; optional `--source` (default `my-whoop`), `--days` (default 90,
  clamped to 1...4000), `--from-day`, `--to-day`, and `--limit` (default 500, clamped to 1...2000).
- `data_freshness`: no tool arguments.
- `sleep_summary`: optional `--days` (default 30, clamped to 1...4000).
- `workout_summary`: optional `--days` (default 90, clamped to 1...4000).
- `heart_rate_series`: optional `--from` / `--to` (`YYYY-MM-DD` or `YYYY-MM-DDTHH:MM` in local time, or
  ISO-8601 with an offset), `--hours` (window length when an end is missing, default 24, max 168) and
  `--bucket-minutes` (default 5, clamped to 1...60). Returns min/avg/max bpm per bucket with local
  timestamps; a window needing more than 2000 buckets gets wider buckets.

The open database is reopened when the file at the resolved path is replaced (a new inode), so a
snapshot refreshed by renaming a new copy over the old one reaches a running MCP session.

Dates use the existing `YYYY-MM-DD` tool contract. The CLI does not add a separate validation or
interpretation layer; it passes accepted arguments to the same bounded read-only dispatcher as MCP.
