# frozen_string_literal: true

require "test_helper"

module RailsEventViewer
  class JsonQueryTest < ActiveSupport::TestCase
    EXTRACT_REQUEST_ID = {
      sqlite: "json_extract(context, '$.request_id')",
      postgresql: "context ->> 'request_id'",
      mysql: "JSON_UNQUOTE(JSON_EXTRACT(context, '$.request_id'))"
    }.freeze

    test "#detect_adapter matches the test database" do
      adapter_name = ActiveRecord::Base.connection.adapter_name.downcase
      expected = { "sqlite" => :sqlite, "postgresql" => :postgresql, "trilogy" => :mysql }

      assert_equal expected.fetch(adapter_name), JsonQuery.detect_adapter
    end

    test "#sqlite_contains with key and value" do
      query, path, value = JsonQuery.sqlite_contains(:tags, "environment", "production")

      assert_equal "json_extract(tags, ?) = ?", query
      assert_equal "$.environment", path
      assert_equal "production", value
    end

    test "#sqlite_contains with key only" do
      query, path = JsonQuery.sqlite_contains(:tags, "environment", nil)

      assert_equal "json_extract(tags, ?) IS NOT NULL", query
      assert_equal "$.environment", path
    end

    test "#sqlite_contains converts integer string to integer" do
      query, path, value = JsonQuery.sqlite_contains(:tags, "count", "42")

      assert_equal 42, value
      assert_kind_of Integer, value
    end

    test "#sqlite_contains converts float string to float" do
      query, path, value = JsonQuery.sqlite_contains(:tags, "rate", "3.14")

      assert_in_delta 3.14, value, 0.001
      assert_kind_of Float, value
    end

    test "#sqlite_contains keeps regular string as string" do
      query, path, value = JsonQuery.sqlite_contains(:tags, "name", "hello")

      assert_equal "hello", value
      assert_kind_of String, value
    end

    test "#postgresql_contains with key and value" do
      query, json = JsonQuery.postgresql_contains(:tags, "environment", "production")

      assert_equal "tags @> ?", query
      assert_equal({ "environment" => "production" }.to_json, json)
    end

    test "#postgresql_contains with key only" do
      condition = JsonQuery.postgresql_contains(:tags, "environment", nil)

      assert_includes Entry.where(*condition).to_sql, "(tags ? 'environment')"
    end

    test "#mysql_contains with key and value" do
      query, json, path = JsonQuery.mysql_contains(:tags, "environment", "production")

      assert_equal "JSON_CONTAINS(tags, ?, ?)", query
      assert_equal "\"production\"", json
      assert_equal "$.environment", path
    end

    test "#mysql_contains with key only" do
      query, path = JsonQuery.mysql_contains(:tags, "environment", nil)

      assert_equal "JSON_CONTAINS_PATH(tags, 'one', ?)", query
      assert_equal "$.environment", path
    end

    test "#fallback_contains with key and value" do
      query, pattern = JsonQuery.fallback_contains(:tags, "environment", "production")

      assert_equal "CAST(tags AS TEXT) LIKE ?", query
      assert_match(/"environment":/, pattern)
      assert_match(/"production"/, pattern)
    end

    test "fallback_contains with key only" do
      query, pattern = JsonQuery.fallback_contains(:tags, "environment", nil)

      assert_equal "CAST(tags AS TEXT) LIKE ?", query
      assert_match(/"environment"/, pattern)
    end

    test "#fallback_contains escapes special characters in key" do
      query, pattern = JsonQuery.fallback_contains(:tags, "some_key%", "value")

      assert_match(/some\\_key\\%/, pattern)
    end

    test "#extract_path uses the syntax of the test database" do
      result = JsonQuery.extract_path(:context, "request_id")

      assert_equal EXTRACT_REQUEST_ID.fetch(JsonQuery.detect_adapter), result
    end

    test "#extract_path rejects keys that could break out of the SQL string" do
      ["x') OR 1=1 --", "a'b", "a b", ""].each do |key|
        assert_raises(ArgumentError) { JsonQuery.extract_path(:context, key) }
      end
    end

    test "#extract_path_not_null uses the syntax of the test database" do
      result = JsonQuery.extract_path_not_null(:context, "request_id")

      assert_equal "#{EXTRACT_REQUEST_ID.fetch(JsonQuery.detect_adapter)} IS NOT NULL", result
    end

    test "#normalize_sqlite_value with non-string returns unchanged" do
      assert_equal 42, JsonQuery.normalize_sqlite_value(42)
      assert_equal 3.14, JsonQuery.normalize_sqlite_value(3.14)
      assert_nil JsonQuery.normalize_sqlite_value(nil)
    end

    test "#normalize_sqlite_value with integer string" do
      assert_equal 123, JsonQuery.normalize_sqlite_value("123")
      assert_equal(-456, JsonQuery.normalize_sqlite_value("-456"))
      assert_equal 0, JsonQuery.normalize_sqlite_value("0")
    end

    test "#normalize_sqlite_value with float string" do
      assert_in_delta 123.45, JsonQuery.normalize_sqlite_value("123.45"), 0.001
      assert_in_delta(-0.5, JsonQuery.normalize_sqlite_value("-0.5"), 0.001)
    end

    test "#normalize_sqlite_value with regular string" do
      assert_equal "hello", JsonQuery.normalize_sqlite_value("hello")
      assert_equal "123abc", JsonQuery.normalize_sqlite_value("123abc")
      assert_equal "", JsonQuery.normalize_sqlite_value("")
    end

    test "INTEGER_PATTERN matches valid integers" do
      assert_match JsonQuery::INTEGER_PATTERN, "123"
      assert_match JsonQuery::INTEGER_PATTERN, "-456"
      assert_match JsonQuery::INTEGER_PATTERN, "0"
    end

    test "INTEGER_PATTERN does not match non-integers" do
      refute_match JsonQuery::INTEGER_PATTERN, "123.45"
      refute_match JsonQuery::INTEGER_PATTERN, "abc"
      refute_match JsonQuery::INTEGER_PATTERN, "12.0"
    end

    test "FLOAT_PATTERN matches valid floats" do
      assert_match JsonQuery::FLOAT_PATTERN, "123.45"
      assert_match JsonQuery::FLOAT_PATTERN, "-0.5"
      assert_match JsonQuery::FLOAT_PATTERN, "123"
      assert_match JsonQuery::FLOAT_PATTERN, "0.0"
    end

    test "FLOAT_PATTERN does not match non-floats" do
      refute_match JsonQuery::FLOAT_PATTERN, "abc"
      refute_match JsonQuery::FLOAT_PATTERN, "1.2.3"
      refute_match JsonQuery::FLOAT_PATTERN, "12a"
    end

    test "#contains works with an actual query" do
      Entry.delete_all

      Entry.create!(
        name: "test.event",
        tags: { environment: "production", count: 5 },
        occurred_at: Time.current
      )
      Entry.create!(
        name: "other.event",
        tags: { environment: "staging" },
        occurred_at: Time.current
      )

      query, *params = JsonQuery.contains(:tags, "environment", "production")
      results = Entry.where(query, *params)

      assert_equal 1, results.count
      assert_equal "test.event", results.first.name
    end

    test "#contains with key only works with an actual query" do
      Entry.delete_all

      Entry.create!(
        name: "with.tag",
        tags: { environment: "production" },
        occurred_at: Time.current
      )
      Entry.create!(
        name: "without.tag",
        tags: {},
        occurred_at: Time.current
      )

      query, *params = JsonQuery.contains(:tags, "environment")
      results = Entry.where(query, *params)

      assert_equal 1, results.count
      assert_equal "with.tag", results.first.name
    end

    test "#extract_path works in SELECT with an actual query" do
      Entry.delete_all

      Entry.create!(
        name: "test.event",
        context: { request_id: "abc-123" },
        occurred_at: Time.current
      )

      json_path = JsonQuery.extract_path(:context, "request_id")
      result = Entry.pluck(Arel.sql(json_path)).first

      assert_equal "abc-123", result
    end

    test "#contains dispatches to the method for the test database" do
      expected = JsonQuery.public_send("#{JsonQuery.detect_adapter}_contains", :tags, "key", "value")

      assert_equal expected, JsonQuery.contains(:tags, "key", "value")
    end
  end
end
