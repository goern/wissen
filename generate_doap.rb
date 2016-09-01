#!/usr/bin/env ruby

require 'tmpdir'
require 'logger'
require 'optparse'

require 'octokit'

require 'rdf'
require 'rdf/ntriples'
require 'rdf/nquads'
require 'sparql'

upstream_projects = [
  { owner: "golang", repo: "go" },
  { owner: "docker", repo: "docker" },
  { owner: "coreos", repo: "etcd" },
  { owner: "kubernetes", repo: "kubernetes" },
  { owner: "projectatomic", repo: "atomic" },
  { owner: "projectatomic", repo: "rpm-ostree" },
  { owner: "openshift", repo: "origin" }
]

# TODO put this in tmpdir
CACHE_FILENAME = 'tmp/database.nt'

options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on("-d", "--debug", "Write some debugging info to STDOUT") do |d|
    options[:debug] = d
  end

  opts.on("-v", "--verbose", "Run verbosely") do |v|
    options[:verbose] = v
  end

  opts.on("-n", "--no-cache", "Do not use any cached data") do |n|
    options[:no_cache] = n
  end
end.parse!

puts options.inspect if options[:verbose]

# reconfigure faraday to do some logging, if we ask for it... --debug
if options[:debug]
  stack = Faraday::RackBuilder.new do |builder|
    builder.response :logger
    builder.use Octokit::Response::RaiseError
    builder.adapter Faraday.default_adapter
  end

  Octokit.middleware = stack
end

# TODO implement faraday caching https://github.com/octokit/octokit.rb#caching
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

# lets dump all the data we got...
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
      deps = client.search_code("Godeps.json+repo:#{repo}+in:path+path:Godeps")

      puts deps.inspect

    rescue Octokit::UnprocessableEntity
      puts "uhhh, #{repo} seems to have no Godeps.json"
    end

  end


end
