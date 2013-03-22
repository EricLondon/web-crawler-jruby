# Simple Crawler

This is a web crawler.

I've just extracted this from a search engine project at http://fit.io so it's still a little rough around the edges.

## Architecture Overview

The Crawler has the following components:

  -  Seeder     (seed script to schedule a crawl of a url)
  -  Worker     (work script to start sidekiq worker, this does the actual crawling)
  -  Monitor    (monitor script to provide a web interface to the work queue)
  -  Dispatchor (dispatch script to schedule jobs based on uncrawled links)

## Installation

*Big Picture*

Requires Jruby, Postgres and Redis to be installed.  Should work with 1.9.3 just need to change some scripts.  Note: this is a library that designed for a highly parallel workload and it would be wise to use Jruby.

The executable scripts will expect bash/jruby to located where the shebangs expect.

Postgres and Redis configs are in /config/database.yml and /config/sidekiq.yml respectively.

The table schema is located in /db/tables.sql.  Instatiate the tables.

*Steps*

1.  review shell script for dependencies on ubuntu in /config/build.sh and install them.
2.  bundle install
3.  db/reset

## Usage

1.  First seed the crawler which will populate a crawl job in sidekiq (note the reset script is set to populate a couple items):

    $ jruby -S seed http://www.craigslit.com http://www.ibm.com http://othersitetocrawl.com


2.  Start the sidekiq worker process with:

    $ work


4.  You can then optionally monitor the work queue with sidekiqs monitor application:

    $ monitor

    It will print up the port on localhost to connect to.


## Context in Larger System

There are 4 tables in crawler database.

  - links         (raw links)
  - docs          (raw documents retrieved from links)
  - emails        (raw strings which match email regexp)
  - images        (urls for images)

The crawler is a relatively dumb service.  It crawls sites based on records in these four tables.  It simply requests links and stores the associated documents and links it finds in the tables.

Typical scenario:

The dispatcher queries for best links to crawl next and schedules jobs.  The crawl priority is dictacted by the *prospect_score* field in the links table. At fit.io I have an external process which uses some fancy calculations to rank links by which are most likely to be job related.  The worker process then picks up those jobs and crawls them creating new links and documents.

## Workflow Tips

clearing the queue:  redis-cli > flushdb


## License

Copyright (c) 2012 Robert Berry

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
