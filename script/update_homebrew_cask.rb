#!/usr/bin/env ruby

path, release_tag, sha256 = ARGV
abort "Usage: script/update_homebrew_cask.rb <cask-path> vX.Y.Z <sha256>" unless ARGV.length == 3
abort "Release tag must use strict vX.Y.Z format: #{release_tag}" unless release_tag.match?(/\Av\d+\.\d+\.\d+\z/)
abort "SHA-256 must contain exactly 64 hexadecimal characters" unless sha256.match?(/\A[0-9a-fA-F]{64}\z/)
abort "Homebrew cask does not exist: #{path}" unless File.file?(path)

version = release_tag.delete_prefix("v")
sha256 = sha256.downcase
asset_url = "https://github.com/ygsgdbd/TypeSwitch/releases/download/#{release_tag}/TypeSwitch-macOS-universal.zip"
content = File.read(path)

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
