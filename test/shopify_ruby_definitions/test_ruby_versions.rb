# typed: true
# frozen_string_literal: true

require "test_helper"

module ShopifyRubyDefinitions
  class TestRubyVersions < Minitest::Test
    def test_ALL_VERSIONS
      assert_operator(RubyVersions::ALL_VERSIONS.length, :>, 0)

      truffleruby_versions, cruby_versions = RubyVersions::ALL_VERSIONS.partition { |v| v.start_with?("truffleruby") }

      cruby_versions.each do |v|
        assert_match(
          %r{
            \A
            (?:yjit\-)?
            \d+\.\d+\.\d+ # match version (e.g. 3.4.0)
            (?:\-preview\d*)? # match -preview optionally
                              # preview tag must be before the pshopify tag
            (?:\-pshopify\d*)? # match -pshopify optionally
            \z
          }x,
          v,
        )
      end

      truffleruby_versions.each do |v|
        next if v.include?("integration")

        assert_match(/\Atruffleruby(?:\+graalvm)?(?:-gftc)?(\-\d+\.\d+\.\d+|-dev)(?:\-ce)?\z/, v)
      end
    end

    def test_version_overrides
      assert_equal("3.0.2-pshopify3", ShopifyRubyDefinitions.version_overrides["3.0.2"])
    end

    def test_resolve_version
      assert_equal("3.0.2-pshopify3", ShopifyRubyDefinitions.resolve_version("3.0"))
    end

    def test_resolve_preview_version
      with_versions(["3.3.0-preview2-pshopify1", "3.3.0-pshopify1"]) do
        assert_equal("3.3.0-preview2-pshopify1", ShopifyRubyDefinitions.resolve_version("3.3.0-preview2"))
        assert_equal("3.3.0-pshopify1", ShopifyRubyDefinitions.resolve_version("3.3"))
      end
    end

    private

    def with_versions(new_versions)
      old_versions = RubyVersions::ALL_VERSIONS
      old_version_overrides = RubyVersions::VERSION_OVERRIDES
      RubyVersions.send(:remove_const, :ALL_VERSIONS)
      RubyVersions.const_set(:ALL_VERSIONS, new_versions)
      RubyVersions.send(:remove_const, :VERSION_OVERRIDES)
      RubyVersions.const_set(:VERSION_OVERRIDES, RubyVersions.build_version_overrides(new_versions))
      yield
    ensure
      RubyVersions.send(:remove_const, :ALL_VERSIONS)
      RubyVersions.const_set(:ALL_VERSIONS, old_versions)
      RubyVersions.send(:remove_const, :VERSION_OVERRIDES)
      RubyVersions.const_set(:VERSION_OVERRIDES, old_version_overrides)
    end
  end
end
