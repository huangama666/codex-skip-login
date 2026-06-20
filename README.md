# Codex 自定义模型

一个只做三件事的 macOS 工具：

1. 按 Codex `model_provider` 配置接入一个自定义模型；
2. 可选设置 `requires_openai_auth = false`，跳过 ChatGPT 登录；
3. 可选地把 Codex Responses API 请求适配为上游 Chat Completions API。

## 图形界面

```bash
bash scripts/package-app.sh
open ~/Applications/Codex+国产模型免登.app
```

填写 API 地址、模型 ID 和 API Key。如果上游只有 `/v1/chat/completions`，勾选协议适配。

## 生成的核心配置

```toml
model = "your-model-name"
model_provider = "custom"

[model_providers.custom]
name = "Custom Model"
base_url = "https://api.example.com/v1"
experimental_bearer_token = "your-api-key"
models = ["your-model-name"]
wire_api = "responses"
requires_openai_auth = false
```

“跳过 ChatGPT 登录”默认不勾选；勾选后才会生成上面的 `requires_openai_auth = false`，否则写入 `true`。

启用协议适配时，`base_url` 会指向本机 `http://127.0.0.1:17638/v1`，本地服务再调用用户填写的 `/v1/chat/completions`。

这套配置与 v0.5.1 的接入路径一致：Codex 始终按 Responses API 请求，自定义上游如果只支持 Chat Completions，则由本地适配器转换协议。API Key 同时保存在权限为 `0600` 的状态文件中；为了兼容 Codex Desktop，自定义 provider 使用 `experimental_bearer_token`，因此 `config.toml` 内也会包含明文 Key。

> 注意：把自定义模型写入 `models_cache.json` 并不能保证它出现在 Codex Desktop 自带的模型下拉框中。是否展示由当前 Codex Desktop 的内部模型目录决定；本工具通过 `model`、`model_provider` 和 provider 的 `models` 配置让实际请求使用指定模型。

## CLI

```bash
printf '%s\n' "$API_KEY" | codex-skip-login local \
  --base-url https://api.example.com/v1 \
  --model your-model-name \
  --api-key-stdin \
  --chat-adapter \
  --skip-login \
  --restart-codex

codex-skip-login status
```

## 安全修改范围

- 修改：`~/.codex/config.toml`
- 保存：`~/.codex/codex-switch-state.json`
- 可选安装：`~/Library/LaunchAgents/com.huangama.codex-skip-login.adapter.plist`
- 不修改：Codex 会话 JSONL、SQLite、Claude Code 配置和 `auth.json`
