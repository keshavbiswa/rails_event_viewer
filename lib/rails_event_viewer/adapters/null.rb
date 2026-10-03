module RailsEventViewer
  module Adapters
    class Null
      include Adapter

      def supports_persistence?
        false
      end

      def supports_analytics?
        false
      end

      def write_events(events)
        nil
      end

      def fetch_events(relation)
        []
      end

      def count_events(relation)
        0
      end

      def distinct_event_names
        []
      end

      def find_event(id)
        nil
      end

      def delete_before(timestamp)
        0
      end

      def events_over_time(range:, interval:)
        {}
      end

      def counts_by_name(limit: nil, range: nil)
        {}
      end

      def count_since(since)
        0
      end

      def group_instances(key, source: :context, limit: 100)
        []
      end
    end
  end
end
