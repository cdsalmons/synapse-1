require 'fnv'

class Promiscuous::Dependency
  attr_accessor :orig_key, :internal_key, :version_pass1, :version_pass2, :type, :owner

  def initialize(*args)
    options = args.extract_options!
    @type = options[:type]
    @owner = options[:owner]

    @orig_key = @internal_key = args.join('/')

    if @internal_key =~ /^[0-9]+$/
      @internal_key = @internal_key.to_i
      @hash = @internal_key
    else
      @hash = FNV.new.fnv1a_32(@internal_key)

      if Promiscuous::Config.hash_size.to_i > 0
        # We hash dependencies to have a O(1) memory footprint in Redis.
        # The hashing needs to be deterministic across instances in order to
        # function properly.
        @hash = @hash % Promiscuous::Config.hash_size.to_i
        @internal_key = @hash
      end
    end

    if @owner
      @internal_key = "#{@owner}:#{@internal_key}"
    end
  end

  def read?
    raise "Type not set" unless @type
    @type == :read
  end

  def write?
    raise "Type not set" unless @type
    @type == :write
  end

  def external?
    raise "Type not set" unless @type
    @type == :external
  end

  def key(role, options={})
    k = options[:dont_hash] ? @orig_key : @internal_key
    Promiscuous::Key.new(role).join(k)
  end

  def redis_node(distributed_redis=nil)
    distributed_redis ||= Promiscuous::Redis.master
    distributed_redis.nodes[@hash % distributed_redis.nodes.size]
  end

  def as_json(options={})
    if @version_pass1 && @version_pass2 && !options[:raw]
      if @version_pass1 == @version_pass2
        "#{@internal_key}:#{@version_pass1}"
      else
        "#{@internal_key}:#{@version_pass1}!#{@version_pass2}"
      end
    else
      @internal_key
    end
  end

  def self.parse(payload, options={})
    case payload
    when /^(.+):([0-9]+)!([0-9]+)$/ then new($1, options).tap { |d| d.version_pass1 = $2.to_i; d.version_pass2 = $3.to_i }
    when /^(.+):([0-9]+)$/          then new($1, options).tap { |d| d.version_pass1 = d.version_pass2 = $2.to_i }
    when /^(.+)$/                   then new($1, options)
    end
  end

  def to_s(options={})
    as_json(options).to_s
  end

  # We need the eql? method to function properly (we use ==, uniq, ...) in operation
  # XXX The version is not taken in account.
  def eql?(other)
    other.is_a?(Promiscuous::Dependency) &&
      self.internal_key == other.internal_key
  end
  alias == eql?

  def hash
    self.internal_key.hash
  end
end
