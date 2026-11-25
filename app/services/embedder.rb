class Embedder
  NO_PREFIXES = { query: "", document: "" }.freeze
  PREFIXES = {
    "nomic-embed-text" => { query: "search_query: ", document: "search_document: " }
    # "bge-m3" => NO_PREFIXES,
  }.freeze

  # @param texts [String, Array<String>] [ "text1", "text2", ... ]
  # @param role [Symbol] :query or :document
  # @return [Array<Array<Float>>] [ [vector1],  [vector2], ... ]
  def self.call(texts, role:)
    self.new(texts, role).embed
  end

  def embed
    response = connection.post("embed") do |req|
      req.body = params.to_json
    end

    JSON.parse(response.body).fetch("embeddings")
  end

  private

  def initialize(texts, role)
    @texts = texts
    @role = role
  end

  def connection
    Faraday.new(base_url, request: { open_timeout: 5, timeout: 60 }) do |builder|
      builder.request :json # Sets the Content-Type header to application/json on each request
      builder.response :raise_error # raise Faraday::Error on status code 4xx or 5xx
    end
  end

  def params
    { model: model, input: prepared_texts, truncate: false }
  end

  def base_url
    config[:base_url].presence || raise("EMBEDDING_BASE_URL is not set")
  end

  def model
    config[:model].presence || raise("EMBEDDING_MODEL is not set")
  end

  def config
    Rails.application.config.x.models.embedding
  end

  def prepared_texts
    return "#{task_instruction_prefix}#{@texts}" if @texts.is_a? String

    @texts.map { |text| "#{task_instruction_prefix}#{text}" }
  end

  def task_instruction_prefix
    prefixes = PREFIXES.fetch(model.split(":").first) { raise "No prefixes defined for embedding model #{model}" }
    prefixes.fetch(@role) # KeyError for an unknown role
  end
end
