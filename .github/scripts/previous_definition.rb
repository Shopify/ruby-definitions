#!/usr/bin/env ruby
# frozen_string_literal: true

# Prints the definition that a given definition should be benchmarked against,
# which is Definitions.previous restricted to the flavors worth benchmarking.
#
# The modgc builds are excluded: they install librubygc.default.so (`make
# install-modular-gc MODULAR_GC=default`), which is the same default GC loaded
# dynamically, so RUBY_GC_LIBRARY=default would measure modular GC call overhead
# rather than a different collector, and no alternative GC (mmtk, wbcheck) is
# installed.
#
# Usage: previous_definition.rb <definition name> [rubies dir]
#
# The result is not necessarily a file in the rubies directory: a definition can
# be compared against a plain upstream version, which ruby-build provides its
# own definition for.
#
# Prints nothing (exit 0) when there is no suitable baseline.

require_relative "definitions"

BENCHMARKED_FLAVORS = ["pshopify"].freeze

name = ARGV[0] or abort("usage: #{$PROGRAM_NAME} <definition name> [rubies dir]")
rubies_dir = ARGV[1] || "rubies"

target = Definitions.parse(name)
exit 0 if target.nil?

unless BENCHMARKED_FLAVORS.include?(target.flavor)
  warn("#{target.flavor} definitions are not benchmarked")
  exit 0
end

puts Definitions.previous(name, rubies_dir)
