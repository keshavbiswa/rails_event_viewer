# frozen_string_literal: true

require "test_helper"
require "mock_redis"
require "rails_event_viewer/adapters/active_record"
require "rails_event_viewer/adapters/memory"
require "rails_event_viewer/adapters/redis"

module RailsEventViewer
  module FilterParityTests
    CONTEXTS = {
      "integer" => { user_id: 42 },
      "string" => { user_id: "42" },
      "float" => { user_id: 42.0 },
      "leading_zero" => { code: "007" },
      "price" => { price: 1.5 },
      "bool_true" => { flag: true },
      "bool_false" => { flag: false },
      "one" => { flag: 1 },
      "hyphen" => { "trace-id": "t1" },
      "dotted" => { "a.b": "flat" },
      "nested" => { a: { b: "deep" } },
      "space" => { "a b": "x" },
      "quote" => { 'q"k': "v" },
      "json_null" => { k: nil },
      "null_string" => { k: "null" },
      "blank" => { request_id: "" },
      "filled" => { request_id: "abc" },
      "padded" => { request_id: "abc " }
    }.freeze

    def write_contexts
      @adapter.write_events(CONTEXTS.map { |name, context| { name: name, context: context, occurred_at: Time.current } })
    end

    def test_a_value_matches_its_text_form_only
      assert_equal %w[integer string], matching("user_id", "42")
      assert_equal %w[float], matching("user_id", "42.0")
      assert_equal %w[leading_zero], matching("code", "007")
      assert_equal %w[price], matching("price", "1.5")
      assert_equal [], matching("price", "1.50")
      assert_equal [], matching("user_id", "nope")
      assert_equal [], matching("k", "1e999")
    end

    def test_booleans_match_true_and_false_not_one_and_zero
      assert_equal %w[bool_true], matching("flag", "true")
      assert_equal %w[bool_false], matching("flag", "false")
      assert_equal %w[one], matching("flag", "1")
      assert_equal [], matching("flag", "0")
    end

    def test_non_string_values_are_compared_as_text
      assert_equal %w[integer string], matching("user_id", 42)
      assert_equal %w[bool_true], matching("flag", true)
      assert_equal %w[bool_false], matching("flag", false)
    end

    def test_the_key_is_one_flat_key
      assert_equal %w[hyphen], matching("trace-id", "t1")
      assert_equal %w[dotted], matching("a.b", "flat")
      assert_equal %w[space], matching("a b", "x")
      assert_equal %w[quote], matching('q"k', "v")
    end

    def test_a_key_alone_matches_rows_that_have_the_key
      assert_equal %w[float integer string], matching("user_id")
      assert_equal %w[hyphen], matching("trace-id")
      assert_equal %w[dotted], matching("a.b")
      assert_equal %w[json_null null_string], matching("k")
      assert_equal [], matching("missing")
    end

    def test_null_blank_and_trailing_space_are_exact
      assert_equal %w[null_string], matching("k", "null")
      assert_equal %w[blank], matching("request_id", "")
      assert_equal %w[filled], matching("request_id", "abc")
      assert_equal %w[padded], matching("request_id", "abc ")
    end

    def test_keys_that_are_not_valid_json_paths_match_nothing
      ["[", "$", "a'b", "x') OR 1=1 --", "%"].each do |key|
        assert_equal [], matching(key)
        assert_equal [], matching(key, "v")
      end
    end

    def test_groups_use_the_same_text_as_filters
      assert_equal [["42", 2], ["42.0", 1]], groups("user_id")
      assert_equal [["1", 1], ["false", 1], ["true", 1]], groups("flag")
      assert_equal [["null", 1]], groups("k")
      assert_equal [["abc", 1], ["abc ", 1]], groups("request_id")
      assert_equal [["t1", 1]], groups("trace-id")
    end

    def test_every_group_opens_with_the_count_it_lists
      %w[user_id flag k request_id code price].each do |key|
        groups(key).each do |value, count|
          assert_equal count, matching(key, value).size, "#{key}=#{value.inspect}"
        end
      end
    end

    private

    def matching(key, value = nil)
      EventsRelation.new(adapter: @adapter).with_context(key, value).limit(100).to_a.map { |event| event[:name] }.sort
    end

    def groups(key)
      @adapter.group_instances(key, source: :context).map { |group| [group[:value], group[:count]] }.sort
    end
  end

  class ActiveRecordFilterParityTest < ActiveSupport::TestCase
    include FilterParityTests

    setup do
      @adapter = Adapters::ActiveRecord.new
      write_contexts
    end
  end

  class MemoryFilterParityTest < ActiveSupport::TestCase
    include FilterParityTests

    setup do
      @adapter = Adapters::Memory.new
      @adapter.clear!
      write_contexts
    end

    teardown { @adapter.clear! }
  end

  class RedisFilterParityTest < ActiveSupport::TestCase
    include FilterParityTests

    setup do
      redis = MockRedis.new
      @adapter = Adapters::Redis.new(pool: ConnectionPool.new(size: 1) { redis })
      write_contexts
    end
  end
end
