#
# Worst part of jruby ... insane and incomplete library support
#
class Java::OrgPostgresqlJdbc4::Jdbc4ResultSet
  
  def to_hash(resultset = self)
    meta = resultset.meta_data
    rows = []

    while resultset.next
      row = {}

      (1..meta.column_count).each do |i|
        name = meta.column_name i
        row[name]  =  case meta.column_type(i)
                      when -6, -5, 5, 4
                        # TINYINT, BIGINT, INTEGER
                        resultset.get_int(i).to_i
                      when 41
                        # Date
                        resultset.get_date(i)
                      when 92
                        # Time
                        resultset.get_time(i).to_i
                      when 93
                        # Timestamp
                        resultset.get_timestamp(i)
                      when 2, 3, 6
                        # NUMERIC, DECIMAL, FLOAT
                        case meta.scale(i)
                        when 0
                          resultset.get_long(i).to_i
                        else
                          BigDecimal.new(resultset.get_string(i).to_s)
                        end
                      when 1, -15, -9, 12
                        # CHAR, NCHAR, NVARCHAR, VARCHAR
                        resultset.get_string(i).to_s
                      else
                        resultset.get_string(i).to_s
                      end
      end

      rows << row
    end
    rows
  end
end

class Java::OrgPostgresqlJdbc4::Jdbc4Connection
  
  def query(q)
    self.createStatement().executeQuery(q).to_hash
  end

  def update(q)
    self.createStatement().executeUpdate(q)
  end

  alias_method :insert, :update
  
end


class String
  
  #
  # A convenience method to clean up the document for insertion to the db
  #
  def sanitize_pg
    self.gsub(/'/, "''")
  end
  
  def collapse_whitespace
    self.gsub(/\s+/, " ").gsub(/[\r|\t]/, " ")
  end

  def remove_tags
    self.gsub(/<[a-zA-Z\/!\.\\\"][^>]*>/, '').strip
  end

  def strip_quotes
    self.gsub(/\"/, "").gsub(/\'/, "")
  end
  
  def alphascrub
    self.gsub(/[^a-zA-Z0-9\.\!\-\?\s\@]/, ' ')
  end
  
  def strip_empty_punctuation
    self.gsub(/[\.\!\?]+\s+[\.\!\?]+/, '. ')
  end

  def clean
    self.remove_tags.strip_quotes.alphascrub.strip_empty_punctuation.collapse_whitespace
  end
  

end



module Sidekiq
  module Logging
    class Pretty

      M = Mutex.new
      
      def initialize
        @workers = []
        @buffer = Array.new(Sidekiq.options[:concurrency]) {' '}
        super
      end
      
      def call(severity, time, program_name, message)
        msg = ""
        add_worker if @workers.index(Thread.current) == nil
        msg = flush_buffer unless @buffer[@workers.index(Thread.current)] == ' '
        
        @buffer[@workers.index(Thread.current)] = case message 
          when /start/ then '*'
          when /done/ then '_'
          else message[0]
        end
  
        return msg
      end
      
      def add_worker
        M.synchronize do
          lazy_worker = @workers.detect {|i| i.stop?}
          if lazy_worker.nil?
            @workers.push Thread.current
          else
            @workers[@workers.index(lazy_worker)] = Thread.current
          end
        end
      end
      
      def flush_buffer
        msg = " " + @buffer.join(" ") + "\n"
        @buffer = Array.new(Sidekiq.options[:concurrency]) {' '}
        return msg
      end
      
    end
  end
end
