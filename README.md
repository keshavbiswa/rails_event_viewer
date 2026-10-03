# RailsEventViewer

A Rails engine that captures events emitted with `Rails.event` and gives you a dashboard to browse, search, and chart them.

> **Experimental.** This gem is in early development and not recommended for production yet. APIs, the database schema, and behavior may change between minor versions.

## Requirements

- Rails 8.1+
- Ruby 3.3+
- SQLite, PostgreSQL, or MySQL 8 for the default ActiveRecord adapter

API-only apps need an asset pipeline to serve the dashboard's CSS and JavaScript. Add `gem "propshaft"`, and run `assets:precompile` when you deploy.

## Installation

```ruby
gem "rails_event_viewer"
```

```bash
bundle install
rails generate rails_event_viewer:install
rails db:migrate
```

The generator creates the migration and an initializer, and mounts the dashboard at `/events`.

## Usage

Emit events with the standard Rails API. RailsEventViewer subscribes automatically.

```ruby
Rails.event.notify("order.placed", order_id: order.id, total: order.total)
```

Query them from code:

```ruby
RailsEventViewer.events
  .with_name("order.placed")
  .with_tag(:priority, "high")
  .since(1.day.ago)
  .limit(50)
  .to_a
```

Other filters: `with_context`, `search`, `until`, `offset`, and `count`.
Without `limit`, a query returns `config.per_page` events, 25 by default.

## Configuration

`config/initializers/rails_event_viewer.rb`:

```ruby
RailsEventViewer.configure do |config|
  config.storage_adapter = :active_record  # :active_record, :redis, :memory, :null, or a class

  config.async = true                       # buffer writes in a background thread
  config.buffer_size = 100                  # flush after this many events
  config.flush_interval = 2                 # or after this many seconds
  config.sample_rate = 1.0                  # 0.1 keeps 10% of events

  config.captured_events = []               # empty captures everything
  config.ignored_events += [/^debug\./]     # strings or regexes
  config.retention_period = 7.days          # used by the cleanup task
end
```

With `async`, events are written by a background thread, never by your web requests. The buffer holds at most 10 times `buffer_size` events. If storage can't keep up, the oldest are dropped and a warning is logged. On a normal shutdown, buffered events are written for up to 5 seconds. Anything left is logged and lost. If the process is killed, the whole buffer is lost.

Internal Rails events such as `active_record.*` and `action_controller.*` are ignored by default. Remove a pattern from `ignored_events` to capture it.

## Sync vs async

- With `async = false`, each event is written inside your transaction, and a failed write is reported to `Rails.error`. In development and test, where Rails sets `raise_on_error`, it raises instead.
- With `async = true`, events wait in an in-memory buffer and are lost if the process is killed. Set `config.buffer` to your own `RailsEventViewer::Buffer`, for example backed by Redis, to keep them.

## Authentication

Without authentication, the dashboard is open in development and test, and returns `403` everywhere else.

```ruby
config.http_basic_auth_enabled = true
config.http_basic_auth_user = ENV["RAILS_EVENT_VIEWER_USER"]
config.http_basic_auth_password = ENV["RAILS_EVENT_VIEWER_PASSWORD"]

# or
config.authentication = ->(controller) {
  controller.authenticate_user!
  controller.current_user.admin?
}
```

Set `RAILS_ENV` on every server. Without it, Rails falls back to development and the dashboard is open.

If both are set, HTTP Basic Auth is used and `config.authentication` is ignored.

## Storage adapters

Set `config.storage_adapter` to `:active_record` (default), `:redis`, `:memory`, or `:null`. Redis needs the `redis` gem and takes options through `config.adapter_options`.

```ruby
config.storage_adapter = :redis
config.adapter_options = {
  redis_options: { url: ENV["REDIS_URL"] },  # passed to Redis.new
  key_prefix: "rails_event_viewer",
  max_events: 10_000
}
```

Pass `pool:` to use your own `ConnectionPool`, or `pool_size:` and `pool_timeout:` to size the built-in one. The memory adapter takes `max_events:`. An unknown option raises an `ArgumentError`.

Filtered queries on Redis scan every stored event, so keep `max_events` (how many events Redis keeps, set in `adapter_options`) modest. For your own storage, include `RailsEventViewer::Adapter`.

## Rake tasks

```bash
bin/rails rails_event_viewer:stats     # counts and top events
bin/rails rails_event_viewer:cleanup   # delete events older than retention_period
bin/rails rails_event_viewer:flush     # write buffered events now
bin/rails rails_event_viewer:clear     # delete everything, asks first
```

Schedule `cleanup` daily, for example with Solid Queue in `config/recurring.yml`:

```yaml
production:
  rails_event_viewer_cleanup:
    command: "RailsEventViewer.adapter.delete_before(RailsEventViewer.retention_period.ago)"
    schedule: every day at 3am
```

## Development

The dashboard ships Chart.js 4.4.1, chartjs-adapter-date-fns 3.0.0 and Chartkick.js 5.0.1.

```bash
bundle install
bundle exec rake test
bin/rails db:migrate && bin/rails server
```

`rake test` prepares the test database first. Run it once before running a single test file.

To test against PostgreSQL or MySQL, set `DATABASE_URL`:

```bash
DATABASE_URL=postgresql://localhost/rails_event_viewer_test bundle exec rake test
DATABASE_URL=trilogy://root@127.0.0.1/rails_event_viewer_test bundle exec rake test
```

## License

MIT.
