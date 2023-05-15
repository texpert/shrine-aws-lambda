# frozen_string_literal: true

require 'spec_helper'

require 'active_record'
require 'shrine'
require 'shrine/plugins/activerecord'
require 'shrine/plugins/instrumentation'
require 'shrine/storage/s3'
require 'shrine/plugins/aws_lambda'

class LambdaUploader < Shrine
  plugin :versions

  def lambda_process_versions(io, context)
    assembly = { function: 'ImageResizeOnDemand' } # Here the AWS Lambda function name is specified

    # Check if the original file format is a image format supported by the Sharp.js library
    if %w[image/gif image/jpeg image/png image/tiff image/webm].include?(io&.data&.dig('metadata', 'mime_type'))
      case context[:name]
        when :avatar
          assembly[:versions] =
            [{ name: :size40, storage: :store, width: 40, height: 40, format: :jpg }]
      end
    end
    assembly
  end
end

RSpec.describe Shrine::Plugins::AwsLambda do
  let(:filename) { 'some_file.png' }
  let(:shrine) { Class.new(Shrine) }
  let(:settings) { Shrine::Plugins::AwsLambda::SETTINGS.dup }
  let(:user) { user_class.new }
  let(:user_class) do
    user_class = Object.const_set(:User, Class.new(ActiveRecord::Base))
    user_class.table_name = :users
    user_class
  end

  describe '#configure' do
    context 'when a known option is passed' do
      before { shrine.plugin :aws_lambda, settings }

      it "sets the received options as uploader's options" do
        expect(shrine.opts).to include(settings)
      end

      it 'set the backgrounding_promote option to uploader' do
        expect(shrine.opts[:backgrounding_promote].inspect)
          .to include('shrine-aws-lambda/lib/shrine/plugins/aws_lambda.rb:')
      end
    end

    context 'when an option with an unknown key is passed' do
      let(:option) { { callback_url: 'some_url', unknown_key: 'some value' } }

      context 'when Shrine logger is enabled' do
        it 'logs the unsupported options' do
          shrine.plugin :instrumentation

          expect_logged("The :unknown_key option is not supported by the Lambda plugin\n", shrine) do
            shrine.plugin :aws_lambda, option
          end
        end
      end

      context 'when Shrine logger is not enabled' do
        it "doesn't log the unsupported options" do
          expect_logged(nil) { shrine.plugin :aws_lambda, option }
        end
      end
    end

    context 'when a required option is not passed' do
      let(:option) { { access_key_id: 'some value' } }

      it 'raise error' do
        expect { shrine.plugin :aws_lambda, option }
          .to raise_exception(Shrine::Plugins::AwsLambda::Error,
                              'The :callback_url option is required for Lambda plugin')
      end
    end
  end

  describe '#load_dependencies' do
    context 'when the plugin is registered' do
      before { allow(shrine).to receive(:plugin).with(:aws_lambda, settings).and_call_original }

      after { shrine.plugin :aws_lambda, settings }

      it 'is loading its dependencies via load_dependencies class method' do
        expect(described_class).to receive(:load_dependencies).with(shrine, settings)
      end

      it "is registering its dependencies via Shrine's plugin method" do
        expect(shrine).to receive(:plugin).with(:aws_lambda, settings)
        expect(shrine).to receive(:plugin).with(:backgrounding)
      end
    end
  end

  describe 'AttacherClassMethods' do
    before do
      configure_uploader_class(Shrine)
      user_class.include shrine.attachment(:avatar)
    end

    after do
      ActiveRecord::Base.remove_connection
      Object.__send__(:remove_const, 'User')
    end

    describe '#lambda_process' do
      context 'when saving user with an attached avatar, the Attacher class method lambda_process is called' do
        it 'retrieves the attacher and calls lambda_process on the attacher instance' do
          user.avatar = FakeIO.new('file', filename: filename)
          file_data = user.avatar

          allow(Shrine::Attacher).to receive(:lambda_process).and_call_original
          allow(Shrine::Attacher).to receive(:retrieve).and_call_original

          expect(Shrine::Attacher)
            .to receive(:lambda_process).with(
              'Shrine::Attacher', 'User', 1, :avatar, { 'id' => file_data.id, 'storage' => file_data.storage_key.to_s }
            )
          expect(Shrine::Attacher).to receive(:retrieve)
          expect_any_instance_of(Shrine::Attacher).to receive(:lambda_process)

          user.save!
        end
      end

      context 'when saving user with no attached avatar' do
        it 'the Attacher class method lambda_process is not called' do
          allow(Shrine::Attacher).to receive(:lambda_process).and_call_original

          expect(Shrine::Attacher).not_to receive(:lambda_process)

          user.save!
        end
      end
    end

    describe '#lambda_authorize' do
      let(:headers) { JSON.parse(File.read("#{RSPEC_ROOT}/fixtures/event_headers.json")) }
      let(:body) { File.read("#{RSPEC_ROOT}/fixtures/event_body.txt") }
      let(:auth_header) do
        { 'Credential'    => 'AKIAI2YBN2CKB6DH77ZQ/20200307/us-east-1/handler/aws4_request',
          'SignedHeaders' => 'host;x-amz-date',
          'Signature'     => '693c6c6232b5494660d5aed1e7b6f2c8995d2ccc0cc0123545eccbbfc9bf8f9a' }
      end
      let(:signature) { instance_double(Aws::Sigv4::Signature) }

      before do
        user.save!

        allow(Shrine::Attacher).to receive(:from_data).and_call_original
      end

      context 'when signature in received headers matches locally computed AWS signature' do
        it 'returns the attacher and the hash of the parsed result from Lambda' do
          allow(Shrine::Attacher).to receive(:auth_header_hash).and_call_original
          expect(Shrine::Attacher)
            .to receive(:auth_header_hash).with(headers['Authorization']).and_return(auth_header)

          allow(Shrine::Attacher).to receive(:build_signer).and_call_original
          expect(Shrine::Attacher).to receive(:build_signer)

          allow_any_instance_of(Aws::Sigv4::Signer).to receive(:sign_request).and_return(signature)
          expect_any_instance_of(Aws::Sigv4::Signer)
            .to receive(:sign_request).with(http_method: 'PUT',
                                            url:         Shrine.opts[:callback_url],
                                            headers:     { 'X-Amz-Date' => headers['X-Amz-Date'] },
                                            body:        body)

          allow(signature).to receive(:headers).and_return('authorization' => headers['Authorization'])

          result = Shrine::Attacher.lambda_authorize(headers, body)

          expect(result).to be_kind_of(Array)
          attacher_from_result = result[0]
          expect(attacher_from_result).to be_kind_of(Shrine::Attacher)
          expect(attacher_from_result.record).to be_kind_of(User)
          expect(attacher_from_result.name).to be(:avatar)
          expect(result[1]).to eql(JSON.parse(body))
        end
      end

      context 'when signature in received headers does not match locally computed AWS signature' do
        it 'returns false' do
          allow_any_instance_of(Aws::Sigv4::Signer).to receive(:sign_request).and_return(signature)

          allow(signature).to receive(:headers).and_return('authorization' => headers['Authorization'].chop)

          result = Shrine::Attacher.lambda_authorize(headers, body)

          expect(result).to be(false)
        end
      end
    end
  end

  describe 'Attacher instance methods' do
    before do
      configure_uploader_class(LambdaUploader)
      user_class.include Class.new(LambdaUploader).attachment(:avatar)
    end

    after do
      ActiveRecord::Base.remove_connection
      Object.__send__(:remove_const, 'User')
    end

    describe '#lambda_process' do
      it 'invokes the lambda function and saves file storage info and metadata into the DB model' do
        user.avatar = FakeIO.new('file', filename: filename, content_type: 'image/png')

        allow_any_instance_of(Shrine::Plugins::AwsLambda::AttacherMethods)
          .to receive(:function_available?).and_return(true)

        expect(LambdaUploader::Attacher).to receive(:retrieve).and_call_original

        expect_any_instance_of(LambdaUploader).to receive(:lambda_process_versions).and_call_original
        allow_any_instance_of(Shrine::Plugins::AwsLambda::AttacherMethods).to receive(:get_upload_options)
        expect_any_instance_of(Shrine).to receive(:generate_location).and_call_original
        expect_any_instance_of(Shrine).to receive(:basic_location)

        aws_lambda_client = Aws::Lambda::Client.new(stub_responses: true)
        allow_any_instance_of(Shrine::Plugins::AwsLambda::AttacherMethods)
          .to receive(:lambda_client).and_return(aws_lambda_client)

        aws_lambda_client.stub_responses(:invoke, { status_code: 200, headers: { 'header-name' => 'header-value' },
                                                    body: { function_error: '' }.to_json })

        user.save!
        user.reload.avatar_data

        expect(user.avatar.storage_key).to be(:cache)
        expect(user.avatar.metadata['filename']).to eql(filename)
        expect(user.avatar.metadata['mime_type']).to eql('image/png')
      end
    end
  end
end
