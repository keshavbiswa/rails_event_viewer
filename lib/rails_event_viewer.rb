require "pagy"
require "chartkick"
require "groupdate"

require "rails_event_viewer/version"
require "rails_event_viewer/engine"

module RailsEventViewer
  mattr_accessor :storage_adapter, default: :active_record
  mattr_accessor :adapter_options, default: {}

  mattr_accessor :async, default: true # Use buffered writes
  mattr_accessor :buffer_size, default: 100 # Flush after N events
  mattr_accessor :flush_interval, default: 2 # Flush every N seconds
  mattr_accessor :sample_rate, default: 1.0 # 1.0 = 100%, 0.1 = 10%

  mattr_accessor :retention_period, default: 7.days
  mattr_accessor :captured_events, default: []      # Empty = capture all
  mattr_accessor :ignored_events, default: [
    /^active_record\./,
    /^action_controller\./,
    /^action_view\./,
    /^active_job\./,
    /^action_mailer\./,
    /^active_storage\./,
    /^action_cable\./,
    /^rails\./,
    /^turbo\./,
    /^cache_/,
    /\.sql$/,
    /^solid_/
  ]
  mattr_accessor :per_page, default: 25

  mattr_accessor :http_basic_auth_enabled, default: false
  mattr_accessor :http_basic_auth_user
  mattr_accessor :http_basic_auth_password
  mattr_accessor :authentication, default: nil

  mattr_accessor :group_keys, default: [:request_id]

  mattr_accessor :logger

  class << self
    def configure
      yield self
    end

    ADAPTER_LOCK = Mutex.new

    def adapter
      @adapter || ADAPTER_LOCK.synchronize { @adapter ||= build_adapter }
    end

    def reset_adapter!
      ADAPTER_LOCK.synchronize { @adapter = nil }
    end

    def events
      EventsRelation.new(adapter: adapter)
    end

    def subscriber
      @subscriber ||= Subscriber.new
    end

    def subscribe!
      return unless defined?(Rails.event)

      Rails.event.subscribe(subscriber)
    end

    def shutdown!
      subscriber.stop!
    end

    private

    def build_adapter
      adapter_instance = case storage_adapter
      when :active_record
        require "rails_event_viewer/adapters/active_record"
        Adapters::ActiveRecord.new(**adapter_options)
      when :redis
        require "rails_event_viewer/adapters/redis"
        Adapters::Redis.new(**adapter_options)
      when :memory
        require "rails_event_viewer/adapters/memory"
        Adapters::Memory.new(**adapter_options)
      when :null
        require "rails_event_viewer/adapters/null"
        Adapters::Null.new
      when Class
        storage_adapter.new(**adapter_options)
      else
        raise ArgumentError, "Unknown adapter: #{storage_adapter}. " \
          "Valid options: :active_record, :redis, :memory, :null, or a custom adapter class"
      end

      if storage_adapter == :active_record && !adapter_instance.table_exists?
        effective_logger.warn "[RailsEventViewer] Table 'rails_event_viewer_entries' not found. " \
                              "Run `rails rails_event_viewer:install:migrations` and `rails db:migrate`. " \
                              "Falling back to NullAdapter (events will not be persisted)."
        require "rails_event_viewer/adapters/null"
        Adapters::Null.new
      else
        adapter_instance
      end
    end

    def effective_logger
      logger || (defined?(Rails) && Rails.logger) || Logger.new($stdout)
    end
  end
end

require "rails_event_viewer/adapter"
require "rails_event_viewer/events_relation"
require "rails_event_viewer/subscriber"
require "rails_event_viewer/json_query"
require "rails_event_viewer/pagy_countable"
require "rails_event_viewer/time_utils"
