module Orel
  module Relation

    ForeignKeyTranslationError = Class.new(StandardError)

    def self.extended(klass)
      Orel.classes << klass
    end

    def arel(sub_name=nil)
      Arel::Table.new(relation_name(sub_name))
    end

    def database
      @database ||= Database.new
    end

    alias_method :orel, :database

    # Public: Get the name of this relation.
    #
    # sub_name - Symbol name of the sub-relation (default: get the base relation).
    #
    # Returns a String.
    def relation_name(sub_name=nil)
      [self.name.underscore, sub_name].compact.join("_")
    end

    # Public: Get the heading of this relation.
    # sub_name - Symbol name of the sub-relation (default: get the base relation).
    #
    # Returns an Orel::Relation::Heading or nil.
    def get_heading(sub_name=nil)
      name = relation_name(sub_name)
      database.headings.find { |h| h.name == name }
    end

    # Top level DSL.

    def heading(sub_name=nil, &block)
      name = relation_name(sub_name)
      heading = Heading.new(name, sub_name.nil?)
      # Automatically add a foreign key to the base relation
      unless heading.base?
        local_heading = get_heading or raise "Missing base relation!"
        foreign_key = ForeignKey.create(local_heading, :primary, heading)
        # Add a key for the foreign key.
        heading.keys << foreign_key.local_key
        # Add the foreign key to the database.
        database.foreign_keys << foreign_key
      end
      HeadingDSL.new(self, heading, database, block)
      database.headings << heading
    end

    # Supporting classes

    # A database contains many relations, but we just
    # track the headings that define those relations.
    # We also maintain a set of relationships between
    # those relations in the form of foreign keys.
    class Database
      def initialize
        @headings = []
        @foreign_keys = []
      end
      attr_reader :headings
      attr_reader :foreign_keys
    end

    # A heading defines the attributes in a relation.
    # It includes 0 or more attributes and may also
    # group those attributes into keys. It may also
    # maintain a set of foreign keys that reference
    # other headings.
    class Heading
      def initialize(name, base)
        @name = name
        @base = base
        @attributes = []
        @keys = []
      end
      attr_reader :name
      attr_reader :base
      alias_method :base?, :base
      attr_reader :attributes
      attr_reader :keys
    end

    # An attribute describes a field in a relation. It
    # has a name and is further defined by its domain.
    class Attribute
      def initialize(name, domain)
        @name = name
        @domain = domain
      end
      attr_reader :name
      attr_reader :domain
      def for_foreign_key(relation_name)
        unless domain.respond_to?(:for_foreign_key)
          raise ForeignKeyTranslationError, "#{domain.inspect} does not support foreign keys. It must define `for_foreign_key`."
        end
        # TODO: expose this naming assumption in a better way. It
        # should probably be an option to this method and be controller
        # by the DSL.
        if name == :id
          fk_name = [relation_name, name].join("_")
        else
          fk_name = name
        end
        fk_domain = domain.for_foreign_key
        self.class.new(fk_name, fk_domain)
      end
    end

    # A key is a set of 0 or more attributes that defines
    # a uniqueness constraint.
    class Key
      def initialize(name, options={})
        @name = name
        @attributes = []
        @references = options.delete(:references)

        # Validate options keys.
        raise ArgumentError, "Unknown options: #{options.keys.inspect}" unless options.empty?

        # Validate options values.
        if @references
          raise ArgumentError, ":references must be a String" unless @references.is_a?(String)
        end
      end
      attr_reader :name
      attr_reader :attributes
      def for_foreign_key(relation_name)
        fk_name = [relation_name, name].join("_")
        foreign_key = self.class.new(fk_name)
        attributes.each { |attribute|
          begin
            foreign_key.attributes << attribute.for_foreign_key(relation_name)
          rescue ForeignKeyTranslationError => e
            raise "Cannot convert key #{name} to a foreign key. #{e.message}"
          end
        }
        foreign_key
      end
    end

    class ForeignKey

      def self.create(local_heading, local_key_name, remote_heading)
        local_name = local_heading.name

        # Find the local key by name.
        local_key = local_heading.keys.find { |k| k.name == local_key_name } or raise "Missing key #{local_key_name.inspect } in #{local_name.inspect}"

        # Add all attributes in the local key to the remote heading.
        remote_heading.attributes.concat local_key.attributes.map { |a| a.for_foreign_key(local_name) }

        # Convert the local heading's key into a key for the remote heading.
        remote_key = local_key.for_foreign_key(local_name)

        # Create the foreign key.
        self.new(remote_heading, local_heading, remote_key, local_key)
      end

      def initialize(local_heading, foreign_heading, local_key, foreign_key)
        @local_heading = local_heading
        @foreign_heading = foreign_heading
        @local_key = local_key
        @foreign_key = foreign_key
      end
      attr_reader :local_heading
      attr_reader :foreign_heading
      attr_reader :local_key
      attr_reader :foreign_key
    end

    # This is the DSL that is used to build up a set of relations.
    class HeadingDSL
      def initialize(klass, heading, database, block)
        @klass = klass
        @attributes = []
        @keys = {}
        @references = []
        instance_eval(&block)
        @attributes.each { |a| heading.attributes << a }
        @keys.values.each { |k| heading.keys << k }
        @references.each { |ref| database.foreign_keys << ref }
      end
      def key(name, domain)
        @keys[:primary] ||= Key.new(:primary)
        @keys[:primary].attributes << att(name, domain)
      end
      def att(name, domain)
        attribute = Attribute.new(name, domain.new)
        @attributes << attribute
        attribute
      end
      def ref(klass)
        # TODO: allow references to non-primary keys
        @references << Reference.new(klass, :primary, @klass)
      end
    end

    class Reference < Struct.new(:local_class, :key_name, :remote_class)
      def to_foreign_key
        local_heading = local_class.get_heading or raise "Missing heading for #{local_class}"
        remote_heading = remote_class.get_heading or raise "Missing heading for #{remote_class}"
        ForeignKey.create(local_heading, key_name, remote_heading)
      end
    end

  end
end