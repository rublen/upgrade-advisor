require "webmock/rspec"
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  # Tag a spec with `:vcr` to record/replay its HTTP calls in a cassette named after the spec.
  config.configure_rspec_metadata!
  config.ignore_localhost = true
  # Hide secrets in recorded cassettes, e.g.:
  # config.filter_sensitive_data("<API_KEY>") { ENV["SOME_API_KEY"] }
end
