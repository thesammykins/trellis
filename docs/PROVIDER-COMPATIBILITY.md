# Direct model provider compatibility

Verified against official documentation on 8 September 2026. Trellis uses its existing native `URLSession` client and tool runtime. Endpoint presets select a wire API, not a model; the user discovers or enters a model available to their account. Codex subscription conversations use the separate Codex app-server client and its context management.

| Preset | Base endpoint | Initial API |
| --- | --- | --- |
| OpenAI API | `https://api.openai.com/v1` | Responses |
| Google Gemini API | `https://generativelanguage.googleapis.com/v1beta/openai` | Chat Completions |
| DeepSeek API | `https://api.deepseek.com` | Chat Completions |
| OpenRouter | `https://openrouter.ai/api/v1` | Chat Completions |

Completion requests use bearer authentication. The configured endpoint owns its Keychain credential. Compatibility adjustments match exact official hosts and documented paths; a custom gateway retains the existing compatible request shape.

## Request differences

- **OpenAI:** Responses uses `max_output_tokens`, `reasoning.effort`, `store: false` and encrypted reasoning inclusion for stateless continuation. Chat Completions uses `max_completion_tokens` and `reasoning_effort`; `max_tokens` is deprecated. Supported effort varies by model. [Responses reference](https://developers.openai.com/api/reference/resources/responses/methods/create), [Chat Completions reference](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create).
- **Gemini:** The preset uses Google's documented OpenAI compatibility endpoint. Trellis omits `store` and `parallel_tool_calls`, which are outside the documented compatibility surface, and retains streaming usage requests. Provider-level effort choices are `none`, `minimal`, `low`, `medium`, and `high`; particular models may reject a choice, including disabling required thinking. This is the official compatibility API, not a claim that Trellis implements every feature of Google's native GenerateContent API. [Google compatibility guide](https://ai.google.dev/gemini-api/docs/openai).
- **DeepSeek:** Chat requests translate the remaining output allowance to `max_tokens`, omit unsupported OpenAI fields and the redundant automatic tool choice, and use an empty string for tool-call assistant content. Explicit tool restrictions remain intact. Disabling reasoning sends `thinking.type: disabled`; other choices use `reasoning_effort`. DeepSeek maps `medium` and `xhigh` to `high`. Responses keeps `max_output_tokens` and `reasoning.effort`, omitting unsupported `store`, `include`, `parallel_tool_calls` and `stream_options`. [Chat reference](https://api-docs.deepseek.com/api/create-chat-completion/), [integration guidance](https://api-docs.deepseek.com/quick_start/agent_integrations/oh_my_pi/), [Responses guide](https://api-docs.deepseek.com/guides/responses_api/).
- **DeepSeek tool schemas:** `strict` is omitted on the standard Chat route because strict mode requires the explicitly selected `/beta` route. It remains enabled on that beta route. Trellis validates every tool call locally regardless of provider schema support. [Tool calls guide](https://api-docs.deepseek.com/guides/tool_calls/).
- **OpenRouter:** Chat uses the currently supported `max_completion_tokens` and unified `reasoning.effort` object; it omits `store`. Effort support and mandatory reasoning vary by routed model. [Chat reference](https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion), [reasoning guide](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens).

## Continuing tool calls

The native runtime retains provider-required metadata in request history without adding it to visible assistant text: OpenAI Responses reasoning items, DeepSeek `reasoning_content`, Google tool-call thought signatures, and OpenRouter `reasoning_details`. These fields are protocol data, not tool authority. Local command review and capability restrictions still apply.

OpenRouter detail objects retain unknown JSON fields and their original sequence. Stream arrays concatenate in received order; Trellis does not rebuild signed reasoning text. Invalid shapes, more than 4,096 details, or more than 128 KiB of detail data fail visibly. Other request, response and conversation bounds still apply. [OpenRouter replay contract](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens), [DeepSeek thinking continuation](https://api-docs.deepseek.com/guides/thinking_mode/), [Google thought signatures](https://ai.google.dev/gemini-api/docs/thought-signatures).

## Discovery and verification limits

Discovery requests the exact configured `<base>/models` endpoint, refuses redirects, validates unique bounded IDs and accepts at most 2 MiB / 2,000 entries. It never follows response-supplied links with a credential. OpenRouter's unpaginated full-list endpoint currently returns text-capable models by default; the public fixture inspected during this pass contained 428 IDs and 704,294 bytes, exceeding Trellis's previous 512 KiB ceiling. This sample is evidence, not a fixed catalogue. [OpenRouter model listing](https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties), [model filtering guide](https://openrouter.ai/docs/guides/overview/models), [DeepSeek model listing](https://api-docs.deepseek.com/api/list-models/).

OpenRouter's public catalogue also loads before a key is saved. This exception applies only to HTTPS `openrouter.ai`, default port or 443, and base path `/api/v1` (with an optional trailing slash), with no user information, query or fragment. An empty key omits Authorization; a supplied key is still validated and sent. Every other endpoint requires a key, including lookalike hosts, custom ports and alternate paths. Anonymous listing does not authorize completions or prove account access to a model.

Focused Swift 6 checks exercise provider request fields, exact-route matching, bounded catalogue parsing, opaque metadata replay/streaming and redirect rejection. Only the public OpenRouter catalogue was fetched; no authenticated or paid provider completion was run. A discovered ID does not prove tool, effort or output-limit compatibility. Account permissions, per-model restrictions and live provider acceptance remain to be exercised with the user's selected routes; provider errors remain visible rather than causing an automatic model or provider switch.
