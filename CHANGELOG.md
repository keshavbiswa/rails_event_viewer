# Changelog

## 0.2.1 (2026-10-01)

- Forked workers no longer duplicate the parent's buffered events on exit.
- Payload, tags and context are snapshotted with `as_json` at emit time.
- Keys are now strings and values are JSON types (e.g. `Time` becomes a string).
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
