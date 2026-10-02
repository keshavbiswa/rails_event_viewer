# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

module RailsEventViewer
  class JsonQueryTest < ActiveSupport::TestCase
    CONTEXTS = {
      "integer" => { user_id: 42 },
      "string" => { user_id: "42" },
      "leading_zero" => { code: "007" },
      "boolean" => { flag: true },
      "hyphen" => { "trace-id" => "t1" },
      "dotted" => { "a.b" => "flat" },
      "json_null" => { k: nil },
      "blank" => { request_id: "" }
    }.freeze

    setup do
      CONTEXTS.each { |name, context| Entry.create!(name: name, context: context, occurred_at: Time.current) }
    end

    test "#detect_adapter matches the test database" do
      adapter_name = ActiveRecord::Base.connection.adapter_name.downcase
      expected = { "sqlite" => :sqlite, "postgresql" => :postgresql, "trilogy" => :mysql }

      assert_equal expected.fetch(adapter_name), JsonQuery.detect_adapter
    end

    test "#fallback_contains with key and value" do
      query, pattern = JsonQuery.fallback_contains(:tags, "environment", "production")

      assert_equal "CAST(tags AS TEXT) LIKE ?", query
      assert_match(/"environment":/, pattern)
      assert_match(/"production"/, pattern)
    end

    test "#fallback_contains with key only" do
      query, pattern = JsonQuery.fallback_contains(:tags, "environment", nil)

      assert_equal "CAST(tags AS TEXT) LIKE ?", query
      assert_match(/"environment"/, pattern)
    end

    test "#fallback_contains escapes special characters in key" do
      _query, pattern = JsonQuery.fallback_contains(:tags, "some_key%", "value")

      assert_match(/some\\_key\\%/, pattern)
    end

    test "#extract_path returns the value as text" do
      assert_equal %w[42 42], extracted("user_id")
      assert_equal %w[007], extracted("code")
      assert_equal %w[true], extracted("flag")
      assert_equal %w[t1], extracted("trace-id")
      assert_equal %w[flat], extracted("a.b")
    end

    test "#extract_path rejects keys that could break out of the SQL string" do
      ["x') OR 1=1 --", "a'b", "a b", 'a"b', ""].each do |key|
        assert_raises(ArgumentError) { JsonQuery.extract_path(:context, key) }
      end
    end

    test "#extract_path_present skips missing keys, JSON null and blank values" do
      assert_equal %w[integer string], present("user_id")
      assert_equal [], present("k")
      assert_equal [], present("request_id")
      assert_equal [], present("missing")
    end

    test "MySQL older than 8.0.17 and MariaDB fall back to a collation they have" do
      skip "MySQL only" unless JsonQuery.detect_adapter == :mysql

      connection = ActiveRecord::Base.connection
      version = ->(string) { ActiveRecord::ConnectionAdapters::AbstractAdapter::Version.new(string) }

      assert_equal "utf8mb4_0900_bin", connection.stub(:database_version, version.call("8.0.17")) { JsonQuery.mysql_collation }
      assert_equal "utf8mb4_bin", connection.stub(:database_version, version.call("8.0.16")) { JsonQuery.mysql_collation }
      assert_equal "utf8mb4_bin", connection.stub(:database_version, version.call("5.7.44")) { JsonQuery.mysql_collation }
      assert_equal "utf8mb4_bin", connection.stub(:mariadb?, true) { JsonQuery.mysql_collation }
    end

    test "filters and groups work with the fallback MySQL collation" do
      skip "MySQL only" unless JsonQuery.detect_adapter == :mysql

      JsonQuery.stub(:mysql_collation, "utf8mb4_bin") do
        assert_equal %w[integer string], Entry.where(*JsonQuery.contains(:context, "user_id", "42")).order(:name).pluck(:name)
        assert_equal %w[42 42], extracted("user_id")
        assert_equal [], present("k")
      end
    end

    private

    def extracted(key)
      Entry.where(JsonQuery.extract_path_present(:context, key)).pluck(Arel.sql(JsonQuery.extract_path(:context, key))).sort
    end

    def present(key)
      Entry.where(JsonQuery.extract_path_present(:context, key)).order(:name).pluck(:name)
    end
  end
end
