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

### 3. App Groups work on a free personal team

Counter to the usual claim. The Xcode-managed profile is a `LocalProvision` and does **not** list
`com.apple.security.application-groups`:

```
"com.apple.application-identifier" => "VG87LBRMTR.dev.erickmenezes.aiusage.spike.widget"
"com.apple.developer.team-identifier" => "VG87LBRMTR"
"keychain-access-groups" => ["VG87LBRMTR.*"]
```

But macOS validates the entitlement from the *signature*, not the profile. `containermanagerd`
provisioned a real managed container anyway:

```
~/Library/Group Containers/group.dev.erickmenezes.aiusage/
  .com.apple.containermanagerd.metadata.plist   <- system-managed, not a plain mkdir
  Library/
  spike-C.json                                   <- written by the unsandboxed host
```

`../disk-usage-widget` independently confirms this: same team, sandboxed app, working App Group.

Note the group id has **no team-ID prefix** (`group.dev.erickmenezes.aiusage`), matching the
convention the disk widget uses.

### 4. Requesting App Groups forces a provisioning profile

With no entitlements the build signs with no profile at all. Adding the App Group makes signing fail
until `-allowProvisioningUpdates` is passed, after which Xcode generates a local profile. That
profile carries **`TimeToLive => 7`** (days).

Whether macOS refuses to launch the app once the embedded profile expires is **not yet verified** —
watch for it. If it bites, the mitigation is either a rebuild (one command) or switching to the
container channel below, which needs no entitlement and therefore no profile at all.

## Decision

**Channel C — App Group `group.dev.erickmenezes.aiusage`.** Host writes `snapshot.json` there;
sandboxed widget reads it.

Keep the `SnapshotStore` protocol as planned. The fallback if profile expiry proves painful is
**Channel B**: the host writes into `~/Library/Containers/<widget-bundle-id>/Data/`, which the
sandboxed extension reads as its own `NSHomeDirectory()`. No entitlement, no profile, no expiry —
at the cost of writing into a bundle container we do not own.

## Configuration that follows

- Host: unsandboxed, hardened runtime, `com.apple.security.application-groups`.
- Widget: `com.apple.security.app-sandbox` **plus** the same group.
- `GENERATE_INFOPLIST_FILE: NO` on the extension target — with `YES`, Xcode synthesizes its own
  Info.plist and drops the `NSExtension` key, and the widget vanishes from the gallery with no error
  (learned in `../disk-usage-widget/project.yml`).
- Build with `-allowProvisioningUpdates`.
- Install to `/Applications` from a **scheme post-action**, not a target build phase: target phases
  run before code-signing, so the copied app is unsigned and launchd rejects it with RBS error 163
  (also from `../disk-usage-widget`).

## Open item

Widget-side read of both channels is not yet confirmed — it needs the extension to actually run,
which means adding the Spike widget from the gallery once. The spike widget renders a ✓/✗ per
channel for exactly this.
