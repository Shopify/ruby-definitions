# typed: true
# frozen_string_literal: true

require "test_helper"

module ShopifyRubyDefinitions
  class TestRubyVersions < Minitest::Test
    def test_ALL_VERSIONS
      assert_operator(RubyVersions::ALL_VERSIONS.length, :>, 0)

      RubyVersions::ALL_VERSIONS.each do |v|
        assert_match(/\A(?:yjit\-)?\d+\.\d+\.\d+(?:\-[\w\-]+)?\z/, v)
      end
    end

    def test_version_overrides
      assert_equal("3.0.2-pshopify3", ShopifyRubyDefinitions.version_overrides["3.0.2"])
    end

    def test_resolve_version
      assert_equal("3.0.2-pshopify3", ShopifyRubyDefinitions.resolve_version("3.0"))
    end
  end
end
