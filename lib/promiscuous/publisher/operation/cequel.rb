require 'cequel'

module Cequel::Record
  def reload
    hydrate(self.class.find(self.id).attributes)
  end
end

module Cql::Client
  module OperationHelpers
    def initialize(options={})
      @query = options[:query]
      parse_query
      super
    end

    def model
      @model ||= Promiscuous::Publisher::Model.publishers[@table_name]
    end

    def get_selector_instance
      model.hydrate(@selector)
    end

    def should_instrument_query?
      super && model
    end

    def recoverable_failure?(exception)
      false # TODO
    end

    def cleanup_value(str)
      str[0] == "'" && str[-1] == "'" ? str[1..-2] : str
    end

    def parse_selector(key, value)
      {key => cleanup_value(value)}
    end

    def extract_attributes_1(fields_str, values_str)
      # TODO We should parse this better, if "," is in a value, we are dead
      fields = fields_str.split(',').map(&:strip)
      values = values_str.split(',').map(&:strip).map { |s| cleanup_value(s) }
      Hash[fields.zip(values)]
    end

    def extract_attributes_2(fields_str)
      Hash[fields_str.split(',').map do |f|
        f.split(' = ').map(&:strip).map { |s| cleanup_value(s) }
      end]
    end
  end

  class InsertOperation < Promiscuous::Publisher::Operation::Atomic
    include OperationHelpers

    def parse_query
      case @query
      when /^INSERT INTO ([^\s]+) \(([^)]+)\) VALUES \(([^)]+)\)\s*$/
        @operation = :create
        @table_name = $1
        @attributes = extract_attributes_1($2, $3)
      else raise "Invalid query: #{@query}"
      end
    end

    def execute_instrumented(query)
      @instance = model.hydrate(@attributes)
      super
    end

    def recovery_payload
      super # TODO
    end

    def self.recover_operation(collection, instance_id)
      super # TODO
    end

    def recover_db_operation
      super # TODO
    end
  end

  class UpdateOperation < Promiscuous::Publisher::Operation::Atomic
    include OperationHelpers

    def parse_query
      case @query
      when /^UPDATE ([^\s]+) SET (.+) WHERE ([^\s]+) = ([^\s]+)\s*$/
        @operation = :update
        @table_name = $1
        @attributes = extract_attributes_2($2)
        @selector = parse_selector($3, $4)
        raise "OOPS" unless @selector.keys == ['id']
      when /^DELETE FROM ([^\s]+) WHERE ([^\s]+) = ([^\s]+)\s*$/
        @operation = :destroy
        @table_name = $1
        @selector = parse_selector($2, $3)
        raise "OOPS" unless @selector.keys == ['id']
      else raise "Invalid query: #{@query}"
      end
    end

    def execute_instrumented(query, &block)
      # We are trying to be optimistic for the locking. We are trying to figure
      # out our dependencies with the selector upfront to avoid an extra read
      # from reload_instance.
      @instance ||= get_selector_instance unless recovering?
      super
    end

    def fetch_instance
      without_promiscuous { model.find(@selector['id']) }
    end

    def any_published_field_changed?
      (@attributes.keys.map(&:to_sym) & model.published_db_fields).present?
    end

    def should_instrument_query?
      super && model && (@operation == :destroy || any_published_field_changed?)
    end

    def increment_version_in_document
      super # TODO
    end

    def use_id_selector(options={})
      super # TODO
    end

    def recovery_payload
      super # TODO
    end

    def self.recover_operation(collection, instance_id)
      super # TODO
    end

    def recover_db_operation
      super # TODO
    end
  end

  class SelectOperation < Promiscuous::Publisher::Operation::NonPersistent
    include OperationHelpers

    def parse_query
      case @query
      when /^SELECT ([^\s]+) FROM ([^\s]+) .* ?WHERE ([^\s]+) = ([^\s]+)/
        @operation = :read
        @fields = $1
        @table_name = $2
        @selector = parse_selector($3, $4)
      when /^SELECT ([^\s]+) FROM ([^\s]+)/
        @operation = :read
        @fields = $1
        @table_name = $2
      else raise "Invalid query: #{@query}"
      end
    end

    def query_dependencies
      return super unless @selector
      deps = dependencies_for(get_selector_instance)
      deps.empty? ? super : deps
    end

    def execute_instrumented(db_operation)
      super
      unless db_operation.failed?
        @instances = db_operation.result.value.map do |row|
          r = Cequel::Metal::Row.from_result_row(row)
          model.hydrate(r)
        end
      end
    end
  end

  class AsynchronousClient
    alias_method :execute_orig, :execute

    def execute(cql, options_or_consistency=nil)
      op = case cql
           when /^INSERT INTO / then InsertOperation.new(:query => cql)
           when /^UPDATE /      then UpdateOperation.new(:query => cql)
           when /^DELETE FROM / then UpdateOperation.new(:query => cql)
           when /^SELECT /      then SelectOperation.new(:query => cql)
           end
      # fetching the value makes our request synchronous, not optional.
      op ? op.execute { execute_orig(cql, options_or_consistency).tap { |r| r.value } } :
                        execute_orig(cql, options_or_consistency)
    end
  end
end
