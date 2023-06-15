# shopify-ruby-definitions

This repository contains [ruby-build](https://github.com/rbenv/ruby-build/) definitions of Rubies we use at Shopify. These builds are generally API complient with release Rubies, but with additional backports for bugfixes and performance.

## Quick start

1. Install ruby-build by [following the instructions](https://github.com/rbenv/ruby-build/#installation).
1. Install the gem:
    ```
    $ gem install shopify-ruby-definitions
    ```
1. Acquire the specific Ruby version of the Ruby version you want to install. Ruby 3.2 is used as an example here:
    ```
    $ export RUBY_VERSION=`ruby -rshopify_ruby_definitions -e 'puts ShopifyRubyDefinitions.resolve_version("3.2")'`
    ```
1. Set the definitions path for ruby-build:
    ```
    $ export RUBY_BUILD_DEFINITIONS=`ruby -rshopify_ruby_definitions -e 'puts ShopifyRubyDefinitions::RubyVersions::VERSIONS_DIRECTORY'`
    ```
1. Install the Ruby version using ruby-build:
    ```
    ruby-build $RUBY_VERSION
    ```
