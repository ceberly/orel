require 'orel'
require 'active_record'
require 'mysql2'

Arel::Table.engine = ActiveRecord::Base

ActiveRecord::Base.establish_connection(
  :adapter => 'mysql2',
  :database => 'orel_test',
  :username => 'root',
  :password => ''
)

class ActiveRecord::ConnectionAdapters::Mysql2Adapter
  def primary_keys(table) #:nodoc:
    keys = []
    result = execute("describe #{quote_table_name(table)}")
    result.each do |h|
      #keys << h["Field"] if h["Key"] == "PRI"
      keys << h[0] if h[3] == "PRI"
    end
    #result.free
    keys
  end
end

module Arel
  class Table
    def primary_keys
      @primary_keys ||= begin
        primary_key_names = @engine.connection.primary_keys(name)
        primary_key_names.map { |k| self[k] }
      end
    end
  end
end