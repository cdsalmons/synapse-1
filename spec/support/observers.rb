module ObserversHelper
  def load_observers
    define_constant :ModelObserver do
      include Promiscuous::Subscriber::Model::Observer
      subscribe :field_1, :field_2, :field_3, :as => :PublisherModel, :from => :test
    end
  end
end
