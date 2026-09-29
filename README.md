# RailsEventViewer

A Rails engine that captures events emitted with `Rails.event` and gives you a dashboard to browse, search, and chart them.

## Requirements

- Rails 8.1+
- Ruby 3.3+

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

Internal Rails events such as `active_record.*` and `action_controller.*` are ignored by default. Remove a pattern from `ignored_events` to capture it.

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

## Storage adapters

| Adapter | Use it for |
|---|---|
| `:active_record` | The default. Stores events in your database, with full analytics. |
| `:redis` | High volume, short-lived storage. Keeps the newest `max_events`. |
| `:memory` | Development and tests. Lost on restart. |
| `:null` | Disables storage. |

Redis needs the `redis` gem:

```ruby
config.storage_adapter = :redis
config.adapter_options = {
  redis_options: { url: ENV["REDIS_URL"] },
  pool_size: 5,
  max_events: 10_000
}
```

Filtered queries on Redis scan every stored event, so keep `max_events` modest.

For a custom adapter, include `RailsEventViewer::Adapter` and implement the methods it lists.

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

```bash
bundle install
bundle exec rake test
cd test/dummy && bin/rails db:migrate && bin/rails server
```

## License

MIT.
