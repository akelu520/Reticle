import AppKit
import ReticleCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let onHotkeyChange: (HotkeyCenter.Action) -> Bool
    let onRecordingShortcut: (Bool) -> Void

    @State private var captureHotkey = Preferences.captureHotkey
    @State private var recordHotkey = Preferences.recordHotkey
    @State private var conflicts: Set<HotkeyCenter.Action> = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var saveDirectory = Preferences.saveDirectory
    @State private var historyEnabled = Preferences.historyEnabled

    var body: some View {
        Form {
            Section("快捷键") {
                hotkeyRow("截图", combo: $captureHotkey, action: .capture, defaultCombo: .defaultCapture)
                hotkeyRow("录屏", combo: $recordHotkey, action: .record, defaultCombo: .defaultRecord)
            }
            Section("通用") {
                Toggle("开机时启动", isOn: $launchAtLogin)
                Toggle("保存截图历史（菜单栏 › 最近截图，保留 \(ScreenshotHistoryStore.defaultLimit) 张）", isOn: $historyEnabled)
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("默认保存目录") {
                    HStack {
                        Text(saveDirectory.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("选择…", action: chooseDirectory)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: captureHotkey) { _, newValue in apply(newValue, for: .capture) }
        .onChange(of: recordHotkey) { _, newValue in apply(newValue, for: .record) }
        .onChange(of: historyEnabled) { _, on in Preferences.historyEnabled = on }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                launchError = nil
            } catch {
                launchError = "设置失败：\(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private func hotkeyRow(_ title: String, combo: Binding<HotkeyCombo>, action: HotkeyCenter.Action, defaultCombo: HotkeyCombo) -> some View {
        LabeledContent(title) {
            HStack {
                HotkeyRecorder(combo: combo, onRecording: onRecordingShortcut)
                    .frame(width: 140, height: 24)
                Button("恢复默认") { combo.wrappedValue = defaultCombo }
                    .disabled(combo.wrappedValue == defaultCombo)
            }
        }
        if conflicts.contains(action) {
            Text("快捷键 \(combo.wrappedValue.displayString) 已被其他应用占用，请换一个。")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func apply(_ combo: HotkeyCombo, for action: HotkeyCenter.Action) {
        Preferences.setHotkey(combo, for: action)
        if onHotkeyChange(action) { conflicts.remove(action) } else { conflicts.insert(action) }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            saveDirectory = url
            Preferences.saveDirectory = url
        }
    }
}
