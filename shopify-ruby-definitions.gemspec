# frozen_string_literal: true

require_relative "lib/shopify_ruby_definitions/version"

Gem::Specification.new do |spec|
  spec.name = "shopify-ruby-definitions"
  spec.version = ShopifyRubyDefinitions::VERSION
  spec.authors = ["Peter Zhu"]
  spec.email = ["ruby@shopify.com"]

  spec.summary = "Ruby builds used at Shopify."
  spec.homepage = "https://github.com/Shopify/ruby-definitions"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Shopify/ruby-definitions"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    %x(git ls-files -z).split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency("rubocop-minitest")
  spec.add_development_dependency("rubocop-shopify")
end
