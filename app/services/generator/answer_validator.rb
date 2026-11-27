class Generator
  # Checks a parsed answer: first against ANSWER_SCHEMA (types, enums, required keys, at least one citation),
  # then the rules the schema can't express: cited chunks must come from the context,
  # and an answer marked as not covered must not contain claims.
  class AnswerValidator
    SCHEMA = JSONSchemer.schema(ANSWER_SCHEMA.deep_stringify_keys)

    # @param answer [Hash] parsed JSON answer
    # @param chunk_ids [Array<Integer>] IDs of the chunks given to the model in the context
    def initialize(answer, chunk_ids)
      @answer = answer
      @chunk_ids = chunk_ids
    end

    # @return [Array<String>] readable problems, empty if the answer is valid
    def errors
      schema_errors = SCHEMA.validate(@answer).map { |error| error["error"] }
      return schema_errors if schema_errors.any? # the checks below rely on a well-formed answer

      citation_errors + coverage_errors
    end

    private

    def citation_errors
      unknown_ids = @answer["items"].flat_map { |item| item["chunk_ids"] }.uniq - @chunk_ids
      return [] if unknown_ids.empty?

      [ "cited chunk IDs not in the context: #{unknown_ids.join(", ")}" ]
    end

    def coverage_errors
      return [] if @answer["covered"] || @answer["items"].empty?

      [ "answer is marked as not covered but has #{@answer["items"].size} items" ]
    end
  end
end
