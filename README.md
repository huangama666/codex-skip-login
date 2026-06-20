# Codex+国产模型免登

一个用于 macOS Codex Desktop 的自定义模型配置工具。通过图形界面填写 API 地址、模型 ID 和 API Key，即可将 Codex 切换到 OpenAI 兼容的自定义模型服务。

## 功能

- 接入 OpenAI Responses API 兼容服务
- 将 Codex Responses 请求适配为上游 Chat Completions 请求
- 可选跳过 ChatGPT 登录，默认不启用
- 一键恢复 Codex 官方 ChatGPT 登录模式
- 保存并回填上次使用的 API 地址、模型和协议选项
- 自动备份修改前的 Codex 配置

## 系统要求

- macOS 13 或更高版本
- 已安装 Codex Desktop
- 使用自定义模型时，需要准备 API 地址、模型 ID 和 API Key

## 下载和启动

从 [Releases](https://github.com/huangama666/codex-skip-login/releases/latest) 下载 `Codex-Skip-Login-macOS.zip`，解压后双击 `Codex+国产模型免登.app`。

也可以将 App 移动到用户应用目录：

```bash
mkdir -p ~/Applications
mv "Codex+国产模型免登.app" ~/Applications/
open ~/Applications/Codex+国产模型免登.app
```

## 使用方法

### 自定义模型

1. 打开“自定义模型免登”页签。
2. 填写 API 地址、模型 ID 和 API Key。
3. 如果上游只提供 `/v1/chat/completions`，勾选“上游仅支持 Chat Completions”。
4. 如果不希望使用 ChatGPT 登录，勾选“跳过 ChatGPT 登录”。该选项默认不勾选。
5. 点击“应用并重启 Codex”。

启用协议适配后，Codex 会请求本机 `http://127.0.0.1:17638/v1`，本地适配器再把请求转换后发送到用户填写的上游地址。

### 恢复官方登录

1. 打开“恢复官方登录”页签。
2. 填写需要使用的官方模型，或保留默认值。
3. 点击“恢复官方登录并重启 Codex”。

自定义 API 配置会被保留，之后仍可重新切回自定义模型。

## 从源码安装

```bash
git clone https://github.com/huangama666/codex-skip-login.git
cd codex-skip-login
bash scripts/install.sh
open ~/Applications/Codex+国产模型免登.app
```

安装脚本会同时安装：

- App：`~/Applications/Codex+国产模型免登.app`
- CLI：`~/.local/bin/codex-skip-login`
- 运行文件：`~/.local/share/codex-skip-login`

## CLI 使用

```bash
printf '%s\n' "$API_KEY" | ~/.local/bin/codex-skip-login local \
  --base-url https://api.example.com/v1 \
  --model your-model-name \
  --api-key-stdin \
  --chat-adapter \
  --skip-login \
  --restart-codex
```

查看当前状态：

```bash
~/.local/bin/codex-skip-login status
```

恢复官方登录：

```bash
~/.local/bin/codex-skip-login official --restart-codex
```

## 配置文件

工具会使用以下文件：

- `~/.codex/config.toml`：Codex Provider、模型和协议配置
- `~/.codex/auth.json`：保留原有 ChatGPT Token，并记录自定义 API Key
- `~/.codex/codex-switch-state.json`：保存工具界面状态
- `~/.codex/codex-switch-model-catalog.json`：自定义模型目录
- `~/Library/LaunchAgents/com.huangama.codex-skip-login.adapter.plist`：协议适配服务

修改前的配置会备份到 `~/.codex/backups/`。

> 为兼容 Codex Desktop，自定义 API Key 会写入 `config.toml` 的 `experimental_bearer_token`。请勿公开分享自己的 `~/.codex/config.toml`、`auth.json` 或状态文件。

## 关于模型下拉框

Codex Desktop 的原生模型下拉框由其内部模型目录控制。自定义模型即使已经正确配置并能够发起请求，也不一定会出现在原生下拉框中；实际请求模型以 `config.toml` 中的 `model` 和 `model_provider` 为准。

## 卸载

```bash
bash scripts/uninstall.sh
```

卸载脚本会删除 App、CLI 和协议适配服务，但会保留 `~/.codex` 中的用户配置与备份。

## License

[MIT](LICENSE)
