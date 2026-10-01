module RailsEventViewer
  module Buffers
    class Memory
      include Buffer

      def initialize
        @queue = Queue.new
      end

      def push(entry)
        @queue << entry
        @queue.size
      end

      def drain(limit)
        entries = []
        limit.times { entries << @queue.pop(true) }
        entries
      rescue ThreadError
        entries
      end

      def revert(entries)
        entries.each { |entry| @queue << entry }
      end

      def size
        @queue.size
      end

      def after_fork
        @queue = Queue.new
      end
    end
  end
end
