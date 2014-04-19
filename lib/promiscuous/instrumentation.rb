module Promiscuous::Instrumentation
  def instrument(type, options={}, &block)
    instr_file_name = Promiscuous::Config.instrumentation_file
    return block.call unless instr_file_name

    start_time = Time.now.to_f
    r = block.call
    end_time = Time.now.to_f

    desc = options[:desc]
    desc = instance_eval(&desc) if desc.is_a?(Proc)
    id = "#{Process.pid}-#{Thread.current.object_id}"

    if !options[:if] || options[:if].call
      File.open(instr_file_name, 'a') do |f|
        f.puts "[#{Promiscuous::Config.app} #{id}] #{type} #{start_time}-#{end_time} #{desc}"
      end
    end

    r
  end
end
