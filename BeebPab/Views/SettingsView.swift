import SwiftUI

struct SettingsView: View {
    @Environment(PresetStore.self) private var presets
    @AppStorage("keepCameraInfo") private var keepCameraInfo = false

    var body: some View {
        Form {
            Section("ความเป็นส่วนตัว") {
                Toggle("เก็บข้อมูลกล้อง (EXIF) ไว้ในไฟล์", isOn: $keepCameraInfo)
                Text("ตำแหน่ง GPS จะถูกลบออกเสมอ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("ข้อมูลขนาดภาพของแพลตฟอร์ม") {
                LabeledContent("ฉบับวันที่", value: presets.catalog.updatedAt)
                LabeledContent("แหล่งข้อมูล", value: presets.origin.label)
                LabeledContent("ตรวจสอบล่าสุด") {
                    Text(presets.lastChecked.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "ยังไม่เคย")
                }
                if let error = presets.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                HStack {
                    Text("ระบบจะตรวจหาค่าใหม่ทุก 24 ชั่วโมงโดยอัตโนมัติ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if presets.isRefreshing { ProgressView().controlSize(.small) }
                    Button("ตรวจสอบตอนนี้") { Task { await presets.refresh() } }
                        .disabled(presets.isRefreshing)
                }
            }

            ForEach(presets.catalog.platforms) { platform in
                Section(platform.name) {
                    ForEach(platform.targets) { target in
                        LabeledContent(target.name) {
                            HStack(spacing: 6) {
                                Text(target.summary).foregroundStyle(.secondary)
                                if let source = target.source, let url = URL(string: source) {
                                    Link(destination: url) { Image(systemName: "link") }
                                        .help("ที่มาของข้อมูล")
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
    }
}
