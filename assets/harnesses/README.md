# Harness marks

These are small source SVGs for 16–24 pt session/profile rows. Keep their `viewBox` and scale them in the host UI; do not rasterize a new source asset.

| Asset | Intended surface | Origin pinned 7 September 2026 | Licence / notice |
| --- | --- | --- | --- |
| `codex-openai.svg` | Any appearance; it inherits `currentColor` | [OpenAI Cookbook: `openai-logomark.svg`](https://github.com/openai/openai-cookbook/blob/a78f3f37bd23637aac2b3f1e8b1251cf5bb9e1a7/examples/agents_sdk/deployment_manager/frontend/src/openai-logomark.svg) | MIT, Copyright 2025 OpenAI. This is the OpenAI knot mark, used here to identify the Codex/OpenAI harness; it is not a Codex-specific product mark. The source licence does not grant trademark rights. |
| `opencode-on-dark.svg` | Dark app/terminal surface | [OpenCode: official dark square logo](https://github.com/anomalyco/opencode/blob/53fec37d8d2b9e0d92a1b4184e8df8f8480a2d26/packages/console/app/src/asset/brand/opencode-logo-dark-square.svg) | MIT, Copyright 2025 opencode. This copy removes the source-only `defs`/mask wrapper; paths and colours are unchanged. |
| `opencode-on-light.svg` | Light app surface | [OpenCode: official light square logo](https://github.com/anomalyco/opencode/blob/53fec37d8d2b9e0d92a1b4184e8df8f8480a2d26/packages/console/app/src/asset/brand/opencode-logo-light-square.svg) | MIT, Copyright 2025 opencode. This copy removes the source-only `defs`/mask wrapper; paths and colours are unchanged. |

Complete upstream licence texts are packaged in [`LICENSES/MIT-openai-cookbook.txt`](LICENSES/MIT-openai-cookbook.txt) and [`LICENSES/MIT-opencode.txt`](LICENSES/MIT-opencode.txt), with their pinned upstream [OpenAI Cookbook](https://github.com/openai/openai-cookbook/blob/a78f3f37bd23637aac2b3f1e8b1251cf5bb9e1a7/LICENSE) and [OpenCode](https://github.com/anomalyco/opencode/blob/53fec37d8d2b9e0d92a1b4184e8df8f8480a2d26/LICENSE) sources.

## Not bundled

- **Pi:** the current official [`earendil-works/pi`](https://github.com/earendil-works/pi/tree/9767ba275f3e9a5ee0f5c5342249b629ab1b2282) repository is MIT licensed but contains no logo/icon SVG. Do not substitute an invented `π` mark; use the `Pi` text label until upstream publishes a reusable asset.
- **Claude and Gemini:** no source artwork is bundled. Their brand resources are not project dependencies and the required redistribution/trademark terms were not established in this task.

The marks are source artwork from their publishers, not image-search thumbnails or generated graphics. Names and marks remain their respective owners' trademarks.
