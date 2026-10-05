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

    test "each filter narrows the list to the matching events" do
      other = Entry.create!(name: "other.event", payload: { note: "needle" }, tags: { environment: "prod" }, occurred_at: 3.days.ago)

      {
        { name: "other.event" } => [other.id],
        { q: "needle" } => [other.id],
        { tag_key: "environment", tag_value: "prod" } => [other.id],
        { end_date: 2.days.ago.to_date.to_s } => [other.id],
        { start_date: 1.day.ago.to_date.to_s } => [@event.id]
      }.each do |params, expected|
        get rails_event_viewer.events_path(params)

        assert_equal expected, controller.instance_variable_get(:@events).pluck(:id), params.inspect
      end
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

    test "show renders for an event whose name has a slash and links to its event type" do
      event = Entry.create!(name: "billing/invoice.paid", occurred_at: Time.current)

      get rails_event_viewer.event_path(event)

      assert_response :success
      assert_select "a[href=?]", rails_event_viewer.event_type_path(name: "billing/invoice.paid")
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

    test "search and filters apply together, and the sidebar keeps the search" do
      Entry.create!(name: "test.other", tags: { environment: "prod" }, occurred_at: Time.current)

      get rails_event_viewer.events_path(q: "test", tag_key: "environment", tag_value: "test")

      assert_equal [@event.id], controller.instance_variable_get(:@events).pluck(:id)
      assert_select "h1", /matching "test"/
      assert_select "input[type=hidden][name=q][value=test]"
    end

    test "an empty list says why: filters matched nothing, or the table is missing" do
      get rails_event_viewer.events_path(tag_key: "nope")

      assert_includes response.body, "Try adjusting your filters"
      assert_select "a", text: "Analytics"

      require "rails_event_viewer/adapters/null"
      RailsEventViewer.instance_variable_set(:@adapter, Adapters::Null.new)
      get rails_event_viewer.events_path

      assert_includes response.body, "Events will appear here"
      assert_select "[role=alert]", /events table is missing/
      assert_select "a", text: "Analytics", count: 0
    end

    test "index ignores malformed params instead of crashing" do
      [
        { start_date: "garbage", end_date: "2026-13-45" },
        { start_date: ["2026-01-01"] },
        { start_date: "1" * 200 },
        { start_date: "999999999-01-01" },
        { page: ["1"] },
        { per_page: ["1"] },
        { name: { a: "b" } },
        { q: ["x"] },
        { tag_key: "environment", tag_value: %w[a b] },
        { context_key: ["request_id"], context_value: { a: "b" } }
      ].each do |params|
        get rails_event_viewer.events_path, params: params

        assert_response :success, params.inspect
      end

      get rails_event_viewer.analytics_overview_path, params: { start_date: "1" * 200, end_date: ["x"] }

      assert_response :success
    end

    test "show finds related events that share a request_id in context" do
      related = Entry.create!(name: "related.event", context: { request_id: "abc123" }, occurred_at: Time.current)
      Entry.create!(name: "unrelated.event", context: { request_id: "other" }, occurred_at: Time.current)

      get rails_event_viewer.event_path(@event)

      related_events = controller.instance_variable_get(:@related_events)
      assert_equal [related.id], related_events.pluck(:id)
    end

    test "index filters by context key and value" do
      Entry.create!(name: "other.event", context: { request_id: "zzz" }, occurred_at: Time.current)

      get rails_event_viewer.events_path(context_key: "request_id", context_value: "abc123")

      assert_equal [@event.id], controller.instance_variable_get(:@events).pluck(:id)
    end

    test "index filters by a numeric context value typed as text" do
      numeric = Entry.create!(name: "order.placed", context: { order_id: 42 }, occurred_at: Time.current)

      get rails_event_viewer.events_path(context_key: "order_id", context_value: "42")

      assert_equal [numeric.id], controller.instance_variable_get(:@events).pluck(:id)
    end

    test "index does not raise on tag and context keys that are not valid JSON paths" do
      ["[", "trace-id", "a b"].each do |key|
        get rails_event_viewer.events_path(tag_key: key, context_key: key, context_value: "x")

        assert_response :success
        assert_empty controller.instance_variable_get(:@events)
      end
    end

    test "index paginates with page param and clamps out of range pages" do
      29.times { |i| Entry.create!(name: "bulk.#{i}", occurred_at: i.minutes.ago) }

      get rails_event_viewer.events_path(page: 2)
      pagination = controller.instance_variable_get(:@pagination)
      assert_equal [2, 2, 30], [pagination.page, pagination.pages, pagination.count]
      assert_equal (24..28).map { |i| "bulk.#{i}" }, controller.instance_variable_get(:@events).pluck(:name)
      assert_select "a[href*='page=1']"

      get rails_event_viewer.events_path(page: 99)
      assert_response :success
      assert_equal 2, controller.instance_variable_get(:@pagination).page
    end

    test "page links keep filters and per_page" do
      30.times { |i| Entry.create!(name: "keep.me", occurred_at: i.minutes.ago) }

      get rails_event_viewer.events_path(name: "keep.me", per_page: 10)

      assert_select "a[aria-current=page]", "Events"
      links = css_select("nav[aria-label=Pagination] a").map { |a| a["href"] }
      assert_includes links, rails_event_viewer.events_path(name: "keep.me", page: 2, per_page: 10)

      get links.find { |link| link.include?("page=2") }
      assert_equal ["keep.me"], controller.instance_variable_get(:@events).pluck(:name).uniq
      assert_equal 10, controller.instance_variable_get(:@events).size
    end

    test "page links cannot be pointed at another host" do
      30.times { |i| Entry.create!(name: "keep.me", occurred_at: i.minutes.ago) }

      get rails_event_viewer.events_path(host: "evil.example", protocol: "https", per_page: 10)

      links = css_select("nav[aria-label=Pagination] a").map { |a| a["href"] }
      assert links.any?
      assert links.all? { |link| link.start_with?(rails_event_viewer.events_path) }, links.inspect
    end

    test "a banner warns when sampling is on" do
      original_sample_rate = RailsEventViewer.sample_rate

      get rails_event_viewer.events_path
      assert_no_match(/Sampling is on/, response.body)

      RailsEventViewer.sample_rate = 0.004
      get rails_event_viewer.events_path
      assert_match(/Sampling is on: only 0.4% of events are recorded/, response.body)
    ensure
      RailsEventViewer.sample_rate = original_sample_rate
    end
  end
end
