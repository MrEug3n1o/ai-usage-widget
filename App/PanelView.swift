import SwiftUI
import UsageModel

/// The menu bar panel. Carries the Tauri widget's information — per-provider
/// accent, standby marker, plan, bars, percentages, renewal times — with the
/// same identity-first ordering the desktop widget uses, so the two surfaces
/// read alike.
struct PanelView: View {
    @ObservedObject var store: UsageStore
    let openAccounts: () -> Void

    private var providers: [Provider] {
        (store.snapshot?.providers ?? []).filter { !$0.isUnconfigured }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            content
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 340)
        // Deliberately no background. MenuBarExtra's own window already paints
        // the menu material, so anything set here stacks a SECOND material on
        // top of it and the panel reads pale next to real dropdowns — which is
        // what `.ultraThickMaterial` did here for two releases. Verified by
        // removing it: the panel still has a blurred background, the system's.
    }

    @ViewBuilder private var content: some View {
        if providers.isEmpty {
            Text(store.snapshot == nil ? "Collecting…" : "Nothing configured")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 30)
        } else {
            VStack(spacing: 8) {
                ForEach(providers, id: \.self) { ProviderCard(provider: $0) }
            }
            .padding(10)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text("AI Usage").font(.system(size: 14, weight: .semibold))
            if store.isFetching {
                ProgressView().controlSize(.small).scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            }
            Spacer()
            IconButton(symbol: "arrow.clockwise", help: "Refresh now") {
                Task { await store.refresh() }
            }
            .disabled(store.isFetching)
            IconButton(symbol: "gearshape", help: "Accounts") {
                // A menu bar app has no Dock icon, so the window would open
                // behind everything without activating first.
                NSApp.activate(ignoringOtherApps: true)
                openAccounts()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var footer: some View {
        HStack {
            if let snapshot = store.snapshot {
                Text("Updated \(snapshot.capturedAt.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// One account. Led by who it is, not by which provider — with two Claude
/// accounts the provider name is the part that does not distinguish them.
private struct ProviderCard: View {
    let provider: Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(provider.shortLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)
                // With two or more Claude accounts the collector flags standby
                // on the ones the CLI is not logged into: the unbadged one is
                // the account actually burning quota.
                if provider.standby {
                    Text("◉ standby")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Circle().fill(provider.accent).frame(width: 6, height: 6)
                    Text(provider.caption.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .layoutPriority(-1)
            }

            if let error = provider.error {
                Text(error)
                    .font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(provider.meters, id: \.self) { meter in
                MeterLine(provider: provider, meter: meter)
            }
            ForEach(provider.details, id: \.self) { detail in
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(detail.hasPrefix("⚠") ? .orange : .secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // No fill: a tinted card sat a shade darker than the panel behind it,
        // which is a seam rather than a grouping — the spacing between cards
        // already separates them.
        .opacity(provider.standby ? 0.62 : 1)
    }
}

private struct MeterLine: View {
    let provider: Provider
    let meter: Meter

    private var tint: Color {
        meter.isIdle ? .secondary : meter.severity.color(accent: provider.accent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(meter.composedLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(meter.isIdle ? .tertiary : .secondary)
                Spacer(minLength: 4)
                Text(meter.percent == nil ? "--" : meter.displayPercent)
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(meter.isIdle ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                // A window that has not opened yet shows "-", not "0m", which
                // would imply it is about to renew.
                Text(meter.isIdle ? "-" : Formatting.resetRemaining(meter.resetAt))
                    .font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
                    .frame(width: 54, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(tint)
                        .frame(width: max(3, geo.size.width * meter.fraction))
                }
            }
            .frame(height: 6)
            .opacity(meter.isIdle ? 0.4 : 1)
        }
    }
}
