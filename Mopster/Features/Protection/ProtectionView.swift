import MopsterCore
import SwiftUI

struct ProtectionView: View {
    let model: ProtectionViewModel

    @ViewBuilder var body: some View {
        Group {
            switch model.flow.phase {
            case .results, .removing, .done:
                results
            case .failed(let message):
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(.orange)
                    Text("The scan failed").font(.title2.bold())
                    Text(message).foregroundStyle(.secondary)
                    Button("Retry", action: model.refresh).buttonStyle(.borderedProminent)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .intro, .scanning:
                ProgressView("Checking…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if case .intro = model.flow.phase { model.refresh() }
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            HStack {
                if model.itemsToReview == 0 {
                    Text("Nothing to review").font(.headline)
                } else {
                    Text("\(model.itemsToReview) items to review").font(.headline).monospacedDigit()
                }
                Spacer()
                Button("Refresh", action: model.refresh)
                    .controlSize(.small)
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)
            List {
                Section("Security checklist") {
                    ForEach(model.checks) { check in
                        CheckRow(check: check, isChecking: check.id == .pendingMacOSUpdates && model.isCheckingSystemUpdates)
                    }
                }
                ForEach(Self.domains, id: \.self) { domain in
                    let rows = model.items.filter { $0.item.domain == domain }
                    if !rows.isEmpty {
                        Section(Self.title(for: domain)) {
                            ForEach(rows) { item in
                                LaunchItemRow(
                                    item: item, isBusy: model.busyItemID == item.id,
                                    canToggle: model.canToggle(item),
                                    reveal: { model.reveal(item) },
                                    toggle: { model.requestToggle(item) },
                                    remove: { model.requestRemove(item) })
                            }
                        }
                    }
                }
            }
            Divider()
            Text(
                "Mopster is not an antivirus. macOS's built-in XProtect checks apps against known malware signatures."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .confirmationDialog(
            dialogTitle, isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } }),
            titleVisibility: .visible, presenting: model.pending
        ) { action in
            switch action {
            case .disable:
                Button("Disable") { model.confirm(action) }
            case .remove:
                Button("Move to Trash", role: .destructive) { model.confirm(action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            switch action {
            case .disable:
                Text("It stops running now and stays off until you enable it again.")
            case .remove(let item) where item.item.domain == .userAgents:
                Text("The file moves to the Trash, where you can restore it.")
            case .remove:
                Text("The file moves to the Trash. macOS will ask for your administrator password.")
            }
        }
        .alert(
            "That didn't work",
            isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
        ) {
            Button("OK") { model.actionError = nil }
        } message: {
            Text(verbatim: model.actionError ?? "")
        }
    }

    private var dialogTitle: Text {
        switch model.pending {
        case .disable(let item)?: Text("Disable “\(LaunchItemRow.name(of: item))”?")
        case .remove(let item)?: Text("Remove “\(LaunchItemRow.name(of: item))”?")
        case nil: Text(verbatim: "")
        }
    }

    private static let domains: [LaunchDomain] = [.userAgents, .systemAgents, .systemDaemons]

    private static func title(for domain: LaunchDomain) -> LocalizedStringKey {
        switch domain {
        case .userAgents: "Your agents"
        case .systemAgents: "All users' agents"
        case .systemDaemons: "System daemons"
        }
    }
}

private struct CheckRow: View {
    let check: SecurityCheck
    var isChecking = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isChecking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbol).foregroundStyle(color).font(.title3)
                }
            }
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                phrase.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isChecking, let pane = Self.pane(for: check.id) {
                Button("Open Settings") { SystemSettings.open(pane) }.controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch check.status {
        case .ok: "checkmark.shield"
        case .warning: "exclamationmark.shield"
        case .unknown: "questionmark.circle"
        }
    }

    private var color: Color {
        switch check.status {
        case .ok: .green
        case .warning: .orange
        case .unknown: .secondary
        }
    }

    private var title: LocalizedStringKey {
        switch check.id {
        case .sip: "System Integrity Protection"
        case .gatekeeper: "Gatekeeper"
        case .fileVault: "FileVault"
        case .firewall: "Firewall"
        case .xprotect: "XProtect definitions"
        case .autoSecurityUpdates: "Automatic security updates"
        case .pendingMacOSUpdates: "Pending macOS updates"
        }
    }

    private var phrase: Text {
        if isChecking { return Text("Checking…") }
        switch (check.id, check.status) {
        case (.xprotect, .ok):
            if let detail = check.detail { return Text("Version \(detail)") }
            return Text("On")
        case (.pendingMacOSUpdates, .ok): return Text("Up to date")
        case (.pendingMacOSUpdates, .warning):
            return check.detail.map { Text(verbatim: $0) } ?? Text("Updates available")
        case (_, .ok): return Text("On")
        case (_, .warning): return Text("Off")
        case (_, .unknown): return Text("Unknown")
        }
    }

    static func pane(for id: SecurityCheckID) -> SystemSettings.Pane? {
        switch id {
        case .sip, .xprotect: nil
        case .gatekeeper: .privacySecurity
        case .fileVault: .fileVault
        case .firewall: .firewall
        case .autoSecurityUpdates, .pendingMacOSUpdates: .softwareUpdate
        }
    }
}

private struct LaunchItemRow: View {
    let item: InspectedLaunchItem
    let isBusy: Bool
    let canToggle: Bool
    let reveal: () -> Void
    let toggle: () -> Void
    let remove: () -> Void

    static func name(of item: InspectedLaunchItem) -> String {
        item.item.label ?? item.item.plist.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(Self.name(of: item)).font(.body).lineLimit(1).truncationMode(.middle)
                    if item.isDisabled { Chip(text: "Disabled") }
                }
                programText
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let badge = signatureBadge { Chip(text: badge, tinted: true) }
                    ForEach(Array(visibleFlags.enumerated()), id: \.offset) { _, flag in
                        Chip(text: hint(for: flag), tinted: true)
                    }
                }
            }
            Spacer(minLength: 8)
            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    Button(action: reveal) { Image(systemName: "folder") }
                        .help("Reveal in Finder")
                        .accessibilityLabel("Reveal in Finder")
                    if canToggle {
                        Button(item.isDisabled ? "Enable" : "Disable", action: toggle)
                    }
                    Button(action: remove) { Image(systemName: "trash") }
                        .help("Remove")
                        .accessibilityLabel("Remove")
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .help(item.item.plist.path)
    }

    private var hasUsableProgram: Bool {
        guard let program = item.item.program else { return false }
        return program.hasPrefix("/") || item.signature != .missing
    }

    @ViewBuilder private var programText: some View {
        if hasUsableProgram, let program = item.item.program {
            Text(program)
        } else {
            Text("No program listed")
        }
    }

    private var signatureBadge: LocalizedStringKey? {
        if item.item.isUnreadable { return "Couldn't be read" }
        guard hasUsableProgram else { return nil }
        let coveredByFlag =
            (item.signature == .unsigned || item.signature == .adHoc) && visibleFlags.contains(.unsignedOrAdHoc)
            || (item.signature == .missing && visibleFlags.contains(.programMissing))
        if coveredByFlag { return nil }
        switch item.signature {
        case .apple: return "Apple"
        case .developerID(let team): return "Developer ID (\(team))"
        case .adHoc: return "Ad hoc"
        case .unsigned: return "Unsigned"
        case .invalid: return "Invalid signature"
        case .missing: return "Program not found"
        }
    }

    /// "Program not found" would contradict "No program listed".
    private var visibleFlags: [PersistenceFlag] {
        hasUsableProgram ? item.flags : item.flags.filter { $0 != .programMissing }
    }

    private func hint(for flag: PersistenceFlag) -> LocalizedStringKey {
        switch flag {
        case .programMissing: "Program not found"
        case .unsignedOrAdHoc: item.signature == .adHoc ? "Ad hoc signature" : "Unsigned"
        case .hiddenOrTemporaryLocation: "Hidden or temporary location"
        case .knownAdware: "Name matches a known adware list"
        }
    }
}

/// Neutral capsule: flags are review hints, never alarms.
struct Chip: View {
    let text: LocalizedStringKey
    var tinted = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(tinted ? 0.18 : 0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }
}
