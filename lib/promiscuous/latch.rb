module Promiscuous::Latch
  extend self

  def latch_name
    "#{Promiscuous::Config.app}:sub_latch"
  end

  def redis_node
    Promiscuous::Redis.master.nodes.first
  end

  def enable
    redis_node.del("#{latch_name}")
    redis_node.set("#{latch_name}:enabled", 1)
  end

  def disable
    redis_node.del("#{latch_name}:enabled")
  end

  def release(num_messages)
    redis_node.lpush("#{latch_name}", num_messages.times.map { 0 })
  end

  def latch_wait
    return unless Promiscuous::Config.subscriber_latch
    if redis_node.get("#{latch_name}:enabled")
      redis_node.blpop("#{latch_name}")
    end
  end
end
