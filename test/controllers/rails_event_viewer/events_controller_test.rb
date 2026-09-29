# frozen_string_literal: true

require "test_helper"

module RailsEventViewer
  class EventsControllerTest < ActionDispatch::IntegrationTest
    setup do
      Entry.delete_all
      @event = Entry.create!(
        name: "test.event",
        payload: { key: "value" },
        tags: { environment: "test" },
        context: { request_id: "abc123" },
        occurred_at: Time.current
      )
    end

    test "index renders successfully" do
      get rails_event_viewer.events_path

      assert_response :success
    end

    test "index with name filter" do
      Entry.create!(name: "other.event", occurred_at: Time.current)

      get rails_event_viewer.events_path(name: "test.event")

      assert_response :success
    end

    test "index with date filters" do
      get rails_event_viewer.events_path(
        start_date: 1.day.ago.to_date.to_s,
        end_date: Date.current.to_s
      )

      assert_response :success
    end

    test "index with tag filter" do
      get rails_event_viewer.events_path(
        tag_key: "environment",
        tag_value: "test"
      )

      assert_response :success
    end

    test "index with search query" do
      get rails_event_viewer.events_path(q: "test")

      assert_response :success
    end

    test "index paginates results" do
      30.times do |i|
        Entry.create!(name: "event.#{i}", occurred_at: i.minutes.ago)
      end

      get rails_event_viewer.events_path

      assert_response :success
    end

    test "show renders successfully" do
      get rails_event_viewer.event_path(@event)

      assert_response :success
    end

    test "show with non-existent event redirects" do
      get rails_event_viewer.event_path(id: 999999)

      assert_redirected_to rails_event_viewer.events_path
      assert_equal "Event not found", flash[:alert]
    end

    test "show finds related events by request_id" do
      Entry.create!(
        name: "related.event",
        context: { request_id: "abc123" },
        occurred_at: 1.second.ago
      )

      get rails_event_viewer.event_path(@event)

      assert_response :success
    end

    test "search renders index template" do
      get rails_event_viewer.search_events_path(q: "test")
      assert_response :success
    end

    test "search with empty query" do
      get rails_event_viewer.search_events_path(q: "")

      assert_response :success
    end

    test "search with matching results" do
      get rails_event_viewer.search_events_path(q: "test.event")

      assert_response :success
    end

    test "search with no matching results" do
      get rails_event_viewer.search_events_path(q: "nonexistent")

      assert_response :success
    end

    test "index ignores unparseable dates instead of crashing" do
      get rails_event_viewer.events_path(start_date: "garbage", end_date: "2026-13-45")
      assert_response :success

      get rails_event_viewer.events_path, params: { start_date: ["2026-01-01"] }
      assert_response :success
    end

    test "show finds related events that share a request_id in context" do
      related = Entry.create!(name: "related.event", context: { request_id: "abc123" }, occurred_at: Time.current)
      Entry.create!(name: "unrelated.event", context: { request_id: "other" }, occurred_at: Time.current)

      get rails_event_viewer.event_path(@event)

      related_events = controller.instance_variable_get(:@related_events)
      assert_equal [related.id], related_events.map(&:id)
    end

    test "index filters by context key and value" do
      Entry.create!(name: "other.event", context: { request_id: "zzz" }, occurred_at: Time.current)

      get rails_event_viewer.events_path(context_key: "request_id", context_value: "abc123")

      assert_equal [@event.id], controller.instance_variable_get(:@events).map(&:id)
    end
  end
end
