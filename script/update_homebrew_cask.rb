#!/usr/bin/env ruby

path, release_tag, sha256 = ARGV
abort "Usage: script/update_homebrew_cask.rb <cask-path> vX.Y.Z <sha256>" unless ARGV.length == 3
version_pattern = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/
release_match = /\Av(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/.match(release_tag)
abort "Release tag must use strict vX.Y.Z format: #{release_tag}" unless release_match
abort "SHA-256 must contain exactly 64 hexadecimal characters" unless sha256.match?(/\A[0-9a-fA-F]{64}\z/)
abort "Homebrew cask does not exist: #{path}" unless File.file?(path)

version = release_tag.delete_prefix("v")
version_parts = release_match.captures.map(&:to_i)
sha256 = sha256.downcase
asset_url = "https://github.com/ygsgdbd/TypeSwitch/releases/download/#{release_tag}/TypeSwitch-macOS-universal.zip"
content = File.read(path)
current_versions = content.scan(/^  version "([^"]+)"$/).flatten
abort "Expected exactly one version entry in #{path}, found #{current_versions.length}" unless current_versions.length == 1

current_version = current_versions.first
current_match = version_pattern.match(current_version)
abort "Current Homebrew cask version must use strict X.Y.Z format: #{current_version}" unless current_match
if (version_parts <=> current_match.captures.map(&:to_i)).negative?
  abort "Refusing to downgrade Homebrew cask from #{current_version} to #{version}."
end

replacements = {
  /^  version ".*"$/ => "  version \"#{version}\"",
  /^  sha256 ".*"$/ => "  sha256 \"#{sha256}\"",
  /^  url ".*"$/ => "  url \"#{asset_url}\"",
}

replacements.each do |pattern, replacement|
  matches = content.scan(pattern).length
  abort "Expected exactly one #{pattern.inspect} entry in #{path}, found #{matches}" unless matches == 1

  content.sub!(pattern, replacement)
end

if content == File.read(path)
  puts "Homebrew cask is already up to date."
else
  File.write(path, content)
  puts "Updated #{path} to #{release_tag}."
end
