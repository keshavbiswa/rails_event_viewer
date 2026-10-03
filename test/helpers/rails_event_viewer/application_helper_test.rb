# frozen_string_literal: true

require "test_helper"

module RailsEventViewer
  class ApplicationHelperTest < ActionView::TestCase
    include RailsEventViewer::ApplicationHelper

    test "#format_event_time with Entry model" do
      event = Entry.new(occurred_at: Time.current)
      result = format_event_time(event)

      assert_match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}/, result)
    end

    test "#format_event_time with hash" do
      event = { occurred_at: Time.current }
      result = format_event_time(event)

      assert_match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}/, result)
    end

    test "#format_event_time with nil time returns N/A" do
      event = Entry.new(occurred_at: nil)

      assert_equal "N/A", format_event_time(event)
    end

    test "#truncate_json with hash" do
      json = { key: "value", another: "data" }
      result = truncate_json(json, length: 50)

      assert result.is_a?(String)
    end

    test "#truncate_json with string" do
      result = truncate_json("some json string", length: 10)

      assert result.is_a?(String)
    end

    test "#truncate_json truncates long content" do
      long_hash = { data: "x" * 200 }
      result = truncate_json(long_hash, length: 50)

      # Result is truncated and ends with "..."
      assert result.end_with?("...")
      # Original JSON would be much longer than 200 chars, but result is limited
      original = long_hash.to_json

      assert result.length < original.length
    end

    test "#json_tree with nil" do
      result = json_tree(nil)

      assert_match(/null/, result)
    end

    test "#json_tree and #truncate_json show special characters readably and escape them once" do
      payload = { note: "Tom & Jerry <b>" }

      [json_tree(payload), ERB::Util.html_escape(truncate_json(payload))].each do |html|
        assert_includes html, "Tom &amp; Jerry &lt;b&gt;"
        assert_not_includes html, "\\u0026"
        assert_not_includes html, "<b>"
      end
    end

    test "#json_tree with empty hash" do
      result = json_tree({})

      assert_match(/\{\}/, result)
    end

    test "#json_tree with empty array" do
      result = json_tree([])

      assert_match(/\[\]/, result)
    end

    test "#json_tree with string value" do
      result = json_tree("hello")

      assert_match(/hello/, result)
      assert_match(/text-green-600/, result)
    end

    test "#json_tree with numeric value" do
      result = json_tree(42)

      assert_match(/42/, result)
      assert_match(/text-blue-600/, result)
    end

    test "#json_tree with boolean value" do
      result = json_tree(true)
      assert_match(/true/, result)
      assert_match(/text-purple-600/, result)
    end

    test "#json_tree with hash" do
      result = json_tree({ name: "test", count: 5 })

      assert_match(/name:/, result)
      assert_match(/test/, result)
      assert_match(/count:/, result)
      assert_match(/5/, result)
    end

    test "#json_tree with array" do
      result = json_tree(["a", "b", "c"])

      assert_match(/\[0\]:/, result)
      assert_match(/\[1\]:/, result)
      assert_match(/\[2\]:/, result)
    end

    test "#json_tree with nested structure" do
      result = json_tree({ user: { name: "Alice", age: 30 } })

      assert_match(/user:/, result)
      assert_match(/name:/, result)
      assert_match(/Alice/, result)
    end

    test "#format_duration with nil returns dash" do
      assert_equal "-", format_duration(nil)
    end

    test "#format_duration with zero" do
      assert_equal "0 seconds", format_duration(0)
    end

    test "#format_duration with seconds" do
      assert_equal "5 seconds", format_duration(5)
    end

    test "#format_duration with one second" do
      assert_equal "1 second", format_duration(1)
    end

    test "#format_duration with minutes" do
      assert_equal "2 minutes", format_duration(120)
    end

    test "#format_duration with minutes and seconds" do
      assert_equal "1 minute and 30 seconds", format_duration(90)
    end

    test "#format_duration with hours" do
      assert_equal "1 hour", format_duration(3600)
    end

    test "#format_duration with complex duration" do
      # 1 hour, 2 minutes, 3 seconds = 3723 seconds
      result = format_duration(3723)

      assert_match(/1 hour/, result)
      assert_match(/2 minutes/, result)
      assert_match(/3 seconds/, result)
    end

    test "#format_duration with days" do
      result = format_duration(86400)

      assert_equal "1 day", result
    end

    test "#event_payload with model" do
      event = Entry.new(payload: { "key" => "value" })

      assert_equal({ "key" => "value" }, event_payload(event))
    end

    test "#event_payload with nil returns empty hash" do
      event = Entry.new(payload: nil)

      assert_equal({}, event_payload(event))
    end

    test "#event_tags with model" do
      event = Entry.new(tags: { "env" => "test" })

      assert_equal({ "env" => "test" }, event_tags(event))
    end

    test "#event_context with model" do
      event = Entry.new(context: { "request_id" => "123" })

      assert_equal({ "request_id" => "123" }, event_context(event))
    end

    test "#event_short_filepath strips path prefix" do
      event = Entry.new(source_file: "/some/long/path/app/controllers/test_controller.rb")

      assert_equal "app/controllers/test_controller.rb", event_short_filepath(event)
    end

    test "#event_short_filepath with nil returns nil" do
      event = Entry.new(source_file: nil)

      assert_nil event_short_filepath(event)
    end
  end
end
