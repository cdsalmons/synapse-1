class Promiscuous::Publisher::Operation::NonPersistent < Promiscuous::Publisher::Operation::Base
  # XXX As opposed to atomic operations, NonPersistent operations deals with an
  # array of instances
  attr_accessor :instances

  def initialize(options={})
    super
    @instances = options[:instances].to_a
  end

  def execute_instrumented(db_operation)
    db_operation.call_and_remember_result(:instrumented)

    unless db_operation.failed?
      current_context.read_operations << self if read?
      trace_operation
    end
  end

  def operation_payloads
    return [] if self.failed?
    @instances.map { |instance| payload_for(instance) }
  end

  def query_dependencies
    @instances.map { |instance| dependencies_for(instance) }
  end
end
