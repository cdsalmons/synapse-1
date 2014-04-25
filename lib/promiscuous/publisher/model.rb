module Promiscuous::Publisher::Model
  extend Promiscuous::Autoload
  autoload :Base, :ActiveRecord, :Ephemeral, :Mock, :Mongoid, :Cequel

  mattr_accessor :publishers
  self.publishers = {}
end
