# frozen_string_literal: true

module ShopifyRubyDefinitions
  module RubyVersions
    VERSIONS_DIRECTORY = File.expand_path("../../../rubies", __FILE__)
    ALL_VERSIONS = Dir["#{VERSIONS_DIRECTORY}/*"].map { |f| File.basename(f) }

    def version_overrides
      {
        "3.0.0" => "3.0.0-pshopify9",
        "3.0.1" => "3.0.1-pshopify2",
        "3.0.2" => "3.0.2-pshopify3",
        "3.1.0" => "3.1.0-pshopify1",
        "3.1.1" => "3.1.1-pshopify2",
        "3.1.2" => "3.1.2-pshopify2",
        "3.1.3" => "3.1.3-pshopify1",
        "3.1.4" => "3.1.4-pshopify1",
        "3.2.0" => "3.2.0-pshopify2",
        "3.2.1" => "3.2.1-pshopify5",
        "3.2.2" => "3.2.2-pshopify3",
      }.freeze
    end

    def resolve_version(version)
      if version.match?(/\A\d+\.\d+\z/)
        pattern = /\A#{Regexp.escape(version)}\.(\d+)\z/
        versions = version_overrides.keys.grep(pattern)
        unless versions.empty?
          version = versions.max_by { |v| v.match(pattern)[1].to_i }
        end
      end
      version_overrides.fetch(version, version)
    end
  end
end
