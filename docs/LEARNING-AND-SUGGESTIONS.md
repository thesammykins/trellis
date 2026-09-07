# Learning and native suggestions

## Two presentations, one application

Advanced mode favours density and direct control. Learning mode adds contextual explanations and verification guidance. Neither changes execution permissions, model credentials, active process or project files. A learner is not a less trusted operator and an advanced user is not exempt from clear approvals.

Keep learning preferences editable. Record only explicit choices such as “explain unfamiliar shell flags” or “prefer short examples.” Do not infer a durable skill level from mistakes, hesitation or a single interaction.

## Initial explanation flow

The user selects terminal text, a proposed command or a diff and chooses Explain. Preview the selected context and model route when transmission is not already authorised for that scope. Return a short explanation with: what is happening, why it matters, what can change and how to check the result.

Make one next action prominent. Deeper detail is expandable. Questions should build understanding, not turn every command into a mandatory lesson. The explanation is a side task with its own cancellation and history, not a hidden prompt inserted into the active agent.

A model explanation is not proof a command is safe. Distinguish observed facts, assumptions and possible consequences. Do not label generated advice “verified” unless an actual check supports that claim.

## Suggestions are a shell feature

Begin with deterministic history/path completions in a supported shell integration, initially zsh. Add optional model-assisted command suggestions after the input-state contract works. Native UI can display candidates adjacent to the terminal, but inserting them requires a verified shell editing context.

Eligibility requires: known interactive shell prompt, supported editor state, no active IME composition, no protected input, no alternate-screen/raw application and a request tied to the current buffer revision. Unknown state disables insertion.

At request time, snapshot the buffer revision and authorised context. Cancel or discard a response when the user changes the command line, project, session, prompt state or focus. Acceptance inserts text without a trailing newline. Return remains a separate explicit execution action.

Never intercept a password prompt or a full-screen agent's editor. Do not send raw keystrokes to a provider. Unsupported shells still work as terminals; they simply do not receive inline assistance.

## Learning content sources

Prefer reviewed project conventions, selected output and explicit user questions. A project-specific answer can link to an approved wiki page. If a memory page is stale or merely proposed, label that state and do not present it as a rule.

Useful topics include reading errors, understanding process output, choosing a small change, reviewing a diff, checking assumptions and deciding which verification is worth doing. Avoid a generic course catalogue until actual use shows a need.

## Acceptance behaviours

Switching modes does not recreate the session. A delayed model response cannot overwrite new shell input. Accept never executes. Moving into an agent TUI removes shell suggestions. The user can disable learning and cloud suggestions independently while keeping memory and normal terminal operation.
