# RailsEventViewer

A Rails engine for viewing and analyzing events emitted via `Rails.event`.
Provides a web UI dashboard for browsing, filtering, and visualizing domain events in your Rails application.

## Features

- Web-based dashboard for viewing events
- Flexible storage adapters (ActiveRecord, Redis, Memory, or custom)
- High-performance buffered ingestion with configurable batch writes
- Fluent query interface for programmatic access
- Event filtering by name, tags, and time range
- Full-text search across event names and payloads
- Analytics with event counts over time
- Configurable retention and automatic cleanup
- HTTP Basic Auth or custom authentication

## Requirements

- Rails 8.1+
- Ruby 3.2+

## Installation

Add this line to your application's Gemfile:

```ruby
gem "rails_event_viewer"
```

And then execute:

```bash
bundle install
```

Run the install generator:

```bash
rails generate rails_event_viewer:install
```

This will:
- Create a migration for the events table (if using ActiveRecord adapter)
- Create an initializer with configuration options
- Mount the engine at `/events`

Run the migration:

```bash
rails db:migrate
```

## Configuration

Configure RailsEventViewer in `config/initializers/rails_event_viewer.rb`:

```ruby
RailsEventViewer.configure do |config|
  # Storage adapter: :active_record, :redis, :memory, :null, or a custom class
  config.storage_adapter = :active_record

  # Adapter-specific options
  config.adapter_options = {}

  # Performance settings
  config.async = true              # Enable buffered writes
  config.buffer_size = 100         # Flush after N events
  config.flush_interval = 2        # Flush every N seconds
  config.sample_rate = 1.0         # 1.0 = capture all, 0.1 = capture 10%

  # Retention
  config.retention_period = 7.days

  # Filtering
  config.captured_events = []      # Empty = capture all
  config.ignored_events = []       # Events to never capture

  # UI settings
  config.per_page = 25

  # Authentication (choose one)
  config.http_basic_auth_enabled = true
  config.http_basic_auth_user = ENV["RAILS_EVENT_VIEWER_USER"]
  config.http_basic_auth_password = ENV["RAILS_EVENT_VIEWER_PASSWORD"]

  # Or use custom authentication
  config.authentication = ->(controller) {
    controller.authenticate_user!
    controller.current_user.admin?
  }
end
```

## Storage Adapters

### ActiveRecord (default)

Stores events in your database. Best for most applications with full analytics support.

```ruby
config.storage_adapter = :active_record
```

The install generator creates the migration for you. If you skipped the generator, copy the migration from the engine instead. Do not do both, or you will get two migrations for the same table.

```bash
rails rails_event_viewer:install:migrations
rails db:migrate
```

### Redis

Stores events in Redis sorted sets. Good for high-volume, ephemeral storage where you don't need long-term persistence.

First, add the redis gem to your Gemfile:

```ruby
gem "redis"
```

Then configure the adapter:

```ruby
config.storage_adapter = :redis
config.adapter_options = {
  redis_options: { url: ENV.fetch("REDIS_URL", "redis://localhost:6379") },
  pool_size: 5,
  key_prefix: "rails_event_viewer",
  max_events: 10_000
}
```

Options:
- `redis_options` - Hash passed to `Redis.new` whenever the pool opens a new connection (default: `{}`)
- `pool_size` - Number of pooled Redis connections, should match your app's thread count (default: `5`)
- `pool_timeout` - Seconds to wait for a free connection before raising (default: `5`)
- `key_prefix` - Prefix for Redis keys (default: `"rails_event_viewer"`). The adapter wraps it in braces, so keys look like `{rails_event_viewer}:events`. The braces are a Redis Cluster hash tag that keeps every key on one node, which the adapter's multi-key commands require. Do not add braces yourself.
- `max_events` - Maximum events to retain, older events are automatically trimmed (default: `10_000`)

The adapter uses a connection pool rather than a single shared connection, since one Redis connection is not safe to use concurrently across multiple threads. Each pooled connection is built independently from `redis_options`. Pass `pool:` with your own `ConnectionPool` for full control.

Note: Redis adapter performs analytics by fetching events into memory, which may be slower than ActiveRecord for large datasets.

Filtered queries and analytics scan every stored event. Keep `max_events` modest, around 10,000, if you filter often.

### Memory

In-memory storage for development and testing.

```ruby
config.storage_adapter = :memory
config.adapter_options = { max_events: 1000 }
```

Options:
- `max_events` - Maximum events to retain (default: `1000`)

Note: Events are lost when the server process restarts. Not recommended for production use.

### Null

Discards all events. Useful for disabling event capture in specific environments.

```ruby
config.storage_adapter = :null
```

### Switching Adapters via Environment Variable

A common pattern is to use different adapters per environment:

```ruby
RailsEventViewer.configure do |config|
  adapter = ENV.fetch("EVENT_STORAGE", "active_record").to_sym
  config.storage_adapter = adapter

  case adapter
  when :redis
    config.adapter_options = {
      redis_options: { url: ENV.fetch("REDIS_URL", "redis://localhost:6379") },
      max_events: 10_000
    }
  when :memory
    config.adapter_options = { max_events: 1000 }
  end
end
```

Then switch adapters when starting your server:

```bash
# Use ActiveRecord (default)
bin/rails server

# Use Redis
EVENT_STORAGE=redis bin/rails server

# Use Memory
EVENT_STORAGE=memory bin/rails server
```

### Custom Adapter

Create your own adapter by including the `RailsEventViewer::Adapter` module:

```ruby
class MyCustomAdapter
  include RailsEventViewer::Adapter

  def write_events(events)
  end

  def fetch_events(relation)
  end

  def count_events(relation)
  end

  def distinct_event_names
  end

  def find_event(id)
  end

  def delete_before(timestamp)
  end

  def distinct_group_values(key, source: :context)
  end

  def group_instances(key, source: :context, limit: 100)
  end

  def events_over_time(since:, interval:)
    # Return { time => count }
  end

  def counts_by_name(limit:)
    # Return { name => count }, highest first
  end

  def count_since(since)
    # Return count of events since a time
  end
end

config.storage_adapter = MyCustomAdapter
```

## Emitting Events

RailsEventViewer automatically subscribes to `Rails.event`. Emit events using the standard Rails API:

```ruby
Rails.event.notify("user.created", user_id: user.id, email: user.email)

Rails.event.notify(
  "order.placed",
  order_id: order.id,
  total: order.total,
  tags: { environment: Rails.env, priority: "high" }
)
```

## Programmatic Access

Use the fluent query interface to access events:

```ruby
# Get all events
RailsEventViewer.events.each { |e| puts e[:name] }

# Filter by name
RailsEventViewer.events.with_name("user.created").to_a

# Filter by tag
RailsEventViewer.events.with_tag(:environment, "production").to_a

# Time range
RailsEventViewer.events.since(1.hour.ago).until(30.minutes.ago).to_a

# Search
RailsEventViewer.events.search("user@example.com").to_a

# Combine filters
RailsEventViewer.events
  .with_name("order.placed")
  .with_tag(:priority, "high")
  .since(1.day.ago)
  .limit(50)
  .each { |e| process(e) }

# Count
RailsEventViewer.events.with_name("user.created").count

# Pagination
RailsEventViewer.events.offset(25).limit(25).to_a
```

## Rake Tasks

```bash
# Show statistics
bin/rails rails_event_viewer:stats

# Clean up old events (based on retention_period)
bin/rails rails_event_viewer:cleanup

# Flush buffered events
bin/rails rails_event_viewer:flush

# Clear all events (interactive confirmation required)
bin/rails rails_event_viewer:clear
```

For automatic cleanup, add to your scheduler:

```yaml
# config/recurring.yml (Solid Queue)
production:
  rails_event_viewer_cleanup:
    command: "RailsEventViewer.adapter.delete_before(RailsEventViewer.retention_period.ago)"
    schedule: every day at 3am
```

Or using the whenever gem:

```ruby
# config/schedule.rb (whenever gem)
every 1.day, at: "3:00 am" do
  rake "rails_event_viewer:cleanup"
end
```

## Event Filtering

Control which events are captured:

```ruby
# Only capture specific events
config.captured_events = ["user.created", "order.placed"]

# Or use regex patterns
config.captured_events = [/^user\./, /^order\./]

# Ignore specific events
config.ignored_events = ["internal.heartbeat", /^debug\./]
```

## Sampling

For high-volume applications, reduce storage by sampling if needed:

```ruby
# Capture only 10% of events
config.sample_rate = 0.1
```

## Authentication

If neither option below is configured, the dashboard is open in development and test, and returns `403 Forbidden` in every other environment, including staging. Enabling HTTP Basic Auth with a blank user or password also returns `403 Forbidden`.

Set `RAILS_ENV` on every deployed server. If it is missing, Rails falls back to development and the dashboard is open.

### HTTP Basic Auth

```ruby
config.http_basic_auth_enabled = true
config.http_basic_auth_user = ENV["RAILS_EVENT_VIEWER_USER"]
config.http_basic_auth_password = ENV["RAILS_EVENT_VIEWER_PASSWORD"]
```

### Custom Authentication

```ruby
# Devise example
config.authentication = ->(controller) {
  controller.authenticate_user!
  controller.current_user.admin?
}
```

## Routes

The engine is mounted at the path specified in your routes (default `/events`):

```ruby
# config/routes.rb
mount RailsEventViewer::Engine, at: "/events"
```

Available routes:
- `/events` - Dashboard
- `/events/events` - Event list with filtering
- `/events/events/:id` - Single event detail
- `/events/analytics/overview` - Analytics dashboard
- `/events/groups` - Event groups

## How Event Capture Works

RailsEventViewer subscribes to `Rails.event` (the Structured Event Reporter introduced in Rails 8.1),
which is built on top of `ActiveSupport::Notifications`. This means internal Rails instrumentation
events (`sql.active_record`, `process_action.action_controller`, etc.) are received by the subscriber.

By default, all internal Rails framework events are excluded via the built-in `ignored_events` patterns.
This prevents noise from flooding your storage.

**Captured by default:**
- Application events emitted via `Rails.event.notify("my.event", ...)`

**Ignored by default** (via `ignored_events`):
- `active_record.*`, `action_controller.*`, `action_view.*`, `active_job.*`
- `action_mailer.*`, `active_storage.*`, `action_cable.*`, `rails.*`
- `turbo.*`, `cache_*`, `*.sql`, `solid_*`

To capture internal Rails events, remove the relevant pattern from `ignored_events`:

```ruby
RailsEventViewer.configure do |config|
  config.ignored_events = RailsEventViewer.ignored_events.reject { |p| p == /^active_record\./ }
end
```

## Development

After checking out the repo, run:

```bash
cd test/dummy
bin/rails db:migrate
bin/rails server
```

Run the test suite:

```bash
bundle exec rake test
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
