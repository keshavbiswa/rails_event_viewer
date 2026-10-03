require_relative "lib/rails_event_viewer/version"

Gem::Specification.new do |spec|
  spec.name        = "rails_event_viewer"
  spec.version     = RailsEventViewer::VERSION
  spec.authors     = ["Keshav Biswa"]
  spec.email       = ["keshavbiswa21@gmail.com"]
  spec.homepage    = "https://github.com/keshavbiswa/rails_event_viewer"
  spec.summary     = "A Rails engine to view structured events from Rails Event Reporter"
  spec.description = "RailsEventViewer provides a web interface to browse, search, and analyze structured events emitted via Rails.event. Features include event listing, filtering, search, and analytics dashboards."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "CHANGELOG.md"]
  end

  spec.required_ruby_version = ">= 3.3"

  spec.add_dependency "rails", ">= 8.1.0"
  spec.add_dependency "chartkick", ">= 5.0", "< 6"
  spec.add_dependency "groupdate", ">= 6.0"
end
