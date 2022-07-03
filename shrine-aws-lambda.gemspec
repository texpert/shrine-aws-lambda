# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)

require 'shrine/plugins/aws_lambda/version'

Gem::Specification.new do |gem|
  gem.name         = 'shrine-aws-lambda'
  gem.version      = Shrine::Plugins::AwsLambda::VERSION
  gem.authors      = ['Aurel Branzeanu']
  gem.email        = ['branzeanu.aurel@gmail.com']
  gem.homepage     = 'https://github.com/texpert/shrine-aws-lambda'
  gem.summary      = 'AWS Lambda integration plugin for Shrine.'
  gem.description  = <<~DESC
    AWS Lambda integration plugin for Shrine File Attachment toolkit for Ruby applications.
    Used for invoking AWS Lambda functions for processing files already stored in some AWS S3 bucket.
  DESC
  gem.license = 'MIT'
  gem.files        = Dir['CHANGELOG.md', 'README.md', 'LICENSE', 'lib/**/*.rb', '*.gemspec']
  gem.require_path = 'lib/shrine/plugins'

  gem.metadata = { 'bug_tracker_uri'       => 'https://github.com/texpert/shrine-aws-lambda/issues',
                   'changelog_uri'         => 'https://github.com/texpert/shrine-aws-lambda/CHANGELOG.md',
                   'source_code_uri'       => 'https://github.com/texpert/shrine-aws-lambda',
                   'rubygems_mfa_required' => 'true' }

  gem.required_ruby_version = '>= 2.7'

  gem.add_dependency 'aws-sdk-lambda', '~> 1.0'
  gem.add_dependency 'aws-sdk-s3', '~> 1.2'
  gem.add_dependency 'shrine', '~> 2.6'

  gem.add_development_dependency 'activerecord', '>= 4.2.0'
  gem.add_development_dependency 'dotenv'
  gem.add_development_dependency 'github_changelog_generator'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'rubocop'
  gem.add_development_dependency 'rubocop-performance'
  gem.add_development_dependency 'rubocop-rspec'
  gem.add_development_dependency 'sqlite3' unless RUBY_ENGINE == 'jruby'

  gem.post_install_message = <<~POSTINSTALL
  POSTINSTALL
end
