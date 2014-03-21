module Promiscuous::Decorator
  extend Promiscuous::Autoload
  extend ActiveSupport::Concern

  include Promiscuous::Subscriber
  include Promiscuous::Publisher

  mattr_accessor :mapping
  self.mapping = {}

  def self._get_parent_publishers(klass)
    pubs = []
    Promiscuous::Subscriber::Model.mapping.each do |from, _as|
      _as.each do |as, defs|
        if defs[:model] == klass
          parent_defs = Promiscuous::Subscriber::Model.mapping[from].select do |_, _defs|
            _defs[:model] == klass.promiscuous_root_class
          end.first
          parent_defs = parent_defs.last.merge(:as => parent_defs.first)

          parent_collection = parent_defs[:parent_collection] ||
                              parent_defs[:as].pluralize.underscore ||
                              klass.promiscuous_collection_name

          pubs << {:from => from, :as => as, :collection_name => parent_collection }
        end
      end
    end
    pubs.uniq
  end

  def self.get_parent_publishers(klass)
    self.mapping[klass] ||= _get_parent_publishers(klass)
  end

  included do
    publish

    Class.new(const_get(:PromiscuousMethods)) do
      def external_dependencies
        return [] unless @instance.id

        Promiscuous::Decorator.get_parent_publishers(@instance.class).map do |pub|
          Promiscuous::Dependency.new(pub[:collection_name], 'id', @instance.id,
                                      :owner => pub[:from], :type => :external)
        end
      end
    end.tap { |klass| const_set(:PromiscuousMethods, klass) }
  end
end
