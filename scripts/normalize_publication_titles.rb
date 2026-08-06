#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"
require "optparse"
require "yaml"

ROOT = File.expand_path("..", __dir__)
PUBLICATIONS_PATH = File.join(ROOT, "_data", "publications.yml")

options = {
  force_html: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/normalize_publication_titles.rb [options]"
  opts.on("--force-html", "Regenerate title_html from title_latex even when title_html already exists.") { options[:force_html] = true }
end.parse!

def load_yaml_array(path)
  data = YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)
  data.nil? ? [] : data
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

def reorder_publication(publication)
  preferred_order = %w[
    id type date title title_latex title_html authors journal journal_html journal_url
    doi arxiv primary_class inspire_id inspire_url orcid_put_code orcid_url publisher
    isbn thesis_type url note source updated_at
  ]

  ordered = {}
  preferred_order.each do |key|
    ordered[key] = publication[key] if publication.key?(key)
  end
  publication.each do |key, value|
    ordered[key] = value unless ordered.key?(key)
  end
  ordered
end

publications = load_yaml_array(PUBLICATIONS_PATH)
publications.map! do |publication|
  title_latex = publication["title_latex"] || publication["title"] || publication["title_html"]
  publication["title_latex"] = title_latex
  publication["title_html"] = latex_inline_math_to_mathjax(title_latex) if options[:force_html] || !publication["title_html"]
  reorder_publication(publication)
end

write_yaml(PUBLICATIONS_PATH, publications)
puts "Normalized title_latex and title_html in #{PUBLICATIONS_PATH}."
