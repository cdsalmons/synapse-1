require 'redis'
require 'redis/distributed'

module Promiscuous::Redis
  extend Promiscuous::Autoload
  autoload :Mutex, :Script, :Async

  def self.connect
    disconnect
    @master = new_connection
  end

  def self.master
    ensure_connected unless @master
    @master
  end

  def self.slave
    ensure_connected unless @slave
    @slave
  end

  def self.ensure_slave
    # ensure_slave is called on the first publisher declaration.
    if Promiscuous::Config.redis_slave_url
      self.slave = new_connection(Promiscuous::Config.redis_slave_url)
    end
  end

  def self.disconnect
    @master.quit if @master
    @slave.quit  if @slave
    @master = nil
    @slave  = nil
  end

  def self.new_connection(url=nil)
    url ||= Promiscuous::Config.redis_urls
    redis = ::Redis::Distributed.new(url, :tcp_keepalive => 60)

    redis.info.each do |info|
      version = info['redis_version']
      unless Gem::Version.new(version) >= Gem::Version.new('2.6.0')
        raise "You are using Redis #{version}. Please use Redis 2.6.0 or later."
      end
    end

    redis
  end

  def self.new_blocking_connection
    # This removes the read/select loop in redis, it's weird and unecessary when
    # blocking on the connection.
    new_connection.tap do |redis|
      redis.nodes.each do |node|
        node.client.connection.instance_eval do
          @sock.instance_eval do
            def _read_from_socket(nbytes)
              readpartial(nbytes)
            end
          end
        end
      end
    end
  end

  def self.ensure_connected
    Promiscuous.ensure_connected

    @master.nodes.each do |node|
      begin
        node.ping
      rescue Exception => e
        raise lost_connection_exception(node, :inner => e)
      end
    end
  end

  def self.lost_connection_exception(node, options={})
    Promiscuous::Error::Connection.new("redis://#{node.location}", options)
  end
end
