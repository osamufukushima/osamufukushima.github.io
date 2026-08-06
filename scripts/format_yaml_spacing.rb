#!/usr/bin/env ruby
# frozen_string_literal: true

paths = ARGV.empty? ? Dir.glob(File.join(__dir__, "..", "_data", "*.yml")).sort : ARGV

def spaced_top_level_items(text)
  output = []
  seen_item = false
  text.lines.each do |line|
    if line.start_with?("- ")
      output << "\n" if seen_item && output.last && !output.last.strip.empty?
      seen_item = true
    end
    output << line
  end
  result = output.join
  result.end_with?("\n") ? result : "#{result}\n"
end

paths.each do |path|
  original = File.read(path)
  formatted = spaced_top_level_items(original)
  next if formatted == original

  File.write(path, formatted)
  puts "Formatted #{path}"
end
