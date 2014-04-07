class Promiscuous::Error::Subscriber < Promiscuous::Error::Base
  attr_accessor :inner, :payload

  def initialize(inner, options={})
    super(nil)
    set_backtrace(inner.backtrace)
    self.inner = inner
    self.payload = options[:payload]
  end

  def message
    "#{inner.class}: #{inner.message}"
  end

  alias to_s message
end
