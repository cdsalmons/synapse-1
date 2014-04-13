module Promiscuous::Instrumentation
  singleton_class.send(:attr_accessor, :log_times)
  self.log_times = ENV['LOG_TIMES']

  def instrument(type, options={}, &block)
    log_times = Promiscuous::Instrumentation.log_times

    return block.call unless log_times

    start_time = Time.now.to_f
    r = block.call
    end_time = Time.now.to_f

    desc = options[:desc]
    desc = instance_eval(&desc) if desc.is_a?(Proc)
    id = "#{Process.pid}-#{Thread.current.object_id}"

    File.open(log_times, 'a') do |log_file|
      log_file.puts "[#{Promiscuous::Config.app} #{id}] #{type} #{start_time}-#{end_time} #{desc}"
    end

    r
  end
end
