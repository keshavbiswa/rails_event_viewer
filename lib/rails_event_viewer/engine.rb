module RailsEventViewer
  class Engine < ::Rails::Engine
    isolate_namespace RailsEventViewer

    initializer "rails_event_viewer.middleware" do |app|
      if app.config.api_only
        config.middleware.use ActionDispatch::Flash
        config.middleware.use Rack::MethodOverride
      end
    end

    initializer "rails_event_viewer.assets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.precompile += %w[
          rails_event_viewer/application.css
          rails_event_viewer/application.js
          rails_event_viewer/chart.umd.min.js
          rails_event_viewer/chartjs-adapter-date-fns.bundle.min.js
          rails_event_viewer/chartkick.min.js
        ]
      end
    end

    config.after_initialize do
      RailsEventViewer.subscribe!
      at_exit { RailsEventViewer.shutdown! }
    end
  end
end
