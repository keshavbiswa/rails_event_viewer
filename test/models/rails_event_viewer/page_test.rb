require "test_helper"

module RailsEventViewer
  class PageTest < ActiveSupport::TestCase
    test "first page of several" do
      page = Page.new(count: 60, per_page: 25, page: 1)

      assert_equal 3, page.pages
      assert_equal 0, page.offset
      assert_equal [1, 25], [page.from, page.to]
      assert_nil page.previous
      assert_equal 2, page.next
    end

    test "last partial page" do
      page = Page.new(count: 60, per_page: 25, page: 3)

      assert_equal 50, page.offset
      assert_equal [51, 60], [page.from, page.to]
      assert_equal 2, page.previous
      assert_nil page.next
    end

    test "no results is a single empty page" do
      page = Page.new(count: 0, per_page: 25, page: 1)

      assert_equal 1, page.pages
      assert_equal [0, 0], [page.from, page.to]
      assert_nil page.previous
      assert_nil page.next
    end

    test "out of range and junk page params are clamped" do
      assert_equal 3, Page.new(count: 60, per_page: 25, page: "99").page
      assert_equal 1, Page.new(count: 60, per_page: 25, page: "-4").page
      assert_equal 1, Page.new(count: 60, per_page: 25, page: "abc").page
      assert_equal 1, Page.new(count: 60, per_page: 25, page: nil).page
    end

    test "count divisible by per_page ends exactly on the last page" do
      page = Page.new(count: 50, per_page: 25, page: 2)

      assert_equal 2, page.pages
      assert_equal [26, 50], [page.from, page.to]
      assert_nil page.next
    end
  end
end
