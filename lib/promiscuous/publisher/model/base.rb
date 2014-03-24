module Promiscuous::Publisher::Model::Base
  extend ActiveSupport::Concern

  included do
    class_attribute :published_attrs, :tracked_attrs
    cattr_accessor  :published_db_fields, :promiscuous_root_class # There is one on each root class, none on the subclasses
    self.published_attrs = []
    self.tracked_attrs = []
    self.published_db_fields = []
    self.promiscuous_root_class = self
    track_dependencies_of :id
    Promiscuous::Publisher::Model.publishers[self.promiscuous_collection_name] = self
  end

  module PromiscuousMethodsBase
    def initialize(instance)
      @instance = instance
    end

    def payload(options={})
      msg = {}
      msg[:types] = @instance.class.ancestors.select { |a| a < Promiscuous::Publisher::Model::Base }.map(&:publish_as)
      msg[:id]    = @instance.id.to_s
      unless options[:with_attributes] == false
        # promiscuous_payload is useful to implement relays
        msg[:attributes] = @instance.respond_to?(:promiscuous_payload) ? @instance.promiscuous_payload :
                                                                         self.attributes
      end
      msg
    end

    def attributes
      Hash[@instance.class.published_attrs.map { |attr| [attr, self.attribute(attr)] }]
    end

    def attribute(attr)
      value = @instance.__send__(attr)
      value = value.promiscuous.payload if value.respond_to?(:promiscuous)
      value
    end

    def get_dependency(attr, value)
      return nil unless value
      @collection ||= @instance.class.promiscuous_collection_name
      Promiscuous::Dependency.new(@collection, attr, value)
    end

    def tracked_dependencies(options={})
      # FIXME This is not sufficient, we need to consider the previous and next
      # values in case of an update.
      # Note that the caller expect the id dependency to come first
      @instance.class.tracked_attrs.map do |attr|
        begin
          [attr, @instance.__send__(attr)]
        rescue Exception => e
          # Don't care about missing attributes for read dependencies.
          raise e unless options[:allow_missing_attributes] && e.is_a?(ActiveModel::MissingAttributeError)
        end
      end
      .map { |attr, value| get_dependency(attr, value) }
      .compact
    end

    def external_dependencies
      # Overriden by lib/promiscuous/decorator.rb
      []
    end
  end

  class PromiscuousMethods
    include Promiscuous::Publisher::Model::Base::PromiscuousMethodsBase
  end

  def promiscuous
    # XXX Not thread safe
    @promiscuous ||= self.class.const_get(:PromiscuousMethods).new(self)
  end

  def valid?(*args)
    # Validations are not dependencies
    # TODO we should yell if the user is trying to write
    without_promiscuous { super }
  end

  module ClassMethods
    # all methods are virtual

    def publish(*args, &block)
      options    = args.extract_options!
      attributes = args.map(&:to_sym)

      # TODO reject invalid options

      @publish_as = options[:as].to_s if options[:as]

      ([self] + descendants).each do |klass|
        # When the user passes :use => [:f1, :f2] for example, operation/mongoid.rb
        # can track f1 and f2 as fields important for the publishing.
        # It's important for virtual attributes. The published_db_fields is global
        # for the entire subclass tree.
        klass.published_db_fields |= [options[:use]].flatten.map(&:to_sym) if options[:use]
        klass.published_db_fields |= attributes # aliased fields are resolved later
        klass.published_attrs     |= attributes
      end


      begin
        @in_publish_block = @in_publish_block.to_i + 1
        block.call if block
      ensure
        @in_publish_block -= 1
      end
    end

    def in_publish_block?
      @in_publish_block.to_i > 0
    end

    def track_dependencies_of(*attributes)
      ([self] + descendants).each { |klass| klass.tracked_attrs |= attributes.map(&:to_sym) }
    end

    def promiscuous_collection_name
      self.name.pluralize.underscore
    end

    def get_operation_class_for(operation)
      Promiscuous::Publisher::Operation::Base
    end

    def publish_as
      @publish_as || name
    end

    def inherited(subclass)
      super
      subclass.published_attrs = self.published_attrs.dup
      subclass.tracked_attrs   = self.tracked_attrs.dup
      # no copy for published_db_fields
    end
  end
end
