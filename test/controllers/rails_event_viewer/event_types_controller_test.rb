# frozen_string_literal: true

require "test_helper"

module RailsEventViewer
  class EventTypesControllerTest < ActionDispatch::IntegrationTest
    setup do
      Entry.delete_all
    end

    test "index renders successfully with no events" do
      get rails_event_viewer.event_types_path

      assert_response :success
    end

    test "index renders successfully with events" do
      Entry.create!(name: "user.created", occurred_at: Time.current)
      Entry.create!(name: "user.updated", occurred_at: Time.current)
      Entry.create!(name: "order.placed", occurred_at: Time.current)

      get rails_event_viewer.event_types_path

      assert_response :success
    end

    test "index groups events by name" do
      3.times { Entry.create!(name: "user.created", occurred_at: Time.current) }
      2.times { Entry.create!(name: "order.placed", occurred_at: Time.current) }

      get rails_event_viewer.event_types_path

      assert_response :success
    end

    test "show renders successfully" do
      Entry.create!(name: "user.created", occurred_at: Time.current)

      get rails_event_viewer.event_type_path(name: "user.created")

      assert_response :success
    end

    test "show with multiple events of same type" do
      5.times do |i|
        Entry.create!(name: "user.created", occurred_at: i.minutes.ago)
      end

      get rails_event_viewer.event_type_path(name: "user.created")

      assert_response :success
    end

    test "show with no events for type" do
      get rails_event_viewer.event_type_path(name: "nonexistent.event")
      assert_response :success
    end

    test "show paginates events" do
      30.times do |i|
        Entry.create!(name: "user.created", occurred_at: i.minutes.ago)
      end

      get rails_event_viewer.event_type_path(name: "user.created")

      assert_response :success
    end

    test "show keeps dots in the event name" do
      Entry.create!(name: "order.placed", occurred_at: Time.current)

      get rails_event_viewer.event_type_path(name: "order.placed")

      assert_response :success
      assert_equal "order.placed", controller.instance_variable_get(:@event_type_name)
      assert_equal 1, controller.instance_variable_get(:@total_count)
    end

    test "every event type on the index opens, whatever characters the name has" do
      names = ["billing/invoice.paid", "/leading", "report.json", "a?b#c&d=e", "50% off", "café", "a b"]
      names.each { |name| Entry.create!(name: name, occurred_at: Time.current) }

      get rails_event_viewer.event_types_path

      assert_response :success
      links = css_select("a[href^='#{rails_event_viewer.event_type_path}?']").map { |link| link["href"] }
      assert_equal names.size, links.size

      opened = links.map do |href|
        get href

        assert_response :success
        assert_equal 1, controller.instance_variable_get(:@total_count)
        controller.instance_variable_get(:@event_type_name)
      end

      assert_equal names.sort, opened.sort
    end

    test "show without a usable name goes back to the index" do
      [rails_event_viewer.event_type_path, rails_event_viewer.event_type_path(name: ""), "#{rails_event_viewer.event_type_path}?name[]=a"].each do |path|
        get path

        assert_redirected_to rails_event_viewer.event_types_path
      end
    end
  end
end
