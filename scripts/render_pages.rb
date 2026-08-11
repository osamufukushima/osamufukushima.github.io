#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "date"
require "fileutils"
require "optparse"
require "yaml"

ROOT = File.expand_path("..", __dir__)
DATA_DIR = File.join(ROOT, "_data")
WEB_DIR = File.join(ROOT, "web")

options = {
  page: "all",
  in_place: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/render_pages.rb [options]"
  opts.on("--page PAGE", "Page to render: publications, presentations, or all. Default: all") { |v| options[:page] = v }
  opts.on("--in-place", "Overwrite web/*/index.html instead of writing index.generated.html") { options[:in_place] = true }
end.parse!

def load_array(path)
  data = YAML.safe_load(File.read(path, encoding: "UTF-8"), permitted_classes: [Date, Time], aliases: true)
  raise "#{path} must contain a YAML array" unless data.is_a?(Array)

  data
end

def h(value)
  CGI.escapeHTML(value.to_s)
end

def attr(value)
  CGI.escapeHTML(value.to_s)
end

def html_text(item, html_key, plain_key)
  item[html_key] || h(item["title_latex"] || item[plain_key])
end

def author_name(name)
  text = name.to_s
  return text unless text.include?(", ")

  last, rest = text.split(", ", 2)
  "#{rest} #{last}"
end

def join_authors(authors)
  names = Array(authors).map { |name| h(author_name(name)) }
  case names.length
  when 0
    ""
  when 1
    names.first
  when 2
    "#{names[0]} and #{names[1]}"
  else
    "#{names[0...-1].join(", ")} and #{names[-1]}"
  end
end

def parse_date(value)
  text = value.to_s
  return Date.new(text.to_i, 1, 1) if text.match?(/\A\d{4}\z/)
  return Date.new(text[0, 4].to_i, text[5, 2].to_i, 1) if text.match?(/\A\d{4}-\d{2}\z/)

  Date.parse(text)
end

MONTHS = %w[Jan. Feb. Mar. Apr. May Jun. Jul. Aug. Sep. Oct. Nov. Dec.].freeze

def display_date(value)
  date = parse_date(value)
  "#{MONTHS[date.month - 1]} #{date.day}, #{date.year}"
rescue ArgumentError
  h(value)
end

def display_month(value)
  date = parse_date(value)
  "#{MONTHS[date.month - 1]} #{date.year}"
rescue ArgumentError
  h(value)
end

def sort_key(item)
  parse_date(item["date"])
rescue ArgumentError
  Date.new(1, 1, 1)
end

def target_path(source_path, in_place)
  return source_path if in_place

  File.join(File.dirname(source_path), "index.generated.html")
end

def strip_front_matter(text)
  lines = text.lines
  return text unless lines.first&.strip == "---"

  closing_index = lines[1..]&.index { |line| line.strip == "---" }
  return text unless closing_index

  lines[(closing_index + 2)..].join
end

def replace_section(template_path, section_html, in_place)
  template = File.read(template_path, encoding: "UTF-8")
  matches = template.scan(%r{<section>.*?</section>}m)
  raise "#{template_path}: expected exactly one <section>...</section>, found #{matches.length}" unless matches.length == 1

  output = template.sub(%r{<section>.*?</section>}m, section_html)
  output = strip_front_matter(output) unless in_place
  path = target_path(template_path, in_place)
  File.write(path, output)
  path
end

def publication_link(url, label)
  return nil if url.to_s.empty? || label.to_s.empty?

  %(&nbsp;<a href="#{attr(url)}" target="_blank" rel="noopener">#{label}</a>)
end

def render_article(item)
  parts = []
  if item["journal_html"]
    parts << publication_link(item["journal_url"], item["journal_html"])
  end
  if item["arxiv"]
    label = "[arXiv:#{h(item["arxiv"])}"
    label += " [#{h(item["primary_class"])}]" if item["primary_class"]
    label += "]"
    parts << publication_link("https://arxiv.org/abs/#{item["arxiv"]}", label)
  elsif item["inspire_url"]
    parts << publication_link(item["inspire_url"], "[INSPIRE]")
  end

  <<~HTML
    <li> #{join_authors(item["authors"])},<br>
      "#{html_text(item, "title_html", "title")}," <br>
      #{parts.compact.join("\n      ")}
    </li>
  HTML
end

def render_book(item)
  isbn = Array(item["isbn"]).join(", ")
  link_label = isbn.empty? ? "Springer" : "ISBN #{h(isbn)}."
  note = item["note"] || "Book"

  <<~HTML
    <li> #{h(note)}: <br>
      "#{html_text(item, "title_html", "title")},"
      #{h(item["publisher"])}, #{h(item["date"].to_s[0, 4])},<br>
      #{publication_link(item["url"], link_label)}
    </li>
  HTML
end

def render_thesis(item)
  title = html_text(item, "title_html", "title")
  title_html = item["url"] ? %(<a href="#{attr(item["url"])}">"#{title},"</a>) : %("#{title},")

  <<~HTML
    <li> #{h(item["thesis_type"] || "Thesis")}: <br>
      #{title_html} &nbsp; #{display_month(item["date"])}.
    </li>
  HTML
end

def render_publications
  publications = load_array(File.join(DATA_DIR, "publications.yml"))
  grouped = publications.group_by { |item| item["type"] }
  articles = Array(grouped["article"])
  books = Array(grouped["book"]).sort_by { |item| sort_key(item) }.reverse
  theses = Array(grouped["thesis"]).sort_by { |item| sort_key(item) }.reverse

  <<~HTML
    <section>
    <h2>Publications</h2>
    <h3>Article</h3>

    <ol>
    #{articles.map { |item| render_article(item) }.join("\n")}
    </ol>

    <h3>Book</h3>

    <ol>
    #{books.map { |item| render_book(item) }.join("\n")}
    </ol>

    <h3>Thesis</h3>

    <ol>
    #{theses.map { |item| render_thesis(item) }.join("\n")}
    </ol>

    </section>
  HTML
end

def presentation_heading(item)
  suffix = item["presentation_type"] == "poster" ? ", poster presentation" : ""
  %("#{h(item["title"])}"#{suffix},)
end

def presentation_place(item)
  [item["event"], item["venue"], item["location"]].compact.reject(&:empty?).map { |value| h(value) }.join(", ")
end

def render_standard_presentation(item)
  <<~HTML
    <li>
      #{presentation_heading(item)} <br>
      &nbsp;#{presentation_place(item)}, #{display_date(item["date"])}.
    </li>
  HTML
end

def render_local_presentation(item)
  links = Array(item["links"]).map do |link|
    %(<a href="#{attr(link["url"])}" target="_blank" rel="noopener">#{h(link["label"])}</a>)
  end

  if item["presentation_type"] == "review"
    detail = %(Review on "#{h(item["title"])}")
    detail += ", #{links.join(" and ")}" unless links.empty?
    detail += "."
  else
    detail = %("#{h(item["title"])}")
    detail += ", poster presentation" if item["presentation_type"] == "poster"
    detail += "."
  end

  <<~HTML
    <li> #{h(item["event"])}, #{display_date(item["date"])}. <br>
      #{detail}
    </li>
  HTML
end

def render_presentations
  presentations = load_array(File.join(DATA_DIR, "presentations.yml"))
  categories = load_array(File.join(DATA_DIR, "presentation_categories.yml"))
  grouped = presentations.group_by { |item| item["category"] }

  body = categories.sort_by { |item| item["order"].to_i }.map do |category|
    items = Array(grouped[category["id"]]).sort_by { |item| sort_key(item) }.reverse
    next if items.empty?

    renderer = category["id"] == "local_talk" ? method(:render_local_presentation) : method(:render_standard_presentation)
    <<~HTML
      <h3> #{h(category["label"])} </h3>

      <ol>
      #{items.map { |item| renderer.call(item) }.join("\n")}
      </ol>
    HTML
  end.compact.join("\n\n")

  <<~HTML
    <section>
    <h2>Presentations</h2>
    #{body}
    </section>
  HTML
end

pages = case options[:page]
        when "all"
          %w[publications presentations]
        when "publications", "presentations"
          [options[:page]]
        else
          raise "Unknown page: #{options[:page]}"
        end

written = pages.map do |page|
  source = File.join(WEB_DIR, page, "index.html")
  section = page == "publications" ? render_publications : render_presentations
  replace_section(source, section, options[:in_place])
end

written.each { |path| puts "Rendered #{path}" }
