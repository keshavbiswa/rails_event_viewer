module RailsEventViewer
  module JsonQuery
    INTEGER_PATTERN = /\A-?\d+\z/ # Matches: "123", "-456", "0"
    FLOAT_PATTERN = /\A-?\d+\.?\d*\z/ # Matches: "123.45", "-0.5", "123"
    SAFE_KEY_PATTERN = /\A[\w.-]+\z/

    module_function

    def contains(column, key, value = nil)
      adapter = detect_adapter

      case adapter
      when :postgresql
        postgresql_contains(column, key, value)
      when :mysql
        mysql_contains(column, key, value)
      when :sqlite
        sqlite_contains(column, key, value)
      else
        fallback_contains(column, key, value)
      end
    end

    def detect_adapter
      adapter_name = ActiveRecord::Base.connection.adapter_name.downcase

      case adapter_name
      when /postgresql/, /postgis/
        :postgresql
      when /mysql/, /trilogy/
        :mysql
      when /sqlite/
        :sqlite
      else
        :fallback
      end
    end

    # PostgreSQL: Uses @> operator for "contains"
    # Example: tags @> '{"env": "production"}'
    def postgresql_contains(column, key, value = nil)
      if value.present?
        ["#{column} @> ?", { key.to_s => value }.to_json]
      else
        ["#{column} ? :key", { key: key.to_s }]
      end
    end

    def mysql_contains(column, key, value = nil)
      if value.present?
        ["JSON_CONTAINS(#{column}, ?, ?)", value.to_json, "$.#{key}"]
      else
        ["JSON_CONTAINS_PATH(#{column}, 'one', ?)", "$.#{key}"]
      end
    end

    def sqlite_contains(column, key, value = nil)
      if value.present?
        # SQLite stores JSON values with their original types (integers stay integers)
        # We need to cast the value appropriately for comparison
        normalized_value = normalize_sqlite_value(value)
        ["json_extract(#{column}, ?) = ?", "$.#{key}", normalized_value]
      else
        ["json_extract(#{column}, ?) IS NOT NULL", "$.#{key}"]
      end
    end

    def normalize_sqlite_value(value)
      return value unless value.is_a?(String)

      if value.match?(INTEGER_PATTERN)
        value.to_i
      elsif value.match?(FLOAT_PATTERN)
        value.to_f
      else
        value
      end
    end

    def fallback_contains(column, key, value = nil)
      if value.present?
        escaped_key = key.to_s.gsub(/[%_\\]/) { |m| "\\#{m}" }
        ["CAST(#{column} AS TEXT) LIKE ?", "%\"#{escaped_key}\":#{value.to_json}%"]
      else
        escaped_key = key.to_s.gsub(/[%_\\]/) { |m| "\\#{m}" }
        ["CAST(#{column} AS TEXT) LIKE ?", "%\"#{escaped_key}\"%"]
      end
    end

    def extract_path(column, key)
      raise ArgumentError, "Invalid JSON key: #{key.inspect}" unless key.to_s.match?(SAFE_KEY_PATTERN)

      adapter = detect_adapter

      case adapter
      when :postgresql
        "#{column} ->> '#{key}'"
      when :mysql
        "JSON_UNQUOTE(JSON_EXTRACT(#{column}, '$.#{key}'))"
      when :sqlite
        "json_extract(#{column}, '$.#{key}')"
      else
        "json_extract(#{column}, '$.#{key}')"
      end
    end

    def extract_path_not_null(column, key)
      "#{extract_path(column, key)} IS NOT NULL"
    end
  end
end
