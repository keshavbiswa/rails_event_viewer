# frozen_string_literal: true

module RailsEventViewer
  module Adapters
    module Concerns
      module InMemoryFiltering
        extend ActiveSupport::Concern

        def distinct_group_values(key, source: :context)
          in_memory_events
            .map { |e| group_value_for(e, key, source) }
            .compact
            .uniq
        end

        def group_instances(key, source: :context, limit: 100)
          in_memory_events
            .group_by { |e| group_value_for(e, key, source) }
            .reject { |value, _| value.nil? }
            .map { |value, events| build_group_instance(value, events) }
            .sort_by { |s| -(s[:last_event_at]&.to_f || 0) }
            .take(limit)
        end

        def event_time_span(relation)
          filtered = filter_events(in_memory_events, relation)
          timestamps = filtered.filter_map { |e| e[:occurred_at] }
          [timestamps.min, timestamps.max]
        end

        private

        def group_value_for(event, key, source)
          data = event[source]
          data&.dig(key.to_s) || data&.dig(key.to_sym)
        end

        def build_group_instance(value, events)
          timestamps = events.map { |e| e[:occurred_at] }.compact
          {
            value: value,
            count: events.size,
            first_event_at: timestamps.min,
            last_event_at: timestamps.max
          }
        end

        def filter_events(events, relation)
          result = events

          result = filter_by_names(result, relation.names)
          result = filter_by_tags(result, relation.tags)
          result = filter_by_contexts(result, relation.contexts)
          result = filter_by_time_range(result, relation.since_time, relation.until_time)
          result = filter_by_search_query(result, relation.query)

          result
        end

        def filter_by_names(events, names)
          return events if names.blank?

          events.select { |e| names.include?(e[:name]) }
        end

        def filter_by_tags(events, tags)
          return events if tags.blank?

          events.select do |e|
            event_tags = e[:tags] || {}
            tags.all? do |key, value|
              hash_key_matches?(event_tags, key, value)
            end
          end
        end

        def filter_by_contexts(events, contexts)
          return events if contexts.blank?

          events.select do |e|
            event_context = e[:context] || {}
            contexts.all? do |key, value|
              hash_key_matches?(event_context, key, value)
            end
          end
        end

        def hash_key_matches?(hash, key, value)
          if value.nil?
            hash.key?(key.to_s) || hash.key?(key.to_sym)
          else
            values_match?(hash[key.to_s], value) || values_match?(hash[key.to_sym], value)
          end
        end

        def values_match?(actual, expected)
          return false if actual.nil?

          actual == expected || actual.to_s == expected.to_s
        end

        def filter_by_time_range(events, since_time, until_time)
          result = events

          if since_time
            result = result.select { |e| e[:occurred_at] && e[:occurred_at] >= since_time }
          end

          if until_time
            result = result.select { |e| e[:occurred_at] && e[:occurred_at] <= until_time }
          end

          result
        end

        def filter_by_search_query(events, query)
          return events if query.blank?

          query_downcase = query.downcase
          events.select do |e|
            name_matches?(e[:name], query_downcase) ||
              payload_matches?(e[:payload], query_downcase)
          end
        end

        def name_matches?(name, query)
          name&.downcase&.include?(query)
        end

        def payload_matches?(payload, query)
          payload.to_s.downcase.include?(query)
        end
      end
    end
  end
end
