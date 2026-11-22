# 迁移说明

## 核心目录

Codex → pi 不是单独一个程序目录，最小结构包括：

```text
Codex MCP 配置
Codex MCP launcher
Node.js / npm
@earendil-works/pi-coding-agent
pi-delegate-mcp
pi Agent 配置
```

本工具包使用用户级 npm 前缀：

```text
%LOCALAPPDATA%\CodexPi\npm-global\
```

launcher 不硬编码该路径，而是读取：

```text
%CODEX_HOME%\mcp\pi-delegate-paths.json
```

## 最小迁移内容

```text
%CODEX_HOME%\config.toml
%CODEX_HOME%\mcp\pi-delegate-mcp-launcher.mjs
%CODEX_HOME%\mcp\pi-delegate-paths.json
%USERPROFILE%\.pi\agent\models-store.json（pi 1.5 当前布局）
%USERPROFILE%\.pi\agent\models.json（旧版兼容布局）
%USERPROFILE%\.pi\agent\auth.json
%USERPROFILE%\.pi\agent\settings.json
```

需要内网 CA 时额外迁移证书，并在 MCP 环境变量中写 `NODE_EXTRA_CA_CERTS`。

`models-store.json`、`models.json`、`auth.json` 和真实 `settings.json` 均包含
本机状态或凭据信息，不得提交到公开仓库。

## 不需要迁移

- Codex 运行日志
- pi 历史会话
- 临时目录
- `.bak.N`
- npm 缓存
- 旧版 Node 备份

## 用户名变化

安装脚本根据 `%USERPROFILE%`、`%CODEX_HOME%`、`%LOCALAPPDATA%` 动态计算路径。

迁移后仍应检查：

```text
%USERPROFILE%\.pi\agent\settings.json
%USERPROFILE%\.pi\agent\trust.json
%USERPROFILE%\.pi\agent\mcp.json
```

里面可能保存旧用户目录、Git Bash 路径或旧项目信任项。

## 代理与证书

发布包不写死任何公司代理。需要时在 `[mcp_servers.pi.env]` 中补充：

```toml
HTTP_PROXY = 'http://proxy.example:8080'
HTTPS_PROXY = 'http://proxy.example:8080'
NO_PROXY = '.corp.example.com,localhost,127.0.0.1'
NODE_EXTRA_CA_CERTS = 'C:\path\to\corporate-root-ca.pem'
```

如果目标机器不在该网络，应保持这些项为空。

## 旧本机路径

原环境曾使用：

```text
C:\Users\<旧用户名>\node-v24.19.0-win-x64\
C:\Users\<旧用户名>\.pi\agent\
C:\Users\<旧用户名>\.codex\
```

新环境不要盲目依赖旧绝对路径。使用本工具包安装器生成新的路径表。
