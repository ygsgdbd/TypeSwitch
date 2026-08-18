#!/usr/bin/env ruby

release_tag = ARGV.first
abort "Usage: script/validate_release_order.rb vX.Y.Z" unless ARGV.length == 1

tag_pattern = /\Av(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/
release_match = tag_pattern.match(release_tag)
abort "Release tag must use strict vX.Y.Z format: #{release_tag}" unless release_match

release_version = release_match.captures.map(&:to_i)
versions = STDIN.each_line.each_with_object([]) do |line, result|
  match = tag_pattern.match(line.strip)
  result << [match.captures.map(&:to_i), match[0]] if match
end

unless versions.any? { |version, tag| version == release_version && tag == release_tag }
  abort "Release tag #{release_tag} was not found among tags merged into origin/main."
end

highest_version, highest_tag = versions.max_by(&:first)
if (release_version <=> highest_version).negative?
  abort "Release tag #{release_tag} would downgrade the latest version #{highest_tag}."
end

puts "Release tag #{release_tag} is the highest version on origin/main."
