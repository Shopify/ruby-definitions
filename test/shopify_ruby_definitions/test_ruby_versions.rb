# typed: true
# frozen_string_literal: true

require "test_helper"

module ShopifyRubyDefinitions
  class TestRubyVersions < Minitest::Test
    def test_ALL_VERSIONS
      assert_operator(RubyVersions::ALL_VERSIONS.length, :>, 0)

      valid_pattern = Regexp.union(
        /\A(?:yjit\-)?\d+\.\d+\.\d+(?:\-[\w\-]+)?\z/, # MRI
        /\Atruffleruby\-(dev|[\d\.]+(?:-preview\d+)?)\z/, # TruffleRuby
      )

      RubyVersions::ALL_VERSIONS.each do |v|
        assert_match(valid_pattern, v)
      end
    end

    def test_version_overrides
      assert_match(/\A3.2.2-pshopify\d\z/, ShopifyRubyDefinitions.version_overrides["3.2.2"])
    end

    def test_resolve_version
      assert_equal("2.6.10", ShopifyRubyDefinitions.resolve_version("2.6"))
      assert_equal("3.3.0-dev", ShopifyRubyDefinitions.resolve_version("ruby-head"))
    end
  end
end
