require 'httpclient'
require 'sidekiq'
require 'jdbc/postgres'
require 'nokogiri'
require 'active_support/core_ext'
require 'ruby-debug'
require 'yaml'
require 'digest/sha1'
require 'simple-rss'
require 'bloomfilter-rb'

require_relative 'monkey_patches'
require_relative 'dispatcher'
require_relative 'crawler'
require_relative 'refiner'

java_import java.sql.DriverManager

CONFIG = YAML.load_file(File.expand_path(File.dirname(__FILE__)) + "/../config/database.yml") unless defined? CONFIG

dburl = "jdbc:postgresql://#{CONFIG['host'] || 'localhost'}/#{CONFIG['database']}"
dbusername = CONFIG["user"] || ""
dbpass = CONFIG["password"] || ""

DriverManager.register_driver(org.postgresql.Driver.new)
POOL = ConnectionPool.new({:size => 10, :timeout => 5}) { DriverManager.get_connection(dburl, dbusername, dbpass) }
SEM = Mutex.new
DISPATCHING = Mutex.new
VISITS = {}
VCOUNT = 0
DOMAIN_SECONDS_RESTRICTION = 7

# This needs to be wired up as optional strategy for de-duping if log(n) index lookups get too extreme.
#BF = BloomFilter::Redis.new(:size => 9000000000, :hashes => 3, :seed => 1359785778)

LINK_BLACK_LIST = Regexp.new /twitter\.com/
