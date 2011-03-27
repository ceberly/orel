module Orel
  module Object

    NoHeadingError = Class.new(StandardError)

    def self.included(base)
      base.extend Orel::Relation
      base.extend ClassMethods
      base.extend ActiveModel::Naming
    end

    module ClassMethods

      # Public: Create and save a new object.
      #
      # Returns an instance of the class this was called on.
      def create(*args)
        object = new(*args)
        object.save
        object
      end
    end

    # Public: Initialize a new object.
    #
    # attributes - A Hash of key/value pairs to use as values on the object.
    #
    def initialize(attributes={})
      @heading = self.class.get_heading
      raise NoHeadingError unless @heading
      @attributes = Attributes.new(@heading, attributes)
      @operator = Operator.new(@heading, @attributes)
      @validator = Validator.new(self, @heading, @attributes)
    end

    attr_reader :attributes

    def id
      if @attributes.att?(:id)
        @attributes[:id]
      else
        super
      end
    end

    # Public: Persist the object's current attributes. If the object has been
    # saved previously, the non-key attributes are updated, else all attributes
    # are stored. If the object defines a Serial key, that attribute will have
    # a value after calling save.
    #
    # Returns nothing.
    def save
      if @operator.persisted?
        @operator.update
      else
        @operator.create
      end
    end

    # Public: Stop persisting this object. If the object has never been persisted,
    # this method has no effect.
    #
    # Returns nothing.
    def destroy
      if @operator.persisted?
        @operator.destroy
      end
    end

    # Public: Determine if a record has been saved.
    #
    # Returns a boolean
    def persisted?
      @operator.persisted?
    end

    # Public: Detemine if the record has been destroyed.
    #
    # Returns a boolean.
    def destroyed?
      @operator.destroyed?
    end

    # Public: Determine whether the record is currently valid.
    #
    # Returns a boolean.
    def valid?
      @validator.valid?
    end

    # Public: Get current validation errors.
    #
    # Returns ActiveModel::Errors.
    def errors
      @validator.errors
    end

    # Public: Convert to ActiveModel.
    #
    # Returns itself.
    def to_model
      self
    end

    # Public: Get an array representing the primary key.
    #
    # Returns an Enumerable or nil.
    def to_key
      if persisted?
        primary_key.attributes.map { |a| @attributes[a.name] }
      else
        nil
      end
    end

    # Public: Get a string representing the primary key.
    #
    # Returns a String or nil.
    def to_param
      if persisted?
        primary_key.attributes.map { |a| @attributes[a.name] }.join(',')
      else
        nil
      end
    end

  protected

    def primary_key
      @heading.get_key(:primary)
    end

    def method_missing(message, *args, &block)
      key, action = @attributes.extract_method_missing(message, args)
      if key && action
        case action
        when :get: @attributes[key]
        when :set: @attributes[key] = args.first
        end
      else
        super
      end
    end

  end
end

