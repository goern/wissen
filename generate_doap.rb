#!/usr/bin/env ruby

require 'tmpdir'

require 'octokit'

require 'rdf'
require 'rdf/ntriples'
require 'rdf/nquads'

upstream_projects = [
  { owner: "docker", repo: "docker" },
  { owner: "coreos", repo: "etcd" },
  { owner: "kubernetes", repo: "kubernetes" },
  { owner: "projectatomic", repo: "atomic" },
  { owner: "projectatomic", repo: "rpm-ostree" },
  { owner: "openshift", repo: "origin" }
]

# TODO put this in tmpdir
CACHE_FILENAME = 'tmp/database.nt'

client = Octokit::Client.new(:netrc => true)
root = client.root

DOAP = RDF::Vocabulary.new("http://usefulinc.com/ns/doap#")

graph = nil

if File.exists?(CACHE_FILENAME)
  graph = RDF::Graph.load(CACHE_FILENAME)
else
  graph = RDF::Graph.new

  # Ok, lets get all the upstream projects from github...
  upstream_projects.each do |project|
    puts project

    # TODO handle API rate limiting
    prj = root.rels[:repository].get :uri => project

    puts prj.data.inspect

    # and put their generated DOAP in the graph
    graph << [RDF::URI(prj.data[:url]), RDF::URI("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"), DOAP.Project]
    graph << [RDF::URI(prj.data[:url]), DOAP['name'], prj.data[:name]]
    graph << [RDF::URI(prj.data[:url]), DOAP['programming-language'], prj.data[:language]]
    graph << [RDF::URI(prj.data[:url]), DOAP['homepage'], RDF::Resource(prj.data[:homepage])] unless prj.data[:homepage].to_s == ''
    graph << [RDF::URI(prj.data[:url]), DOAP['description'], prj.data[:description]]


    # created shortdesc description category license repository

  end

end

puts graph.dump(:ntriples)

# lets dump all the data we got...
RDF::Writer.open(CACHE_FILENAME) do |writer|
  writer << graph
end

query = RDF::Query.new({
  project: {
    RDF.type  => DOAP.Project,
    DOAP['programming-language'] => :lang
  }
})

query.execute(graph) do |solution|
  puts "lang=#{solution.lang}"
end
