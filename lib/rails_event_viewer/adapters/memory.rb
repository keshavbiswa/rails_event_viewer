# frozen_string_literal: true

require_relative "concerns/in_memory_filtering"

module RailsEventViewer
  module Adapters
    class Memory
      include Adapter
      include Concerns::InMemoryFiltering

      @events = []
      @id_counter = 0
      @mutex = Mutex.new

      class << self
        attr_accessor :events, :id_counter, :mutex
      end

      def events
        self.class.events
      end

      def initialize(max_events: 1000)
        @max_events = max_events
      end

      def supports_retention?
        true
      end

      def write_events(new_events)
        return if new_events.empty?

        mutex.synchronize do
          new_events.each do |event|
            self.class.id_counter += 1
            events << event.merge(id: self.class.id_counter)
          end
          trim_to_max
        end
      end

      def fetch_events(relation)
        sorted = sort_by_occurred_at(mutex.synchronize { events.dup })
        filtered = filter_events(sorted, relation)
        filtered.drop(relation.offset_value).take(relation.limit_value)
      end

      def count_events(relation)
        filter_events(mutex.synchronize { events.dup }, relation).size
      end

      def distinct_event_names
        mutex.synchronize { events.map { |e| e[:name] } }.uniq.compact.sort
      end

      def find_event(id)
        parsed = Integer(id, exception: false)
        return nil unless parsed
        mutex.synchronize { events.find { |e| e[:id] == parsed } }
      end

      def delete_before(timestamp)
        mutex.synchronize do
          original_size = events.size
          events.reject! { |e| e[:occurred_at] && e[:occurred_at] < timestamp }
          original_size - events.size
        end
      end

      def events_over_time(since:, interval:)
        snapshot = mutex.synchronize { events.dup }
        filtered = snapshot.select { |e| e[:occurred_at] && e[:occurred_at] >= since }

        grouped = filtered.group_by do |e|
          TimeUtils.truncate_to_interval(e[:occurred_at], interval)
        end

        grouped.transform_values(&:size).sort.to_h
      end

      def counts_by_name(limit:)
        mutex.synchronize { events.dup }
          .group_by { |e| e[:name] }
          .transform_values(&:size)
          .sort_by { |_, count| -count }
          .take(limit)
          .to_h
      end

      def count_since(since)
        mutex.synchronize { events.count { |e| e[:occurred_at] && e[:occurred_at] >= since } }
      end

      def clear!
        mutex.synchronize do
          events.clear
          self.class.id_counter = 0
        end
      end

      def size
        mutex.synchronize { events.size }
      end

      private

      def in_memory_events
        mutex.synchronize { events.dup }
      end

      def mutex
        self.class.mutex
      end

      def sort_by_occurred_at(evts)
        evts.sort_by { |e| -(e[:occurred_at]&.to_f || 0) }
      end

      def trim_to_max
        return unless events.size > @max_events

        events.sort_by! { |e| e[:occurred_at]&.to_f || 0 }
        events.slice!(0, events.size - @max_events)
      end
    end
  end
end
