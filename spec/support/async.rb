module AsyncHelper
  extend self

  def eventually(options = {})
    timeout = options[:timeout] || ENV['TIMEOUT'].try(:to_f) || 2
    interval = options[:interval] || 0.1
    time_limit = Time.now + timeout
    loop do
      begin
        yield
      rescue => error
      end
      return if error.nil?
      raise error if Time.now >= time_limit
      sleep interval.to_f
    end
  end

  def wait_for_rabbit_publish
    done = false
    Promiscuous::Redis::Async.enqueue_work_for(Promiscuous::AMQP) do
      done = true
    end
    sleep 0.01 until done
  end
end

class Promiscuous::AMQP::Fake
  alias_method :get_next_message_orig, :get_next_message
  def get_next_message
    AsyncHelper.wait_for_rabbit_publish
    get_next_message_orig
  end
end
