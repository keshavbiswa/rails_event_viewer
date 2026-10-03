require "test_helper"

module RailsEventViewer
  class EntryTest < ActiveSupport::TestCase
    setup do
      @entry = Entry.create!(
        name: "test.event",
        payload: { user_id: 123, action: "create" },
        tags: { environment: "test", section: "admin" },
        context: { request_id: "abc123" },
        source_file: "/app/models/user.rb",
        source_line: 42,
        source_label: "User#create",
        occurred_at: Time.current
      )
    end

    test "stores entry with all fields" do
      assert_equal "test.event", @entry.name
      assert_equal({ "user_id" => 123, "action" => "create" }, @entry.payload)
      assert_equal({ "environment" => "test", "section" => "admin" }, @entry.tags)
      assert_equal({ "request_id" => "abc123" }, @entry.context)
      assert_equal "/app/models/user.rb", @entry.source_file
      assert_equal 42, @entry.source_line
      assert_equal "User#create", @entry.source_label
    end
  end
end
