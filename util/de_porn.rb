require 'lib/init'
cnt = POOL.with {|c| c.query("select count(*) as cnt from links") }.map {|i| i['cnt']}[0]
0.upto(cnt / 10000) do |i|
  ls = POOL.with {|c| c.query("select id, href from links offset #{10000 * i} limit 10000")}
  to_del = []
  ls.each do |i| 
    l = i['href']
    s = Crawler.porn_score(l)
    if s >= 100
      puts s.to_s + " - " + l.to_s
      to_del.push i['id'] 
    end  
  end
  puts "delete from links where id in ( #{to_del.join(", ")} )"
  POOL.with {|c| c.update("delete from links where id in ( #{to_del.join(", ")} )")} unless to_del.blank?
end
