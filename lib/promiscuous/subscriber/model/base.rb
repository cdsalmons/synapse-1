module Promiscuous::Subscriber::Model::Base
  extend ActiveSupport::Concern

  def __promiscuous_eventual_consistency_update(operation)
    return true unless Promiscuous::Config.consistency == :eventual
    return true unless operation.message.has_dependencies?
    return true unless self.respond_to?(:attributes) && self.respond_to?(:write_attribute)

    version = operation.message_processor.instance_dep.version_pass2
    generation = operation.message.generation
    version = (generation << 50) | version

    if self.attributes[Promiscuous::Config.version_field].to_i <= version
      self.write_attribute(Promiscuous::Config.version_field, version)
      true
    else
      Promiscuous.debug "[receive] out of order message #{self.class}/#{id}/g:#{generation},v:#{version}"
      false
    end
  end

  def __promiscuous_update(payload, options={})
    payload.routed_attributes.map(&:to_s).each do |attr|
      unless payload.attributes.has_key?(attr)
        "Attribute '#{attr}' is missing from the payload".tap do |error_msg|
          Promiscuous.warn "[receive] #{error_msg}"
          raise error_msg
        end
      end

      value = payload.attributes[attr]
      update = true

      attr_payload = Promiscuous::Subscriber::Operation::Regular.new(value)
      if model = attr_payload.model
        # Nested subscriber
        old_value =  __send__(attr)
        instance = old_value || model.__promiscuous_fetch_new(attr_payload.id)

        if instance.class != model
          # Because of the nasty trick with 'promiscuous_embedded_many'
          instance = model.__promiscuous_fetch_new(attr_payload.id)
        end

        nested_options = {:parent => self, :old_value => old_value}
        update = instance.__promiscuous_update(attr_payload, nested_options)
        value = instance
      end

      self.__send__("#{attr}=", value) if update
      true
    end
  end

  included do
    class_attribute :promiscuous_root_class, :subscribe_foreign_key
    self.promiscuous_root_class = self
    self.subscribe_foreign_key = :id
  end

  module ClassMethods
    def subscribe(*args)
      options    = args.extract_options!
      attributes = args

      # TODO reject invalid options

      self.subscribe_foreign_key = options[:foreign_key] if options[:foreign_key]
      register_klass(options.merge(:attributes => attributes))
    end

    def register_klass(options={})
      from = options[:from].try(:to_s)
      raise "You must specify the publisher with :from" unless from
      attributes = options[:attributes]

      Promiscuous::Subscriber::Model.mapping[from] ||= {}
      ([self] + descendants).each do |klass|
        as = options[:as].try(:to_s) || klass.name
        defs = Promiscuous::Subscriber::Model.mapping[from]
        defs[as] ||= {:attributes => []}
        defs[as][:model] = self
        defs[as][:attributes] += attributes
        defs[as][:parent_collection] = options[:parent_collection] if options[:parent_collection]
      end
    end

    def inherited(subclass)
      super

      Promiscuous::Subscriber::Model.mapping.each do |from, _as|
        new_mapping = {}
        _as.each do |as, defs|
          if defs[:model] == self && as == self.name
            new_mapping[subclass.name] = defs.merge(:model => subclass)
          end
        end
        _as.merge!(new_mapping)
      end
    end

    class None; end
    def __promiscuous_missing_record_exception
      None
    end

    def __promiscuous_fetch_new(id)
      new.tap { |m| m.__send__("#{subscribe_foreign_key}=", id) }
    end
  end
end
