module RailsEventViewer
  module Adapters
    class ActiveRecord
      include Adapter

      def initialize(**options)
        @options = options
      end

      def table_exists?
        Entry.table_exists?
      rescue ::ActiveRecord::NoDatabaseError, ::ActiveRecord::StatementInvalid
        false
      end

      def write_events(events)
        return if events.empty?

        # Use insert_all for bulk inserts (more efficient)
        records = events.map do |event|
          {
            name: event[:name],
            payload: event[:payload] || {},
            tags: event[:tags] || {},
            context: event[:context] || {},
            source_file: event[:source_file],
            source_line: event[:source_line],
            source_label: event[:source_label],
            occurred_at: event[:occurred_at],
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        Entry.insert_all(records)
      end

      def fetch_events(relation)
        build_scope(relation)
          .offset(relation.offset_value)
          .limit(relation.limit_value)
      end

      def count_events(relation)
        build_scope(relation).count
      end

      def distinct_event_names
        Entry.distinct.pluck(:name).compact.sort
      end

      def find_event(id)
        Entry.find_by(id: id)
      end

      def delete_before(timestamp)
        Entry.where("occurred_at < ?", timestamp).in_batches.delete_all
      end

      def events_over_time(since:, interval:)
        scope = Entry.where("occurred_at >= ?", since)

        case interval
        when :minute
          scope.group_by_minute(:occurred_at).count
        when :hour
          scope.group_by_hour(:occurred_at).count
        when :day
          scope.group_by_day(:occurred_at).count
        when :week
          scope.group_by_week(:occurred_at).count
        else
          scope.group_by_hour(:occurred_at).count
        end
      end

      def counts_by_name(limit:)
        Entry.group(:name)
             .order(Arel.sql("COUNT(*) DESC"))
             .limit(limit)
             .count
      end

      def count_since(since)
        Entry.where("occurred_at >= ?", since).count
      end

      def event_type_statistics
        Entry
          .group(:name)
          .order(Arel.sql("COUNT(*) DESC"))
          .pluck(:name, Arel.sql("COUNT(*)"), Arel.sql("MAX(occurred_at)"))
          .map do |name, count, last_event_at|
            {
              name: name,
              count: count,
              last_event_at: parse_timestamp(last_event_at)
            }
          end
      end

      def distinct_group_values(key, source: :context)
        column = source == :tags ? :tags : :context
        json_path = JsonQuery.extract_path(column, key)

        Entry
          .where(JsonQuery.extract_path_present(column, key))
          .distinct
          .pluck(Arel.sql(json_path))
      end

      def group_instances(key, source: :context, limit: 100)
        column = source == :tags ? :tags : :context
        json_path = JsonQuery.extract_path(column, key)

        Entry
          .select(
            Arel.sql("#{json_path} as group_value"),
            Arel.sql("COUNT(*) as event_count"),
            Arel.sql("MIN(occurred_at) as first_event_at"),
            Arel.sql("MAX(occurred_at) as last_event_at")
          )
          .where(JsonQuery.extract_path_present(column, key))
          .group(Arel.sql(json_path))
          .order(Arel.sql("MAX(occurred_at) DESC"))
          .limit(limit)
          .map do |row|
            {
              value: row.group_value,
              count: row.event_count,
              first_event_at: parse_timestamp(row.first_event_at),
              last_event_at: parse_timestamp(row.last_event_at)
            }
          end
      end

      def fetch_last(relation)
        build_scope(relation).reorder(occurred_at: :asc, id: :asc).first
      end

      def event_time_span(relation)
        row = build_scope(relation).unscope(:order).pick(
          Arel.sql("MIN(occurred_at)"),
          Arel.sql("MAX(occurred_at)")
        )
        return [nil, nil] unless row
        [parse_timestamp(row[0]), parse_timestamp(row[1])]
      end

      private

      def parse_timestamp(value)
        return nil if value.nil?
        return value if value.is_a?(Time)

        ActiveSupport::TimeZone["UTC"].parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def build_scope(relation)
        scope = Entry.order(occurred_at: :desc)
        scope = apply_name_filters(scope, relation)
        scope = apply_tag_filters(scope, relation)
        scope = apply_context_filters(scope, relation)
        scope = apply_time_filters(scope, relation)
        scope = apply_search(scope, relation)
        scope
      end

      def apply_name_filters(scope, relation)
        return scope if relation.names.blank?

        if relation.names.size == 1
          scope.where(name: relation.names.first)
        else
          scope.where(name: relation.names)
        end
      end

      def apply_tag_filters(scope, relation)
        return scope if relation.tags.blank?

        relation.tags.each do |key, value|
          scope = scope.where(*JsonQuery.contains(:tags, key, value))
        end
        scope
      end

      def apply_context_filters(scope, relation)
        return scope if relation.contexts.blank?

        relation.contexts.each do |key, value|
          scope = scope.where(*JsonQuery.contains(:context, key, value))
        end
        scope
      end

      def apply_time_filters(scope, relation)
        scope = scope.where("occurred_at >= ?", relation.since_time) if relation.since_time
        scope = scope.where("occurred_at <= ?", relation.until_time) if relation.until_time
        scope
      end

      def apply_search(scope, relation)
        return scope if relation.query.blank?

        sanitized = "%#{Entry.sanitize_sql_like(relation.query.downcase, "!")}%"
        text_type = JsonQuery.detect_adapter == :mysql ? "CHAR" : "TEXT"
        scope.where(
          "LOWER(name) LIKE :q ESCAPE '!' OR LOWER(CAST(payload AS #{text_type})) LIKE :q ESCAPE '!'",
          q: sanitized
        )
      end
    end
  end
end
