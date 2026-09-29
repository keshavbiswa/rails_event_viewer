module RailsEventViewer
  class PagyCountable
    def initialize(relation)
      @relation = relation
    end

    def count(*)
      @relation.count
    end

    def offset(value)
      OffsetWrapper.new(@relation, value)
    end

    # Intermediate wrapper that captures offset and applies limit
    class OffsetWrapper
      def initialize(relation, offset_value)
        @relation = relation
        @offset_value = offset_value
      end

      def limit(value)
        @relation.offset(@offset_value).limit(value).to_a
      end

      def to_a
        @relation.offset(@offset_value).to_a
      end
    end
  end
end
