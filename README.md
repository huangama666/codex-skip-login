# Codex+国产模型免登

> 一键让 Codex 接入国产大模型（GLM、DeepSeek、Qwen 等），免去 ChatGPT OAuth 登录验证。

## 功能

- **跳过登录**：自动绕过 Codex 的 ChatGPT OAuth 登录验证，直接使用自定义 API
- **恢复官方登录**：一键恢复官方原版配置，恢复 ChatGPT 登录要求
- **多模型支持**：注册多个国产模型到 Codex 的模型选择器
- **Chat 适配器**：本地代理自动将 Codex 的 Responses API 转为 Chat Completions
- **Claude Code 支持**：同时支持切换 Claude Code 的自定义 API 路由
- **macOS 原生 App**：SwiftUI 界面，黑白极简风格

## 安装

### 方式一：从源码打包

```bash
git clone https://github.com/huangama666/codex-skip-login.git
cd codex-skip-login
bash scripts/package-app.sh
open ~/Applications/Codex+国产模型免登.app
```

### 方式二：下载 Release

从 [GitHub Releases](https://github.com/huangama666/codex-skip-login/releases/latest) 下载 zip，解压后放入 `~/Applications`。

## 使用

1. 打开 App，填写 API 地址和模型 ID
2. 填写 API Key（留空沿用已保存的）
3. 勾选「跳过登录」绕过 ChatGPT OAuth
4. 点击「应用并重启 Codex」

想恢复官方登录？点「恢复官方登录」按钮即可。

## CLI 用法

App 内嵌了 `codex-skip-login` CLI，也可以单独使用：

```bash
# 切到自定义模型（自动跳过登录）
codex-skip-login local --model glm-5.2-max --base-url https://your-api.com/v1

# 切回官方模式（恢复登录）
codex-skip-login official

# 查看当前状态
codex-skip-login status
```

## 原理

- 修改 `~/.codex/config.toml` 中 `[model_providers.custom]` 的 `requires_openai_auth` 字段
- `false` = 跳过登录，`true` = 需要登录
- 首次运行时自动备份官方原版配置到 `~/.codex/config.toml.official-backup`

## 要求

- macOS 13+
- 已安装 [Codex](https://openai.com/codex) 桌面版

## License

MIT
