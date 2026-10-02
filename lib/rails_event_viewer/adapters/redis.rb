# frozen_string_literal: true

require_relative "concerns/in_memory_filtering"

module RailsEventViewer
  module Adapters
    class Redis
      include Adapter
      include Concerns::InMemoryFiltering

      DEFAULT_KEY_PREFIX = "rails_event_viewer"
      DEFAULT_MAX_EVENTS = 10_000
      DEFAULT_POOL_SIZE = 5
      DEFAULT_POOL_TIMEOUT = 5
      NAME_BATCH_TTL_SECONDS = 60

      # Matches event IDs in format: microsecond_timestamp-hex
      # Example: "1702089600123456-a1b2c3d4e5f6g7h8"
      EVENT_ID_PATTERN = /^(\d+)-([a-f0-9]+)$/i

      def initialize(redis_options: {}, pool_size: DEFAULT_POOL_SIZE, pool_timeout: DEFAULT_POOL_TIMEOUT,
                     pool: build_pool(pool_size, pool_timeout, redis_options),
                     key_prefix: DEFAULT_KEY_PREFIX, max_events: DEFAULT_MAX_EVENTS)
        @redis = pool
        @key_prefix = "{#{key_prefix}}"
        @max_events = max_events
      end

      def supports_analytics?
        true
      end

      def write_events(events)
        return if events.empty?

        newest_by_name = Hash.new(0)
        batch_key = "#{@key_prefix}:name_batch:#{SecureRandom.hex(8)}"

        @redis.with do |redis|
          results = redis.pipelined do |pipe|
            events.each do |event|
              timestamp_usec = (event[:occurred_at].to_f * 1_000_000).to_i
              pipe.zadd(events_key, timestamp_usec, serialize_event(event, timestamp_usec))
              name = event[:name].to_s
              newest_by_name[name] = timestamp_usec if timestamp_usec > newest_by_name[name]
            end
            pipe.zadd(batch_key, newest_by_name.map { |name, score| [score, name] })
            pipe.expire(batch_key, NAME_BATCH_TTL_SECONDS)
            pipe.zunionstore(names_key, [names_key, batch_key], aggregate: "max")
            pipe.del(batch_key)
            pipe.zremrangebyrank(events_key, 0, -@max_events - 1)
          end

          prune_names(redis) if results.last.to_i.positive?
        end
      end

      def fetch_events(relation)
        if relation.filtered?
          return fetch_all_filtered(relation).drop(relation.offset_value).take(relation.limit_value)
        end

        start_idx = relation.offset_value
        end_idx = start_idx + relation.limit_value - 1

        @redis.with { |conn| conn.zrevrange(events_key, start_idx, end_idx) }.map { |json| deserialize_event(json) }
      end

      def count_events(relation)
        if relation.filtered?
          fetch_all_filtered(relation).size
        else
          @redis.with { |conn| conn.zcard(events_key) }
        end
      end

      def distinct_event_names
        @redis.with { |conn| conn.zrange(names_key, 0, -1).sort }
      end

      def find_event(id)
        id_str = id.to_s
        match = id_str.match(EVENT_ID_PATTERN)
        return nil unless match

        timestamp_usec = match[1].to_i

        serialized_events = @redis.with { |conn| conn.zrangebyscore(events_key, timestamp_usec, timestamp_usec) }
        return nil if serialized_events.empty?

        serialized_events.each do |json|
          event = deserialize_event(json)
          return event if event[:id] == id_str
        end

        nil
      end

      def delete_before(timestamp)
        score = (timestamp.to_f * 1_000_000).to_i
        @redis.with do |conn|
          deleted = conn.zremrangebyscore(events_key, "-inf", score)
          prune_names(conn)
          deleted
        end
      end

      def count_since(since)
        score = (since.to_f * 1_000_000).to_i
        @redis.with { |conn| conn.zcount(events_key, score, "+inf") }
      end

      def clear!
        @redis.with { |conn| conn.del(events_key, names_key) }
      end

      private

      def build_pool(size, timeout, redis_options)
        require "connection_pool"
        ConnectionPool.new(size: size, timeout: timeout) { build_redis(redis_options) }
      rescue LoadError
        raise ArgumentError, "connection_pool gem not loaded. Add `gem 'connection_pool'` to your Gemfile."
      end

      def build_redis(options)
        if defined?(::Redis)
          ::Redis.new(**options)
        else
          raise ArgumentError, "Redis gem not loaded. Add `gem 'redis'` to your Gemfile."
        end
      end

      def events_key
        "#{@key_prefix}:events"
      end

      def names_key
        "#{@key_prefix}:name_index"
      end

      def prune_names(conn)
        conn.watch(events_key) do
          oldest = conn.zrange(events_key, 0, 0, with_scores: true).first

          conn.multi do |tx|
            if oldest
              tx.zremrangebyscore(names_key, "-inf", "(#{oldest.last.to_i}")
            else
              tx.del(names_key)
            end
          end
        end
      end

      def serialize_event(event, timestamp_usec = nil)
        timestamp_usec ||= (event[:occurred_at].to_f * 1_000_000).to_i
        event_with_id = event.merge(id: "#{timestamp_usec}-#{SecureRandom.hex(8)}")
        JSON.generate(event_with_id)
      end

      def deserialize_event(json)
        data = JSON.parse(json, symbolize_names: true)

        if data[:occurred_at].is_a?(String)
          data[:occurred_at] = Time.parse(data[:occurred_at])
        elsif data[:occurred_at].is_a?(Numeric)
          data[:occurred_at] = Time.at(data[:occurred_at])
        end

        data
      end

      def fetch_all_events
        serialized_events = @redis.with { |conn| conn.zrevrange(events_key, 0, -1) }
        serialized_events.map { |json| deserialize_event(json) }
      end

      def fetch_all_filtered(relation)
        events = fetch_all_events
        filter_events(events, relation)
      end

      def in_memory_events
        fetch_all_events
      end
    end
  end
end
