class Promiscuous::Subscriber::Worker::Message
  attr_accessor :payload, :parsed_payload

  def initialize(payload, options={})
    self.payload = payload
    @metadata = options[:metadata]
    @root_worker = options[:root_worker]
  end

  def parsed_payload
    @parsed_payload ||= MultiJson.load(payload)
  end

  def context
    parsed_payload['context']
  end

  def app
    parsed_payload['app']
  end

  def timestamp
    parsed_payload['timestamp'].to_i
  end

  def generation
    parsed_payload['generation']
  end

  def dependencies
    @dependencies ||= begin
      dependencies = parsed_payload['dependencies'] || {}
      deps = dependencies['read'].to_a.map  { |dep| Promiscuous::Dependency.parse(dep, :type => :read, :owner => app) } +
             dependencies['write'].to_a.map { |dep| Promiscuous::Dependency.parse(dep, :type => :write, :owner => app) }

      deps
    end
  end

  def write_dependencies
    @write_dependencies ||= dependencies.select(&:write?)
  end

  def read_dependencies
    @read_dependencies ||= dependencies.select(&:read?)
  end

  def happens_before_dependencies
    @happens_before_dependencies ||= begin
      deps = []
      deps += (parsed_payload['dependencies'] || {})['external']
                .to_a.map do |dep|
                  dep =~ /^([^:]+):(.*)$/
                  Promiscuous::Dependency.parse($2, :type => :external, :owner => $1)
                end
      deps += read_dependencies
      deps += write_dependencies

      # We return the most difficult condition to satisfy first
      deps.uniq.reverse
    end
  end

  def has_dependencies?
    dependencies.present?
  end

  def was_during_bootstrap?
    !!parsed_payload['was_during_bootstrap']
  end

  def to_s
    "#{app}/#{context} -> #{parsed_payload['dependencies']}"
  end

  def ack
    time = Time.now
    Promiscuous.debug "[receive] #{payload}"
    @metadata.try(:ack)
    @root_worker.stats.notify_processed_message(self, time) if @root_worker
  rescue Exception => e
    # We don't care if we fail, the message will be redelivered at some point
    Promiscuous.warn "[receive] Some exception happened, but it's okay: #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.call(e)
  end

  def postpone
    # Only used during bootstrapping
    @metadata.postpone
  rescue Exception => e
    # We don't care if we fail
    Promiscuous.warn "[receive] (postpone) Some exception happened, but it's okay: #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.call(e)
  end

  def unit_of_work(type, &block)
    # write_dependencies are given for the publisher context, so that it
    # uses the proper dependencies and versions.
    external_dependencies = write_dependencies.map do |_d|
      _d.dup.tap do |d|
        d.type = :external
        d.version_pass1 = d.version_pass2 + 1
        d.version_pass2 = nil
      end
    end
    chain = block
    if defined?(ActiveRecord)
      chain = lambda { ActiveRecord::Base.transaction { chain.call } }
    end
    Promiscuous.context('subscriber', :extra_dependencies => external_dependencies) { chain.call }
  ensure
    if defined?(ActiveRecord)
      ActiveRecord::Base.clear_active_connections!
    end
  end

  def process
    unit_of_work(context) do
      if Promiscuous::Config.bootstrap
        Promiscuous::Subscriber::MessageProcessor::Bootstrap.process(self)
      else
        Promiscuous::Subscriber::MessageProcessor::Regular.process(self)
      end
    end
  rescue Exception => orig_e
    e = Promiscuous::Error::Subscriber.new(orig_e, :payload => payload)
    Promiscuous.warn "[receive] #{payload} #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.call(e)
  end
end
