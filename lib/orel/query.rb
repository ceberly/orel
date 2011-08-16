module Orel
  class Query
    include Orel::SqlDebugging

    def initialize(klass, heading)
      @klass = klass
      @heading = heading
    end

    def query(description=nil)
      # Setup Arel query engine.
      table = Orel.arel_table(@heading)
      manager = Arel::SelectManager.new(table.engine)
      manager.from table

      # Overlay Orel heading and association information.
      query = Select.new(manager, @heading)
      relation = Relation.new(table, @klass, @heading)

      # Always project the full heading so that we can instantiate
      # fully valid objects.
      @heading.attributes.each { |a| manager.project table[a.name] }

      # Yield to customize the query.
      yield query, relation if block_given?

      # Turn rows into objects.
      objects = []
      execute(manager.to_sql, description || "#{self.class} on #{@klass}").each(:as => :hash, :symbolize_keys => true) { |row|
        object = @klass.new(row)
        # The object is persisited because it came from the databse.
        object.persisted!
        # The object is readonly because it's a complex relation
        object.readonly!
        # The object is locked for query because you should get all
        # of the data you're interested in one shot.
        #object.locked_for_query!
        objects << object
      }
      objects
    end

  protected

    def execute(statement, description=nil)
      begin
        Orel.execute(statement, description)
      rescue StandardError => e
        debug_sql_error(statement)
        raise
      end
    end

    class Select
      def initialize(select_manager, heading)
        @select_manager = select_manager
        @heading = heading
        @joins = {}
      end

      # Public: Specify a condition on the query.
      #
      # condition - An object that can be joined, such as:
      #             Arel::Nodes::Node, as returned by arel_table[:attribute].
      #             Orel::Query::Join as returned by orel_table[Class]
      #
      # Returns nothing.
      def where(condition)
        case condition
        when Join
          _add_join(condition)
          condition.wheres.each { |where| @select_manager.where(where) }
        when Arel::Nodes::Node
          @select_manager.where(condition)
        else
          raise "Unhandled where condition of type #{condition.inspect}"
        end
        nil
      end

      # Public: Specify an association to be included in the result set.
      # Calling this prepopulates the association on the returned
      # objects.
      #
      # join - Orel::Query::Join as returned by
      #        orel_table[Class or :simple_association].
      #
      # Returns nothing.
      def join(join)
        _add_join(join)
        return # no-op for now
        @select_manager.project(*join.attributes) if join.projected?
        nil
      end

    protected

      def _add_join(join)
        unless @joins[join.join_id]
          @select_manager.join(join.join_table).on(*join.join_conditions)
          @joins[join.join_id] = true
        end
      end
    end

    class Relation
      def initialize(table, klass, heading)
        @table = table
        @klass = klass
        @heading = heading
        @simple_associations = SimpleAssociations.new(klass, klass.relation_set)
        @join_id = 0
        @joins = {}
      end

      # Public: Get an attribute or association, with the intent of
      # adding it to the current query.
      #
      # key - Symbol attribute, Class or symbol of simple association.
      #
      # Examples
      #
      #   table_proxy[:name] # => Arel::Nodes::Node
      #   table_proxy[:simple_association] # => Orel::Query::Join
      #   table_proxy[OrelClassReference] # => Orel::Query::Join
      #
      # Returns an object suitable for passing to QueryProxy methods.
      def [](key)
        case key
        when Class
          heading = key.get_heading
          table = Orel.arel_table(heading)
          @joins[heading.name] ||= Join.new(join_id, @klass, @heading, @table, key, heading, table)
        else
          if @simple_associations.include?(key)
            heading = @klass.get_heading(key)
            table = Orel.arel_table(heading)
            @joins[heading.name] ||= Join.new(join_id, @klass, @heading, @table, nil, heading, table)
          else
            @table[key]
          end
        end
      end

    protected

      def join_id
        id = @join_id += 1
        "j#{id}"
      end
    end

    class Join
      def initialize(join_id, klass, heading, table, join_class, join_heading, join_table)
        @join_id = join_id
        @class = klass
        @heading = heading
        @table = table
        @join_class = join_class
        @join_heading = join_heading
        @join_table = join_table
        @wheres = []

        @child_reference = @join_heading.get_parent_reference(@class)
        @parent_reference = @class.get_heading.get_parent_reference(@join_class)
      end

      attr_reader :wheres
      attr_reader :join_table
      attr_reader :join_id

      def attributes
        @join_heading.attributes.map { |a|
          @join_table[a.name].as("#{join_id}__#{a.name}")
        }
      end

      def join_conditions
        case
        when @child_reference
          @heading.get_key(:primary).attributes.map { |a|
            @table[a.name].eq(@join_table[a.to_foreign_key.name])
          }
        when @parent_reference
          @join_heading.get_key(:primary).attributes.map { |a|
            @table[a.to_foreign_key.name].eq(@join_table[a.name])
          }
        else
          raise "No child or parent reference was found for class:#{@class} join:#{@join_class}"
        end
      end

      # Public: Retrieve an attribute from the join table.
      #
      # name - Symbol name of the attribute.
      #
      # Returns a JoinProxy on which to specify conditions of the attribute.
      def [](name)
        JoinCondition.new(self, @join_table[name])
      end

      # Public: Limit the results to objects that have an object as
      # their parent.
      #
      # object - Orel::Object in the parent relationshin the parent
      #          relationship.
      #
      # Returns this Join object.
      def eq(object)
        unless object.is_a?(@join_class)
          raise ArgumentError, "Expected a #{@join_class} but got a #{object.class}"
        end
        case
        when @parent_reference
          @parent_reference.parent_key.attributes.each { |a|
            @wheres << @table[a.name].eq(object[a.to_foreign_key.name])
          }
        when @child_reference
          @child_reference.parent_key.attributes.each { |a|
            @wheres << @table[a.name].eq(object[a.to_foreign_key.name])
          }
        else
          raise ArgumentError, "No reference was found from class:#{@class.inspect} to join:#{@join_class.inspect}"
        end
        self
      end
    end

    class JoinCondition
      def initialize(join, attribute)
        @join = join
        @attribute = attribute
      end

      # Public: Perform an Arel node operation such as `eq`.
      #
      # Returns the underlying Join.
      def method_missing(message, *args)
        @join.wheres << @attribute.__send__(message, *args)
        @join
      end
    end

  end
end
