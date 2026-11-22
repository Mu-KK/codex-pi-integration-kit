# Codex pi Integration Kit

一套面向 Windows 的用户级 Codex → pi MCP 集成工具包。它负责安装固定版本的
pi、部署便携 launcher、合并 Codex MCP 配置、写入分层委派规则，并提供可重复的
安装后验证流程。

[![validate](https://github.com/Mu-KK/codex-pi-integration-kit/actions/workflows/validate.yml/badge.svg)](https://github.com/Mu-KK/codex-pi-integration-kit/actions/workflows/validate.yml)

## 功能

- 用户级安装，不要求管理员权限。
- 固定安装 `@earendil-works/pi-coding-agent@1.5.0` 和
  `pi-delegate-mcp@0.1.1`。
- 通过路径表部署 launcher，避免把用户目录硬编码进 MCP 命令。
- 在 `config.toml` 中管理独立的 `[mcp_servers.pi]` 块。
- 通过 `CODEX_PI_KIT` 标记块合并 `AGENTS.md`，保留标记外规则。
- 默认只读工具集为 `read,grep,find,ls`，单次任务可进一步收窄。
- 支持 L0/L1/L2/L3 影响面分级，避免把高风险修改交给 pi。
- 不覆盖项目、现有 MCP 配置、pi 凭据或 pi 历史会话。
- 提供安装、provider 配置、kit 自检和安装后验证脚本。
- 支持 Codex 与 pi 使用不同模型，并在 `status` 中核对实际模型。

## 架构

```text
Codex desktop / Codex CLI
          |
          | MCP
          v
[mcp_servers.pi]
          |
          v
pi-delegate-mcp-launcher.mjs
          |
          +--> pi-delegate-mcp
          |
          +--> pi coding agent
                    |
                    +--> pi provider / model
```

默认安装路径：

```text
程序前缀:       %LOCALAPPDATA%\CodexPi
npm 前缀:       %LOCALAPPDATA%\CodexPi\npm-global
MCP launcher:   %CODEX_HOME%\mcp\pi-delegate-mcp-launcher.mjs
路径表:         %CODEX_HOME%\mcp\pi-delegate-paths.json
安装报告:       %LOCALAPPDATA%\CodexPi\install-report.json
pi Agent 配置:  %USERPROFILE%\.pi\agent
```

## 前置条件

- Windows 10 或 Windows 11。
- PowerShell 5.1 或 PowerShell 7。
- Node.js `22.19.0` 或更高版本；推荐当前 Node.js 24 LTS。
- `node.exe` 和 `npm.cmd` 可用，或可显式传入真实路径。
- 可访问 npm registry，或已正确配置企业代理/镜像。
- pi 的 provider 和凭据由用户自行准备。

检查环境：

```powershell
node --version
npm.cmd --version
(Get-Command node.exe).Source
(Get-Command npm.cmd).Source
```

## 快速安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

显式指定 Node.js 路径：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\install.ps1 `
  -NodeExe "C:\Program Files\nodejs\node.exe" `
  -NpmCmd "C:\Program Files\nodejs\npm.cmd"
```

安装器会：

1. 将固定版本依赖安装到 `%LOCALAPPDATA%\CodexPi\npm-global`。
2. 部署 launcher 和包路径表。
3. 追加 `[mcp_servers.pi]`，或更新已有 kit 管理块。
4. 将受管理规则合并到 `%CODEX_HOME%\AGENTS.md`。
5. 安装 `%CODEX_HOME%\PI_PLAYBOOK.md`。
6. 创建缺失的 pi settings/mcp 示例文件。
7. 在修改全局文件前创建同目录 `.bak.N` 备份。

如果已有不带 kit 标记的 `[mcp_servers.pi]`，安装器不会覆盖。它会生成：

```text
%CODEX_HOME%\mcp\pi-mcp-snippet.toml
```

请先比较路径、超时、审批模式和工具权限，再人工决定是否合并。

## 配置 pi 模型

优先复用当前 pi 1.5 已配置的凭据和模型存储：

```powershell
pi --version
pi models
```

如果尚未配置 provider：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\configure-provider.ps1
```

脚本使用 `Read-Host -AsSecureString` 接收 API Key。不要把密钥写入仓库、
README、AGENTS、日志、issue 或聊天。

pi 当前版本可能使用以下本地文件：

```text
%USERPROFILE%\.pi\agent\models-store.json
%USERPROFILE%\.pi\agent\auth.json
%USERPROFILE%\.pi\agent\settings.json
```

旧版本可能使用 `models.json`。两种布局均不能提交到 Git。

## 验证

Kit 自检：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\validate-kit.ps1
```

安装后验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\verify.ps1
```

模型 smoke 会产生真实 API 用量：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\verify.ps1 -RunSmoke
```

完整 MCP 验收顺序：

```text
重启 Codex
  -> pi MCP init
  -> spawn（显式 cwd、id、label、tools、model）
  -> status 轮询到 done
  -> sessions 复核
```

写入测试只能使用临时目录。不得在真实项目中测试覆盖或删除。

## 使用不同模型

Codex 模型和 pi 模型相互独立。只要 pi 的 provider 已配置、模型存在于
`models-store.json`，并列入 `settings.json` 的 `enabledModels`，就可以在
`spawn` 或 `spawn_batch` 中按调用覆盖模型：

```json
{
  "id": "readonly-model-check",
  "label": "different-model-smoke",
  "cwd": "C:\\Users\\Example\\AppData\\Local\\Temp\\codex-pi-smoke",
  "tools": ["read", "grep", "find", "ls"],
  "model": "provider/model-b",
  "prompt": "只读检查当前临时目录，返回 READY，不修改任何文件。"
}
```

随后用 `status` 检查 `model` 是否等于请求值。MCP 遇到不可用模型会硬失败，
不会静默回退。若启用了 `PI_DELEGATE_STRICT_SCOPE=1`，模型必须存在于 pi 的
`enabledModels`。

## 分层委派规则

| 等级 | 执行方式 | pi 权限 |
|---|---|---|
| L0 | 文档、注释、文案等低风险任务，默认交给 pi | 最小读写权限 |
| L1 | 局部样式、隔离小逻辑，默认交给 pi | 最小读写权限 |
| L2 | Codex 负责架构和最终验证；pi 只做机械子任务 | 明确限定文件与动作 |
| L3 | Codex 执行；pi 只做只读复审 | `read,grep,find,ls` |

等级不确定时按更高一级处理。pi-delegate 不是沙箱；授予 `bash` 或
`powershell` 等于允许当前 Windows 用户可执行的全部操作。

## 安全边界

- 不提交 `.env`、`auth.json`、`models.json`、真实 `config.toml`、证书或备份。
- 不把 API Key 放入命令行参数、环境日志或聊天正文。
- `default_tools_approval_mode = "approve"` 用于非交互 MCP 验证；如不接受自动批准，
  请改回交互审批，并在每次调用时人工确认。
- `PI_DELEGATE_ALLOW_TOOLS` 是允许上限，不是任务授权。每次 `spawn` 仍应传入最小
  `tools`。
- 公开仓库中只保留占位地址和示例凭据字段。

详见 [SECURITY.md](SECURITY.md)。

## 可直接交给 Codex 的配置提示词

完整版本也保存在 [CODEX_SETUP_PROMPT.md](CODEX_SETUP_PROMPT.md)。将下面整段复制到
Codex，并从本仓库根目录运行：

~~~text
你当前位于 codex-pi-integration-kit 仓库根目录。请把本项目安装并配置成
当前 Windows 电脑可用的 Codex -> pi MCP 集成。严格按以下步骤执行：

1. 只读检查 README.md、AGENTS.md、PI_PLAYBOOK.md、VERSION、config、mcp 和 scripts。
   先确认 %CODEX_HOME%、%LOCALAPPDATA% 和 %USERPROFILE%\.pi\agent 的实际路径。
2. 确认 node.exe 与 npm.cmd 的真实路径，并检查 Node.js 版本不低于 22.19.0。
   如果缺少 Node.js 或 npm，只报告前置条件和官方安装来源，不要静默下载未知二进制。
3. 修改全局文件前，为即将修改的 %CODEX_HOME%\config.toml、AGENTS.md 和
   PI_PLAYBOOK.md 创建同目录 .bak.N 备份。目标文件不存在时明确记录“无需备份”。
4. 运行 scripts\install.ps1 做用户级安装。默认前缀必须是
   %LOCALAPPDATA%\CodexPi，不得要求管理员权限，不得覆盖项目文件或 pi 历史会话。
5. 如果 config.toml 已有 [mcp_servers.pi]：
   - 不得直接覆盖；
   - 保留原配置；
   - 比较安装器生成的 pi-mcp-snippet.toml；
   - 只有确认 command、args、超时和工具权限后才合并。
6. 检查 pi 是否已有可用 provider/model：
   - 优先识别当前 pi 1.5 的 models-store.json/settings.json/auth.json；
   - 如果没有可用模型，再运行 scripts\configure-provider.ps1；
   - API Key 必须用隐藏输入，不得在聊天中索要 API Key；
   - 不得打印、回传或把密钥写入 README、AGENTS、日志、Git 或最终回复。
7. AGENTS.md 与 PI_PLAYBOOK.md 按 CODEX_PI_KIT 标记块合并，保留标记外用户规则。
   必须保留以下策略：L0/L1 默认交给 pi；L2 只交给 pi 可独立验收的机械子任务；
   L3 禁止 pi 执行修改，只允许 read/grep/find/ls 只读复审。
8. 运行 scripts\verify.ps1。核对 Node 版本、pi 1.5.0、pi-delegate-mcp 0.1.1、
   launcher 语法、路径表、config.toml、AGENTS.md 和 pi Agent 目录。
9. 重启 Codex 或启动一个全新 Codex 会话，使 MCP 配置重新加载。先调用 pi MCP 的
   init，再用 tools=["read","grep","find","ls"] 启动短任务，并使用 status 轮询到
   done。长任务不要使用阻塞式 run。
10. 写入测试只允许在系统临时目录中新增文件。不得在真实项目中测试覆盖或删除。
11. 如需验证“Codex 与 pi 使用不同模型”：
    - 记录 Codex 当前模型；
    - 在 pi MCP 的 spawn 调用中显式传入另一个已启用的 provider/model；
    - 通过 status 核对实际 model，出现作用域错误时不得宣称成功或降级成功。
12. 最终只报告：改动文件、安装路径、备份路径、版本、实际验证结果、
    未配置的模型/证书/代理项和剩余风险。没有实际运行时不得声称“测试通过”。

目标：完成安装后，Codex 能在无需管理员权限的情况下通过名为 pi 的 MCP
发现工具、执行 init、按最小工具集委派任务，并保留用户现有配置和历史。
~~~

## 回滚

从安装报告读取本次实际备份路径，通常包括：

```text
%CODEX_HOME%\config.toml.bak.N
%CODEX_HOME%\AGENTS.md.bak.N
%CODEX_HOME%\PI_PLAYBOOK.md.bak.N
```

恢复前先确认备份时间和安装报告。程序前缀位于用户目录，删除前应确认完整绝对路径。

## 项目结构

```text
codex-pi-integration-kit/
├─ README.md
├─ CODEX_SETUP_PROMPT.md
├─ AGENTS.md
├─ PI_PLAYBOOK.md
├─ INSTALL_PROMPT.md
├─ MIGRATION_GUIDE.md
├─ SECURITY.md
├─ CONTRIBUTING.md
├─ CHANGELOG.md
├─ VERSION
├─ config/
├─ mcp/
├─ scripts/
└─ .github/workflows/
```

## 第三方组件

本仓库不重新分发 pi 或 pi-delegate-mcp 的完整源码。安装器从 npm 获取固定版本。
详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## License

[MIT](LICENSE)
