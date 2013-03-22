#
# This is a simple, well, mostly simple web crawler.
#
#   It is a sidekiq worker which means that this class just handles a single job,
#     it queries the db for the link.  Requests the resource, preprocesses the resource
#     and saves the resulting document to the docs table associated to that link.
#     The process also updates state on the link that is has been crawled.
#
#   TODO:  A couple key methods can be improved from using naive heuristics.
#
#          extract_content()
#          link_wanted?()
#
#          Also need to update the mutex polling to reschedule the job for a later time to free up the thread.
#
class Crawler

  include Sidekiq::Worker
  sidekiq_options :queue => :crawler, :timeout => 120

  URLREG = Regexp.new(/((([A-Za-z]{3,9}:(?:\/\/)?)(?:[-;:&=\+\$,\w]+@)?[A-Za-z0-9.-]+|(?:www.|[-;:&=\+\$,\w]+@)[A-Za-z0-9.-]+)((?:\/[\+~%\/.\w-_]*)?\??(?:[-\+=&;%@.\w_]*)#?(?:[\w]*))?)/)
  DOMAINREG = Regexp.new(/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}/)
  BASEURLREG = Regexp.new(/^https*:\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}/)
  EMAILREG = Regexp.new(/[A-Za-z0-9_\-\.]+@[A-Za-z0-9_\-\.]+\.[A-Za-z]{2,4}/)

  def initialize
    @h = HTTPClient.new
  end

  def perform(link_id, mark_as_job = false)

    Dispatcher.dispatch_if_necessary

    link = POOL.with { |c| c.query("select href, visited_at from links where id = #{link_id}") }.first
    @link_id = link_id
    @request_href = link["href"]
    @mark_as_job = mark_as_job

    return true unless ready_to_crawl?(link)

    POOL.with { |c| c.update("update links set visited_at = current_timestamp where id = #{@link_id}") }
    return true unless !@request_href.match LINK_BLACK_LIST

    begin
      response = @h.get @request_href
      handle_redirect(response) unless !response.redirect?
      extract_response_documents(response).each do |i|
        doc_id = handle_document(i)
        # IF want to process documents hook here to pass document id to processor jobs
      end unless response.body.blank?
    rescue URI::InvalidURIError => e
      "IU".split("").each {|i| logger.info i} # Swallow
    rescue HTTPClient::ConnectTimeoutError => et
      logger.info "T"
      puts @request_href
    end

    Dispatcher.dispatch_if_necessary
  end

  #
  # Extracts and stores redirect link from http headers
  #
  def handle_redirect(response)
    redirect_href = response.http_header["Location"]
    redirect_href = redirect_href.first unless !redirect_href.is_a? Array
    redirect_href = expand_path(redirect_href)
    store_link('redirect', redirect_href, @link_id)
  end

  #
  # Is the document returned an rss feed or an html document response?
  #
  #   Returns an array of documents to parse.
  #   Can consider breaking html pages into multiple documents here theoretically one day.
  #
  def extract_response_documents(response)
    return [response.body] unless @request_href.match(/\.(atom|rss|xml)$|\.(atom|rss|xml)\?/)

    # RSS Feed case:
    response_bodies = []

    SimpleRSS.parse(response.body).items.each do |i|
      doc = ""
      i.each {|k, v| doc += "#{k} is #{v}. "}
      response_bodies.push doc
    end

    return response_bodies
  end

  #
  #  Extracts and stores links and document from response.
  #
  def handle_document(response_doc)
    doc_content = extract_content(response_doc)
    doc_id = store_document(doc_content, @link_id) unless doc_content.blank? || doc_content.length < 200
    doc = Nokogiri::HTML(response_doc)
    extract_and_store_links(doc)
    extract_and_store_emails(doc)
    extract_and_store_images(doc)
    return doc_id
  end

  private

  #
  # Turns a relative path into an absolute path.  Also deals with some common edge cases like fake hrefs for js.
  #
  def expand_path(href)
    return href if href.match(/^https*:\/\//) # if starts with protocol complete link
    return @request_href unless href.match(/[a-zA-Z0-9]+/) # rejects href="#" and allows non-unique exception handling.
    return @request_href if href.match(/#[a-zA-Z0-9]*$/)

    if href[0, 1] != "/"
      return @request_href + href if @request_href[-1, 1] == "/"
      return @request_href + "/" + href
    else
      # relative path from domain.
      base_url = @request_href.match(BASEURLREG).to_a.first
      return base_url + href unless base_url[-1, 1] == "/"
      return base_url.chop + href
    end
  end

  def store_link(content, href, parent_id)
    begin
      link_insert = "insert into links (content, href, parent_id, domain) values ('#{content.collapse_whitespace.sanitize_pg}', '#{href.collapse_whitespace.downcase.sanitize_pg}', #{parent_id}, '#{Crawler.get_domain(href).to_s.sanitize_pg}')"
      POOL.with { |c| c.insert(link_insert) }

    rescue Java::OrgPostgresqlUtil::PSQLException => e
      raise e unless e.message.include?("violates unique constraint") || e.message.include?("violates check constraint")
    end
  end

  def store_document(content, link_id)
    begin
      if @mark_as_job
        POOL.with { |c| c.insert("insert into docs (content, hashtext, link_id, is_job_label) values ('#{content.sanitize_pg}', '#{Digest::SHA1.hexdigest content}', #{link_id}, true)") }
      else
        POOL.with { |c| c.insert("insert into docs (content, hashtext, link_id) values ('#{content.sanitize_pg}', '#{Digest::SHA1.hexdigest content}', #{link_id})") }
      end
      logger.info 'D'
      return POOL.with { |c| c.query("select max(id) as id from docs where hashtext = '#{Digest::SHA1.hexdigest content}' and link_id = #{link_id}")[0]["id"]}
    rescue Java::OrgPostgresqlUtil::PSQLException => e
      raise e unless e.message.include? "violates unique constraint"
    end
  end

  #
  # Extracts the content from a nokogiri document and returns a string.
  #
  #   Currently uses hueristics.
  def extract_content(response_doc)
    doc = Nokogiri::HTML(response_doc)

    doc.xpath('//javascript').remove
    doc.xpath('//script').remove

    doc.xpath('//head').remove
    doc.xpath('//header').remove
    doc.xpath('//footer').remove
    doc.xpath('//*[contains(@class, "nav")]').remove

    doc.xpath('//*[contains(@class, "head")]').each do |n|
      n.remove unless n["class"].length > 9
    end

    doc.xpath('//*[contains(@class, "foot")]').each do |n|
      n.remove unless n["class"].length > 9
    end

    doc.xpath('//input').remove
    doc.xpath('//button').remove

    doc.xpath('//style').remove

    body = doc.at_css('body')
    body = doc unless !body.blank?

    body.traverse do |node|
      begin
        node_content = node.content.clean
        if node_content.length > 35
          node.content = node_content + (node_content.last == "." ? " " : ". ")
        elsif node.name == "td"
          node.content = node_content + " "
        elsif node_content.to_s.count(" ") < 1
          node.remove
        else
          node.content = node_content + " "
        end
      rescue Java::JavaLang::NullPointerException => e
      rescue NoMethodError => e
        # Swallow error from mutating the document while traversing it.
      end
    end

    return body.content.clean
  end

  def extract_and_store_emails(doc)
    doc.content.scan(EMAILREG).compact.uniq.each do |m|
      POOL.with do |c|
        begin
          c.insert("insert into emails (link_id, address) values (#{@link_id}, '#{m.sanitize_pg}')")
        rescue StandardError => e
          puts e.message.to_s
        end
      end
    end
  end

  def extract_and_store_links(doc)
    links = doc.xpath '//a'

    # TODO bulk insert.  How deal with constraint implications.
    #  currently preprocess relative links, reduce to uniq
    seen_links = []
    links.each do |l|
      href = expand_path(l["href"].to_s)
      store_link(l.content, href, @link_id) if (!seen_links.include?(href) && link_wanted?(href))
      seen_links.push href
    end
  end

  def extract_and_store_images(doc)
    image_nodes = doc.xpath '//img'
    image_nodes.each do |imn|
      image_link = expand_path(imn["src"].to_s).gsub(/\s/, '%20')
      if link_wanted?(image_link) && image_link_wanted?(image_link)
        begin
          POOL.with do |c|
            c.insert("insert into images (link_id, alt, url) values (#{@link_id}, '#{imn["alt"].to_s.sanitize_pg}', '#{image_link.sanitize_pg}')")
          end
        rescue Java::OrgPostgresqlUtil::PSQLException => e
          raise e unless e.message.include? "violates unique constraint"
        rescue StandardError => e
          logger.info "e"
        end
      end
    end

  end

  def ready_to_crawl?(link)
    return false unless (link["visited_at"].blank? || link["visited_at"] < Time.now - 24.hours)
    domain = Crawler.get_domain link["href"]

    ready = false
    SEM.synchronize do # Do not ddos
      last_visit = VISITS[domain]
      if last_visit.blank? || (Time.now - last_visit > 4)
        ready = true
        VISITS[domain] = Time.now
      end
    end
    logger.info "k" unless ready

    return ready
  end

  def link_wanted?(href)
    return false unless !href.match(/mailto:/)
    return false unless !(href.split("#").first == @request_href)
    return false unless !href.match(/#[a-zA-Z0-9]*$/)
    return false unless href.length < 1000
    return false unless Crawler.porn_score(href) < 100
    return false unless !href.match(/itpc:\/\//)
    return true
  end

  def image_link_wanted?(href)
    return false if href.length > 400
    return false if href.scan(/http/).length > 1
    return true
  end

  def self.get_domain(href)
    domain = href.match(DOMAINREG).to_a.first
    pieces = domain.to_s.split(".")
    if pieces.length > 21
      tld = pieces.pop
      toplevel = pieces.pop
      domain = toplevel + "." + tld
    end
    return domain
  end

  # Can't believe I had to write this...
  PORN_WORDS = ['tranny', 'sex', 'xxx', 'slut', 'pussy', 'cock' 'joyourself', 'mycams', 'blowjob', 'handjob', 'vagina', 'penis', ]
  WARM_WORDS = ['girl', 'boy', 'cam', 'xx', 'ass', 'tit', 'porn', 'cum', 'xoxo', 'mature']
  TEPID_WORDS = ['nasty', 'private', 'live', 'hot', 'desire', 'doll']
  def self.porn_score(href)
    score = 0
    dom = Crawler.get_domain(href).to_s.downcase.alphascrub
    PORN_WORDS.each {|i| score += 100 if dom.match /#{i}/ }
    WARM_WORDS.each {|i| score += 50 if dom.match /#{i}/ }
    TEPID_WORDS.each {|i| score += 25 if dom.match /#{i}/ }
    return score
  end
  

end
