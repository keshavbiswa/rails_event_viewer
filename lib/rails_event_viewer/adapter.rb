module RailsEventViewer
  module Adapter
    extend ActiveSupport::Concern

    def supports_persistence?
      true
    end

    def supports_analytics?
      true
    end

    def write_events(events)
      raise NotImplementedError, "#{self.class} must implement #write_events"
    end

    def fetch_events(relation)
      raise NotImplementedError, "#{self.class} must implement #fetch_events"
    end

    def count_events(relation)
      raise NotImplementedError, "#{self.class} must implement #count_events"
    end

    def distinct_event_names
      raise NotImplementedError, "#{self.class} must implement #distinct_event_names"
    end

    def delete_before(timestamp)
      raise NotImplementedError, "#{self.class} must implement #delete_before"
    end

    def find_event(id)
      raise NotImplementedError, "#{self.class} must implement #find_event"
    end

    def events_over_time(range:, interval:)
      raise NotImplementedError, "#{self.class} must implement #events_over_time" if supports_analytics?
      {}
    end

    def counts_by_name(limit: nil, range: nil)
      raise NotImplementedError, "#{self.class} must implement #counts_by_name" if supports_analytics?
      {}
    end

    def count_since(since)
      raise NotImplementedError, "#{self.class} must implement #count_since" if supports_analytics?
      0
    end

    def event_type_statistics
      distinct_event_names.map do |name|
        build_event_type_stats(name)
      end.sort_by { |s| -s[:count] }
    end

    def group_instances(key, source: :context, limit: 100)
      raise NotImplementedError, "#{self.class} must implement #group_instances"
    end

    def event_time_span(relation)
      [nil, nil]
    end

    private

    def build_event_type_stats(name)
      relation = RailsEventViewer.events.with_name(name)
      last_event = relation.first

      {
        name: name,
        count: relation.count,
        last_event_at: extract_occurred_at(last_event)
      }
    end

    def extract_occurred_at(event)
      return nil unless event

      event.respond_to?(:occurred_at) ? event.occurred_at : event[:occurred_at]
    end
  end
end
