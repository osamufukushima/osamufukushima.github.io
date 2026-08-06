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
DEFAULT_CACHE_DIR = File.join(ROOT, "data_raw", "orcid")

options = {
  orcid: ENV.fetch("ORCID_ID", "0000-0001-7205-5324"),
  output: DEFAULT_OUTPUT,
  cache_dir: DEFAULT_CACHE_DIR,
  cache: true
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/sync_orcid.rb [options]"
  opts.on("--orcid ID", "ORCID iD. Default: #{options[:orcid]}") { |v| options[:orcid] = v }
  opts.on("--output PATH", "YAML database to update. Default: _data/publications.yml") { |v| options[:output] = File.expand_path(v, ROOT) }
  opts.on("--cache-dir PATH", "Raw JSON cache directory. Default: data_raw/orcid") { |v| options[:cache_dir] = File.expand_path(v, ROOT) }
  opts.on("--no-cache", "Do not save raw API response.") { options[:cache] = false }
end.parse!

def fetch_json(url)
  headers = { "Accept" => "application/vnd.orcid+json" }
  token = ENV["ORCID_ACCESS_TOKEN"]
  headers["Authorization"] = "Bearer #{token}" if token && !token.empty?

  URI.open(url, headers.merge(read_timeout: 30)) do |io|
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

def value_at(hash, *keys)
  keys.reduce(hash) { |memo, key| memo.is_a?(Hash) ? memo[key] : nil }
end

def external_ids(summary)
  ids = value_at(summary, "external-ids", "external-id") || []
  ids.each_with_object({}) do |item, hash|
    type = item["external-id-type"].to_s.downcase
    value = item["external-id-value"].to_s
    next if type.empty? || value.empty?

    hash[type] ||= value
  end
end

def date_from(summary)
  date = summary["publication-date"] || {}
  year = value_at(date, "year", "value")
  month = value_at(date, "month", "value")
  day = value_at(date, "day", "value")
  [year, month, day].compact.join("-")
end

def key_for(record)
  return "arxiv:#{record["arxiv"]}" if record["arxiv"]
  return "doi:#{record["doi"].downcase}" if record["doi"]

  record["id"]
end

works_url = "https://pub.orcid.org/v3.0/#{options[:orcid]}/works"
data = fetch_json(works_url)
if options[:cache]
  FileUtils.mkdir_p(options[:cache_dir])
  File.write(File.join(options[:cache_dir], "works.json"), JSON.pretty_generate(data))
end

records = Array(data["group"]).map do |group|
  summary = Array(group["work-summary"]).first
  next unless summary

  ids = external_ids(summary)
  doi = ids["doi"]
  arxiv = ids["arxiv"] || ids["arxiv-id"]
  title = value_at(summary, "title", "title", "value")
  next unless title

  id = if arxiv
         "arxiv:#{arxiv}"
       elsif doi
         "doi:#{doi.downcase}"
       else
         "orcid-put-code:#{summary["put-code"]}"
       end

  {
    "id" => id,
    "type" => "article",
    "date" => date_from(summary),
    "title" => title,
    "title_html" => title,
    "journal" => value_at(summary, "journal-title", "value") && { "title" => value_at(summary, "journal-title", "value") },
    "doi" => doi,
    "arxiv" => arxiv,
    "orcid_put_code" => summary["put-code"],
    "orcid_url" => "https://orcid.org/#{options[:orcid]}/work/#{summary["put-code"]}",
    "source" => "orcid",
    "updated_at" => Time.now.utc.iso8601
  }.compact
end.compact

existing = load_yaml_array(options[:output])
existing_by_key = existing.each_with_object({}) { |entry, hash| hash[key_for(entry)] = entry if entry.is_a?(Hash) }

added = 0
records.each do |record|
  key = key_for(record)
  if existing_by_key[key]
    existing_by_key[key] = record.merge(existing_by_key[key])
  else
    existing_by_key[key] = record
    added += 1
  end
end

ordered = existing_by_key.values.sort_by { |entry| entry["date"].to_s }.reverse
write_yaml(options[:output], ordered)
puts "Merged #{records.length} ORCID works into #{options[:output]} (#{added} new)."
