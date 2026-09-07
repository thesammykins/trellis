# Using the built-in agent

Open **Ask Trellis Agent** (⇧⌘A). Each terminal session has its own conversation
and draft. Configure **Settings → Native Chat & Direct API** with a Responses or
Chat Completions endpoint, model and endpoint-specific Keychain key. Codex's
ChatGPT sign-in remains a separate terminal harness route.

**Load Models** reads the configured base URL's `/models` endpoint (for example,
`/v1/models`). Choose an advertised ID or retain manual entry when a provider
does not support discovery. **Reasoning effort** is explicit and optional; the
model list does not establish which efforts a model supports. Responses sends
`reasoning.effort`; Chat Completions sends `reasoning_effort`. See the provider's
[model listing contract](https://platform.openai.com/docs/api-reference/models/list).

The chat stays scoped to the folder where its conversation started. A later `cd`
updates Files and the terminal label; the existing conversation does not silently
change its file-tool scope. Start a new conversation to work in the new folder.
Conversation history is currently in memory and ends with app exit. Settings
changes apply to new conversations; an active conversation keeps its connection.
Stopped or incomplete partial replies remain marked after a successful follow-up.
A session with a waiting tool review shows a chat attention control that returns
you to the pending approval.

## Context and app integration

- **Instructions & Skills** lets you inspect selected AGENTS.md sources and the
  discovered skill catalogue, including `~/.agents/skills`, before sending them.
- **Attach Terminal** offers an editable viewport snapshot. The agent can also
  request a fresh terminal snapshot or structured session details; both require
  approval and output review. Secure input blocks terminal capture.
- In **Files**, use **Ask Trellis Agent…** on a file or folder to put its path in
  an unsent question. This does not read the file or send its contents.
- Memory search/read use approved project notes with retrieval records. Recipe
  proposals are separate from ordinary knowledge pages.

Terminal text is context, not an authoritative protocol for another running agent.
Background tools use the app's environment and normal macOS permissions, not a
copy of the interactive shell's environment or a Trellis security sandbox.

## Reusable tools

Try: “Propose a reusable command that shows this repository's short Git status.”
The agent proposes a name, purpose, absolute executable, exact argument array and
folder relative to the conversation scope. Open the wrench **Reusable Tools**
button to compare and apply the proposed version. Applying a recipe does not run
it. A subsequent “Use that tool” still requires execution approval and review of
what output is sent to the model.

Try: “Improve the status tool so it also shows the branch.” Replacements must
refer to the current reviewed revision. Stale proposals, modified recipe files,
and changed execution snapshots are refused. **Disable Tool** removes a recipe
from the usable catalogue; enabling it is an explicit user action.

Recipes currently contain fixed arguments, without template interpolation or
an unrestricted plug-in loader. They belong to the built-in harness and project,
not the user's global agent configuration. Executable paths and arguments are
reviewed; installed binary contents are not frozen by recipe approval.

## Fonts and first use

**Help → Getting Started with Trellis** reopens the optional guide. Home Shell
needs no account. **Settings → Download Google Fonts…** provides JetBrains Mono,
Roboto Mono, IBM Plex Mono, Inconsolata and Space Mono. Downloading explicitly
selects the font for Trellis. Existing terminal preferences can restore another
font. Fonts remain app-managed; no system-wide font installation occurs.

Downloads use Google's [CSS v2 service](https://developers.google.com/fonts/docs/css2).
The list is curated because the [complete catalogue API](https://developers.google.com/fonts/docs/developer_api)
requires a key. Each entry links to its specimen and license. Onboarding follows
Apple's guidance to keep introductions [optional and brief](https://developer.apple.com/design/human-interface-guidelines/onboarding).
