# Run as `ruby import_language.rb es path/to/site.es.json`
require 'json'
require 'fileutils'
require 'ruby-lokalise-api'
require 'open-uri'
require 'zip'
require 'metadown'
require_relative '_plugins/common'

def language_dir(lang)
  "_sections/*/#{lang}"
end

SOURCE_LANG = "en"
SOURCE_DIR = language_dir(SOURCE_LANG)

SECTIONS_TO_FILES = {}
Dir["#{SOURCE_DIR}/**/*.md"].sort!.each { |filename|
  SECTIONS_TO_FILES[key_from_filename(filename)] = filename
}

TOP_LEVEL_PAGES = {}
Dir["*-en.md"].sort!.each { |filename|
  TOP_LEVEL_PAGES[key_from_top_level_file(filename)] = filename
}

def generate_content(translations_lang, translations_file)
  translations = JSON.parse(File.open(translations_file, 'r:UTF-8') { |f| f.read })

  FileUtils.rm_r(language_dir(translations_lang), force: true)

  SECTIONS_TO_FILES.each do |section, source_file|
    translated_file = source_file.sub("/en/", "/#{translations_lang}/")
    translated_dir = File.dirname(translated_file)
    FileUtils.mkdir_p(translated_dir)
    File.open(translated_file, "w:UTF-8") { |file|
      file.puts translations[section]
    }
  end

  TOP_LEVEL_PAGES.each do |page, source_file|
    puts "source_file: #{source_file}"
    puts "page: #{page}"
    puts "tranlsations_lang: #{translations_lang}"
    metadata = Metadown.render(File.open(source_file, 'r:UTF-8') { |f| f.read }).metadata
    metadata["lang"] = translations_lang
    metadata["title"] = translations["#{page}-title"] if translations["#{page}-title"]
    translated_file = source_file.sub(/-en.md$/, "-#{translations_lang}.md")
    puts "Translated_file: #{translated_file}"
    File.open(translated_file, "w:UTF-8") { |file|
      file.puts metadata.to_yaml
      file.puts "---\n" # Not sure why `#to_yaml` doesn't output the separator at the end
      file.puts translations[page]
    }
  end
end

LOKALISE_TOKEN = ARGV[0]
SINGLE_LANG = ARGV[1]
PROJECT_ID = "423383895e6b8c4b081a89.98184174"
client = Lokalise.client LOKALISE_TOKEN

puts "Building files from Lokalise"
response = client.download_files(PROJECT_ID, {format: "json", filter_filenames: ["pasted.json"], replace_breaks: false, placeholder_format: :icu})

puts "Downloading #{response["bundle_url"]} ..."
content = open(response["bundle_url"])
Zip::File.open_buffer(content) do |zip|
  zip.each do |entry|
    next unless entry.name.end_with?("pasted.json")
    next if entry.name.end_with?("#{SOURCE_LANG}/pasted.json")
    lang = entry.name.split("/")[0]
    next if SINGLE_LANG != nil && lang != SINGLE_LANG
    dest = "_translations/#{lang}.json"
    puts "Saving #{dest}"
    entry.extract(dest) { true }

    puts "Expanding .md"
    generate_content(lang, dest)
  end
end
