# Changelog

## 0.4.1 (2026-10-03)

Added:

- `config.transactional`, on by default. With `async = false`, set it to `false` so a failed event write does not abort the transaction caller's code is running in.

## 0.4.0 (2026-10-03)

Breaking:

- Removed `Adapter#distinct_group_values` and `Adapter#supports_retention?`. Nothing called them.
- Removed `Entry#source_location`, `#short_filepath`, `#tagged?`, `#has_context?` and `#tag`.
- The ActiveRecord adapter raises on unknown `adapter_options`, like the other adapters.
- Times show in the host app's time zone. The engine no longer reads a `timezone` cookie.

Changed:

- New installs skip the index on `name` alone. The `(name, occurred_at)` index covers it. Existing apps can drop it with `remove_index :rails_event_viewer_entries, :name`.
- Chartkick is pinned below 6, to match the bundled Chartkick.js.
- Dashboard scripts load with `defer`.

Fixed:

- Events with the same timestamp keep a stable order across pages.
- Pagination renders only the page links it shows, not one loop per page.
- Related events look one hour either side of the event, so the lookup no longer scans the whole table.
- Form fields have labels, tables have column headers, and the current page is marked for screen readers. Grey text has more contrast.

## 0.3.1 (2026-10-03)

Changed:

- The nav search goes to the events list and works together with the filters. The `/events/search` page is removed.
- The Analytics link is hidden when the adapter has no analytics.
- The group page no longer shows an Event Types count. It counted only the current page.

Fixed:

- Array, hash and invalid values in query params are ignored instead of raising.
- Event rows contain a real link, so keyboard and new-tab clicks work. Selecting text in a row no longer opens the event.
- `rails_event_viewer:clear` works with the ActiveRecord adapter.
- Redis keeps event times to the microsecond, and `delete_before` keeps an event at the exact cutoff.
- Payloads show `&`, `<` and `>` instead of unicode escapes.
- A banner explains a missing events table. A filtered empty list says no events match.
- Pages fit narrow screens, and long names and payloads wrap.
- Charts render when the host app sets its own Chartkick `content_for`.
- `with_name` accepts a symbol.

## 0.3.0 (2026-10-02)

Breaking:

- Event type and group pages moved to `/event_type?name=...` and `/group?key=...&value=...`. Old links to those pages no longer work.
- Custom adapters: `counts_by_name` and `events_over_time` now take a `range:` argument.
- Unknown options for the Redis and memory adapters raise an `ArgumentError`.
- `with_tag` and `with_context` with a value of `""` or `false` now match that value, not every event that has the key.

Fixed:

- PostgreSQL: group pages no longer raise.
- MySQL: the migration runs and search works.
- Event names and group values with a slash no longer break the Event Types and Groups pages.
- Tag and context filters return the same events on every database and adapter. A value typed as text also matches numbers and booleans.
- Filter keys with a hyphen, dot, space or quote work on every database.
- Events the database rejects no longer hold up the events behind them.
- Payloads that cannot be serialized, such as invalid UTF-8, are stored as text.
- A dropped connection during the first table check no longer stops capture until restart.
- The analytics page respects its date range.
- The generated Redis config suggests `redis_options`, which the adapter reads.
- The generated initializer adds to `ignored_events` and keeps the defaults.

Changed:

- Removed two unused analytics endpoints.
- The engine migration has a new timestamp and targets Rails 8.1. Apps that already installed it need no action.

## 0.2.1 (2026-10-01)

- Forked workers no longer duplicate the parent's buffered events on exit.
- Payload, tags and context are snapshotted at emit time as JSON values (`Time` becomes a string).
- Unserializable payloads are stored via `inspect` instead of raising.
- The flusher writes inside the Rails executor.
- Shutdown has a deadline and logs buffered and dropped events.

## 0.2.0 (2026-10-01)

- Pluggable buffers: `config.buffer` accepts any object implementing `RailsEventViewer::Buffer` (`push`, `drain`, `commit`, `revert`, `dead`, `size`, `after_fork`). `push` returns the new size. The in-memory buffer remains the default.
- A failed batch is reverted and retried with exponential backoff. After three failures it is written one event at a time.
- Events the adapter keeps rejecting, and events dropped by the buffer cap, are passed to `dead` instead of being lost silently.
- A failed sync write, or a failed `push` to the buffer in async mode, is now logged and re-raised to `Rails.event`, which reports it to `Rails.error` (or raises, with `raise_on_error`), instead of being swallowed.
- A banner warns when `sample_rate` is below 1.0, since timelines can have gaps.
- README now marks the gem as experimental and not yet recommended for production.

## 0.1.3 (2026-10-01)

- The flusher thread starts on the first buffered event, not at boot, so consoles and rake tasks no longer run an idle thread.
- Flusher start/stop messages log at debug level.
- Events emitted after shutdown are written immediately instead of lost.
- Web requests never write to storage. A full buffer wakes the flusher thread instead.
- The buffer is capped at 10 times `buffer_size`. Overflow drops the oldest events and logs a warning.
- Removed the unused ActionCable broadcast.

## 0.1.2 (2026-09-30)

- Removed the `pagy` dependency. Pagination is handled by a small built-in class, so host apps on any Pagy version, or none, can install the gem.
- Page links now keep the active filters, search query, and `per_page`. Previously every page link dropped them, so page 2 of a filtered list showed unfiltered results.
- A page number past the end now shows the last page instead of an empty one.

## 0.1.1 (2026-09-30)

- The dashboard now works under a strict Content Security Policy. Tailwind CSS is compiled into the gem, and Chart.js, its date adapter, and Chartkick are served from the host app with CSP nonces instead of from CDNs.
- Replaced inline `onclick` handlers and inline `style` attributes with data attributes and a small bundled script, so clickable rows, the payload Copy button, chart sizing, and progress bars work without `unsafe-inline`.
- The dashboard no longer loads the host app's importmap JavaScript.
- Fixed event type and group pages for names and values containing dots, such as `order.placed` or `alice@example.com`. Rails was reading the part after the dot as a format, so these pages rendered empty.
- Ruby 3.3 or newer is required.

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
