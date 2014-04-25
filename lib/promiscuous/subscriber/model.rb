module Promiscuous::Subscriber::Model
  extend Promiscuous::Autoload
  autoload :Base, :ActiveRecord, :Mongoid, :Observer, :Cequel

  mattr_accessor :mapping
  self.mapping = {}
end
