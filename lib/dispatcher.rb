#
# The dispatcher is responsible for populating the work queue.
#
#  It looks for the best links to process and puts them into the work queue.
#
#    It is intended to be called from crawlers who notice a short queue.
#
class Dispatcher
  include Sidekiq::Worker
  sidekiq_options :queue => :dispatcher, :backtrace => true

  SALT_LIMIT = 500
  PROSPECT_LIMIT = 10000

  def perform

    return true unless DISPATCHING.try_lock

    "dispatch".split('').each {|i| logger.info i}

    begin
      get_fountain_links.each {|l| Crawler.perform_async(l) }
      #get_salt_links.each {|l| Crawler.perform_async(l)}
      get_prospect_links.each { |l| Crawler.perform_async(l) }
    rescue StandardError => e
      puts e.to_s 
    ensure
      DISPATCHING.unlock
    end

    Dispatcher.dispatch_if_necessary

  end

  #
  # Returns an array of link ids to schedule for crawling with unique domains and sorted by prospect_score.
  #
  def get_prospect_links
  
    logger.info '<'
    
    q = <<SQL
      with recursive
        r(id,domain,prospect_score,count,seen)
          as ( (select id, domain, prospect_score, 1, array[domain] from links where visited_at is null order by prospect_score desc nulls last, id desc, visited_at limit 1)
               union all
               (select (b).*, count+1, seen || (b).domain
                  from (select (select row(id, domain, prospect_score)::links_info from links b
                                 where (prospect_score,id) < (r.prospect_score,r.id) and domain <> all (r.seen) and visited_at is null
                                 order by prospect_score desc nulls last, id desc, visited_at limit 1) as b,
                               r.count, r.seen
                          from r
                         where r.count < 10000
                         offset 0
                       ) s1 where not (b is null))
             )
      select id from r;
SQL

    links = POOL.with { |c| c.query(q) }.map {|i| i['id']}
    logger.info '>'
    puts 'warning: may not have prospected; may have null domain' if links.length < 100    
    return links
  end

  #
  # Returns an array of link ids for crawling that are re-visits.
  #
  def get_fountain_links
    links = POOL.with do |c|
      c.query("select id from links where fountain_score > 0 and visited_at < (current_timestamp - interval '2 hours') order by visited_at asc").map {|i| i['id'] }
    end
    return links
  end

  #
  # Returns some random links.  Keeps things not getting too focused on prospecting.
  #   Also much faster on big table, give workers something to crunch while the really slow prospect_links euns.
  #
  def get_salt_links
    links = POOL.with do |c|
      c.query("select id from links where visited_at is null random() < 0.0001 limit #{SALT_LIMIT}").map {|i| i['id'] }
    end
    return links
  end

  #
  # Faster prospect score ordering
  #
  def get_sloppy_links
    h = {}
    POOL.with do |c|
      c.query("select id, href from links where visited_at is null order by prospect_score desc nulls last limit #{SLOPPY_LIMIT}").each {|j| h[Crawler.get_domain(j['href'])] = j['id'] }
    end
    links = h.values
    return links
  end
  #
  #  Schedules a dispatch job which will schedule new crawl jobs.
  #
  #  TODO restrict to just crawl queues, not dispatch queues.
  #
  def self.dispatch_if_necessary
    # Can put an in memory counter of some kind to reduce redis roundtrips if ever a bottleneck.
    if Sidekiq::Stats.new.queues["crawler"].to_i < (Sidekiq.options[:concurrency] * 100) && !DISPATCHING.locked?
      perform_async
    end
  end

end
