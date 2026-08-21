import SwiftUI
import UsageModel
import UsageCollector

/// Account management. This lives in the app and not the widget because the
/// widget is sandboxed: it can reach neither the Keychain nor the config dir.
struct AccountsView: View {
    @ObservedObject var store: UsageStore

    @State private var detection: Accounts.Detection?
    @State private var busy: String?
    @State private var message: (text: String, isError: Bool)?

    /// Registered Claude accounts, taken from the last reading rather than by
    /// re-identifying each profile — that would mean a network round trip and a
    /// Keychain prompt just to draw the list.
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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                claudeSection
                Divider()
                CursorSection(configured: detection?.cursorConfigured ?? false,
                              onChange: reload)
            }
            .padding(20)
        }
        .frame(width: 460, height: 560)
        .task { detection = Accounts.detect() }
        .safeAreaInset(edge: .bottom) {
            if let message {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(message.isError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(.bar)
            }
        }
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude accounts").font(.headline)

            if registered.isEmpty {
                Text("No accounts registered yet.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(registered, id: \.self) { provider in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayLabel).font(.callout.weight(.medium))
                        Text(provider.plan.isEmpty ? provider.account
                                                   : "\(provider.account) · \(provider.plan)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove") { remove(provider.account) }
                        .disabled(busy != nil)
                }
                .padding(.vertical, 2)
            }

            Text("Available on this Mac").font(.subheadline).padding(.top, 6)
            if offerable.isEmpty {
                Text("Every login found here is already registered.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(offerable) { candidate in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.label).font(.callout)
                        if let email = candidate.email {
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if busy == candidate.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Add") { add(candidate) }.disabled(busy != nil)
                    }
                }
                .padding(.vertical, 2)
            }
            // Reading the secret is what triggers the prompt; listing above
            // never touches one.
            Text("Adding an account reads its credential, so macOS will ask for "
                 + "permission the first time.")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.top, 2)
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
                    ? "\(result.email) was already registered as \(result.profile); its source was re-pointed here."
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cursor").font(.headline)
                Spacer()
                if configured {
                    Button("Remove") {
                        do { try Accounts.removeCursor(); message = ("Removed.", false); onChange() }
                        catch { message = (error.localizedDescription, true) }
                    }
                }
            }
            Text(configured ? "Configured." : "Not configured.")
                .font(.caption).foregroundStyle(.secondary)

            Picker("Method", selection: $method) {
                Text("Team admin key").tag("admin_key")
                Text("Dashboard cookie").tag("dashboard_cookie")
            }
            .pickerStyle(.segmented)

            // SecureField: these are credentials, and this window can be on
            // screen while sharing one.
            SecureField(method == "admin_key" ? "key_…" : "WorkosCursorSessionToken=…",
                        text: $secret)
            if method == "admin_key" {
                TextField("Your email on the team", text: $email)
            } else {
                Text("The team admin key is preferred; the dashboard endpoint is "
                     + "internal and may break without notice.")
                    .font(.caption2).foregroundStyle(.secondary)
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
        }
    }
}
