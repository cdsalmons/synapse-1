module Promiscuous::Subscriber
  extend Promiscuous::Autoload
  autoload :Worker, :MessageProcessor, :Model, :Operation

  extend ActiveSupport::Concern

  included do
    include Model::Mongoid      if defined?(Mongoid::Document)  && self < Mongoid::Document
    include Model::ActiveRecord if defined?(ActiveRecord::Base) && self < ActiveRecord::Base
    include Model::Observer     unless self < Model::Base
  end
end
