# typed: strong
# frozen_string_literal: true

module ShopifyRubyDefinitions
  module RubyBuild
    extend T::Sig

    RUBY_BUILD_DIRECTORY = T.let(File.expand_path("../../../vendor/ruby-build", __FILE__), String)
  end
end
