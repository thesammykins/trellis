# Using the built-in agent

Open **Ask Trellis Agent** (⇧⌘A). Each terminal session has its own conversation
and draft. Configure **Settings → Trellis Agent** with a Responses or
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

- **Conversation Actions → Instructions & Skills** lets you inspect selected AGENTS.md sources and the
  discovered skill catalogue, including `~/.agents/skills`, before sending them.
- **Attach Terminal** offers an editable viewport snapshot. The agent can also
  request a fresh terminal snapshot or structured session details; both require
  approval and output review. Secure input blocks terminal capture.
- Type **@** at a word boundary and select **Sessions**, or choose **Session Context**, to reference
  a tab or pane from any open window. Its name and location are attached to the
  next message. Capture a viewport only when wanted, edit it, and remove references
  in **Session Context**. Snapshots retain their capture time and location; they
  do not grant control of the referenced session. Up to eight references and
  48 KiB of reference context can accompany a message.
- In **Files**, use **Ask Trellis Agent…** on a file or folder to put its path in
  an unsent question. This does not read the file or send its contents.
- Memory search/read use approved project notes with retrieval records. Recipe
  proposals are separate from ordinary knowledge pages.

Terminal text is context, not an authoritative protocol for another running agent.
Background tools use the app's environment and normal macOS permissions, not a
copy of the interactive shell's environment or a Trellis security sandbox.

## Approvals and visible terminal commands

New conversations offer three approval policies. **Auto-read & Share** permits
scoped file, memory, selected-skill and reusable-tool catalogue reads and sends
their results to the configured model. **Auto-read; Review Sharing** retains the
output review step. **Review Every Action** retains both steps. The policy is
fixed when the conversation starts and recorded on automatic tool receipts.
Commands, terminal/session access and proposals always require review.

Permission cards show the actual action and exact arguments, plus the agent's
short reason. The explanation does not grant permission. Output review names
the conversation's configured endpoint and lets you edit what is shared.

For a local shell, ask the agent to use **run_in_terminal**. It submits a reviewed,
single-line command to the originating visible Ghostty terminal and presses
Return once. Confirm the shell is at an empty prompt; returning focus to the
terminal or changing its input clears that confirmation. Each approval can submit
only its exact command once. The host rechecks the live original surface,
folder, local shell profile, secure input and Ghostty's prompt signal. The visible-terminal tool is not offered for remote, tmux or agent CLI sessions.

Submission is not completion: the acknowledgement has no inferred exit status or
captured output. A fresh terminal read still needs approval and output review.
The host does not automatically retry an uncertain submission.

## Specialist agents and routes

**Settings → Agent Team** provides Explore, Coding, Writing and Review starters.
Create, duplicate, disable or delete agents; edit their handle, instructions,
tool access, endpoint, model and limits. Changes are saved explicitly and apply
to new conversations. Unsaved edits survive switching Settings categories.

Each agent inherits the conversation gateway and model unless overridden.
A custom endpoint has its own API selection and exact-endpoint Keychain controls;
configuring it does not change the main connection. Use **Load Models** to choose
an advertised identifier. Model names and reasoning support vary by provider;
Trellis does not invent a fallback model. Reasoning effort defaults to the
provider's default for each specialist.

Type **@** or open **Mention Agent or Session** and select an agent. The next
message goes directly to that specialist, without a routing-model request.
Each assignment starts a fresh, bounded child task with the submitted message
and attachments. It does not receive the parent transcript or selected private
instruction sources automatically. Session references are available in the same
picker's **Sessions** tab.

The main agent can assign enabled specialists. A specialist can delegate only
to its configured targets or escalate to its selected specialist. Click a target
in the route display to edit it. The host rejects disabled, missing, self and
ancestor routes. Tasks execute sequentially; task count, nesting depth and model
requests are shared across the whole conversation, including follow-ups.
Starting **New Conversation** resets those shared limits.

**Allow Automatic Delegation** allows configured same-endpoint routes in automatic
approval modes. **Review Every Action** reviews model-initiated dispatch and
result sharing. **Auto-read; Review Sharing** keeps result sharing reviewed.
An explicit same-endpoint @ assignment needs no additional dispatch approval;
a different endpoint requires review before credentials are loaded or task
context is sent. Command execution and command output retain their own reviews.

Tool access is enforced by the host as well as reflected in the model's tool
catalogue. Text-only agents cannot read project files; read-project agents cannot
run commands. Reviewed-tools agents can request background commands and proposals.
Child agents cannot operate the visible terminal; that remains with the originating
conversation's separately reviewed terminal tools. All children retain the
conversation's original project scope.

**Agent Activity & Usage** shows the delegation tree, task transcripts, receipts,
models, endpoints and state. The conversation shows a compact activity row when
children exist, and any child approval appears in the main permission card with
the requesting agent's name. **Stop** cancels the active child chain. Child results
return as bounded briefs; failures are reported as failures.

## Context and cache efficiency

Requests use deterministic JSON and a stable system/tool prefix. Child prompts
include the relevant role and explicit task context. Tool catalogues are filtered
by actual capability; tool output and retained context have configurable byte
limits per specialist. The host removes only complete older turns when history
exceeds its budget, preserving tool-call/result pairs and the current turn, with
an explicit omission notice. It fails clearly if the newest turn alone is too
large. No extra model request is spent summarizing history, and file reads are
not memoized across changes.

Activity reports observed input, output, cached-input and reasoning token counters
when supplied by the provider, alongside actual request counts, request bytes and
omitted-turn counts. Missing counters remain unknown; partial reported totals do
not establish total spend or savings. Shared request limits and per-response
output limits are execution bounds, not a token or currency spending budget.
Provider-managed prefix caching is not guaranteed by deterministic requests.

The wire parser supports Responses usage and Chat Completions usage-only stream
chunks. Provider reasoning items and tool signatures needed by later turns remain
in wire history and are not shown as assistant prose. Primary compatibility
references: [DeepSeek Responses](https://api-docs.deepseek.com/guides/responses_api/),
[DeepSeek Chat](https://api-docs.deepseek.com/api/create-chat-completion/) and
[Gemini OpenAI compatibility](https://ai.google.dev/gemini-api/docs/openai).

## Panes, windows and scheduled commands

Split the focused pane right or down, up to eight panes in a tab. **Split →
Balance as Grid** restores an even layout; **Maximize Focused Pane** (⇧⌘Return)
temporarily gives one pane the working area. **View → Move Tab to Window** moves
the existing panes, processes, chat and drafts into another or a new window.
Use **Arrange Existing Panes** for explicit drop targets; tab context menus offer
equivalent move actions.

**View → Automations**, also linked from Settings, schedules exact commands at
an interval or daily time while Trellis is open and the Mac is awake. Commands
run in the background with Trellis's environment and normal user permissions;
they do not type into an interactive shell. Review and enable each command,
pause future runs, run once, stop a running attempt, and inspect its last output.
There is a 30-second run limit, up to four concurrent runs, and 8 KiB of retained
output. Missed runs are skipped. An interrupted attempt pauses on restart until
reviewed again. This does not install system cron or wake the Mac.

## Reusable tools

Try: “Propose a reusable command that shows this repository's short Git status.”
The agent proposes a name, purpose, absolute executable, exact argument array and
folder relative to the conversation scope. Open **Conversation Actions (•••) →
Reusable Tools…** to compare and apply the proposed version. Applying a recipe does not run
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
needs no account. **Settings → Terminal → Download Google Fonts…** provides JetBrains Mono,
Roboto Mono, IBM Plex Mono, Inconsolata and Space Mono. Downloading explicitly
selects the font for Trellis. Existing terminal preferences can restore another
font. Fonts remain app-managed; no system-wide font installation occurs.

Downloads use Google's [CSS v2 service](https://developers.google.com/fonts/docs/css2).
The list is curated because the [complete catalogue API](https://developers.google.com/fonts/docs/developer_api)
requires a key. Each entry links to its specimen and license. Onboarding follows
Apple's guidance to keep introductions [optional and brief](https://developer.apple.com/design/human-interface-guidelines/onboarding).
