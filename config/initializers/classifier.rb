# The local model that decides whether a candidate post is really about a place (LocalClassifier).
#
# OLLAMA_URL       where Ollama listens; the ollama service in docker-compose.yml, or a local install
# OLLAMA_MODEL     any instruct model Ollama can pull. ~8B fits in 8 GB of RAM; use a 3-4B one on a small VPS
# LOCAL_THRESHOLD  how sure the model must be (0-1) before a post is shown on the site
Rails.application.configure do
  config.x.ollama_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
  config.x.ollama_model = ENV.fetch("OLLAMA_MODEL", "qwen3:8b")
  config.x.local_threshold = Float(ENV.fetch("LOCAL_THRESHOLD", "0.6"))
end
