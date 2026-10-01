module RailsEventViewer
  module Buffer
    def push(entry)
      raise NotImplementedError, "#{self.class} must implement #push"
    end

    def drain(limit)
      raise NotImplementedError, "#{self.class} must implement #drain"
    end

    def commit(entries)
    end

    def revert(entries)
    end

    def dead(entries)
      commit(entries)
    end

    def size
      raise NotImplementedError, "#{self.class} must implement #size"
    end

    def after_fork
    end
  end
end
