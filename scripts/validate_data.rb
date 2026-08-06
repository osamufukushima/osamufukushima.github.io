#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"
require "date"
require "yaml"

ROOT = File.expand_path("..", __dir__)

def load_array(path)
  data = YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)
  raise "#{path} must contain a YAML array" unless data.is_a?(Array)

  data
end

def require_fields(item, fields, label, errors)
  fields.each do |field|
    value = item[field]
    errors << "#{label}: missing #{field}" if value.nil? || value == "" || value == []
  end
end

errors = []

publications_path = File.join(ROOT, "_data", "publications.yml")
presentations_path = File.join(ROOT, "_data", "presentations.yml")
categories_path = File.join(ROOT, "_data", "presentation_categories.yml")
overrides_path = File.join(ROOT, "_data", "publication_overrides.yml")

publications = load_array(publications_path)
presentations = load_array(presentations_path)
categories = load_array(categories_path)
load_array(overrides_path)

ids = Set.new
publications.each do |item|
  label = "publication #{item["id"] || "(no id)"}"
  require_fields(item, %w[id type date title title_latex title_html authors], label, errors)
  errors << "#{label}: duplicate id" if item["id"] && !ids.add?(item["id"])
  errors << "#{label}: authors must be an array" unless item["authors"].is_a?(Array)
  errors << "#{label}: invalid date #{item["date"].inspect}" unless item["date"].to_s.match?(/\A\d{4}(-\d{2}(-\d{2})?)?\z/)
  errors << "#{label}: title_html should use MathJax \\(...\\), not $...$" if item["title_html"].to_s.include?("$")
  if item["type"] == "article" && !item["arxiv"] && !item["doi"] && !item["inspire_id"]
    errors << "#{label}: article should have arxiv, doi, or inspire_id"
  end
end

category_ids = categories.map { |item| item["id"] }.compact.to_set
ids.clear
presentations.each do |item|
  label = "presentation #{item["id"] || "(no id)"}"
  require_fields(item, %w[id category date title event presentation_type], label, errors)
  errors << "#{label}: duplicate id" if item["id"] && !ids.add?(item["id"])
  errors << "#{label}: unknown category #{item["category"].inspect}" unless category_ids.include?(item["category"])
  errors << "#{label}: invalid date #{item["date"].inspect}" unless item["date"].to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
end

if errors.empty?
  puts "Data validation OK: #{publications.length} publications, #{presentations.length} presentations."
else
  warn errors.join("\n")
  exit 1
end
