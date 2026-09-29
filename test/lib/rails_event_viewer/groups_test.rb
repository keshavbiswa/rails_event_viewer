# frozen_string_literal: true

require "test_helper"
require "rails_event_viewer/adapters/memory"

module RailsEventViewer
  class GroupsTest < ActiveSupport::TestCase
    setup do
      @adapter = Adapters::Memory.new
      @adapter.clear!

      travel_to Time.zone.local(2026, 1, 1, 12, 0, 0) do
        @adapter.write_events([
          {
            name: "request.started",
            payload: { path: "/users" },
            context: { "request_id" => "req-123", "user_id" => "user-1" },
            tags: { "env" => "test" },
            occurred_at: 10.seconds.ago
          },
          {
            name: "db.query",
            payload: { sql: "SELECT * FROM users" },
            context: { "request_id" => "req-123", "user_id" => "user-1" },
            tags: { "env" => "test" },
            occurred_at: 8.seconds.ago
          },
          {
            name: "request.completed",
            payload: { status: 200 },
            context: { "request_id" => "req-123", "user_id" => "user-1" },
            tags: { "env" => "test" },
            occurred_at: 5.seconds.ago
          },
          {
            name: "request.started",
            payload: { path: "/orders" },
            context: { "request_id" => "req-456", "user_id" => "user-2" },
            tags: { "env" => "test" },
            occurred_at: 3.seconds.ago
          },
          {
            name: "request.completed",
            payload: { status: 201 },
            context: { "request_id" => "req-456", "user_id" => "user-2" },
            tags: { "env" => "test" },
            occurred_at: 1.second.ago
          }
        ])
      end
    end

    test "with_context filters events by context key and value" do
      relation = EventsRelation.new(adapter: @adapter)
      events = relation.with_context("request_id", "req-123").to_a

      assert_equal 3, events.size
      assert events.all? { |e| e[:context]["request_id"] == "req-123" }
    end

    test "with_context can be chained" do
      relation = EventsRelation.new(adapter: @adapter)
      events = relation
        .with_context("request_id", "req-123")
        .with_name("db.query")
        .to_a

      assert_equal 1, events.size
      assert_equal "db.query", events.first[:name]
    end

    test "distinct_group_values returns unique values for context key" do
      values = @adapter.distinct_group_values("request_id", source: :context)

      assert_includes values, "req-123"
      assert_includes values, "req-456"
      assert_equal 2, values.size
    end

    test "distinct_group_values returns unique values for tag key" do
      values = @adapter.distinct_group_values("env", source: :tags)

      assert_includes values, "test"
      assert_equal 1, values.size
    end

    test "distinct_group_values omits events missing the key" do
      @adapter.write_events([{ name: "no.context", context: {}, occurred_at: Time.current }])

      values = @adapter.distinct_group_values("request_id", source: :context)

      refute_includes values, nil
      assert_equal 2, values.size
    end

    test "group_instances returns statistics grouped by context key" do
      stats = @adapter.group_instances("request_id", source: :context)

      assert_equal 2, stats.size

      first = stats.first
      assert_equal "req-456", first[:value]
      assert_equal 2, first[:count]
      assert_not_nil first[:first_event_at]
      assert_not_nil first[:last_event_at]

      second = stats[1]
      assert_equal "req-123", second[:value]
      assert_equal 3, second[:count]
    end

    test "group_instances respects limit" do
      stats = @adapter.group_instances("request_id", source: :context, limit: 1)

      assert_equal 1, stats.size
    end

    test "group_instances works with tags source" do
      stats = @adapter.group_instances("env", source: :tags)

      assert_equal 1, stats.size
      assert_equal "test", stats.first[:value]
      assert_equal 5, stats.first[:count]
    end

    test "EventsRelation contexts are cloned properly" do
      relation = EventsRelation.new(adapter: @adapter)
      original = relation.with_context("request_id", "req-123")
      cloned = original.with_name("db.query")

      assert_equal 3, original.count
      assert_equal 1, cloned.count
    end

    test "EventsRelation filtered? includes contexts" do
      relation = EventsRelation.new(adapter: @adapter)

      refute relation.filtered?

      filtered = relation.with_context("request_id", "req-123")
      assert filtered.filtered?
    end
  end
end
