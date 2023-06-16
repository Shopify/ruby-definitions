# shopify-ruby-definitions

This repository contains [ruby-build](https://github.com/rbenv/ruby-build/) definitions of Rubies we use at Shopify.
These builds are API complient with release Rubies, but with additional backports for bugfixes and performance.

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
