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
        app.config.assets.paths << root.join("app/assets/stylesheets")
        app.config.assets.precompile += %w[rails_event_viewer/application.css]
      end
    end

    config.after_initialize do
      RailsEventViewer.subscribe!
      at_exit { RailsEventViewer.shutdown! }
    end
  end
end
