# The model that decides whether a candidate post is really about a place (LocalClassifier).
#
# CLASSIFIER         "claude" (Anthropic API) or "ollama" (a local model). Defaults to claude when
#                    ANTHROPIC_API_KEY is set, otherwise ollama
# ANTHROPIC_API_KEY  for claude; or credentials.anthropic.api_key
# CLAUDE_MODEL       default claude-haiku-5-5
# OLLAMA_URL         for ollama: the ollama service in docker-compose.ollama.yml, or a local install
# OLLAMA_MODEL       for ollama: any instruct model Ollama can pull; the prompt was first tuned on qwen3:4b
# LOCAL_THRESHOLD    how sure the model must be (0-1) before a post is shown on the site
Rails.application.configure do
  config.x.anthropic_api_key = ENV["ANTHROPIC_API_KEY"].presence || Rails.application.credentials.dig(:anthropic, :api_key)
  config.x.classifier = ENV.fetch("CLASSIFIER") { config.x.anthropic_api_key ? "claude" : "ollama" }
  config.x.claude_model = ENV.fetch("CLAUDE_MODEL", "claude-haiku-5-5")
  config.x.ollama_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
  config.x.ollama_model = ENV.fetch("OLLAMA_MODEL", "qwen3:4b")
  config.x.local_threshold = Float(ENV.fetch("LOCAL_THRESHOLD", "0.6"))
end
