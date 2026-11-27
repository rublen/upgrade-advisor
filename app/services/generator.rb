class Generator
  class InvalidAnswer < StandardError; end

  FALLBACK_ERRORS = [ Faraday::TooManyRequestsError, Faraday::ServerError, Faraday::ResourceNotFound ].freeze
  ANSWER_SCHEMA = {
    type: "object",
    properties: {
      summary: { type: "string", description: "A short overall answer of two or three sentences" },
      items: { type: "array",
               items: { type: "object",
               properties: { claim: { type: "string", description: "One change, stated in one sentence, supported by the cited entries." },
                             version: { type: "string", description: "Rails version of the cited entry, e.g. \"7.1.0\"." },
                             kind: { type: "string", enum: %w[breaking deprecation feature fix other] },
                             chunk_ids: { type: "array", items: { type: "integer" }, minItems: 1,
                                          description: "IDs of the entries that support the claim. Use only IDs given in the context." } },
               required: %w[claim version kind chunk_ids],
               additionalProperties: false } },
      covered: { type: "boolean", description: "false if the entries do not answer the question; then items must be empty." }
    },
    required: %w[summary items covered],
    additionalProperties: false
  }.freeze

  # answer: the parsed JSON answer; errors: problems found by AnswerValidator; the rest describes how it was produced
  Result = Data.define(:answer, :errors, :model, :usage, :duration) do
    def valid? = errors.empty?
  end

  # @param system [String] message for a system role
  # @param prompt [String] message for a user role
  # @param chunk_ids [Array<Integer>] IDs of the chunks in the prompt's context; the answer may cite only these
  # @param temperature [Numeric] 0 by default: repeatable answers for evaluation
  # @return [Generator::Result]
  #   answer:   { "summary" => "...",
  #               "items" => [{ "claim" => "...", "version" => "...", "kind" => "...", "chunk_ids" => [1, 2]}, ...],
  #               "covered" => true }
  #   errors:   [ "cited chunk IDs not in the context: 99", ... ], empty if valid
  #   model:    the model that answered (LLM_MODEL, or LLM_FALLBACK_MODEL after a fallback)
  #   usage:    { "prompt_tokens" => 120, "completion_tokens" => 45, "total_tokens" => 165, ... }
  #   duration: seconds for the whole call, including a failed attempt before a fallback
  # @raise [Generator::InvalidAnswer] if the reply has no content or isn't a JSON object
  def self.call(system:, prompt:, chunk_ids:, temperature: 0)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response, model_name = self.new.generate(system, prompt, temperature)
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    body = JSON.parse(response.body)
    answer = parse_answer(body, model_name)

    Result.new(
      answer: answer,
      errors: AnswerValidator.new(answer, chunk_ids).errors,
      model: model_name,
      usage: body["usage"],
      duration: duration
    )
  end

  def self.parse_answer(body, model_name)
    content = body.dig("choices", 0, "message", "content")
    raise InvalidAnswer, "#{model_name} returned no content" if content.blank?

    answer = JSON.parse(content)
    raise InvalidAnswer, "#{model_name} returned JSON that is not an object: #{content.truncate(200)}" unless answer.is_a?(Hash)

    answer
  rescue JSON::ParserError
    raise InvalidAnswer, "#{model_name} returned invalid JSON: #{content.truncate(200)}"
  end
  private_class_method :parse_answer

  # @return [Array(Faraday::Response, String)] the response and the model that produced it
  def generate(system, prompt, temperature)
    [ request_completion(model, system, prompt, temperature), model ]
  rescue *FALLBACK_ERRORS
    raise unless fallback_model

    [ request_completion(fallback_model, system, prompt, temperature), fallback_model ]
  end

  private

  def request_completion(model_name, system, prompt, temperature)
    connection.post("chat/completions") do |req|
      req.body = request_body(model_name, system, prompt, temperature)
    end
  end

  def request_body(model_name, system, prompt, temperature)
    {
      model: model_name,
      messages: [
        { role: "system", content: system },
        { role: "user",   content: prompt }
      ],
      response_format: { type: "json_schema",
                         json_schema: { name: "answer", strict: true, schema: ANSWER_SCHEMA } },
      temperature: temperature,
      stream: false
    }
  end

  def connection
    Faraday.new(base_url, request: { open_timeout: 5, timeout: 120 }) do |builder|
      builder.request :authorization, "Bearer", api_key
      builder.request :json # Sets the Content-Type header to application/json on each request
      builder.response :raise_error # raise Faraday::Error on status code 4xx or 5xx
    end
  end

  def base_url
    config[:base_url].presence || raise("LLM_BASE_URL is not set")
  end

  def model
    config[:model].presence || raise("LLM_MODEL is not set")
  end

  def fallback_model
    config[:fallback_model].presence
  end

  def api_key
    config[:api_key].presence || raise("LLM_API_KEY is not set")
  end

  def config
    Rails.application.config.x.models.llm
  end
end
