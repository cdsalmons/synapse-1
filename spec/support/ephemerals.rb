module EphemeralsHelper
  def load_ephemerals
    define_constant :ModelEphemeral  do
      include Promiscuous::Publisher::Model::Ephemeral
      publish :field_1, :field_2, :field_3, :as => :PublisherModel
    end
  end
end
