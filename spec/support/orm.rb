module ORM
  def self.backend
    @backend ||= ENV['TEST_ENV'].gsub(/_(mysql|oracle)/, '').gsub(/[0-9]/, '').to_sym
  end

  def self.has(feature)
    {
      :active_record           => [:active_record],
      :transaction             => [:active_record],
      :mongoid                 => [:mongoid],
      :polymorphic             => [:mongoid],
      :embedded_documents      => [:mongoid],
      :many_embedded_documents => [:mongoid],
      :versioning              => [:mongoid],
      :find_and_modify         => [:mongoid],
      :uniqueness              => [:active_record, :mongoid],
      :sum                     => [:active_record, :mongoid],
      :cequel                  => [:cequel],
    }[feature].any? { |orm| orm == backend }
  end

  class << self; alias has? has; end


  if has(:mongoid)
    #Operation = Promiscuous::Publisher::Model::Mongoid::Operation
    ID = :_id
  elsif has(:active_record)
    #Operation = Promiscuous::Publisher::Operation
    ID = :id
  end

  def self.generate_id
    if has(:mongoid)
      BSON::ObjectId.new
    else
      @ar_id ||= 10
      @ar_id += 1
      @ar_id
    end
  end

  def self.purge!
    Mongoid.purge! if has(:mongoid)
  end
end
