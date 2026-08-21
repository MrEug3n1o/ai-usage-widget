# Phase 0 — host → widget data channel

**Question.** A WidgetKit extension cannot collect our data: the collector needs the login Keychain,
arbitrary paths (`~/.config/ai-usage-monitor`, `~/.claude*`, `~/.codex`), and a `codex` subprocess.
So the host app collects and the widget reads a snapshot. How does the snapshot get across?

Tested on macOS 26.6.2, Xcode 26.6, signing team `VG87LBRMTR` (**free personal team**).
Spike lives in `spike/` and is throwaway.

## Findings

### 1. The widget extension MUST be sandboxed

Built without `com.apple.security.app-sandbox`, the extension embeds and code-signs fine, `BUILD
SUCCEEDED`, the `.appex` is present in `Contents/PlugIns/` with a correct `NSExtension` dictionary —
and it **never registers**:

```
$ pluginkit -m -p com.apple.widgetkit-extension | grep -i spike
(nothing)
```

No build error, no runtime message, no log entry. `lsregister -f` and `pluginkit -a` do not help.
Adding the sandbox entitlement and rebuilding registers it immediately:

```
$ pluginkit -m -p com.apple.widgetkit-extension | grep -i spike
     dev.erickmenezes.aiusage.spike.widget(1.0)
```

**This kills the simplest design** (unsandboxed extension reading the config dir directly). It is
also a nasty failure mode to hit later: the symptom is "my widget isn't in the gallery" with nothing
anywhere explaining why.

### 2. The host app can stay unsandboxed

An unsandboxed host embedding a sandboxed extension is fine — signature verifies, extension
registers. This matters because our host cannot be sandboxed.

### 3. App Groups work on a free personal team — but only team-ID prefixed

Counter to the usual claim, the free team is not the obstacle. The Xcode-managed profile is a
`LocalProvision` and does **not** list `com.apple.security.application-groups`:

```
"com.apple.application-identifier" => "VG87LBRMTR.dev.erickmenezes.aiusage.spike.widget"
"com.apple.developer.team-identifier" => "VG87LBRMTR"
"keychain-access-groups" => ["VG87LBRMTR.*"]
```

macOS validates the entitlement from the *signature* instead, so the group still works. The group
**id** is what matters:

| Group id | Sandboxed extension read |
|---|---|
| `group.dev.erickmenezes.aiusage` | ✗ "you don't have permission to view it" |
| `VG87LBRMTR.group.dev.erickmenezes.aiusage` | ✓ |

This is the documented rule for macOS apps signed outside the Mac App Store: the group id must begin
with the team identifier. Do not trust the container's mere existence as evidence — with the
unprefixed id `containermanagerd` still created a fully managed container, the unsandboxed host still
wrote into it, and only the *sandboxed reader* was denied. The failure is invisible from the host
side.

(`../disk-usage-widget` uses an unprefixed `group.com.erickmenezes.DiskUsage` and does work — its
`lowSpace.*` keys really are in the group container, not fallen back to `.standard`. Its host app is
sandboxed, which ours cannot be. Prefixed is the form that works in *our* configuration and the form
Apple documents, so use it.)

### 4. Requesting App Groups forces a provisioning profile

With no entitlements the build signs with no profile at all. Adding the App Group makes signing fail
until `-allowProvisioningUpdates` is passed, after which Xcode generates a local profile. That
profile carries **`TimeToLive => 7`** (days).

Whether macOS refuses to launch once the embedded profile expires is **not verified** — watch for
it. Mitigation is a rebuild (one command), or Channel B below, which needs no entitlement and so no
profile at all.

## Results

Probed from the running extension (`log show --predicate 'subsystem == "dev.erickmenezes.aiusage.spike"'`
— note `log` is a zsh builtin, use `/usr/bin/log`):

| Channel | Host write | Sandboxed widget read |
|---|---|---|
| **A** — widget reads `~/.config/ai-usage-monitor` directly | n/a | ✗ denied, and an unsandboxed widget never registers at all |
| **B** — host writes into `~/Library/Containers/<widget-id>/Data/` | ✓ | ✓ |
| **C** — App Group, team-ID prefixed | ✓ | ✓ |

## Decision

**Channel C — App Group `VG87LBRMTR.group.<bundle-prefix>`.** Host writes `snapshot.json` there;
the sandboxed widget reads it. Supported, documented, and survives the host being unsandboxed.

Keep the `SnapshotStore` protocol as planned. If profile expiry proves painful, **Channel B** is a
verified fallback: no entitlement, no profile, no expiry — at the cost of writing into a bundle
container we do not own.

## Configuration that follows

- Host: unsandboxed, hardened runtime, `com.apple.security.application-groups` with the prefixed id.
- Widget: `com.apple.security.app-sandbox` **plus** the same prefixed group.
- `GENERATE_INFOPLIST_FILE: NO` on the extension target — with `YES`, Xcode synthesizes its own
  Info.plist and drops the `NSExtension` key, and the widget vanishes from the gallery with no error
  (learned in `../disk-usage-widget/project.yml`).
- Build with `-allowProvisioningUpdates`.
- Install to `/Applications` from a **scheme post-action**, not a target build phase: target phases
  run before code-signing, so the copied app is unsigned and launchd rejects it with RBS error 163
  (also from `../disk-usage-widget`).

## Status

Resolved. Both surviving channels verified end to end against a running extension.
