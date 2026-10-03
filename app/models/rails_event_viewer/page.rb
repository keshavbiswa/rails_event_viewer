module RailsEventViewer
  class Page
    attr_reader :page, :per_page, :count

    def initialize(count:, per_page:, page:)
      @count = count
      @per_page = per_page
      @page = page.to_i.clamp(1, pages)
    end

    def pages
      [(count.to_f / per_page).ceil, 1].max
    end

    def offset
      (page - 1) * per_page
    end

    def from
      count.zero? ? 0 : offset + 1
    end

    def to
      [offset + per_page, count].min
    end

    def previous
      page - 1 if page > 1
    end

    def next
      page + 1 if page < pages
    end

    def window
      numbers = [1, *(page - 2..page + 2), pages].select { |number| number.between?(1, pages) }.uniq.sort

      numbers.each_with_object([]) do |number, items|
        items << :gap if items.any? && number > items.last + 1
        items << number
      end
    end
  end
end
