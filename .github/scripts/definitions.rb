#!/usr/bin/env ruby
# frozen_string_literal: true

# Shared parsing and ordering for the ruby-build definitions in rubies/.
module Definitions
  # 3.4.10-pshopify1 / 3.2.2-pshopify14 / 3.4.7-modgc / 3.4.0-preview1-pshopify
  NAME = /\A(?<base>\d+(?:\.\d+)*)(?:-(?<pre>preview\d+|rc\d+))?-(?<flavor>[a-z]+?)(?<rev>\d*)\z/

  # An override for what a definition is compared against, e.g.
  #   # baseline: 3.4.9-pshopify1
  #   # baseline: none
  BASELINE = /^#\s*baseline:\s*(?<name>\S+)/

  # The build line of a definition, whose trailing arguments are build steps:
  #   install_git "ruby-4.0.7-pshopify1" "https://github.com/Shopify/ruby.git" "v4.0.7-pshopify1" autoconf enable_shared standard
  INSTALL_GIT = /^\s*install_git\s+"(?<package>[^"]+)"\s+"(?<url>[^"]+)"\s+"(?<ref>[^"]+)"/

  Definition = Struct.new(:name, :flavor, :sort_key, keyword_init: true)
  Source = Struct.new(:package, :repo, :ref, keyword_init: true)

  # Returns nil for names that are not versioned CRuby definitions, e.g.
  # "truffleruby-24.0.0" or "README".
  def self.parse(name)
    match = NAME.match(name)
    return nil unless match

    pre =
      case match[:pre]
      when nil then [2, 0] # final releases sort above previews/rcs
      when /\Arc(\d+)\z/ then [1, Integer(Regexp.last_match(1))]
      when /\Apreview(\d+)\z/ then [0, Integer(Regexp.last_match(1))]
      end

    Definition.new(
      name: name,
      flavor: match[:flavor],
      sort_key: [match[:base].split(".").map { |part| Integer(part) }, pre, match[:rev].to_i],
    )
  end

  # The git source a definition builds from, or nil if it does not use install_git
  # (released definitions usually build from a tarball instead).
  def self.source(path)
    return nil unless File.exist?(path)

    match = INSTALL_GIT.match(File.read(path))
    return nil unless match

    repo = match[:url][%r{github\.com[:/](.+?)(?:\.git)?\z}, 1]
    return nil unless repo

    Source.new(
      package: match[:package],
      repo: repo,
      # ruby-build supports "branch@sha" refs.
      ref: match[:ref].split("@").last,
    )
  end

  # What a definition should be compared against, in order of preference:
  #
  #   1. an explicit `# baseline:` comment in the definition, where "none"
  #      means there is nothing useful to compare against
  #   2. the previous revision of the same ruby version, e.g.
  #      4.0.7-pshopify2 -> 4.0.7-pshopify1
  #   3. the upstream release it is based on, e.g. 4.0.7-pshopify1 -> 4.0.7,
  #      which isolates the Shopify patch set. Only used when the definition
  #      actually patches upstream (its git ref is not just the upstream tag).
  #   4. the highest-versioned definition of the same flavor sorting below it,
  #      e.g. 4.0.1-modgc -> 3.4.7-modgc
  #
  # Returns a definition name, a bare upstream version for case 3, or nil.
  def self.previous(name, rubies_dir)
    target = parse(name)
    return nil if target.nil?

    override = baseline_override(File.join(rubies_dir, name))
    return (override == "none" ? nil : override) if override

    earlier = earlier(name, rubies_dir)

    same_version = earlier.find { |candidate| candidate.sort_key[0, 2] == target.sort_key[0, 2] }
    return same_version.name if same_version

    # Skipped for previews and rcs, whose upstream tags are not spelled "v<version>".
    base_version = target.sort_key[0].join(".")
    final_release = target.sort_key[1] == [2, 0]
    source = source(File.join(rubies_dir, name))
    return base_version if final_release && source && source.ref != "v#{base_version}"

    earlier.first&.name
  end

  def self.baseline_override(path)
    return nil unless File.exist?(path)

    BASELINE.match(File.read(path))&.[](:name)
  end

  # Definitions of the same flavor that sort below the given one, newest first.
  def self.earlier(name, rubies_dir)
    target = parse(name)
    return [] if target.nil?

    Dir.children(rubies_dir)
      .filter_map { |entry| parse(entry) }
      .select { |candidate| candidate.flavor == target.flavor }
      .select { |candidate| (candidate.sort_key <=> target.sort_key) == -1 }
      .sort_by(&:sort_key)
      .reverse
  end
end
