// Secrets set via `wrangler secret put` — not in wrangler.jsonc
declare namespace Cloudflare {
  interface Env {
    INTERNAL_API_SECRET: string;
    GOOGLE_GENERATIVE_AI_API_KEY: string;
  }
}
