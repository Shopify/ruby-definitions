# frozen_string_literal: true

module ShopifyRubyDefinitions
  module RubyVersions
    class << self
      def build_version_overrides(all_versions)
        all_versions.sort_by do |version|
          version.scan(/\d+/).map(&:to_i)
        end.to_h do |version|
          [version.partition("-pshopify").first, version]
        end.freeze
      end
    end

    VERSIONS_DIRECTORY = File.expand_path("../../../rubies", __FILE__)
    ALL_VERSIONS = Dir["#{VERSIONS_DIRECTORY}/*"].map { |f| File.basename(f) }
    VERSION_OVERRIDES = build_version_overrides(ALL_VERSIONS)

    def version_overrides
      VERSION_OVERRIDES
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
