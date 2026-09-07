# App Intents, Siri and system discovery

## Goal

Expose a few useful typed actions and approved entities. Do not expose an unrestricted command runner or an index of every terminal transcript.

Apple's macOS 27 material and WWDC26 App Intents session describe richer Siri/content integration. The exact APIs, availability and system behaviour must be verified against the installed SDK and device configuration. This blueprint does not claim a working Siri integration. [S06](../research/SOURCES.md#s06)[S07](../research/SOURCES.md#s07)[S08](../research/SOURCES.md#s08)

## Proposed entities

`ProjectEntity`: stable registered project ID, safe display name and availability. `MemoryPageEntity`: approved page ID, title, scope and optional user-approved excerpt. `SessionEntity`: a registered session with a safe label and current known state.

These are proposed app type names, not Apple-defined entity classes. Their queries resolve registered IDs through the same authorisation services as the UI. Do not resolve a spoken phrase into an arbitrary filesystem path.

## Initial actions

| Proposed intent | Result | Boundary |
| --- | --- | --- |
| Open Project | Focus/open its workspace | Registered accessible project only |
| Show Memory Page | Open approved content | Search/index opt-in and scope checks |
| Open Review | Show pending proposal review | Does not approve or apply |
| Prepare Agent Session | Open prefilled launch UI | No hidden command execution |
| Draft Prompt | Create a visible draft | Does not send it |
| Show Dreaming Report | Open latest eligible report | Sensitive content excluded by default |

Start with Shortcuts execution and entity resolution. Then verify Siri discovery, disambiguation and deep linking on the target system. An intent compiling successfully does not prove Siri chooses it for a user's phrase.

## Content exposure

Off by default for terminal output and private memory. Let the user choose which projects and approved page kinds can be indexed or exposed as on-screen context. Never expose credentials, `.env` content, raw prompts or pending observations through broad system search.

On-screen awareness should use a deliberately selected/sanitised entity representation, not an indiscriminate capture of the terminal buffer. Treat cloud-assisted system features as a separate disclosure surface from Trellis's local storage.

## Execution and concurrency

Use the same application service methods and policy checks as UI actions. An intent must not construct its own bypass path to the memory writer or process launcher. Resolve state again when performing an action because an entity may have been removed, disconnected or had permissions changed.

Read-only actions can return a useful result when no workspace is open. Side-effecting actions open a visible confirmation surface. Unknown user/session state fails safely rather than creating work in the wrong project.

## Verification

Test an unavailable project, ambiguous names, deleted memory page, locked/private scope and an app that was not running. Confirm that a pending proposal cannot be approved through a generic deep link. Capture actual Shortcuts/Siri results and record unavailable capabilities rather than fabricating a successful integration.
