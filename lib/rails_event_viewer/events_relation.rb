module RailsEventViewer
  class EventsRelation
    include Enumerable

    attr_reader :names, :tags, :contexts, :query, :since_time, :until_time
    attr_reader :limit_value, :offset_value

    def initialize(adapter: RailsEventViewer.adapter)
      @adapter = adapter
      @names = []
      @tags = {}
      @contexts = {}
      @query = nil
      @since_time = nil
      @until_time = nil
      @limit_value = RailsEventViewer.per_page
      @offset_value = 0
    end

    def with_name(*event_names)
      event_names = event_names.flatten.compact
      return self if event_names.empty?

      clone_with { |rel| rel.names.concat(event_names) }
    end

    def with_tag(key, value = nil)
      return self if key.blank?

      clone_with { |rel| rel.tags[key.to_s] = value }
    end

    def with_context(key, value = nil)
      return self if key.blank?

      clone_with { |rel| rel.contexts[key.to_s] = value }
    end

    def search(term)
      return self if term.blank?

      clone_with { |rel| rel.query = term.to_s }
    end

    def since(time)
      return self if time.nil?

      clone_with { |rel| rel.since_time = time }
    end

    def until(time)
      return self if time.nil?

      clone_with { |rel| rel.until_time = time }
    end

    def limit(value)
      clone_with { |rel| rel.limit_value = value.to_i }
    end

    def offset(value)
      clone_with { |rel| rel.offset_value = value.to_i }
    end

    def each(&block)
      return to_enum(:each) unless block_given?

      @adapter.fetch_events(self).each(&block)
    end

    def count
      @adapter.count_events(self)
    end

    alias_method :size, :count
    alias_method :length, :count

    def to_a
      @adapter.fetch_events(self).to_a
    end

    def any?
      count > 0
    end

    def empty?
      count == 0
    end

    alias_method :none?, :empty?

    def first
      limit(1).to_a.first
    end

    def last
      return @adapter.fetch_last(self) if @adapter.respond_to?(:fetch_last)

      n = count
      offset(n - 1).first if n.positive?
    end

    def filtered?
      names.any? || tags.any? || contexts.any? || query.present? || since_time.present? || until_time.present?
    end

    def inspect
      "#<#{self.class.name} names=#{names.inspect} tags=#{tags.inspect} " \
        "contexts=#{contexts.inspect} query=#{query.inspect} " \
        "since=#{since_time.inspect} until=#{until_time.inspect} " \
        "limit=#{limit_value} offset=#{offset_value}>"
    end

    private

    def clone_with
      dup.tap do |rel|
        rel.instance_variable_set(:@names, @names.dup)
        rel.instance_variable_set(:@tags, @tags.dup)
        rel.instance_variable_set(:@contexts, @contexts.dup)
        yield rel if block_given?
      end
    end

    protected

    attr_writer :names, :tags, :contexts, :query, :since_time, :until_time
    attr_writer :limit_value, :offset_value
  end
end
