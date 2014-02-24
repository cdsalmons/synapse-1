class Promiscuous::Redis::Async
  class << self
    attr_accessor :mutex, :queues
  end

  self.mutex = Mutex.new
  self.queues = {}

  def self.enqueue_work_for(node, &block)
    Future.new(block).tap { |f| get_queue_for(node) << f }
  end

  def self.get_queue_for(node)
    mutex.synchronize do
      queues[node] ||= Queue.new.tap { |q| Thread.new { main_loop(q) } }
    end
  end

  def self.main_loop(queue)
    loop { queue.pop.process }
  rescue Exception => e
    Promiscuous.warn "[async] #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.call(e)
  end

  class Future
    def initialize(block)
      @processed = false
      @block = block

      @mutex = Mutex.new
      @cond = ConditionVariable.new
    end

    def process
      begin
        @value = @block.call
      rescue Exception => e
        @value = e
      end
      @block = nil
      @processed = true
      @mutex.synchronize { @cond.broadcast }
    end

    def wait_for_value
      @mutex.synchronize do
        loop do
          return if @processed
          @cond.wait(@mutex)
        end
      end
    end

    def value
      wait_for_value
      @value.is_a?(Exception) ? raise(@value) : @value
    end
  end
end
