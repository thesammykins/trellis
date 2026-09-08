# App Intents and system discovery

`Trellis/TrellisIntents.swift` defines two native App Shortcuts:

| Action | Behavior |
| --- | --- |
| Open Project | Open a registered project in the app |
| Show Project Memory | Open the memory view for a registered project |

`ProjectEntity` resolves projects from the saved workspace archive. Performing an
intent revalidates that the project is still registered, then hands the request to
the app's main-actor navigation. It does not resolve a spoken phrase into an
arbitrary path or expose an unrestricted command runner.

These intents compile with the app. Live Shortcuts invocation, Siri discovery,
disambiguation and behavior while the app is closed have not been verified in the
latest pass. Compiler success is not evidence that Siri chooses an action for a
spoken phrase. See [current status](STATUS.md).

## Boundaries for future actions

Use the same service methods and policy checks as UI actions. A system action must
not bypass memory review or process-launch approval. Unknown, removed or private
entities should fail safely instead of creating work in another project.

Do not expose terminal transcripts, credentials, raw prompts or pending proposals
through broad search or on-screen context. Any future content indexing needs an
explicit scope and disclosure decision. No such indexing is claimed here.

Verify missing projects, ambiguous names, app-closed behavior and actual system
invocation before documenting broader support. Use Apple's
[App Intents documentation](https://developer.apple.com/documentation/appintents)
and the installed SDK when extending the integration.
