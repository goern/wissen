#!/usr/bin/env ruby
# encoding: utf-8

require 'logger'
require 'optparse'

require 'json'

require 'rdf'
require 'rdf/ntriples'
require 'sparql'

Version = '1.0.0'

options = {}

OptionParser.new do |parser|
  parser.banner = "Usage: #{$0} [options]"
  parser.separator ""
  parser.separator "Specific options:"

  parser.on("-d", "--debug", "Write some debugging info to STDOUT") do |d|
    options[:debug] = true
  end

  parser.on("-c", "--config FILENAME", "Set config file name to FILENAME") do |config_file|
    options[:config_file] = config_file
  end

  parser.separator ""
  parser.separator "Common options:"

  parser.on_tail("-v", "--verbose", "Run verbosely") do |v|
    options[:verbose] = true
  end

  parser.on_tail("-h", "--help", "Show this message") do
    puts parser
    exit
  end

  parser.on_tail("--version", "Show version") do
    puts Version
    exit
  end
end.parse!

puts options.inspect if options[:verbose]

# check which config file to read and read it...
if options[:config_file].to_s == ''
  config_file = File.read('config.json')
else
  config_file = File.read(options[:config_file].to_s)
end
config_hash = JSON.parse(config_file)

CACHE_FILENAME = config_hash['cache_file']

# define some vocabularies we use later on
DOAP = RDF::Vocabulary.new('http://usefulinc.com/ns/doap#')
XKOS = RDF::Vocabulary.new('http://rdf-vocabulary.ddialliance.org/xkos#')
SKOS = RDF::Vocabulary.new('http://www.w3.org/2004/02/skos/core#')
GR = RDF::Vocabulary.new('http://purl.org/goodrelations/v1#')
SO = RDF::Vocabulary.new('http://schema.org/version/3.1/')

# we log to STDOUT
logger = Logger.new(STDOUT)

if options[:debug]
  logger.level = Logger::DEBUG
else
  logger.level = Logger::WARN
end


graph = nil
begin
  graph = RDF::Repository.load(CACHE_FILENAME)
rescue
  # TODO handle this
end

# get all projects
sse = SPARQL.parse("""
PREFIX doap: <http://usefulinc.com/ns/doap#>
PREFIX rdfs: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX xkos: <http://rdf-vocabulary.ddialliance.org/xkos#>
PREFIX so: <http://schema.org/version/3.1/>
SELECT *
WHERE {
  ?product rdfs:type so:SoftwareApplication .
  ?product so:name ?productName .
  OPTIONAL {
    ?product xkos:hasPart ?project .
    ?project rdfs:type doap:Project .
    ?project doap:description ?description .
    ?project doap:name ?projectName .
    OPTIONAL {
      ?project xkos:hasPart ?technology .
      ?technology doap:name ?technologyName .
    }
  }
}
ORDER BY ?project
""")

graph.query(sse) do |solutions|
  print "#{solutions[:productName]}"
  print " includes #{solutions[:projectName]}" unless solutions[:projectName].to_s == ''
  print " which uses #{solutions[:technologyName]}" unless solutions[:technologyName].to_s == ''
  puts
end
