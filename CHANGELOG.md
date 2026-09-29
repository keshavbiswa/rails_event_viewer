# Changelog

## 0.1.0 (2026-09-29)

Initial release.

- Web dashboard for browsing, searching, and analyzing events emitted via `Rails.event` (Rails 8.1+).
- Storage adapters: ActiveRecord (default), Redis, Memory, Null, or a custom class.
- Buffered async ingestion with configurable buffer size, flush interval, and sampling.
- Event filtering with `captured_events` and `ignored_events`.
- Event groups by context or tag keys, such as `request_id`.
- Analytics: events over time and counts by event name.
- HTTP Basic Auth or custom authentication. The dashboard returns 403 outside development and test when neither is configured, and when Basic Auth is enabled with a blank user or password.
- Rake tasks: `stats`, `cleanup`, `flush`, `clear`, `install:migrations`.
