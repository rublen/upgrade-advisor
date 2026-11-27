require "rails_helper"

RSpec.describe Generator, "with the configured provider" do
  it "returns an answer matching the schema with citations from the context" do
    context = <<~TEXT
      Context entries:
      [id=11] Rails 7.1.0, Active Record: Add composite primary key support.
      [id=12] Rails 7.1.0, Active Support: Deprecate `ActiveSupport::Deprecation.warn` singleton usage.
    TEXT

    VCR.use_cassette("generate answer") do
      result = described_class.call(
        system: "Answer only from the given changelog entries and cite their ids.",
        prompt: "#{context}\nQuestion: What changed in Active Record in Rails 7.1?",
        chunk_ids: [ 11, 12 ]
      )

      expect(result).to be_valid, -> { "errors: #{result.errors}" }
      expect(result.answer).to include("summary" => be_a(String), "covered" => true)
      expect(result.answer["items"]).to all(include("claim", "version", "kind", "chunk_ids"))
      expect(result.answer["items"].flat_map { |item| item["chunk_ids"] }).to all(be_in([ 11, 12 ]))
      expect(result.model).to eq Rails.application.config.x.models.llm[:model]
      expect(result.usage).to include("prompt_tokens", "completion_tokens")
    end
  end
end

RSpec.describe Generator do
  subject(:result) { described_class.call(system: "Be brief.", prompt: "What changed?", chunk_ids: [ 11 ]) }

  let(:config) { { base_url: "https://llm.example.com/v1", model: "main-model", fallback_model: nil, api_key: "secret-key" } }
  let(:completions_url) { "https://llm.example.com/v1/chat/completions" }
  let(:answer) do
    {
      "summary" => "Composite primary keys were added.",
      "items" => [ { "claim" => "Active Record supports composite primary keys.", "version" => "7.1.0",
                     "kind" => "feature", "chunk_ids" => [ 11 ] } ],
      "covered" => true
    }
  end

  def completion(answer)
    {
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        choices: [ { message: { role: "assistant", content: answer.to_json } } ],
        usage: { prompt_tokens: 100, completion_tokens: 40, total_tokens: 140 }
      }.to_json
    }
  end

  before do
    allow(Rails.application.config.x.models).to receive(:llm).and_return(config)
  end

  it "returns the parsed answer with the model, usage and duration" do
    stub_request(:post, completions_url).to_return(completion(answer))

    expect(result).to be_a(Generator::Result)
    expect(result.answer).to eq answer
    expect(result.errors).to be_empty
    expect(result).to be_valid
    expect(result.model).to eq "main-model"
    expect(result.usage).to include("total_tokens" => 140)
    expect(result.duration).to be >= 0
  end

  it "sends both messages, the answer schema, temperature 0 and the API key" do
    stub = stub_request(:post, completions_url)
      .with(
        headers: { "Authorization" => "Bearer secret-key" },
        body: hash_including(
          "model" => "main-model",
          "messages" => [ { "role" => "system", "content" => "Be brief." }, { "role" => "user", "content" => "What changed?" } ],
          "response_format" => {
            "type" => "json_schema",
            "json_schema" => { "name" => "answer", "strict" => true, "schema" => Generator::ANSWER_SCHEMA.deep_stringify_keys }
          },
          "temperature" => 0,
          "stream" => false
        )
      )
      .to_return(completion(answer))

    result

    expect(stub).to have_been_requested
  end

  it "passes a custom temperature" do
    stub = stub_request(:post, completions_url).with(body: hash_including("temperature" => 0.7)).to_return(completion(answer))

    described_class.call(system: "Be brief.", prompt: "What changed?", chunk_ids: [ 11 ], temperature: 0.7)

    expect(stub).to have_been_requested
  end

  context "with an answer that breaks the rules" do
    before do
      bad_answer = answer.merge("items" => [ answer["items"][0].merge("chunk_ids" => [ 99 ]) ])
      stub_request(:post, completions_url).to_return(completion(bad_answer))
    end

    it "returns it with the validation errors instead of raising" do
      expect(result).not_to be_valid
      expect(result.errors).to eq [ "cited chunk IDs not in the context: 99" ]
      expect(result.answer["items"][0]["chunk_ids"]).to eq [ 99 ]
    end
  end

  {
    "no content" => nil,
    "an empty content" => "",
    "content that is not JSON" => "Sure! Composite primary keys were added.",
    "a JSON array instead of an object" => "[1, 2]"
  }.each do |reply, content|
    context "when the model returns #{reply}" do
      before do
        stub_request(:post, completions_url).to_return(
          status: 200, headers: { "Content-Type" => "application/json" },
          body: { choices: [ { message: { role: "assistant", content: content } } ] }.to_json
        )
      end

      it "raises InvalidAnswer naming the model" do
        expect { result }.to raise_error Generator::InvalidAnswer, /\Amain-model returned/
      end
    end
  end

  {
    "rate limited" => [ 429, Faraday::TooManyRequestsError ],
    "failing on the provider side" => [ 503, Faraday::ServerError ],
    "not served by the provider" => [ 404, Faraday::ResourceNotFound ]
  }.each do |situation, (status, error)|
    context "when the model is #{situation}" do
      before do
        stub_request(:post, completions_url).with(body: hash_including("model" => "main-model")).to_return(status: status)
      end

      it "raises without a fallback model" do
        expect { result }.to raise_error error
      end

      context "with a fallback model" do
        let(:config) { super().merge(fallback_model: "fallback-model") }

        it "answers with the fallback model and reports it" do
          stub_request(:post, completions_url).with(body: hash_including("model" => "fallback-model"))
            .to_return(completion(answer))

          expect(result.answer).to eq answer
          expect(result.model).to eq "fallback-model"
        end

        it "raises if the fallback model fails too" do
          stub_request(:post, completions_url).with(body: hash_including("model" => "fallback-model")).to_return(status: status)

          expect { result }.to raise_error error
        end
      end
    end
  end

  context "with a fallback model and a request error" do
    let(:config) { super().merge(fallback_model: "fallback-model") }

    it "raises without trying the fallback model" do
      stub_request(:post, completions_url).to_return(status: 401)

      expect { result }.to raise_error Faraday::UnauthorizedError
      expect(a_request(:post, completions_url)).to have_been_made.once
    end
  end

  {
    base_url: "LLM_BASE_URL is not set",
    model: "LLM_MODEL is not set",
    api_key: "LLM_API_KEY is not set"
  }.each do |key, message|
    context "without #{key} in the app config" do
      let(:config) { super().merge(key => nil) }

      it "raises" do
        expect { result }.to raise_error RuntimeError, message
      end
    end
  end
end
