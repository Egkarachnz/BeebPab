import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(PresetStore.self) private var presets
    @Environment(\.openSettings) private var openSettings
    @AppStorage("keepCameraInfo") private var keepCameraInfo = false

    private var selectedCount: Int { presets.catalog.orderedKeys(in: model.selectedTargets).count }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        StepHeader(number: 2, title: "เลือกเป้าหมาย", symbol: "scope", isComplete: selectedCount > 0)
                        PlatformPicker()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        StepHeader(number: 3, title: "เลือกโฟลเดอร์บันทึก", symbol: "folder",
                                   isComplete: model.outputFolder != nil)
                        OutputFolderCard()
                    }
                }
                .padding(16)
            }

            VStack(alignment: .leading, spacing: 10) {
                if model.isProcessing {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("กำลังย่อภาพ…", systemImage: "gearshape.2.fill")
                                .symbolEffect(.pulse)
                            Spacer()
                            Text("\(model.completedTasks)/\(model.totalTasks)").monospacedDigit()
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.blue)
                        ProgressView(value: Double(model.completedTasks), total: Double(max(model.totalTasks, 1)))
                            .tint(Theme.blue)
                    }
                } else if let summary = model.lastRunSummary {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.green)
                        Text(summary)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button { model.revealOutputFolder() } label: {
                            Label("เปิดใน Finder", systemImage: "folder.fill")
                        }
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.green.opacity(0.12)))
                }

                Button {
                    model.process(catalog: presets.catalog, options: ProcessOptions(keepCameraInfo: keepCameraInfo))
                } label: {
                    Label(buttonTitle, systemImage: "wand.and.stars")
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canProcess(with: presets.catalog))

                if let hint, !model.isProcessing {
                    Label(hint, systemImage: model.pendingImageCount(with: presets.catalog) == 0 && !model.jobs.isEmpty
                          && selectedCount > 0 && model.outputFolder != nil ? "checkmark.circle" : "arrow.turn.left.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                PresetStatusPill { openSettings() }
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var buttonTitle: String {
        let pending = model.pendingImageCount(with: presets.catalog)
        guard pending > 0, selectedCount > 0 else { return "ย่อภาพ" }
        let isAddition = pending < model.jobs.count
        let noun = isAddition ? "ภาพที่ยังไม่ได้ย่อ" : "ภาพ"
        return "ย่อ\(noun) \(pending) ภาพ" + (selectedCount > 1 ? " × \(selectedCount) แบบ" : "")
    }

    /// Tells the user which step is still missing.
    private var hint: String? {
        if model.jobs.isEmpty { return "เพิ่มภาพก่อน (ขั้นที่ 1)" }
        if selectedCount == 0 { return "เลือกเป้าหมายอย่างน้อย 1 แบบ (ขั้นที่ 2)" }
        if model.outputFolder == nil { return "เลือกโฟลเดอร์บันทึก (ขั้นที่ 3)" }
        if model.pendingImageCount(with: presets.catalog) == 0 {
            return "ย่อครบทุกภาพแล้ว · คลิกขวาที่ภาพเพื่อย่อใหม่"
        }
        return nil
    }
}

private struct OutputFolderCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.chooseOutputFolder() } label: {
            HStack(spacing: 10) {
                IconTile(symbol: model.outputFolder == nil ? "folder.badge.plus" : "folder.fill",
                         color: model.outputFolder == nil ? .secondary : Theme.blue, size: 36,
                         filled: model.outputFolder != nil)
                VStack(alignment: .leading, spacing: 2) {
                    if let folder = model.outputFolder {
                        Text(folder.lastPathComponent)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(folder.deletingLastPathComponent().path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    } else {
                        Text("คลิกเพื่อเลือกโฟลเดอร์")
                            .font(.system(size: 13, weight: .semibold))
                        Text("ภาพที่ย่อแล้วจะถูกบันทึกที่นี่")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card(cornerRadius: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(model.outputFolder == nil ? Theme.blue.opacity(0.45) : .clear,
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .help(model.outputFolder?.path ?? "เลือกโฟลเดอร์สำหรับบันทึกภาพ")
        .disabled(model.isProcessing)
    }
}

struct PlatformPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(PresetStore.self) private var presets

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(presets.catalog.platforms) { platform in
                let color = Theme.platformColor(platform.id)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        IconTile(symbol: Theme.platformSymbol(platform.id), color: color, size: 24)
                        Text(platform.name).font(.system(size: 14, weight: .bold))
                        Spacer()
                        let count = platform.targets.filter {
                            model.selectedTargets.contains(TargetKey(platformID: platform.id, targetID: $0.id))
                        }.count
                        if count > 0 { Chip(text: "เลือก \(count)", color: color) }
                    }

                    ForEach(platform.targets) { target in
                        TargetCard(platformID: platform.id, target: target, color: color)
                    }

                    if let note = platform.note {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill").foregroundStyle(Theme.orange)
                            Text(note).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.orange.opacity(0.09)))
                    }
                }
            }
        }
    }
}

private struct TargetCard: View {
    @Environment(AppModel.self) private var model
    let platformID: String
    let target: OutputTarget
    let color: Color
    @State private var isHovering = false

    var body: some View {
        let key = TargetKey(platformID: platformID, targetID: target.id)
        let selected = model.selectedTargets.contains(key)
        Button {
            withAnimation(.easeOut(duration: 0.12)) { model.toggle(key) }
        } label: {
            HStack(spacing: 10) {
                IconTile(symbol: Theme.symbol(for: target), color: color, size: 32, filled: selected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(target.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? color : Color.secondary.opacity(0.5))
            }
            .padding(8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? color.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? color : Color.secondary.opacity(isHovering ? 0.35 : 0.15),
                                  lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(target.detail ?? target.summary)
        .disabled(model.isProcessing)
    }
}

private struct PresetStatusPill: View {
    @Environment(PresetStore.self) private var presets
    var action: () -> Void

    var body: some View {
        let ok = presets.lastError == nil
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(ok ? Theme.green : Theme.orange)
                    .frame(width: 7, height: 7)
                Text("ข้อมูลขนาดภาพ \(presets.catalog.updatedAt) · \(presets.origin.label)")
                if presets.isRefreshing { ProgressView().controlSize(.mini) }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(presets.lastError ?? "ระบบตรวจขนาดภาพล่าสุดของ Facebook และ LINE ให้อัตโนมัติ · คลิกเพื่อดูรายละเอียด")
    }
}
