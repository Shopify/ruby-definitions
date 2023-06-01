# typed: strong
# frozen_string_literal: true

module ShopifyRubyDefinitions
  module RubyVersions
    extend T::Sig

    VERSIONS_DIRECTORY = T.let(File.join(RubyBuild::RUBY_BUILD_DIRECTORY, "share/ruby-build"), String)
    ALL_VERSIONS = T.let(Dir["#{VERSIONS_DIRECTORY}/*"].map { |f| File.basename(f) }, T::Array[String])

    sig { returns(T::Hash[String, String]) }
    def version_overrides
      {
        "head" => ruby_head_version,
        "ruby-head" => ruby_head_version,
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

    sig { params(version: String).returns(String) }
    def resolve_version(version)
      if version.match?(/\A\d+\.\d+\z/)
        pattern = /\A#{Regexp.escape(version)}\.(\d+)\z/
        versions = ALL_VERSIONS.grep(pattern)
        unless versions.empty?
          version = T.must(versions.max_by { |v| T.must(v.match(pattern))[1].to_i })
        end
      end
      version_overrides.fetch(version, version)
    end

    private

    sig { returns(String) }
    def ruby_head_version
      T.must(ALL_VERSIONS.grep(/\A[\d\.]+-dev\z/).max)
    end
  end
end
