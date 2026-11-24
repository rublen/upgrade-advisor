require 'rails_helper'

RSpec.describe Embedder do
  subject(:response) { described_class.call([ 'stars', 'sun' ]) }

  it 'embeds a string' do
    VCR.use_cassette("embed string") do
      response = described_class.call('The sky is blue')
      expect(response).to be_a(Array)
      expect(response.count).to eq 1
      expect(response[0]).to be_a(Array)
      expect(response[0].size).to eq 768
    end
  end

  it 'embeds an array' do
    VCR.use_cassette("embed array") do
      expect(response).to be_a(Array)
      expect(response.count).to eq 2
      expect(response.map(&:size)).to eq [ 768, 768 ]
    end
  end

  it 'raises for 404 status' do
    stub_request(:post, "#{Rails.application.config.x.models.embedding[:base_url]}/embed")
      .to_return(status: 404, body: "")
    VCR.turned_off do
      expect { response }.to raise_error Faraday::Error
    end
  end

  it 'raises if an embedding model is not defined in the app config' do
    allow(Rails.application.config.x.models).to receive(:embedding).and_return({ base_url: "url" })

    VCR.turned_off do
      expect { response }.to raise_error StandardError, "EMBEDDING_MODEL is not set"
    end
  end

  it 'raises if an embedding base URL is not defined in the app config' do
    allow(Rails.application.config.x.models).to receive(:embedding).and_return({})

    VCR.turned_off do
      expect { response }.to raise_error StandardError, "EMBEDDING_BASE_URL is not set"
    end
  end

  it 'raises on embedding a too large text chunk rather than silently cut it' do
    large_chunk = file_fixture("too_large_chunk.txt").read # ~2,700 tokens > 2,048 limit

    VCR.use_cassette("embed too large chunk") do
      expect { described_class.call(large_chunk) }.to raise_error(Faraday::BadRequestError) { |e|
        expect(e.response[:body]).to include("the input length exceeds the context length")
      }
    end
  end
end
