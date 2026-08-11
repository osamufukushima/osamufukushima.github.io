#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "time"
require "uri"
require "open-uri"
require "yaml"

ROOT = File.expand_path("..", __dir__)
DEFAULT_OUTPUT = File.join(ROOT, "_data", "publications.yml")
DEFAULT_OVERRIDES = File.join(ROOT, "_data", "publication_overrides.yml")
DEFAULT_CACHE_DIR = File.join(ROOT, "data_raw", "inspire")

options = {
  author_id: "1818804",
  query: nil,
  size: 100,
  output: DEFAULT_OUTPUT,
  overrides: DEFAULT_OVERRIDES,
  cache_dir: DEFAULT_CACHE_DIR,
  cache: true
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/sync_inspire.rb [options]"
  opts.on("--author-id ID", "INSPIRE author record id. Default: #{options[:author_id]}") { |v| options[:author_id] = v }
  opts.on("--query QUERY", "Explicit INSPIRE literature query. Overrides --author-id.") { |v| options[:query] = v }
  opts.on("--size N", Integer, "Page size. Default: #{options[:size]}") { |v| options[:size] = v }
  opts.on("--output PATH", "YAML database to update. Default: _data/publications.yml") { |v| options[:output] = File.expand_path(v, ROOT) }
  opts.on("--overrides PATH", "YAML overrides file. Default: _data/publication_overrides.yml") { |v| options[:overrides] = File.expand_path(v, ROOT) }
  opts.on("--cache-dir PATH", "Raw JSON cache directory. Default: data_raw/inspire") { |v| options[:cache_dir] = File.expand_path(v, ROOT) }
  opts.on("--no-cache", "Do not save raw API responses.") { options[:cache] = false }
end.parse!

def fetch_json(url)
  URI.open(url, "Accept" => "application/json", read_timeout: 30) do |io|
    JSON.parse(io.read)
  end
end

def load_yaml_array(path)
  return [] unless File.exist?(path)

  data = YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)
  data.nil? ? [] : data
end

def write_yaml(path, data)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, spaced_top_level_items(YAML.dump(data)))
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

def first_value(items, key)
  Array(items).find { |item| item.is_a?(Hash) && item[key] }&.fetch(key)
end

def publication_year(metadata)
  info_year = Array(metadata["publication_info"]).find { |info| info["year"] }&.fetch("year", nil)
  return info_year.to_s if info_year

  date = metadata["preprint_date"] || metadata["earliest_date"]
  date.to_s[0, 4] if date
end

def normalized_date(metadata)
  info = Array(metadata["publication_info"]).find { |entry| entry["year"] }
  if info && info["year"] && info["journal_volume"].to_s.match?(/\A\d{2}\z/)
    return "#{info["year"]}-#{info["journal_volume"]}"
  end

  date = metadata["preprint_date"] || metadata["earliest_date"]
  return date.to_s if date && !date.to_s.empty?

  year = publication_year(metadata)
  year || "9999"
end

def arxiv_sort_key(arxiv, fallback_date)
  text = arxiv.to_s
  if text.match?(/\A(\d{2})(\d{2})\.(\d+)(?:v\d+)?\z/)
    year = Regexp.last_match(1).to_i
    year += year >= 90 ? 1900 : 2000
    return [year, Regexp.last_match(2).to_i, Regexp.last_match(3).to_i]
  end

  if text.match?(%r{\A[^/]+/(\d{2})(\d{2})(\d+)(?:v\d+)?\z})
    year = Regexp.last_match(1).to_i
    year += year >= 90 ? 1900 : 2000
    return [year, Regexp.last_match(2).to_i, Regexp.last_match(3).to_i]
  end

  date = fallback_date.to_s
  if date.match?(/\A(\d{4})(?:-(\d{2}))?(?:-(\d{2}))?\z/)
    return [
      Regexp.last_match(1).to_i,
      (Regexp.last_match(2) || "1").to_i,
      (Regexp.last_match(3) || "0").to_i
    ]
  end

  [0, 0, 0]
end

def journal_from(metadata)
  info = Array(metadata["publication_info"]).first || {}
  return nil if info.empty?

  journal = {
    "title" => info["journal_title"],
    "volume" => info["journal_volume"],
    "issue" => info["journal_issue"],
    "page" => info["artid"] || info["page_start"],
    "year" => info["year"]
  }.compact
  journal.empty? ? nil : journal
end

def journal_html(journal)
  return nil unless journal && journal["title"]

  bits = [journal["title"]]
  bits << "<b>#{journal["volume"]}</b>" if journal["volume"]
  bits << "no.#{journal["issue"]}" if journal["issue"]
  bits << journal["page"] if journal["page"]
  text = bits.join(", ")
  text += " (#{journal["year"]})" if journal["year"]
  "#{text}."
end

def latex_inline_math_to_mathjax(text)
  input = text.to_s
  output = +""
  in_math = false
  i = 0

  while i < input.length
    if input[i] == "\\" && input[i + 1] == "$"
      output << "\\$"
      i += 2
    elsif input[i, 2] == "$$"
      output << (in_math ? "\\)" : "\\(")
      in_math = !in_math
      i += 2
    elsif input[i] == "$"
      output << (in_math ? "\\)" : "\\(")
      in_math = !in_math
      i += 1
    else
      output << input[i]
      i += 1
    end
  end

  output
end

def document_types(metadata)
  Array(metadata["document_type"]).map { |value| value.to_s.downcase }
end

def article_record?(metadata)
  types = document_types(metadata)
  types.empty? || types.include?("article")
end

def inspire_candidate_keys(metadata, hit)
  arxiv_entry = Array(metadata["arxiv_eprints"]).first || {}
  doi = first_value(metadata["dois"], "value")
  inspire_id = metadata["control_number"] || hit["id"]
  [
    arxiv_entry["value"] && "arxiv:#{arxiv_entry["value"]}",
    doi && "doi:#{doi.downcase}",
    inspire_id && "inspire:#{inspire_id}"
  ].compact
end

def record_key(record)
  return "arxiv:#{record["arxiv"]}" if record["arxiv"]
  return "doi:#{record["doi"].downcase}" if record["doi"]
  return "inspire:#{record["inspire_id"]}" if record["inspire_id"]

  record["id"]
end

def candidate_keys(record)
  [
    record["id"],
    record["arxiv"] && "arxiv:#{record["arxiv"]}",
    record["doi"] && "doi:#{record["doi"].downcase}",
    record["inspire_id"] && "inspire:#{record["inspire_id"]}"
  ].compact
end

def deep_merge(base, override)
  base.merge(override) do |_key, left, right|
    left.is_a?(Hash) && right.is_a?(Hash) ? deep_merge(left, right) : right
  end
end

query = options[:query] || "authors.record.$ref:#{options[:author_id]}"
params = URI.encode_www_form(q: query, sort: "mostrecent", size: options[:size], page: 1)
base_url = "https://inspirehep.net/api/literature?#{params}"

records = []
page = 1
loop do
  page_url = base_url.sub(/page=1/, "page=#{page}")
  data = fetch_json(page_url)
  FileUtils.mkdir_p(options[:cache_dir]) if options[:cache]
  if options[:cache]
    File.write(File.join(options[:cache_dir], "literature_page_#{page}.json"), JSON.pretty_generate(data))
  end

  hits = data.dig("hits", "hits") || []
  records.concat(hits)
  break if hits.empty? || hits.length < options[:size]

  page += 1
end

skipped_keys = {}
skipped_records = 0
normalized = records.map do |hit|
  metadata = hit["metadata"] || {}
  unless article_record?(metadata)
    skipped_records += 1
    inspire_candidate_keys(metadata, hit).each { |key| skipped_keys[key] = true }
    next
  end

  arxiv_entry = Array(metadata["arxiv_eprints"]).first || {}
  doi = first_value(metadata["dois"], "value")
  journal = journal_from(metadata)
  inspire_id = metadata["control_number"] || hit["id"]
  title_latex = Array(metadata["titles"]).first&.fetch("title", nil)

  {
    "id" => arxiv_entry["value"] ? "arxiv:#{arxiv_entry["value"]}" : "inspire:#{inspire_id}",
    "type" => "article",
    "date" => normalized_date(metadata),
    "title" => title_latex,
    "title_latex" => title_latex,
    "title_html" => title_latex && latex_inline_math_to_mathjax(title_latex),
    "authors" => Array(metadata["authors"]).map { |author| author["full_name"] || author["name"] }.compact,
    "journal" => journal,
    "journal_html" => journal_html(journal),
    "journal_url" => doi && "https://doi.org/#{doi}",
    "doi" => doi,
    "arxiv" => arxiv_entry["value"],
    "primary_class" => arxiv_entry["categories"]&.first,
    "inspire_id" => inspire_id,
    "inspire_url" => "https://inspirehep.net/literature/#{inspire_id}",
    "source" => "inspire",
    "updated_at" => Time.now.utc.iso8601
  }.compact
end.compact

existing = load_yaml_array(options[:output])
overrides = load_yaml_array(options[:overrides])
override_by_key = overrides.each_with_object({}) do |entry, hash|
  next unless entry.is_a?(Hash) && entry["key"]

  body = entry.dup
  key = body.delete("key")
  hash[key] = body
end

existing_by_key = existing.each_with_object({}) { |entry, hash| hash[record_key(entry)] = entry if entry.is_a?(Hash) }
merged_keys = {}
merged_articles = normalized.map do |record|
  manual = candidate_keys(record).map { |key| existing_by_key[key] }.compact.first || {}
  override = candidate_keys(record).map { |key| override_by_key[key] }.compact.reduce({}) { |acc, item| deep_merge(acc, item) }
  merged = deep_merge(record, manual)
  merged = deep_merge(merged, override)
  merged_keys[record_key(merged)] = true
  merged
end

preserved = existing.reject do |entry|
  next false unless entry.is_a?(Hash) && entry["type"] == "article"

  merged_keys[record_key(entry)] || candidate_keys(entry).any? { |key| skipped_keys[key] }
end

output = (merged_articles + preserved).sort_by { |entry| arxiv_sort_key(entry["arxiv"], entry["date"]) }.reverse
write_yaml(options[:output], output)
puts "Updated #{options[:output]} with #{merged_articles.length} INSPIRE article records."
puts "Skipped #{skipped_records} non-article INSPIRE record(s) (#{skipped_keys.length} identifier(s))."
