require "webmock/rspec"
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  # Tag a spec with `:vcr` to record/replay its HTTP calls in a cassette named after the spec.
  config.configure_rspec_metadata!
  # config.ignore_localhost = true # disabled not to run models in tests (important for CI)
  # Never save API keys (e.g. Groq's Bearer token) in cassettes; requests are matched without headers.
  config.before_record do |interaction|
    interaction.request.headers.delete("Authorization")
  end
end
