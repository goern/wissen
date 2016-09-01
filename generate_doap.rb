#!/usr/bin/env ruby
# encoding: utf-8

require 'tmpdir'
require 'logger'
require 'optparse'

require 'json'

require 'octokit'
require 'faraday/http_cache'

require 'rdf'
require 'rdf/ntriples'
require 'rdf/nquads'
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

  parser.on("-n", "--no-cache", "Do not use any cached data") do |n|
    options[:no_cache] = true
  end

  parser.on("-f", "--http-cache", "Use a http caching layer") do |f|
    options[:http_cache] = true
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

# TODO overwrite other options from config file...
upstream_projects = config_hash['projects']

# TODO put this in tmpdir
CACHE_FILENAME = config_hash['cache_file'] || 'tmp/datenbank.nt'

# reconfigure faraday to do some logging, if we ask for it... --debug
if options[:debug] and options[:http_cache].nil?
  stack = Faraday::RackBuilder.new do |builder|
    builder.response :logger
    builder.use Octokit::Response::RaiseError
    builder.adapter Faraday.default_adapter
  end

  Octokit.middleware = stack
end

if options[:http_cache] and options[:debug].nil?
  stack = Faraday::RackBuilder.new do |builder|
    builder.use Faraday::HttpCache, serializer: Marshal, shared_cache: false
    builder.use Octokit::Response::RaiseError
    builder.adapter Faraday.default_adapter
  end

  Octokit.middleware = stack
end

client = Octokit::Client.new(:netrc => true)
root = client.root

# define some vocabularies we use later on
DOAP = RDF::Vocabulary.new("http://usefulinc.com/ns/doap#")

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

if (File.exists?(CACHE_FILENAME) and options[:no_cache].nil?)
  logger.info('using cached data')
  graph = RDF::Repository.load(CACHE_FILENAME)
else
  logger.info('no cache! downloading data')

  graph = RDF::Repository.new

  # Ok, lets get all the upstream projects from github...
  upstream_projects.each do |project|
    logger.debug project

    # TODO handle API rate limiting
    prj = root.rels[:repository].get :uri => project

    logger.debug prj.data.inspect

    # and put their generated DOAP in the graph
    graph << [RDF::URI(prj.data[:url]), RDF::URI("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"), DOAP.Project]
    graph << [RDF::URI(prj.data[:url]), DOAP['name'], prj.data[:name]]
    graph << [RDF::URI(prj.data[:url]), DOAP['programming-language'], prj.data[:language]]
    graph << [RDF::URI(prj.data[:url]), DOAP['homepage'], RDF::Resource(prj.data[:homepage])] unless prj.data[:homepage].to_s == ''
    graph << [RDF::URI(prj.data[:url]), DOAP['description'], prj.data[:description]]

    # created shortdesc category license repository

  end

end

puts graph.dump(:ntriples) if options[:verbose]

# lets dump all the data we have...
RDF::Writer.open(CACHE_FILENAME) do |writer|
  writer << graph
end

# get all projects written in Go and parse Godeps.json for something we might have in our knowledge base
sse = SPARQL.parse("PREFIX doap: <http://usefulinc.com/ns/doap#> SELECT * WHERE { ?s doap:programming-language 'Go' }")
graph.query(sse) do |solutions|
  solutions.each do |solution|
    # extract the repo from all results/solutions
    repo = solution[1].path.split('/')[2..3].join('/') # FIXME this looks way to funny!

    # get Godeps.json
    begin
      deps = client.search_code "Godeps.json repo:#{repo} in:path path:Godeps", :sort  => 'indexed', :order => 'desc'

      # if we have any Godeps.json within that repository
      if deps[:total_count] > 0
        # the highest scored 'may' be the one we want, the root one, the project wide
        puts "#{repo} has #{deps.items[0].path}"

        # TODO now lets see if repo depends on something we have in our knowledge base
      else
        puts "uhhh, #{repo} seems to have no Godeps.json"
      end

    rescue Octokit::UnprocessableEntity
      puts "Octokit cant process #{repo}"
    end

  end


end
