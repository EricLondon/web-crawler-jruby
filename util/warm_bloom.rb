## Warms up the bloom filter.
require_relative '../lib/init'

BATCH_SIZE = 10000

cnt = POOL.with {|c| c.query("select count(*) as cnt from links where visited_at is not null") }.map {|i| i['cnt']}[0]
0.upto((cnt / BATCH_SIZE) + 1) do |i|
  POOL.with {|c| c.query("select href from links where visited_at is not null limit #{BATCH_SIZE}")}.each do |l|
    BF.insert l['href'].to_s
  end
  print "."; STDOUT.flush
end
