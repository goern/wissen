#!/usr/bin/env ruby
# encoding: utf-8

require 'tmpdir'
require 'logger'
require 'optparse'

require 'json'

require 'rdf'
require 'rdf/ntriples'

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

CACHE_FILENAME = config_hash['cache_file'] || 'tmp/datenbank.nt'

# define some vocabularies we use later on
DOAP = RDF::Vocabulary.new('http://usefulinc.com/ns/doap#')
XKOS = RDF::Vocabulary.new('http://rdf-vocabulary.ddialliance.org/xkos#')
SKOS = RDF::Vocabulary.new('http://www.w3.org/2004/02/skos/core#')
GR = RDF::Vocabulary.new('http://purl.org/goodrelations/v1#')
SO = RDF::Vocabulary.new('http://schema.org/version/3.1/')

# and initialize and empty graph, or repository
graph = nil

# we log to STDOUT
logger = Logger.new(STDOUT)

if options[:debug]
  logger.level = Logger::DEBUG
else
  logger.level = Logger::WARN
end

logger.debug options.inspect

# TODO turn https://www.redhat.com/en/technologies/all-products into a machine readable form

if File.exists?(CACHE_FILENAME)
  graph = RDF::Repository.load(CACHE_FILENAME)

  begin
    logger.info "Adding the Red Hat, Inc. organization"
    graph << [RDF::URI('https://www.redhat.com/'), RDF::URI("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"), SO['Organization']]
    graph << [RDF::URI('https://www.redhat.com/'), SO['legalName'], "Red Hat, Inc."]
    graph << [RDF::URI('https://www.redhat.com/'), SO['logo'], "https://www.redhat.com/profiles/rh/themes/redhatdotcom/img/logo.png"]


    logger.info "reading all redhat products from file..."
    redhat_products_file = File.read("redhat_products.json")
    redhat_products = JSON.parse(redhat_products_file)

    redhat_products.each do |product|
      logger.info "adding #{product['name']} to knowledge base"

      graph << [RDF::URI(product['uri']), RDF::URI("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"), SO['Product']]
      graph << [RDF::URI(product['uri']), RDF::URI("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"), SO['SoftwareApplication']]
      graph << [RDF::URI(product['uri']), SO['name'], product['name']]
      graph << [RDF::URI(product['uri']), SO['manufacturer'], RDF::URI('https://www.redhat.com/')]
      graph << [RDF::URI(product['uri']), SO['applicationCategory'], product['category']]

    end

  rescue
    # TODO no rescue?

  end

end

graph << [RDF::URI('https://access.redhat.com/products/openshift-enterprise-red-hat/'), XKOS['hasPart'], RDF::URI('https://api.github.com/repos/openshift/origin')]
graph << [RDF::URI('https://access.redhat.com/products/openshift-enterprise-red-hat/'), XKOS['hasPart'], RDF::URI('https://access.redhat.com/products/red-hat-enterprise-linux/')]

graph << [RDF::URI('https://access.redhat.com/products/red-hat-enterprise-linux/'), XKOS['hasPart'], RDF::URI('https://api.github.com/repos/projectatomic/docker')]

# lets dump all the data we have...
puts graph.dump(:ntriples) if options[:verbose]

RDF::Writer.open(CACHE_FILENAME) do |writer|
  writer << graph
end
