class Embedder
  # @param texts [String, Array<String>] [ "text1", "text2", ... ]
  # @return [Array<Array<Float>>] [ [vector1],  [vector2], ... ]
  def self.call(texts)
    self.new(texts).embed
  end

  def embed
    response = connection.post("embed") do |req|
      req.body = params.to_json
    end

    JSON.parse(response.body).fetch("embeddings")
  end

  private

  def initialize(texts)
    @texts = texts
  end

  def connection
    Faraday.new(base_url, request: { open_timeout: 5, timeout: 60 }) do |builder|
      builder.request :json # Sets the Content-Type header to application/json on each request
      builder.response :raise_error # raise Faraday::Error on status code 4xx or 5xx
    end
  end

  def params
    { model: model, input: @texts, truncate: false }
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
end
