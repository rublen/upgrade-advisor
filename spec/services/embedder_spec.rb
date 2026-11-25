require 'rails_helper'

RSpec.describe Embedder do
  subject(:response) { described_class.call([ 'stars', 'sun' ], role: :document) }

  it 'embeds a string' do
    VCR.use_cassette("embed string") do
      response = described_class.call('The sky is blue', role: :document)
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
      expect { described_class.call(large_chunk, role: :document) }
        .to raise_error(Faraday::BadRequestError) { |e|
          expect(e.response[:body]).to include("the input length exceeds the context length")
        }
    end
  end

  describe 'roles for prefixes' do
    subject(:prepared_texts) { embedder_instance.send(:prepared_texts) }

    let(:embedder_instance) { described_class.new([ 'stars', 'sun' ], role) }
    let(:role) { :document }

    it 'adds the document-specific prefix to each string' do
      expect(prepared_texts).to eq [ 'search_document: stars', 'search_document: sun' ]
    end

    context "with a single string" do
      let(:embedder_instance) { described_class.new('sun', role) }

      it 'adds the document-specific prefix to the string' do
        expect(prepared_texts).to eq 'search_document: sun'
      end
    end

    context "with a :query role" do
      let(:role) { :query }

      it 'adds the query-specific prefix to each string' do
        expect(prepared_texts).to eq [ 'search_query: stars', 'search_query: sun' ]
      end
    end

    context "with an unknown role" do
      let(:role) { :unknown }

      it 'raises KeyError' do
        expect { prepared_texts }.to raise_error KeyError, include("key not found")
      end
    end

    context "without a role" do
      let(:role) { nil }

      it 'raises KeyError' do
        expect { prepared_texts }.to raise_error KeyError, include("key not found")
      end
    end
  end

  context "with unsupported model" do
    before do
      allow(Rails.application.config.x.models)
        .to receive(:embedding).and_return({ base_url: "url", model: "other-model" })
    end

    it "raises" do
      expect { response }.to raise_error "No prefixes defined for embedding model other-model"
    end
  end
end
