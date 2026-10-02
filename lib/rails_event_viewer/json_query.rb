module RailsEventViewer
  module JsonQuery
    SAFE_KEY_PATTERN = /\A[\w.-]+\z/

    module_function

    def contains(column, key, value = nil)
      return exists(column, key) if value.nil?

      adapter = detect_adapter
      return fallback_contains(column, key, value) if adapter == :fallback

      condition = "#{text_at(column, ':path')} = :value"
      binds = { path: path_for(key), value: value.to_s }
      return [condition, binds] unless adapter == :postgresql

      variants = { as_string: value.to_s, as_scalar: parse_scalar(value) }.compact
      prefilter = variants.keys.map { |name| "#{column} @> :#{name}" }.join(" OR ")
      ["(#{prefilter}) AND #{condition}", binds.merge(variants.transform_values { |variant| { key.to_s => variant }.to_json })]
    end

    def exists(column, key)
      case detect_adapter
      when :postgresql
        ["#{column} ? :key", { key: key.to_s }]
      when :mysql
        ["JSON_CONTAINS_PATH(#{column}, 'one', ?)", quoted_path(key)]
      when :sqlite
        ["json_type(#{column}, ?) IS NOT NULL", quoted_path(key)]
      else
        fallback_contains(column, key)
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

    def fallback_contains(column, key, value = nil)
      escaped_key = key.to_s.gsub(/[%_\\]/) { |m| "\\#{m}" }

      if value.nil?
        ["CAST(#{column} AS TEXT) LIKE ?", "%\"#{escaped_key}\"%"]
      else
        ["CAST(#{column} AS TEXT) LIKE ?", "%\"#{escaped_key}\":#{value.to_json}%"]
      end
    end

    def extract_path(column, key)
      raise ArgumentError, "Invalid JSON key: #{key.inspect}" unless key.to_s.match?(SAFE_KEY_PATTERN)

      text_at(column, "'#{path_for(key)}'")
    end

    def extract_path_present(column, key)
      path = extract_path(column, key)
      "#{path} IS NOT NULL AND #{path} <> ''"
    end

    def text_at(column, path)
      case detect_adapter
      when :postgresql
        "#{column} ->> #{path}"
      when :mysql
        "JSON_UNQUOTE(NULLIF(JSON_EXTRACT(#{column}, #{path}), CAST('null' AS JSON))) COLLATE #{mysql_collation}"
      else
        "CASE json_type(#{column}, #{path}) WHEN 'true' THEN 'true' WHEN 'false' THEN 'false' " \
          "ELSE CAST(json_extract(#{column}, #{path}) AS TEXT) END"
      end
    end

    def mysql_collation
      connection = ActiveRecord::Base.connection
      !connection.mariadb? && connection.database_version >= "8.0.17" ? "utf8mb4_0900_bin" : "utf8mb4_bin"
    end

    def path_for(key)
      detect_adapter == :postgresql ? key.to_s : quoted_path(key)
    end

    def quoted_path(key)
      %($."#{key.to_s.gsub(/["\\]/) { |m| "\\#{m}" }}")
    end

    def parse_scalar(value)
      parsed = JSON.parse(value.to_s)
      parsed if parsed.is_a?(Numeric) || parsed == true || parsed == false
    rescue JSON::ParserError
      nil
    end
  end
end
