# shopify-ruby-definitions

This repository contains [ruby-build](https://github.com/rbenv/ruby-build/) definitions of Rubies we use at Shopify.
These builds are API compliant with release Rubies, but with additional backports for bugfixes and performance.

## rbenv integration

If you use `rbenv`, you can add the custom rubies with:

```bash
$ gem install shopify-ruby-definitions
$ eval "$(shopify-ruby env)"
```

## standalone ruby-build

If you are using another ruby version manager or no manager at all:

1. Install ruby-build by [following the instructions](https://github.com/rbenv/ruby-build/#installation).

2. Install the gem:
    ```bash
    $ gem install shopify-ruby-definitions
    ```

3. List the custom Ruby versions available:
    ```bash
    $ shopify-ruby versions
    3.0.0-pshopify9
    3.0.1-pshopify2
    3.0.2-pshopify3
    3.1.0-pshopify1
    3.1.1-pshopify2
    3.1.2-pshopify2
    3.1.3-pshopify1
    3.1.4-pshopify1
    3.2.0-pshopify2
    3.2.1-pshopify5
    3.2.2-pshopify3
    3.2.2-pshopify4
    ```

4. Install the Ruby version you want, [options are the same than regular `ruby-build`](https://github.com/rbenv/ruby-build#advanced-usage):
    ```bash
    $ shopify-ruby build 3.2.2-pshopify4 ~/.rubies/versions/3.2.2
    ```

5. Resolve a less specific version to one of these definitions
    ```bash
    $ shopify-ruby resolve 3.2
    $ shopify-ruby resolve 3.2
    3.2.2-pshopify4
    ```

## Creating a new pshopify definition

A rake task automates the creation of new pshopify definition files:

```bash
$ rake pshopify:create              # uses latest stable Ruby from ruby-build
$ rake "pshopify:create[4.0.2]"     # uses a specific version
```

This will:
- Default to the latest stable CRuby version if none is specified
- Determine the next pshopify number (e.g. `4.0.2-pshopify2` if `4.0.2-pshopify1` already exists)
- Verify the branch exists on [Shopify/ruby](https://github.com/Shopify/ruby)
- Read the openssl line from the upstream ruby-build definition
- Fetch the changelog from the GitHub compare API
- Generate the definition file in `rubies/`

### Prerequisites

- The [`gh` CLI](https://cli.github.com/) must be installed and authenticated
- A local [ruby-build](https://github.com/rbenv/ruby-build) checkout must be available. The task searches for sibling directories matching `*ruby-build`, or you can set `RUBY_BUILD_PATH`:

```bash
$ RUBY_BUILD_PATH=~/src/ruby-build rake "pshopify:create[4.0.2]"
```
