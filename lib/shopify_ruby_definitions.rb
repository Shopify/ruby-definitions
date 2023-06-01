# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require_relative "shopify_ruby_definitions/ruby_build"
require_relative "shopify_ruby_definitions/ruby_versions"
require_relative "shopify_ruby_definitions/version"

module ShopifyRubyDefinitions
  extend RubyVersions
end
