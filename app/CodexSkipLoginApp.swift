import AppKit
import Foundation
import SwiftUI

private enum Constants {
    static let appName = "Codex 自定义模型"
    static let cliPaths = [
        NSString(string: "~/.local/bin/codex-skip-login").expandingTildeInPath,
        "/usr/local/bin/codex-skip-login",
    ]
}

private struct CommandResult {
    let status: Int32
    let output: String
}

private enum Mode {
    case custom
    case official
}

@MainActor
private final class ViewModel: ObservableObject {
    @Published var baseURL = ""
    @Published var model = ""
    @Published var apiKey = ""
    @Published var useChatAdapter = true
    @Published var skipLogin = false
    @Published var officialModel = "gpt-5.5"
    @Published var currentMode: Mode = .custom

    @Published var output = ""
    @Published var busy = false
    @Published var succeeded = false

    nonisolated private var cliPath: String? {
        if let bundled = Bundle.main.path(forResource: "codex-skip-login", ofType: nil) {
            return bundled
        }
        return Constants.cliPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func load() {
        Task.detached { [weak self] in
            guard let self else { return }
            let result = self.run(["status"])
            let values = self.parse(result.output)
            await MainActor.run {
                // The provider URL is local when the adapter is enabled. Show
                // the real upstream URL in the form instead.
                if let v = values["upstream_base_url"], v != "(missing)" {
                    self.baseURL = v
                } else if let v = values["custom.base_url"], v != "(missing)" {
                    self.baseURL = v
                }
                if let v = values["model"], v != "(missing)" { self.model = v }
                self.useChatAdapter = values["chat_adapter"] != "false"
                self.skipLogin = values["skip_login"] == "true"
                self.currentMode = values["model_provider"] == "openai" ? .official : .custom
            }
        }
    }

    /// 应用免登 + 自定义模型
    func applyCustom() {
        let cleanURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let adapterEnabled = useChatAdapter
        let skipLoginEnabled = skipLogin
        guard !cleanURL.isEmpty, !cleanModel.isEmpty else {
            output = "API 地址和模型 ID 不能为空。"
            return
        }
        busy = true; succeeded = false
        Task.detached { [weak self] in
            guard let self else { return }
            var args = ["local", "--base-url", cleanURL, "--model", cleanModel, "--restart-codex"]
            if adapterEnabled { args.append("--chat-adapter") }
            if skipLoginEnabled { args.append("--skip-login") }
            if !cleanKey.isEmpty { args += ["--api-key-stdin"] }
            let result = self.run(args, input: cleanKey.isEmpty ? nil : cleanKey + "\n")
            await MainActor.run {
                self.output = result.output
                self.busy = false
                self.succeeded = result.status == 0
                if result.status == 0 {
                    self.apiKey = ""
                    self.currentMode = .custom
                }
            }
        }
    }

    func restoreOfficial() {
        let cleanModel = officialModel.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true; succeeded = false
        Task.detached { [weak self] in
            guard let self else { return }
            var args = ["official", "--restart-codex"]
            if !cleanModel.isEmpty { args += ["--model", cleanModel] }
            let result = self.run(args)
            await MainActor.run {
                self.output = result.output
                self.busy = false
                self.succeeded = result.status == 0
                if result.status == 0 { self.currentMode = .official }
            }
        }
    }

    nonisolated private func run(_ arguments: [String], input: String? = nil) -> CommandResult {
        guard let path = cliPath else {
            return CommandResult(status: 127, output: "内嵌 CLI 未找到。")
        }
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        let inputPipe = input == nil ? nil : Pipe()
        process.standardInput = inputPipe
        do {
            try process.run()
            if let input, let inputPipe {
                inputPipe.fileHandleForWriting.write(Data(input.utf8))
                inputPipe.fileHandleForWriting.closeFile()
            }
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return CommandResult(
                status: process.terminationStatus,
                output: String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        } catch {
            return CommandResult(status: 126, output: error.localizedDescription)
        }
    }

    nonisolated private func parse(_ output: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 { values[parts[0]] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        return values
    }
}

private struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 82, alignment: .trailing)
            content()
        }
    }
}

private struct StatusBadge: View {
    let mode: Mode
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(mode == .custom ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(mode == .custom ? "自定义模型免登" : "官方登录")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ContentView: View {
    @StateObject private var viewModel = ViewModel()
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            // 标题区
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Constants.appName).font(.title2.bold())
                    Text("配置模型、跳过登录，并按需适配 Chat Completions。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(mode: viewModel.currentMode)
            }

            Divider()
            Picker("", selection: $selectedTab) {
                Text("🔓 自定义模型免登").tag(0)
                Text("🔑 恢复官方登录").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if selectedTab == 0 { customPanel } else { officialPanel }

            // 输出区
            if !viewModel.output.isEmpty {
                ScrollView {
                    Text(viewModel.output)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120).padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(24)
        .frame(width: 520)
        .overlay {
            if viewModel.busy {
                ProgressView("正在应用…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear { viewModel.load() }
        .onChange(of: viewModel.currentMode) { mode in
            selectedTab = mode == .official ? 1 : 0
        }
    }

    // MARK: - 免登配置面板

    private var customPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            FieldRow(label: "API 地址") {
                TextField("https://api.example.com/v1", text: $viewModel.baseURL)
                    .textFieldStyle(.roundedBorder)
            }
            FieldRow(label: "模型 ID") {
                TextField("your-model-name", text: $viewModel.model)
                    .textFieldStyle(.roundedBorder)
            }
            FieldRow(label: "API Key") {
                SecureField("留空沿用已保存的 Key", text: $viewModel.apiKey)
                    .textFieldStyle(.roundedBorder)
            }
            FieldRow(label: "协议适配") {
                Toggle("上游仅支持 Chat Completions", isOn: $viewModel.useChatAdapter)
                    .toggleStyle(.checkbox)
            }
            FieldRow(label: "登录方式") {
                Toggle("跳过 ChatGPT 登录", isOn: $viewModel.skipLogin)
                    .toggleStyle(.checkbox)
            }
            Text(viewModel.skipLogin
                 ? "将设置 requires_openai_auth = false。"
                 : "保留 ChatGPT 官方登录校验。")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 94)

            Button("应用并重启 Codex") { viewModel.applyCustom() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.busy)
        }
    }

    private var officialPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            FieldRow(label: "官方模型") {
                TextField("gpt-5.5", text: $viewModel.officialModel)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                Text("恢复 Codex 官方 Provider，并使用 ChatGPT 账号登录。")
            }
            .font(.caption).foregroundStyle(.secondary)

            Button("恢复官方登录并重启 Codex") { viewModel.restoreOfficial() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.busy)
        }
    }

}

@main
struct CodexSkipLoginApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowResizability(.contentSize)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
