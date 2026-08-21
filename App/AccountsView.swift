import SwiftUI
import UsageModel
import UsageCollector

/// Account management. This lives in the app and not the widget because the
/// widget is sandboxed: it can reach neither the Keychain nor the config dir.
///
/// Laid out as a grouped Form, which is the shape macOS Settings uses — the
/// sections read as sections without hand-drawn boxes, and the window sizes
/// itself to the content instead of leaving a slab of empty space below it.
struct AccountsView: View {
    @ObservedObject var store: UsageStore

    @State private var detection: Accounts.Detection?
    @State private var busy: String?
    @State private var message: (text: String, isError: Bool)?

    /// Registered accounts come from the last reading rather than from
    /// re-identifying each profile, which would mean a network round trip and a
    /// Keychain prompt just to draw a list.
    private var registered: [Provider] {
        (store.snapshot?.providers ?? []).filter { $0.name == "Claude" }
    }

    private var registeredEmails: Set<String> {
        Set(registered.map { $0.email.lowercased() }.filter { !$0.isEmpty })
    }

    /// Sources whose account is already registered are not offered again.
    private var offerable: [Accounts.Candidate] {
        (detection?.claude ?? []).filter { candidate in
            guard let email = candidate.email?.lowercased(), !email.isEmpty else { return true }
            return !registeredEmails.contains(email)
        }
    }

    var body: some View {
        Form {
            claudeSection
            availableSection
            CursorSection(configured: detection?.cursorConfigured ?? false, onChange: reload)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 400, maxHeight: 700)
        .task { detection = Accounts.detect() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let message {
                HStack(spacing: 6) {
                    Image(systemName: message.isError
                          ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text(message.text).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(message.isError ? .red : .secondary)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
        }
    }

    private var claudeSection: some View {
        Section("Claude accounts") {
            if registered.isEmpty {
                Text("None registered yet.").foregroundStyle(.secondary)
            }
            ForEach(registered, id: \.self) { provider in
                HStack(spacing: 10) {
                    Circle().fill(provider.accent).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(provider.displayLabel)
                            .lineLimit(1).truncationMode(.middle)
                        Text(provider.plan.isEmpty
                             ? provider.account : "\(provider.account) · \(provider.plan)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Remove") { remove(provider.account) }
                        .disabled(busy != nil)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var availableSection: some View {
        Section {
            if offerable.isEmpty {
                Text("Every Claude Code login on this Mac is already registered.")
                    .foregroundStyle(.secondary)
            }
            ForEach(offerable) { candidate in
                HStack(spacing: 10) {
                    Image(systemName: candidate.id.hasPrefix("keychain:")
                          ? "key.fill" : "doc.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(candidate.label).lineLimit(1)
                        if let email = candidate.email {
                            Text(email).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 8)
                    if busy == candidate.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Add") { add(candidate) }.disabled(busy != nil)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Available on this Mac")
        } footer: {
            // Listing never reads a secret; Add does, and that is what prompts.
            Text("Adding an account reads its credential, so macOS asks for "
                 + "permission the first time.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func add(_ candidate: Accounts.Candidate) {
        busy = candidate.id
        message = nil
        Task {
            defer { busy = nil }
            do {
                let result = try await Accounts.addClaude(candidate.id)
                message = (result.already
                    ? "\(result.email) was already registered as \(result.profile); its source now points here."
                    : "Added \(result.email) as \(result.profile).", false)
                reload()
            } catch {
                message = (error.localizedDescription, true)
            }
        }
    }

    private func remove(_ profile: String) {
        do {
            try Accounts.removeClaude(profile)
            message = ("Removed \(profile).", false)
            reload()
        } catch {
            message = (error.localizedDescription, true)
        }
    }

    private func reload() {
        detection = Accounts.detect()
        Task { await store.refresh() }
    }
}

/// Cursor takes a key rather than a login, so it is a form rather than a list.
private struct CursorSection: View {
    let configured: Bool
    let onChange: () -> Void

    @State private var method = "admin_key"
    @State private var secret = ""
    @State private var email = ""
    @State private var message: (text: String, isError: Bool)?

    var body: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 8) {
                    Text(configured ? "Configured" : "Not configured")
                        .foregroundStyle(.secondary)
                    if configured {
                        Button("Remove") {
                            do {
                                try Accounts.removeCursor()
                                message = ("Removed.", false)
                                onChange()
                            } catch {
                                message = (error.localizedDescription, true)
                            }
                        }
                    }
                }
            }
            Picker("Method", selection: $method) {
                Text("Team admin key").tag("admin_key")
                Text("Dashboard cookie").tag("dashboard_cookie")
            }
            // In a grouped Form the first string is the row's LABEL, not a
            // placeholder — passing "key_…" there labelled the row "key_…"
            // beside an empty box. The example goes in `prompt`.
            //
            // SecureField because these are credentials and this window can be
            // open while a screen is being shared.
            SecureField(method == "admin_key" ? "Admin key" : "Session cookie",
                        text: $secret,
                        prompt: Text(method == "admin_key"
                                     ? "key_…" : "WorkosCursorSessionToken=…"))
            if method == "admin_key" {
                TextField("Email", text: $email, prompt: Text("you@company.com"))
            }
            HStack {
                Spacer()
                Button("Save") {
                    do {
                        try Accounts.saveCursor(method: method, secret: secret, email: email)
                        secret = ""
                        message = ("Saved.", false)
                        onChange()
                    } catch {
                        message = (error.localizedDescription, true)
                    }
                }
                .disabled(secret.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            if let message {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(message.isError ? .red : .secondary)
            }
        } header: {
            Text("Cursor")
        } footer: {
            if method == "dashboard_cookie" {
                Text("The team admin key is preferred; the dashboard endpoint is "
                     + "internal and may break without notice.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
