require "test_helper"
require "rails_event_viewer/adapters/active_record"
require "rails_event_viewer/adapters/memory"
require "rails_event_viewer/adapters/null"

module RailsEventViewer
  class ConfigurationTest < ActiveSupport::TestCase
    teardown do
      RailsEventViewer.storage_adapter = :active_record
      RailsEventViewer.adapter_options = {}
      RailsEventViewer.async = false
      RailsEventViewer.buffer_size = 100
      RailsEventViewer.flush_interval = 2
      RailsEventViewer.sample_rate = 1.0
      RailsEventViewer.retention_period = 7.days
      RailsEventViewer.per_page = 25
      RailsEventViewer.captured_events = []
      RailsEventViewer.ignored_events = []
      RailsEventViewer.reset_adapter!
    end

    test "configure yields self" do
      RailsEventViewer.configure do |config|
        assert_same RailsEventViewer, config
      end
    end

    test "storage_adapter defaults to :active_record" do
      RailsEventViewer.reset_adapter!
      RailsEventViewer.storage_adapter = :active_record
      assert_instance_of RailsEventViewer::Adapters::ActiveRecord, RailsEventViewer.adapter
    end

    test "storage_adapter can be set to :memory" do
      RailsEventViewer.storage_adapter = :memory
      RailsEventViewer.reset_adapter!

      assert_instance_of RailsEventViewer::Adapters::Memory, RailsEventViewer.adapter
    end

    test "storage_adapter can be set to :null" do
      RailsEventViewer.storage_adapter = :null
      RailsEventViewer.reset_adapter!

      assert_instance_of RailsEventViewer::Adapters::Null, RailsEventViewer.adapter
    end

    test "storage_adapter raises for unknown adapter" do
      RailsEventViewer.storage_adapter = :unknown
      RailsEventViewer.reset_adapter!

      assert_raises ArgumentError do
        RailsEventViewer.adapter
      end
    end

    test "storage_adapter accepts custom class" do
      custom_adapter = Class.new do
        include RailsEventViewer::Adapter

        def write_events(events); end
        def fetch_events(relation); []; end
        def count_events(relation); 0; end
        def distinct_event_names; []; end
        def find_event(id); nil; end
        def delete_before(timestamp); 0; end
      end

      RailsEventViewer.storage_adapter = custom_adapter
      RailsEventViewer.reset_adapter!

      assert_instance_of custom_adapter, RailsEventViewer.adapter
    end

    test "adapter_options are passed to adapter" do
      RailsEventViewer.storage_adapter = :memory
      RailsEventViewer.adapter_options = { max_events: 50 }
      RailsEventViewer.reset_adapter!

      adapter = RailsEventViewer.adapter
      assert_equal 50, adapter.instance_variable_get(:@max_events)
    end

    test "events returns EventsRelation" do
      assert_instance_of EventsRelation, RailsEventViewer.events
    end

    test "subscriber returns Subscriber instance" do
      assert_instance_of Subscriber, RailsEventViewer.subscriber
    end

    test "reset_adapter! clears cached adapter" do
      adapter1 = RailsEventViewer.adapter
      RailsEventViewer.reset_adapter!
      adapter2 = RailsEventViewer.adapter

      refute_same adapter1, adapter2
    end

    test "http_basic_auth_enabled defaults to false" do
      assert_equal false, RailsEventViewer.http_basic_auth_enabled
    end

    test "authentication defaults to nil" do
      assert_nil RailsEventViewer.authentication
    end
  end
end
