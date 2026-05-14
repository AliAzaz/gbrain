import type { Recipe } from '../types.ts';

/**
 * OpenRouter is an OpenAI-compatible routing layer that fronts dozens of
 * providers (OpenAI, Anthropic, Google, Meta, Qwen, DeepSeek, etc.) behind a
 * single API key. Useful for distributions that want to ship gbrain with one
 * key covering both embeddings AND chat without each user signing up for
 * multiple provider accounts.
 *
 * OpenRouter ships both `/chat/completions` and `/embeddings` endpoints, so
 * unlike most openai-compat recipes (which only serve chat), this recipe
 * declares all three touchpoints. Embedding models are routed through
 * upstream providers (OpenAI's text-embedding-3-*, Qwen's qwen3-embedding,
 * etc.) — see https://openrouter.ai/models?fmt=cards&output_modalities=embeddings
 * for the live model list.
 *
 * Model IDs in OpenRouter use `<upstream>/<model>` shape (e.g.
 * `openai/text-embedding-3-small`). In gbrain config they become
 * `openrouter:openai/text-embedding-3-small` — parseModelId splits on the
 * first colon, so the slash inside the model id is preserved correctly and
 * threads through to the OpenRouter wire format unchanged.
 */
export const openrouter: Recipe = {
  id: 'openrouter',
  name: 'OpenRouter',
  tier: 'openai-compat',
  implementation: 'openai-compatible',
  base_url_default: 'https://openrouter.ai/api/v1',
  auth_env: {
    required: ['OPENROUTER_API_KEY'],
    setup_url: 'https://openrouter.ai/keys',
  },
  touchpoints: {
    embedding: {
      // OpenRouter routes embedding requests to the upstream provider named
      // in the model id. Declared list is the common subset; users can pass
      // any embedding model OpenRouter lists at runtime — the v0.31.12
      // extended-models registry permits config-time selection of ids not
      // in this array, with provider rejection surfacing at HTTP call time.
      models: [
        'openai/text-embedding-3-small',
        'openai/text-embedding-3-large',
        'qwen/qwen3-embedding-0.6b',
      ],
      default_dims: 1536, // text-embedding-3-small native; matches gbrain's pgvector default
      dims_options: [256, 512, 768, 1024, 1536, 3072],
      cost_per_1m_tokens_usd: 0.02, // text-embedding-3-small upstream baseline
      price_last_verified: '2026-05-14',
      // Explicit opt-out of the missing-max_batch_tokens startup warning.
      // OpenRouter's batch capacity is determined by the upstream model the
      // request routes to (OpenAI ~300K, Qwen smaller); there is no static
      // cap that fits the whole catalog, mirroring the litellm-proxy recipe.
      no_batch_cap: true,
    },
    expansion: {
      models: [
        'openai/gpt-4o-mini',
        'anthropic/claude-haiku-4.5',
        'google/gemini-2.0-flash-lite',
      ],
      cost_per_1m_tokens_usd: 0.15,
      price_last_verified: '2026-05-14',
    },
    chat: {
      models: [
        'anthropic/claude-sonnet-4.5',
        'anthropic/claude-opus-4.7',
        'openai/gpt-4o',
        'openai/gpt-5',
        'google/gemini-2.5-pro',
      ],
      supports_tools: true,
      // OpenRouter's tool-call surface is OpenAI-compatible; upstream providers
      // that natively support tools (Anthropic, OpenAI, Google) preserve
      // tool_call_id stability across replays. Subagent loop is safe on the
      // major upstreams listed above.
      supports_subagent_loop: true,
      // Anthropic prompt-cache markers are stripped at the OpenRouter boundary
      // for the openai-compat surface — set false so the subagent loop doesn't
      // assume cache hits it won't get. (Users wanting cache should hit
      // Anthropic directly via the `anthropic` recipe.)
      supports_prompt_cache: false,
      max_context_tokens: 200000,
      cost_per_1m_input_usd: 3.0, // anthropic/claude-sonnet-4.5 baseline (varies by upstream)
      cost_per_1m_output_usd: 15.0,
      price_last_verified: '2026-05-14',
    },
  },
  setup_hint: 'Get an API key at https://openrouter.ai/keys, then `export OPENROUTER_API_KEY=...`',
};
