# Install

Consider using [rvm](https://rvm.io/).
After you have cloned this repository, install all the dependencies by
`bundle install`.

Dont forget to put your github.com credentials in `~/.netrc`, see also https://github.com/octokit/octokit.rb#using-a-netrc-file If you dont give
your credentials, you will be struck by rate limiting!


# Usage

To download and populate our knowledge base use `generate_doap.rb`.

```
$ ./generate_doap.rb --version
1.0.0

$ ./generate_doap.rb --help
Usage: ./generate_doap.rb [options]

Specific options:
    -d, --debug                      Write some debugging info to STDOUT
    -n, --no-cache                   Do not use any cached data
    -f, --http-cache                 Use a http caching layer
    -c, --config FILENAME            Set config file name to FILENAME

Common options:
    -v, --verbose                    Run verbosely
    -h, --help                       Show this message
        --version                    Show version
```

A real short example on how to extract data from the knowledge base is `overview.rb`.
