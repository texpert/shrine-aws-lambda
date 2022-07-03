# frozen_string_literal: true

module UploadersHelpers
  def s3(bucket: nil, **options)
    Shrine::Storage::S3.new(bucket: bucket, stub_responses: true, **options)
  end

  def configure_uploader_class(uploader)
    uploader.plugin :activerecord
    uploader.plugin :backgrounding
    uploader.plugin :aws_lambda, settings

    uploader::Attacher.promote do |data|
      uploader::Attacher.lambda_process(data)
    end

    Shrine.storages[:store] = s3(bucket: 'store')
    Shrine.storages[:cache] = s3(bucket: 'cache')
    Shrine.opts[:lambda_function_list] = ['ImageResizeOnDemand']
    uploader.storages[:store] = s3(bucket: 'store')
    uploader.storages[:cache] = s3(bucket: 'cache')

    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    ActiveRecord::Base.connection.create_table(:users) do |t|
      t.string :name
      t.text :avatar_data
    end
    ActiveRecord::Base.raise_in_transactional_callbacks = true if ActiveRecord.version < Gem::Version.new('5.0.0')
  end
end
