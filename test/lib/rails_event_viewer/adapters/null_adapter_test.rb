require "test_helper"
require "rails_event_viewer/adapters/null"

module RailsEventViewer
  module Adapters
    class NullAdapterTest < ActiveSupport::TestCase
      setup do
        @adapter = RailsEventViewer::Adapters::Null.new
      end

      test "group methods return empty results" do
        assert_equal [], @adapter.distinct_group_values(:request_id)
        assert_equal [], @adapter.group_instances(:request_id, source: :tags)
      end

      test "write_events does nothing" do
        events = [{ name: "test", occurred_at: Time.current }]
        result = @adapter.write_events(events)
        assert_nil result
      end

      test "fetch_events returns empty array" do
        relation = EventsRelation.new(adapter: @adapter)
        assert_equal [], @adapter.fetch_events(relation)
      end

      test "count_events returns zero" do
        relation = EventsRelation.new(adapter: @adapter)
        assert_equal 0, @adapter.count_events(relation)
      end

      test "distinct_event_names returns empty array" do
        assert_equal [], @adapter.distinct_event_names
      end

      test "find_event returns nil" do
        assert_nil @adapter.find_event(1)
      end

      test "delete_before returns zero" do
        assert_equal 0, @adapter.delete_before(Time.current)
      end

      test "events_over_time returns empty hash" do
        assert_equal({}, @adapter.events_over_time(since: 1.hour.ago, interval: :hour))
      end

      test "counts_by_name returns empty hash" do
        assert_equal({}, @adapter.counts_by_name(limit: 10))
      end

      test "count_since returns zero" do
        assert_equal 0, @adapter.count_since(1.hour.ago)
      end

      test "supports_persistence? returns false" do
        refute @adapter.supports_persistence?
      end

      test "supports_analytics? returns false" do
        refute @adapter.supports_analytics?
      end

      test "supports_retention? returns false" do
        refute @adapter.supports_retention?
      end
    end
  end
end
