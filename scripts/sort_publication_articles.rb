#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"
require "optparse"
require "yaml"

ROOT = File.expand_path("..", __dir__)
DEFAULT_PATH = File.join(ROOT, "_data", "publications.yml")

options = {
  path: DEFAULT_PATH,
  check: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/sort_publication_articles.rb [options]"
  opts.on("--path PATH", "YAML publication database. Default: _data/publications.yml") { |v| options[:path] = File.expand_path(v, ROOT) }
  opts.on("--check", "Only check whether article records are sorted.") { options[:check] = true }
end.parse!

def load_yaml_array(path)
  data = YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)
  raise "#{path} must contain a YAML array" unless data.is_a?(Array)

  data
end

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

def write_yaml(path, data)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, spaced_top_level_items(YAML.dump(data)))
end

def arxiv_sort_key(arxiv)
  text = arxiv.to_s
  if (match = text.match(/\A(\d{2})(\d{2})\.(\d+)(?:v\d+)?\z/))
    year = match[1].to_i
    year += year >= 90 ? 1900 : 2000
    return [year, match[2].to_i, match[3].to_i]
  end

  if (match = text.match(%r{\A[^/]+/(\d{2})(\d{2})(\d+)(?:v\d+)?\z}))
    year = match[1].to_i
    year += year >= 90 ? 1900 : 2000
    return [year, match[2].to_i, match[3].to_i]
  end

  [0, 0, 0]
end

def article?(entry)
  entry.is_a?(Hash) && entry["type"] == "article"
end

def sorted_articles(entries)
  entries.sort do |left, right|
    comparison = arxiv_sort_key(right["arxiv"]) <=> arxiv_sort_key(left["arxiv"])
    next comparison unless comparison.zero?

    left["id"].to_s <=> right["id"].to_s
  end
end

data = load_yaml_array(options[:path])
articles = data.select { |entry| article?(entry) }
sorted = sorted_articles(articles)

if options[:check]
  if articles == sorted
    puts "Article records are sorted by arXiv id descending."
    exit 0
  end

  warn "Article records are not sorted by arXiv id descending."
  exit 1
end

sorted_queue = sorted.dup
output = data.map do |entry|
  article?(entry) ? sorted_queue.shift : entry
end

write_yaml(options[:path], output)
puts "Sorted #{articles.length} article record(s) in #{options[:path]} by arXiv id descending."
