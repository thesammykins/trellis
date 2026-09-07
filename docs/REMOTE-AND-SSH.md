# Remote persistence and SSH

## Preferred approach

Use `/usr/bin/ssh` and the user's existing host aliases, not a new SSH implementation. Let OpenSSH handle authentication, host keys, ProxyJump and existing configuration. Selective native UI can explain and launch these configurations without becoming a private-key manager. The upstream OpenSSH manual describes these features; verify supported options in the macOS-shipped client as well. [S25](../research/SOURCES.md#s25)

Use a remote tmux session to keep the shell or agent alive when the local terminal disconnects. The server owns that process lifetime. A tmux session does not automatically survive server reboot, and a saved transcript cannot restore a running process. [S26](../research/SOURCES.md#s26)

## Connection profile

Store a stable profile ID, host alias, user-visible label, remote project directory, selected agent, tmux session identity and intended memory scope. Credentials are references to an authentication mechanism, not key material in the profile. Record a separate attachment identity for each local connection.

Keep the effective host/account visible. Use OpenSSH's config inspection where appropriate, but remember that user SSH configuration can contain executable hooks such as ProxyCommand or Match exec. Do not execute arbitrary SSH configurations discovered inside a repository without explicit trust.

## Create versus reconnect

The first connection has an explicit setup step. Check the host, directory, selected CLI and tmux availability. Ask before installing anything remotely. Create the persistent session only on a new-session action and record its exact identity.

On reconnect, perform an attach-only lookup. Do not use a convenience “attach-or-create” operation in the restore path. A missing session is meaningful information: the machine rebooted, the session was closed or the profile is wrong. Re-running the startup command could duplicate expensive or destructive work.

Use a bounded, backoff-based connection retry that retries transport establishment only. It must not replay agent prompts or recreate jobs. Cancellation stops retries without killing the remote session.

## Remote command safety

OpenSSH remote commands introduce a remote-shell parsing boundary even when the local process was spawned with argv. Use a small audited serializer or a separately versioned remote helper. Do not claim local argv alone eliminates remote shell injection.

Keep generated tmux names restricted to a conservative ASCII namespace with an app prefix and random ID. Quote directory and command arguments for the actual remote shell. Prefer separate noninteractive preflight/create operations and an interactive attach operation, with independently tested handling of spaces, quotes and newlines.

Do not silently detach another client on reconnect. Do not kill all tmux sessions on cleanup. Only act on recorded app-owned sessions, and ask before terminating a workload.

## 1Password

Integrate through the supported 1Password SSH agent and OpenSSH `IdentityAgent` configuration. The user enables the agent in 1Password and authorises key use through its normal UI. Trellis can check configuration and explain connection errors without extracting the private key. [S23](../research/SOURCES.md#s23)[S24](../research/SOURCES.md#s24)

Do not require the 1Password CLI merely to use its SSH agent. Do not export keys into temporary files. Do not treat biometric unlock as authentication that Trellis itself owns.

Agent forwarding is off by default. Connecting to a host using a local agent does not require forwarding that agent into the remote host. A user who explicitly enables forwarding should see its expanded trust implications and exact host scope. Respect existing user configuration without silently rewriting it.

## Remote memory

A remote agent cannot read a local Mac path, and a laptop that is offline cannot serve a live local plugin connection. Begin with a versioned, approved memory snapshot copied over SSH to the remote project scope. Record the snapshot identity; explain that it is a snapshot rather than live synchronisation.

For full remote memory support, use an explicitly installed remote bridge or an authenticated tunnel with scoped credentials and lifecycle handling. If disconnected, collect remote candidate observations in a bounded private spool and reconcile them later as proposals. Do not sync global personal memory by default or allow a remote process to choose arbitrary local file paths.

## Essential recovery cases

Exercise network loss, app relaunch, a locked 1Password agent, changed host key, missing tmux, missing agent binary, server reboot and two simultaneous local attachments. A changed host key blocks rather than offering an automatic `StrictHostKeyChecking=no` workaround.

A screenshot of restored text is not proof. Compare the remote session identity and workload process before and after a disconnect, and record the actual result.
