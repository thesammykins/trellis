# Personal trial status · 0.3.2

Trellis includes a full Ghostty-backed native terminal, shell and agent launchers,
split panes, independent windows, saved sessions, local/SSH tmux attachment,
Markdown memory review, theme import/export, Ghostty settings import and onboarding.
Workspace customization adds ordered tab details, category shortcuts, session
icons, sidebar layout and portable presentation presets.

The native side chat now keeps a separate conversation and draft for each terminal
session, streams Responses and Chat Completions replies, renders headings/lists/links
and copyable fenced code, and places reviewed tool receipts beside their originating
turn. Commands and terminal access keep separate execution and output approvals;
new conversations can automatically review scoped reads and sharing. Chat history
is in-memory; a conversation keeps its original tool scope after the shell changes
folder. Terminal context is attached explicitly.

The native Files outline follows the active local terminal folder, with a labelled
launch-folder fallback, lazy folders, Refresh, Finder/default-app actions and path
copy/drag. Remote browsing is unavailable. Narrow layouts compact navigation;
terminal panes and selected tabs expose meaningful accessibility identity. Theme
editing diagnoses app-text contrast and offers an explicit correction.
It uses Direct API settings. ChatGPT subscription authentication is available
through the Codex terminal harness, not through the native side chat.

The built-in harness also supports reviewed terminal/session reads and a separate
per-project reusable-tool library. The agent can propose exact command recipes and
revision-checked improvements; the user applies or rejects them, can disable tools,
and still reviews each execution and output release. Instructions and skill
selections now survive switching sessions before a conversation starts.

Getting Started is an optional four-step guide with home-shell and agent actions.
Settings provides five downloadable Google monospace families, installed only for
Trellis and registered at launch. Native chat endpoint settings are always visible.
See [Built-in agent](BUILT-IN-AGENT.md) for setup and examples.

The follow-up polish preserves explicit agent reasoning during discovery failures,
keeps interrupted turns marked after recovery, exposes background chat approvals,
and makes connection adoption and saved-key setup explicit. Code copying now
respects matching Markdown fences. Narrow chat controls and onboarding dismissal
also received focused fixes.

The UX14 settings pass adds searchable categories, inline terminal and shell
preferences, workspace layout entry points, assistant naming and grouped connection
controls. Agent Settings links open the correct category even after an empty
search. Saved-key status no longer reads secret bytes just to report presence.
The workspace sidebar removes duplicate session search and uses a Settings label;
secondary chat controls now live in the Conversation Actions menu.

UX15 adds explicit @ references to open tabs and panes, editable viewport context,
and an optional automatic policy for scoped reads and sharing. Permission cards
show the exact action, the agent's reason and the output destination. A reviewed
command can run once in its originating visible local Ghostty shell; changing
terminal input invalidates the prompt confirmation. The acknowledgement reports
submission only, without inventing completion or capturing output.

Tabs support up to eight panes with grid balancing and temporary maximization.
Moving a tab between windows retains its live terminals, conversation and draft.
Automations schedule reviewed exact commands at intervals or daily times while
Trellis is open, with pause/resume, run-now, cancellation and local output review.
Missed runs are skipped; no system scheduler is installed.

UX16 adds configurable specialist agents with direct @ assignment, editable
agent-to-agent delegation/escalation routes, inherited or custom model connections,
host-enforced tool capabilities, and shared conversation limits. Agent Team Settings
supports role creation, duplication, deletion, instructions, model discovery and
inline endpoint credentials. The compact activity entry opens a task tree with
child transcripts, requesting-agent identity and observed provider usage.

Stable request serialization, capability-filtered tools, bounded child briefs and
complete-turn compaction reduce unnecessary context. Token/cache counters remain
unknown when providers omit them. No additional summarizer model, dependency or
local mutable-file cache is introduced. Specialist tasks are sequential; chat and
child histories remain in memory. Shared limits cover requests/tasks/depth rather
than promising a token or currency spending cap.

The independent review fixes Files refresh for cached folders and changed file
types, makes proposal rows fully clickable, and keeps memory edits in one
sheet-owned draft with their original page version. Approval verifies the exact
proposal displayed; stale drafts and revision overflow fail without overwriting
content. Draft controls pause while saving.

Direct Responses parsing now rejects premature completion and preserves streamed
text from sparse completed responses. Agent file searches handle root scopes and
macOS path aliases. Successful Dreaming snapshots remain deduplicated when record
timestamps tie. Failed tool probes retain bounded recovery diagnostics, and the
new-session Shell preview shows the configured executable and exact arguments.

## Verification

The independent review passed all 33 feature checks, terminal host checks, and
the native development build. Added regressions were demonstrated against old
behavior for Files refresh, incomplete streams, file scope, Dreaming retries,
tool diagnostics and revision overflow. Native fixture interaction exercised
Files refresh, changed-proposal rejection, fresh approval, stale-draft rejection,
initial edit state, row activation, and configured bash preview/launch. Original
development shell settings were restored. Provider and SSH paths used local
fixtures; no new live-provider or remote-host claim is made. The personal app and
DMG were not replaced.

UX16 passed 33 feature checks, the terminal host checks, focused Swift 6 team,
context and runtime checks, and the native build and Apple Development signed
package. Native Settings dogfood exercised duplicate/edit/save, draft retention,
route editing/navigation, deletion, model discovery and isolated endpoint-key UI.
The final starter roster inherits the saved gateway/model; no credentials changed.

Real configured-provider runs verified direct Explore assignment with no root
model request, scoped file reads, Explore-to-Coding escalation, separately reviewed
child command execution and output sharing, and the resulting activity tree.
Provider token/cache counters were observed, and individual metrics expose labelled
accessibility values. Live validation caught ambiguous delegation target strings;
the tool now enumerates exact permitted handles and gives distinct route errors.
Manual-policy bypass, cancellation/stale approvals and Chat follow-up serialization
are covered by retained regression checks. See Built-in Agent for the supported
routes and limitations; local screenshots and logs live under ignored evidence.

UX15 passed all feature checks, terminal host checks, the native build and Apple
Development signed packaging. Real configured-provider runs exercised automatic
scoped reads/sharing, reviewed visible-shell submission, input invalidation and
separate acknowledgement release. Native checks covered @ capture/edit/insertion,
four/eight panes, maximize/restore, live transfers to new and existing windows,
and continued session reads after the original window closed. Automations passed
create-paused, Run Now, resume, a timed run with its window closed, pause and
deletion. The final accessibility tree exposed updated attempt/result times.
The fixture schedule was removed. The signed app was rebuilt; the older DMG was
not rebuilt for UX14/UX15.

UX14 passed the native development build, the existing feature checks and a final
focused Settings check. Native interaction exercised all Settings categories,
search and empty results, direct Agent Settings navigation, font-size changes,
light/dark appearance, workspace customization and Dreaming entry points,
connection details, reusable tools and keyboard session search. The shell process
survived Settings and appearance changes. A subsequent Apple Development signed
build exercised a real configured-provider command, separate output review and
completed reply with the existing saved credential. Full VoiceOver certification
is not claimed for this pass.

The UX10 development build and feature checks passed. Native localhost testing
exercised streaming rich replies, exact code copying, terminal focus during
completion, independent session drafts, live folder changes with shell PID
continuity, and output-review draft retention across inspector switching.
UX11 adds real downloaded-font checks, saved-tool proposal/apply/discover/run/output
review, terminal read/withhold, Files-to-draft, home-shell onboarding and split-pane
navigation. The signed 0.3.0 personal app and rebuilt DMG include both passes; the
packaged app launched and ran a shell command. Temporary fixture credentials were
removed. UX12 then verified real Responses and Chat Completions on Luna Low,
including execution/output review, and a ChatGPT-subscription Codex Luna Low
canary. Model discovery retains manual entry and exposes explicit reasoning effort.
Sparse Responses completion no longer discards already streamed text. Actual
VoiceOver checks covered onboarding headings, settings/account status, Files
navigation and chat approval/completion. The signed 0.3.1 app and DMG include these
fixes; fixture tabs and temporary accessibility settings were cleaned up.


The earlier 0.2.0 macOS build, focused feature checks, Apple Development signing and DMG
validation passed. Native UI checks exercised session search/category assignment,
preset export/reset/import, custom symbols, vertical-tab collapse and menu-driven
pane moves preserving live shell identities. A localhost Responses fixture
exercised command approval, output review and continued chat history.

```sh
./script/check-features.sh
./script/build_and_run.sh --build-only
./script/package-personal.sh
./script/build-dmg.sh
```

Detailed run records and screenshots are local development artifacts, excluded
from the repository. Fixture success is not evidence of a live cloud-provider run.

UX13's local streaming cancellation/failure/recovery tests, model/fence checks and
native background-approval flow passed. Inspector layouts were observed at native
320- and 400-point widths. Final rich-content VoiceOver navigation, larger-text and
light-theme coverage remain targeted trial checks; this is not a full AX certification.

## Known limits and next checks

- Drag sources were observed, but native automation did not complete target/drop
  delivery. Tab, pane and sidebar drag gestures still need a manual trial.
  Equivalent menu and layout controls remain available.
- Pi, Claude Code and Gemini CLI launches have not been exercised on the
  development machine. SSH checks covered only an authorized fixture host.
- The core VoiceOver flow was exercised; Braille, alternate verbosity, every
  dialog, other input methods, external displays, Shortcuts and Siri remain
  outside this latest validation pass.
- Identity overrides are per session. Layout exports contain presentation only;
  they exclude commands, credentials, private paths and instruction trust.
- This is an Apple Silicon/macOS 27 personal build. Public distribution requires
  a source-license decision and a Developer ID/hardened-runtime/notarization route.

Next work should scope the development run script's shutdown to its own artifact
after a successful build; its current run mode can stop other worktrees' development
apps. Settings can still label a failed installed-agent probe as "Not found", and
Dreaming's five-minute eligibility window needs a midnight boundary check. Native
drag gestures remain a user-trial priority.
