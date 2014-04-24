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
    }[feature].any? { |orm| orm == backend }
  end

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
    if has(:active_record)
      PromiscuousMigration::TABLES.each do |table|
        ActiveRecord::Base.connection.exec_delete("DELETE FROM #{table}", "Cleanup", [])
      end
    end
  end
end
