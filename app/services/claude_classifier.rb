# LocalClassifier on Claude (Haiku by default) through the Anthropic API rather than a local Ollama model.
# The prompt, the schema and the checks on the answer are LocalClassifier's; only the call differs.
#
# Thinking stays adaptive at low effort, so the model can skip it on easy posts; temperature is left out
# because current models reject non-default sampling. Structured outputs make the reply match SCHEMA.
class ClaudeClassifier < LocalClassifier
  # The same fields in the same order (the model describes the project before it decides). Numeric bounds
  # are left out: LocalClassifier clamps the confidence and range-checks the place number itself.
  SCHEMA = {
    type: "object",
    properties: {
      project: { type: "string" },
      place_role: { type: "string", enum: %w[ about name maker mention none ] },
      place: { type: "integer" },
      local: { type: "boolean" },
      confidence: { type: "number" }
    },
    required: %w[ project place_role place local confidence ],
    additionalProperties: false
  }.freeze
  MAX_TOKENS = 2_048 # room for some thinking as well as the short answer

  # client: anything with messages.create like Anthropic::Client (tests pass a fake).
  def initialize(model: Rails.configuration.x.claude_model, client: nil)
    @model = model
    @client = client || Anthropic::Client.new(api_key: Rails.configuration.x.anthropic_api_key, max_retries: 4)
  end

  private

  def ask(user)
    message = @client.messages.create(
      model: @model, max_tokens: MAX_TOKENS, system_: SYSTEM,
      messages: [ { role: "user", content: user } ],
      output_config: { effort: "low", format: { type: "json_schema", schema: SCHEMA } }
    )
    raise BadAnswer, "stopped: #{message.stop_reason}" unless message.stop_reason.to_s == "end_turn"

    JSON.parse(message.content.find { it.type.to_s == "text" }&.text.to_s)
  rescue Anthropic::Errors::APIConnectionError, Anthropic::Errors::RateLimitError, Anthropic::Errors::InternalServerError,
         Anthropic::Errors::AuthenticationError, Anthropic::Errors::PermissionDeniedError, Anthropic::Errors::PaymentRequiredError => e
    # The SDK has already retried what it could. Stop the run; the posts stay candidates for the next one.
    raise Unavailable, "#{e.class.name.demodulize}: #{e.message.to_s.truncate(200)}"
  end
end
