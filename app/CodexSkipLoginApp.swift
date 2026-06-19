import AppKit
import Foundation
import SwiftUI

// MARK: - Constants

private enum Constants {
    static let appName = "Codex+国产模型免登"
    static let releasesURL = URL(string: "https://github.com/huangama666/codex-skip-login/releases/latest")!
    static let defaultCodexBaseURL = "https://jp.icodeeasy.cc"
    static let defaultCodexModel = "my-gpt-5.5"
    static let defaultClaudeBaseURL = "http://127.0.0.1:15721"
    static let defaultClaudeModel = "claude-sonnet-4-6"
    static let defaultCodexOfficialModel = "gpt-5.5"
    static let defaultClaudeOfficialModel = "claude-sonnet-4-6"
    static let codexConfigRelativePath = ".codex/config.toml"
    static let codexConfigBackupName = "config.toml.official-backup"

    static let cliSearchPaths: [String] = [
        NSString(string: "~/.local/bin/codex-skip-login").expandingTildeInPath,
        "/usr/local/bin/codex-skip-login",
    ]
}

// MARK: - Models

enum ProviderMode: String, CaseIterable, Identifiable {
    case custom
    case official

    var id: String { rawValue }
}

enum SwitchTarget: String, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { rawValue }
}

struct CommandResult {
    let status: Int32
    let output: String
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    case failed
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                (colorScheme == .dark ? Color.white : Color.black)
                    .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1.0) : 0.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? Color.primary : Color.primary.opacity(0.4))
            .frame(height: 36)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.gray.opacity(isEnabled ? 0.5 : 0.25), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - VersionComparator

private enum VersionComparator {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = numericParts(candidate)
        let currentParts = numericParts(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidateValue = index < candidateParts.count ? candidateParts[index] : 0
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            if candidateValue != currentValue {
                return candidateValue > currentValue
            }
        }
        return false
    }

    private static func numericParts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                Int(component.prefix(while: { $0.isNumber })) ?? 0
            }
    }
}

// MARK: - ViewModel

final class SwitchViewModel: ObservableObject {
    @Published var statusValues: [String: String] = [:]
    @Published var localBaseURL = ""
    @Published var localModel = ""
    @Published var localModelDisplayName = ""
    @Published var useChatAdapter = true
    @Published var skipLogin = true
    @Published var replacementAPIKey = ""
    @Published var officialModel = ""
    @Published var output = ""
    @Published var isBusy = false
    @Published var switchSucceeded = false
    @Published var switchFailed = false
    @Published var completedMode = ProviderMode.custom
    @Published var completedTarget = SwitchTarget.codex
    @Published var updateState = UpdateState.idle
    @Published var releaseURL = Constants.releasesURL

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private var cliPath: String? {
        // 1. App 内嵌 CLI
        if let bundled = Bundle.main.path(forResource: "codex-skip-login", ofType: nil) {
            return bundled
        }
        // 2-3. 外部安装路径
        let fm = FileManager.default
        for path in Constants.cliSearchPaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private var codexHome: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex").path
    }

    private var configPath: String {
        codexHome + "/config.toml"
    }

    private var backupPath: String {
        codexHome + "/" + Constants.codexConfigBackupName
    }

    func load(target: SwitchTarget = .codex) {
        checkForUpdates()
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let status = self.run(self.statusArguments(for: target))
            let config = self.run(self.configShowArguments(for: target))
            DispatchQueue.main.async {
                self.statusValues = self.parse(status.output)
                let values = self.parse(config.output)
                self.localBaseURL = values["local_base_url"] ?? (target == .claude ? Constants.defaultClaudeBaseURL : Constants.defaultCodexBaseURL)
                self.localModel = values["local_model"] ?? (target == .claude ? Constants.defaultClaudeModel : Constants.defaultCodexModel)
                self.localModelDisplayName = values["local_model_display_name"] ?? self.localModel
                self.useChatAdapter = (values["chat_adapter"] ?? "true") != "false"
                self.officialModel = values["official_model"] ?? (target == .claude ? Constants.defaultClaudeOfficialModel : Constants.defaultCodexOfficialModel)
                self.skipLogin = self.readSkipLoginState()
                if status.status != 0 || config.status != 0 {
                    self.output = [status.output, config.output].filter { !$0.isEmpty }.joined(separator: "\n")
                }
                self.isBusy = false
            }
        }
    }

    func checkForUpdates() {
        guard updateState != .checking else { return }
        updateState = .checking

        var request = URLRequest(url: Constants.releasesURL)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("\(Constants.appName)/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let releaseURL = httpResponse.url,
                  releaseURL.path.contains("/releases/tag/") else {
                DispatchQueue.main.async { self.updateState = .failed }
                return
            }

            let version = releaseURL.lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            DispatchQueue.main.async {
                self.releaseURL = releaseURL
                self.updateState = VersionComparator.isNewer(version, than: self.currentVersion)
                    ? .available(version: version)
                    : .upToDate
            }
        }.resume()
    }

    func performUpdateAction() {
        switch updateState {
        case .available:
            NSWorkspace.shared.open(releaseURL)
        case .checking:
            break
        case .idle, .upToDate, .failed:
            checkForUpdates()
        }
    }

    func switchProvider(to mode: ProviderMode, target: SwitchTarget) {
        isBusy = true
        output = ""
        switchSucceeded = false
        switchFailed = false
        let baseURL = localBaseURL
        let local = localModel
        let displayName = localModelDisplayName
        let useAdapter = useChatAdapter
        let doSkipLogin = skipLogin
        let replacementKey = replacementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let official = officialModel
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if target == .codex {
                self.configureCodex(
                    baseURL: baseURL,
                    customModel: local,
                    displayName: displayName,
                    officialModel: official,
                    mode: mode,
                    useChatAdapter: useAdapter,
                    skipLogin: doSkipLogin,
                    replacementKey: replacementKey
                )
                return
            }
            let save = self.run(self.configSetArguments(for: target) + [
                "--local-base-url", baseURL,
                "--local-model", local,
                "--official-model", official,
            ])
            guard save.status == 0 else {
                DispatchQueue.main.async {
                    self.output = save.output
                    self.isBusy = false
                    self.switchFailed = true
                }
                return
            }
            var switchArguments = self.switchArguments(for: target, mode: mode)
            var switchInput: String?
            if mode == .custom && !replacementKey.isEmpty {
                switchArguments.append(target == .claude ? "--auth-token-stdin" : "--api-key-stdin")
                switchInput = replacementKey + "\n"
            }
            let switched = self.run(switchArguments, standardInput: switchInput)
            let status = self.run(self.statusArguments(for: target))
            DispatchQueue.main.async {
                self.output = switched.output
                self.statusValues = self.parse(status.output)
                self.isBusy = false
                self.completedMode = mode
                self.completedTarget = target
                if switched.status == 0 {
                    self.replacementAPIKey = ""
                    self.switchSucceeded = true
                } else {
                    self.switchFailed = true
                }
            }
        }
    }

    private func configureCodex(baseURL: String, customModel: String, displayName: String, officialModel: String, mode: ProviderMode, useChatAdapter: Bool, skipLogin: Bool, replacementKey: String) {
        let defaultProvider = mode == .custom ? "custom" : "openai"
        var arguments = [
            "configure",
            "--base-url", baseURL,
            "--custom-model", customModel,
            "--custom-model-name", displayName,
            "--official-model", officialModel,
            "--default-provider", defaultProvider,
        ]
        if useChatAdapter {
            arguments.append("--chat-adapter")
        }
        var switchInput: String?
        if !replacementKey.isEmpty {
            arguments.append("--api-key-stdin")
            switchInput = replacementKey + "\n"
        }
        let configured = run(arguments, standardInput: switchInput)
        // configure 写完配置后，再根据 toggle 状态设置登录项
        if skipLogin && mode == .custom {
            applySkipLogin(enable: true)
        } else {
            applySkipLogin(enable: false)
        }
        // 登录项写完后才重启 Codex
        restartCodexProcess()
        let status = run(["status"])
        DispatchQueue.main.async {
            self.output = configured.output
            self.statusValues = self.parse(status.output)
            self.isBusy = false
            self.completedTarget = .codex
            self.completedMode = mode
            if configured.status == 0 {
                self.replacementAPIKey = ""
                self.switchSucceeded = true
            } else {
                self.switchFailed = true
            }
        }
    }

    private func restartCodexProcess() {
        // 先关闭 Codex，等一下再重新打开
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killTask.arguments = ["-f", "Codex"]
        try? killTask.run()
        killTask.waitUntilExit()
        Thread.sleep(forTimeInterval: 1.0)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Codex.app"))
    }

    private func applySkipLogin(enable: Bool) {
        guard var content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }
        if enable {
            content = content.replacingOccurrences(of: "requires_openai_auth = true", with: "requires_openai_auth = false")
        } else {
            content = content.replacingOccurrences(of: "requires_openai_auth = false", with: "requires_openai_auth = true")
        }
        try? content.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    private func readSkipLoginState() -> Bool {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return true }
        return content.contains("requires_openai_auth = false")
    }

    /// 首次运行时备份官方原版 config.toml（仅当备份文件不存在时执行）
    func backupOfficialConfigIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: backupPath),
              fm.fileExists(atPath: configPath) else { return }
        try? fm.copyItem(atPath: configPath, toPath: backupPath)
    }

    /// 恢复官方登录
    func restoreOfficialLogin() {
        isBusy = true
        output = ""
        switchSucceeded = false
        switchFailed = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default

            var resultText = ""
            if fm.fileExists(atPath: self.backupPath) {
                try? fm.removeItem(atPath: self.configPath)
                try? fm.copyItem(atPath: self.backupPath, toPath: self.configPath)
                resultText = "已从备份恢复官方原版 config.toml"
            } else {
                self.applySkipLogin(enable: false)
                resultText = "已将 requires_openai_auth 恢复为 true"
            }

            let restart = self.run(["official", "--migrate-latest", "--restart-codex"])
            if restart.status == 0 {
                resultText += "\n已切换到官方模式并重启 Codex"
            } else {
                resultText += "\n" + restart.output
            }

            let status = self.run(["status"])
            DispatchQueue.main.async {
                self.output = resultText
                self.statusValues = self.parse(status.output)
                self.skipLogin = false
                self.isBusy = false
                self.completedMode = .official
                self.completedTarget = .codex
                if restart.status == 0 {
                    self.switchSucceeded = true
                } else {
                    self.switchFailed = true
                }
            }
        }
    }

    private func statusArguments(for target: SwitchTarget) -> [String] {
        target == .claude ? ["claude-status"] : ["status"]
    }

    private func configShowArguments(for target: SwitchTarget) -> [String] {
        target == .claude ? ["claude-config", "show"] : ["config", "show"]
    }

    private func configSetArguments(for target: SwitchTarget) -> [String] {
        target == .claude ? ["claude-config", "set"] : ["config", "set"]
    }

    private func switchArguments(for target: SwitchTarget, mode: ProviderMode) -> [String] {
        if target == .claude {
            return [mode == .custom ? "claude-local" : "claude-official"]
        }
        return [mode == .custom ? "local" : "official", "--migrate-latest", "--restart-codex"]
    }

    private func run(_ arguments: [String], standardInput: String? = nil) -> CommandResult {
        guard let resolvedPath = cliPath else {
            return CommandResult(status: 127, output: "codex-skip-login CLI 未找到。请确认已安装到 ~/.local/bin/ 或 /usr/local/bin/")
        }
        guard FileManager.default.isExecutableFile(atPath: resolvedPath) else {
            return CommandResult(status: 127, output: "codex-skip-login CLI not executable at \(resolvedPath)")
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: resolvedPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        let inputPipe = standardInput == nil ? nil : Pipe()
        process.standardInput = inputPipe
        do {
            try process.run()
            if let standardInput, let inputPipe {
                inputPipe.fileHandleForWriting.write(Data(standardInput.utf8))
                inputPipe.fileHandleForWriting.closeFile()
            }
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CommandResult(status: process.terminationStatus, output: text)
        } catch {
            return CommandResult(status: 126, output: error.localizedDescription)
        }
    }

    private func parse(_ output: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                values[parts[0]] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return values
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var model = SwitchViewModel()
    @State private var targetTool = SwitchTarget.codex

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(Constants.appName)
                    .font(.system(size: 20, weight: .bold, design: .default))
                Spacer()
                if case .available(let v) = model.updateState {
                    Button { model.performUpdateAction() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("v\(v) 可用").font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 16) {

                // ━━━ 配置表单 ━━━
                customSection

                // ━━━ 操作按钮 ━━━
                HStack(spacing: 12) {
                    Button {
                        model.switchProvider(to: .custom, target: targetTool)
                    } label: {
                        Text(targetTool == .codex ? "应用并重启 Codex" : "应用配置")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isBusy)

                    Button {
                        model.restoreOfficialLogin()
                    } label: {
                        Text("恢复官方登录")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isBusy)
                }

                // ━━━ 执行结果 ━━━
                if !model.output.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("执行结果")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(model.output)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 70)
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            if model.isBusy {
                ZStack {
                    Color.black.opacity(0.08)
                    ProgressView("处理中…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            } else if model.switchSucceeded || model.switchFailed {
                resultOverlay
            }
        }
        .onAppear {
            model.backupOfficialConfigIfNeeded()
            model.load(target: targetTool)
        }
        .onChange(of: targetTool) { newTool in
            model.replacementAPIKey = ""
            model.load(target: newTool)
        }
    }

    // MARK: - 自定义 API 配置区

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldRow(label: "API 协议") {
                Picker("", selection: $targetTool) {
                    Text("OpenAI 协议").tag(SwitchTarget.codex)
                    Text("Anthropic 协议").tag(SwitchTarget.claude)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FieldRow(label: "API 地址") {
                TextField(targetTool == .claude ? Constants.defaultClaudeBaseURL : Constants.defaultCodexBaseURL,
                          text: $model.localBaseURL)
                    .textFieldStyle(.roundedBorder)
            }

            FieldRow(label: "模型 ID") {
                TextField(targetTool == .claude ? Constants.defaultClaudeModel : Constants.defaultCodexModel,
                          text: $model.localModel)
                    .textFieldStyle(.roundedBorder)
            }

            if targetTool == .codex {
                FieldRow(label: "显示名称") {
                    TextField("模型显示名", text: $model.localModelDisplayName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            FieldRow(label: "API Key") {
                SecureField(apiKeyPlaceholder, text: $model.replacementAPIKey)
                    .textFieldStyle(.roundedBorder)
            }

            if targetTool == .codex {
                Divider().padding(.vertical, 4)

                FieldRow(label: "Chat 适配器") {
                    Toggle("Chat Completions → Responses", isOn: $model.useChatAdapter)
                        .toggleStyle(.checkbox)
                }

                FieldRow(label: "跳过登录") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("绕过 ChatGPT OAuth 登录验证", isOn: $model.skipLogin)
                            .toggleStyle(.checkbox)
                        if model.skipLogin {
                            Text("⚠️ 免登模式下 Codex 不会显示接入的模型，但不影响正常使用")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }



    // MARK: - 结果弹窗

    private var resultOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: model.switchSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(model.switchSucceeded ? Color.white : Color.red.opacity(0.8))
                Text(model.switchSucceeded ? "操作成功" : "操作失败")
                    .font(.title2.bold())
                Text(resultMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 340)
                Button("确定") {
                    model.switchSucceeded = false
                    model.switchFailed = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 200)
            }
            .padding(28)
            .frame(width: 420)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.3), radius: 30)
        }
    }

    private var resultMessage: String {
        if model.switchFailed {
            return model.output.isEmpty ? "请检查配置后重试。" : model.output
        }
        if model.completedTarget == .claude {
            return model.completedMode == .custom
                ? "已切换 Claude Code 到自定义 API。重启终端会话后生效。"
                : "已切换 Claude Code 到官方 Claude。重启终端会话后生效。"
        }
        return "已保存配置并重启 Codex。可在模型选择器里切换模型。"
    }

    // MARK: - Helpers

    private var apiKeyPlaceholder: String {
        let k = model.statusValues["api_key"] ?? ""
        return (k.isEmpty || k == "(none)" || k == "-")
            ? "输入 API Key"
            : "留空沿用 \(k)"
    }

    private var updateIcon: String {
        switch model.updateState {
        case .idle:      return "arrow.clockwise.circle"
        case .checking:  return "arrow.triangle.2.circlepath"
        case .upToDate:  return "checkmark.circle"
        case .available: return "arrow.down.circle.fill"
        case .failed:    return "exclamationmark.triangle"
        }
    }

    private var updateTitle: String {
        switch model.updateState {
        case .idle:              return "检查更新"
        case .checking:          return "检查中…"
        case .upToDate:          return "已是最新"
        case let .available(v):  return "v\(v) 可用"
        case .failed:            return "重试"
        }
    }


}

// MARK: - FieldRow

private struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            content()
        }
    }
}

@main
struct CodexSkipLoginApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
