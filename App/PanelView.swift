import SwiftUI
import UsageModel

/// The menu bar panel, carrying the Tauri widget's compact layout: per-provider
/// accent, bars, percentages, renewal time and the standby marker.
struct PanelView: View {
    @ObservedObject var store: UsageStore
    let openAccounts: () -> Void

    private var providers: [Provider] {
        (store.snapshot?.providers ?? []).filter { !$0.isUnconfigured }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if providers.isEmpty {
                Text(store.snapshot == nil ? "Collecting…" : "Nothing configured")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(providers, id: \.self) { ProviderCard(provider: $0) }
                }
                .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("AI Usage").font(.headline)
            if store.isFetching {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
            Spacer()
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            .disabled(store.isFetching)

            Button {
                // A menu bar app has no Dock icon, so the window would open
                // behind everything without activating first.
                NSApp.activate(ignoringOtherApps: true)
                openAccounts()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Accounts")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let snapshot = store.snapshot {
                Text("Updated \(snapshot.capturedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct ProviderCard: View {
    let provider: Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(provider.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(provider.accent)
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
                if !provider.plan.isEmpty {
                    Text(provider.plan.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(provider.displayLabel)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)

            if let error = provider.error {
                Text("! \(error)")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(provider.meters, id: \.self) { meter in
                MeterLine(provider: provider, meter: meter)
            }
            ForEach(provider.details, id: \.self) { detail in
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(detail.hasPrefix("⚠") ? .orange : .secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(provider.standby ? 0.6 : 1)
    }
}

private struct MeterLine: View {
    let provider: Provider
    let meter: Meter

    private var tint: Color {
        meter.isIdle ? .secondary : meter.severity.color(accent: provider.accent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(meter.composedLabel)
                    .font(.caption)
                    .foregroundStyle(meter.isIdle ? .tertiary : .secondary)
                Spacer(minLength: 4)
                Text(meter.percent == nil ? "--" : meter.displayPercent)
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(meter.isIdle ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                // A window that has not opened yet shows "-", not "0m", which
                // would imply it is about to renew.
                Text(meter.isIdle ? "-" : Formatting.resetRemaining(meter.resetAt))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(width: 52, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(tint)
                        .frame(width: max(2, geo.size.width * meter.fraction))
                }
            }
            .frame(height: 5)
            .opacity(meter.isIdle ? 0.4 : 1)
        }
    }
}
