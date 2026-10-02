# frozen_string_literal: true

require "test_helper"

module RailsEventViewer
  class GroupsControllerTest < ActionDispatch::IntegrationTest
    setup do
      Entry.delete_all
      @original_group_keys = RailsEventViewer.group_keys
      RailsEventViewer.group_keys = [:request_id, :order_id]
    end

    teardown do
      RailsEventViewer.group_keys = @original_group_keys
    end

    test "index renders successfully with no group keys" do
      RailsEventViewer.group_keys = []

      get rails_event_viewer.groups_path

      assert_response :success
    end

    test "index renders successfully with group keys configured" do
      get rails_event_viewer.groups_path

      assert_response :success
    end

    test "index uses first group key by default" do
      Entry.create!(
        name: "test.event",
        context: { request_id: "req-123" },
        occurred_at: Time.current
      )

      get rails_event_viewer.groups_path

      assert_response :success
    end

    test "index with specific key parameter" do
      Entry.create!(
        name: "order.created",
        context: { order_id: "order-456" },
        occurred_at: Time.current
      )

      get rails_event_viewer.groups_path(key: "order_id")

      assert_response :success
    end

    test "index with source parameter context" do
      Entry.create!(
        name: "test.event",
        context: { request_id: "req-123" },
        occurred_at: Time.current
      )

      get rails_event_viewer.groups_path(key: "request_id", source: "context")

      assert_response :success
    end

    test "index with source parameter tags" do
      Entry.create!(
        name: "test.event",
        tags: { request_id: "req-123" },
        occurred_at: Time.current
      )

      get rails_event_viewer.groups_path(key: "request_id", source: "tags")

      assert_response :success
    end

    test "index groups events and returns correct group counts" do
      3.times do
        Entry.create!(
          name: "test.event",
          context: { request_id: "req-123" },
          occurred_at: Time.current
        )
      end
      2.times do
        Entry.create!(
          name: "test.event",
          context: { request_id: "req-456" },
          occurred_at: Time.current
        )
      end

      get rails_event_viewer.groups_path(key: "request_id")

      assert_response :success
      groups = controller.instance_variable_get(:@groups)
      assert_equal 2, groups.size
      req123 = groups.find { |g| g[:value] == "req-123" }
      assert_equal 3, req123[:count]
    end

    test "index ignores key not in configured group_keys" do
      get rails_event_viewer.groups_path(key: "x') IS NOT NULL OR 1=1 --")

      assert_response :success
      assert_equal "request_id", controller.instance_variable_get(:@selected_key)
    end

    test "index with invalid source param falls back to context" do
      Entry.create!(
        name: "test.event",
        context: { request_id: "req-123" },
        occurred_at: Time.current
      )

      get rails_event_viewer.groups_path(key: "request_id", source: "payload")

      assert_response :success
      assert_equal :context, controller.instance_variable_get(:@source)
    end

    test "show renders successfully" do
      Entry.create!(
        name: "test.event",
        context: { request_id: "req-123" },
        occurred_at: Time.current
      )

      get rails_event_viewer.group_path(value: "req-123", key: "request_id")

      assert_response :success
    end

    test "show with context source" do
      Entry.create!(
        name: "test.event",
        context: { request_id: "req-123" },
        occurred_at: Time.current
      )

      get rails_event_viewer.group_path(value: "req-123", key: "request_id", source: "context")

      assert_response :success
    end

    test "show with tags source" do
      Entry.create!(
        name: "test.event",
        tags: { request_id: "req-123" },
        occurred_at: Time.current
      )

      get rails_event_viewer.group_path(value: "req-123", key: "request_id", source: "tags")

      assert_response :success
    end

    test "show displays timeline with correct event count" do
      5.times do |i|
        Entry.create!(
          name: "event.#{i}",
          context: { request_id: "req-123" },
          occurred_at: i.seconds.ago
        )
      end

      get rails_event_viewer.group_path(value: "req-123", key: "request_id")

      assert_response :success
      assert_equal 5, controller.instance_variable_get(:@total_count)
    end

    test "show total_count covers all pages not just current page" do
      30.times do |i|
        Entry.create!(
          name: "event.#{i}",
          context: { request_id: "req-123" },
          occurred_at: i.minutes.ago
        )
      end

      get rails_event_viewer.group_path(value: "req-123", key: "request_id")

      assert_response :success
      assert_equal 30, controller.instance_variable_get(:@total_count)
    end

    test "show with no matching events" do
      get rails_event_viewer.group_path(value: "nonexistent", key: "request_id")
      assert_response :success
    end

    test "show time span covers all events not just current page" do
      Entry.create!(name: "first", context: { request_id: "req-123" }, occurred_at: 2.hours.ago)
      25.times { Entry.create!(name: "middle", context: { request_id: "req-123" }, occurred_at: 30.minutes.ago) }
      Entry.create!(name: "last", context: { request_id: "req-123" }, occurred_at: 1.minute.ago)

      get rails_event_viewer.group_path(value: "req-123", key: "request_id")

      assert_response :success
      first_at = controller.instance_variable_get(:@first_event_at)
      last_at = controller.instance_variable_get(:@last_event_at)

      assert_not_nil first_at
      assert_not_nil last_at
      assert first_at < last_at
      assert last_at - first_at > 60 * 60, "time span should cover more than 1 hour, covering all pages"
    end

    test "show keeps dots in the group value" do
      Entry.create!(name: "user.signed_in", context: { request_id: "alice@example.com" }, occurred_at: Time.current)

      get rails_event_viewer.group_path(value: "alice@example.com", key: "request_id")

      assert_response :success
      assert_equal "alice@example.com", controller.instance_variable_get(:@value)
      assert_equal 1, controller.instance_variable_get(:@total_count)
    end

    test "a numeric group opens with the count the index shows" do
      RailsEventViewer.group_keys = [:user_id]
      2.times { Entry.create!(name: "order.placed", context: { user_id: 42 }, occurred_at: Time.current) }
      Entry.create!(name: "order.placed", context: { user_id: "42" }, occurred_at: Time.current)

      get rails_event_viewer.groups_path
      groups = controller.instance_variable_get(:@groups)

      assert_equal [["42", 3]], groups.map { |group| [group[:value], group[:count]] }

      get rails_event_viewer.group_path(value: "42", key: "user_id")

      assert_response :success
      assert_equal 3, controller.instance_variable_get(:@total_count)
    end

    test "show does not raise on a key that is not a valid JSON path" do
      Entry.create!(name: "order.placed", context: { user_id: 42 }, occurred_at: Time.current)

      ["[", "trace-id", "a b"].each do |key|
        get rails_event_viewer.group_path(value: "42", key: key)

        assert_response :success
      end
    end

    test "every group on the index opens, whatever characters the value has" do
      values = ["/orders/1", "a/b/c", "report.json", "a?b#c&d=e", "50% off", "café", "a b", " "]
      values.each { |value| Entry.create!(name: "page.viewed", context: { request_id: value }, occurred_at: Time.current) }

      get rails_event_viewer.groups_path

      assert_response :success
      links = css_select("a[href^='#{rails_event_viewer.group_path}?']").map { |link| link["href"] }
      assert_equal values.size, links.size

      opened = links.map do |href|
        get href

        assert_response :success
        assert_equal 1, controller.instance_variable_get(:@total_count)
        controller.instance_variable_get(:@value)
      end

      assert_equal values.sort, opened.sort
    end

    test "show without a usable key and value goes back to the index" do
      [
        rails_event_viewer.group_path,
        rails_event_viewer.group_path(key: "request_id"),
        rails_event_viewer.group_path(value: "r1"),
        "#{rails_event_viewer.group_path}?key[]=request_id&value=r1",
        "#{rails_event_viewer.group_path}?key=request_id&value[a]=r1"
      ].each do |path|
        get path

        assert_redirected_to rails_event_viewer.groups_path
      end
    end
  end
end
