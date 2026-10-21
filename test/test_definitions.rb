# frozen_string_literal: true

require "test_helper"
require "tmpdir"

require_relative "../.github/scripts/definitions"

# The definitions in rubies/ are append-only, so these use fixtures rather than
# the real directory: adding a definition should never change what an existing
# test asserts.
class TestDefinitions < Minitest::Test
  def test_parse_returns_nil_for_names_that_are_not_versioned_cruby
    assert_nil(Definitions.parse("truffleruby-24.0.0"))
    assert_nil(Definitions.parse("truffleruby+graalvm-dev"))
    assert_nil(Definitions.parse("README"))
    assert_nil(Definitions.parse("3.4.7"))
  end

  def test_parse_splits_name_into_flavor_and_sort_key
    definition = Definitions.parse("3.2.2-pshopify14")

    assert_equal("3.2.2-pshopify14", definition.name)
    assert_equal("pshopify", definition.flavor)
    assert_equal([[3, 2, 2], [2, 0], 14], definition.sort_key)
  end

  def test_parse_handles_a_flavor_without_a_revision
    assert_equal([[4, 0, 1], [2, 0], 0], Definitions.parse("4.0.1-modgc").sort_key)
  end

  def test_revisions_sort_numerically_rather_than_as_strings
    assert_sorted(["3.2.2-pshopify9", "3.2.2-pshopify10"])
  end

  def test_previews_and_rcs_sort_below_the_release_they_lead_to
    assert_sorted([
      "3.3.0-preview1-pshopify1",
      "3.3.0-preview2-pshopify1",
      "3.3.0-rc1-pshopify1",
      "3.3.0-pshopify1",
    ])
  end

  def test_source_reads_the_repo_and_ref_from_install_git
    with_definitions("4.0.7-pshopify1" => patched("v4.0.7-pshopify1")) do |dir|
      source = Definitions.source(File.join(dir, "4.0.7-pshopify1"))

      assert_equal("ruby-4.0.7-pshopify1", source.package)
      assert_equal("Shopify/ruby", source.repo)
      assert_equal("v4.0.7-pshopify1", source.ref)
    end
  end

  def test_source_is_nil_for_a_definition_that_builds_from_a_tarball
    with_definitions("4.0.7-pshopify1" => released) do |dir|
      assert_nil(Definitions.source(File.join(dir, "4.0.7-pshopify1")))
    end
  end

  def test_previous_prefers_the_previous_revision_of_the_same_version
    definitions = {
      "4.0.6-pshopify2" => patched("v4.0.6-pshopify2"),
      "4.0.7-pshopify1" => patched("v4.0.7-pshopify1"),
      "4.0.7-pshopify2" => patched("v4.0.7-pshopify2"),
    }

    with_definitions(definitions) do |dir|
      assert_equal("4.0.7-pshopify1", Definitions.previous("4.0.7-pshopify2", dir))
    end
  end

  def test_previous_falls_back_to_the_upstream_release_being_patched
    definitions = {
      "4.0.6-pshopify2" => patched("v4.0.6-pshopify2"),
      "4.0.7-pshopify1" => patched("v4.0.7-pshopify1"),
    }

    with_definitions(definitions) do |dir|
      assert_equal("4.0.7", Definitions.previous("4.0.7-pshopify1", dir))
    end
  end

  # The patch set is empty, so the upstream release would compare a ruby against
  # itself.
  def test_previous_skips_the_upstream_release_when_the_ref_is_the_upstream_tag
    definitions = {
      "4.0.6-pshopify2" => patched("v4.0.6-pshopify2"),
      "4.0.7-pshopify1" => patched("v4.0.7"),
    }

    with_definitions(definitions) do |dir|
      assert_equal("4.0.6-pshopify2", Definitions.previous("4.0.7-pshopify1", dir))
    end
  end

  # Upstream does not tag a preview as "v3.3.0", so there is no release to
  # compare against.
  def test_previous_skips_the_upstream_release_for_a_preview
    definitions = {
      "3.2.2-pshopify20" => patched("v3.2.2-pshopify20"),
      "3.3.0-preview2-pshopify1" => patched("v3.3.0-preview2-pshopify1"),
    }

    with_definitions(definitions) do |dir|
      assert_equal("3.2.2-pshopify20", Definitions.previous("3.3.0-preview2-pshopify1", dir))
    end
  end

  # The modgc definitions build from an upstream tag, so the upstream release
  # case does not apply to them and they fall through to the same flavor.
  def test_previous_only_considers_the_same_flavor
    definitions = {
      "3.4.7-modgc" => patched("v3.4.7"),
      "4.0.6-pshopify2" => patched("v4.0.6-pshopify2"),
      "4.0.1-modgc" => patched("v4.0.1"),
    }

    with_definitions(definitions) do |dir|
      assert_equal("3.4.7-modgc", Definitions.previous("4.0.1-modgc", dir))
    end
  end

  def test_previous_is_nil_when_there_is_nothing_earlier
    with_definitions("4.0.7-pshopify1" => patched("v4.0.7")) do |dir|
      assert_nil(Definitions.previous("4.0.7-pshopify1", dir))
    end
  end

  def test_previous_honors_a_baseline_override
    definitions = {
      "4.0.7-pshopify1" => patched("v4.0.7-pshopify1"),
      "4.0.7-pshopify2" => "# baseline: 4.0.7\n#{patched("v4.0.7-pshopify2")}",
    }

    with_definitions(definitions) do |dir|
      assert_equal("4.0.7", Definitions.previous("4.0.7-pshopify2", dir))
    end
  end

  def test_previous_is_nil_for_a_baseline_override_of_none
    definitions = {
      "4.0.7-pshopify1" => patched("v4.0.7-pshopify1"),
      "4.0.7-pshopify2" => "# baseline: none\n#{patched("v4.0.7-pshopify2")}",
    }

    with_definitions(definitions) do |dir|
      assert_nil(Definitions.previous("4.0.7-pshopify2", dir))
    end
  end

  def test_earlier_is_newest_first_and_excludes_the_definition_itself
    definitions = {
      "4.0.6-pshopify2" => patched("v4.0.6-pshopify2"),
      "4.0.7-pshopify1" => patched("v4.0.7-pshopify1"),
      "4.0.7-pshopify2" => patched("v4.0.7-pshopify2"),
      "truffleruby-24.0.0" => "# not a cruby definition\n",
    }

    with_definitions(definitions) do |dir|
      earlier = Definitions.earlier("4.0.7-pshopify2", dir)

      assert_equal(["4.0.7-pshopify1", "4.0.6-pshopify2"], earlier.map(&:name))
    end
  end

  private

  def sort_key(name)
    Definitions.parse(name).sort_key
  end

  # Array#<=> rather than Array#<, which does not exist.
  def assert_sorted(names)
    names.each_cons(2) do |lower, higher|
      assert_equal(-1, sort_key(lower) <=> sort_key(higher), "expected #{lower} to sort below #{higher}")
    end
  end

  def patched(ref)
    %(install_git "ruby-#{ref.delete_prefix("v")}" "https://github.com/Shopify/ruby.git" "#{ref}" standard\n)
  end

  def released
    %(install_package "ruby-4.0.7" "https://cache.ruby-lang.org/pub/ruby/4.0/ruby-4.0.7.tar.gz#abc" standard\n)
  end

  def with_definitions(definitions)
    Dir.mktmpdir do |dir|
      definitions.each { |name, body| File.write(File.join(dir, name), body) }
      yield dir
    end
  end
end
