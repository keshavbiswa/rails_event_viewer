require "rails/generators"
require "rails/generators/active_record"

module RailsEventViewer
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Installs RailsEventViewer: creates migration, initializer, and mounts the engine"

      class_option :storage_adapter, type: :string, default: "active_record",
        desc: "Storage adapter to use (active_record, redis, memory)"

      class_option :skip_migration, type: :boolean, default: false,
        desc: "Skip creating the migration file"

      class_option :skip_initializer, type: :boolean, default: false,
        desc: "Skip creating the initializer file"

      class_option :skip_routes, type: :boolean, default: false,
        desc: "Skip mounting the engine in routes"

      def create_migration_file
        return if options[:skip_migration]
        return if options[:storage_adapter] != "active_record"

        migration_template(
          "create_rails_event_viewer_entries.rb.erb",
          "db/migrate/create_rails_event_viewer_entries.rb"
        )
      end

      def create_initializer
        return if options[:skip_initializer]

        template(
          "initializer.rb.erb",
          "config/initializers/rails_event_viewer.rb"
        )
      end

      def mount_engine
        return if options[:skip_routes]

        route_line = 'mount RailsEventViewer::Engine, at: "/events"'

        routes_file = File.join(destination_root, "config/routes.rb")
        if File.exist?(routes_file) && File.read(routes_file).include?("RailsEventViewer::Engine")
          say_status :skip, "Engine already mounted in routes", :yellow
          return
        end

        route route_line
      end

      def show_post_install_message
        say ""
        say "RailsEventViewer has been installed!", :green
        say ""
        say "Next steps:"

        if options[:storage_adapter] == "active_record" && !options[:skip_migration]
          say "  1. Run migrations: rails db:migrate"
        end

        say "  2. Configure authentication in config/initializers/rails_event_viewer.rb"
        say "  3. Visit /events to view your events"
        say ""
        say "For more information, visit: https://github.com/keshavbiswa/rails_event_viewer"
        say ""
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end

      def storage_adapter
        options[:storage_adapter]
      end
    end
  end
end
