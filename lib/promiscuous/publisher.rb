module Promiscuous::Publisher
  extend Promiscuous::Autoload
  autoload :Model, :Operation, :MockGenerator, :Context, :Worker, :Bootstrap

  extend ActiveSupport::Concern

  included do
    include Model::Mongoid      if defined?(Mongoid::Document)  && self < Mongoid::Document
    include Model::ActiveRecord if defined?(ActiveRecord::Base) && self < ActiveRecord::Base
    include Model::Ephemeral    unless self < Model::Base
  end
end
