module RailsEventViewer
  module Adapters
    class ActiveRecord
      include Adapter

      def table_exists?
        Entry.table_exists?
      rescue ::ActiveRecord::NoDatabaseError
        false
      end

      def write_events(events)
        return if events.empty?

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

        Entry.transaction(requires_new: !RailsEventViewer.transactional) do
          Entry.insert_all(records, returning: false)
        end
      end

      def fetch_events(relation)
        build_scope(relation)
          .offset(relation.offset_value)
          .limit(relation.limit_value)
          .map { |entry| to_event(entry) }
      end

      def count_events(relation)
        build_scope(relation).count
      end

      def distinct_event_names
        Entry.distinct.pluck(:name).compact.sort
      end

      def find_event(id)
        entry = Entry.find_by(id: id)
        to_event(entry) if entry
      end

      def delete_before(timestamp)
        Entry.where("occurred_at < ?", timestamp).in_batches.delete_all
      end

      def clear!
        Entry.in_batches.delete_all
      end

      def events_over_time(range:, interval:)
        Entry.where(occurred_at: range).group_by_period(interval, :occurred_at).count
      end

      def counts_by_name(limit: nil, range: nil)
        scope = range ? Entry.where(occurred_at: range) : Entry
        scope.group(:name).order(Arel.sql("COUNT(*) DESC")).limit(limit).count
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
        entry = build_scope(relation).reorder(occurred_at: :asc, id: :asc).first
        to_event(entry) if entry
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

      def to_event(entry)
        entry.attributes.deep_symbolize_keys
      end

      def parse_timestamp(value)
        return nil if value.nil?
        return value if value.is_a?(Time)

        ActiveSupport::TimeZone["UTC"].parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def build_scope(relation)
        scope = Entry.order(occurred_at: :desc, id: :desc)
        scope = scope.where(name: relation.names) if relation.names.present?
        scope = apply_json_filters(scope, :tags, relation.tags)
        scope = apply_json_filters(scope, :context, relation.contexts)
        scope = apply_time_filters(scope, relation)
        scope = apply_search(scope, relation)
        scope
      end

      def apply_json_filters(scope, column, filters)
        filters.each do |key, value|
          scope = scope.where(*JsonQuery.contains(column, key, value))
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
