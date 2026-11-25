# The local model that decides whether a candidate post is really about a place (LocalClassifier).
#
# OLLAMA_URL       where Ollama listens; the ollama service in docker-compose.yml, or a local install
# OLLAMA_MODEL     any instruct model Ollama can pull. The prompt is tuned on qwen3:4b (~3 GB of RAM)
# LOCAL_THRESHOLD  how sure the model must be (0-1) before a post is shown on the site
Rails.application.configure do
  config.x.ollama_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
  config.x.ollama_model = ENV.fetch("OLLAMA_MODEL", "qwen3:4b")
  config.x.local_threshold = Float(ENV.fetch("LOCAL_THRESHOLD", "0.6"))
end
