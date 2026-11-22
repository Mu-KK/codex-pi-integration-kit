<!-- CODEX_PI_KIT:BEGIN -->
# AGENTS.md — Codex 调用 pi 的执行规范

> 本文件由 Codex pi Integration Kit 管理。安装器只更新本标记块，保留标记外的用户规则。
>
> 标记：
>
> `CODEX_PI_KIT:BEGIN` / `CODEX_PI_KIT:END`

## 1. 适用范围

本规范适用于 Codex 通过 MCP `pi` 或 CLI `pi` 委派任务的工作流。

当任务涉及安装、修复、迁移或验收 Codex → pi：

1. 先读 `README.md`、`PI_PLAYBOOK.md` 和安装报告。
2. 先确认 Node、pi 和 `pi-delegate-mcp` 的实际版本。
3. 修改全局配置前先创建 `.bak.N` 备份。
4. 不把 API Key、Bearer Token、身份信息或完整鉴权头复制到聊天、日志、报告和 Git。

## 2. 目录与入口

默认路径：

```text
Codex 配置:       %CODEX_HOME%\config.toml
Codex 规则:       %CODEX_HOME%\AGENTS.md
pi 调用细则:      %CODEX_HOME%\PI_PLAYBOOK.md
MCP launcher:     %CODEX_HOME%\mcp\pi-delegate-mcp-launcher.mjs
launcher 路径表:  %CODEX_HOME%\mcp\pi-delegate-paths.json
pi Agent 配置:    %USERPROFILE%\.pi\agent\
安装前缀:         %LOCALAPPDATA%\CodexPi\
安装报告:         %LOCALAPPDATA%\CodexPi\install-report.json
```

如果环境变量 `CODEX_HOME` 或 `PI_CODING_AGENT_DIR` 已设置，以环境变量为准。

## 3. 影响面分级

| 等级 | 典型任务 | 默认执行主体 | pi 权限 | 验证 |
|---|---|---|---|---|
| L0 | 文档、注释、文案、配置说明 | CLI `pi` | 最小读写权限 | 语法、格式、配置解析；不跑完整测试 |
| L1 | 样式、单个局部组件、隔离的小逻辑 | CLI `pi` | 最小读写权限 | 相关测试；前端相关构建或类型检查 |
| L2 | API、服务逻辑、共享组件、多模块联动 | Codex 主代理负责架构与验收；pi 只做可独立验收的机械子任务 | 明确限定文件与动作 | 相关测试 + smoke；必要时 core |
| L3 | 表结构、鉴权、价格/核心计算、并发、依赖升级、发布、影响面不明 | Codex 主代理执行；pi 只读复审 | `read,grep,find,ls` | 先建恢复点，再跑 core/full 和端到端检查 |

等级不确定时按更高一级处理。L0/L1 不应为了保险升级为 full。

## 4. pi 调用入口

优先使用 MCP：

```text
init
spawn
spawn_batch
status
steer
answer
follow_up
abort
sessions
forget
models
run
```

必须遵循：

1. 先调用 `init`。
2. 长任务用 `spawn` + `status`，不要用阻塞式 `run`。
3. 每个任务显式指定 `cwd`、`id`、`label` 和最小工具集。
4. 任务跑偏时优先 `steer`，不要立刻 abort。
5. 任务完成后用 `follow_up` 复用原上下文，避免重复读取。
6. 已在 pi 内执行时，禁止再次启动 pi 或子 pi。

MCP 不适配时使用 CLI：

```powershell
& "<PI_CMD>" -p `
  --no-extensions --no-mcp `
  --tools read,grep,find,ls `
  --session-id "<stable-task-id>" `
  "<完整任务说明>"
```

CLI 工具集：

```text
只读:     read,grep,find,ls
可修改:   read,edit,write,powershell,grep,find,ls
```

不要为 CLI pi 分配交互式 PTY。使用普通非交互进程和 `-p`。

## 5. 任务说明模板

每次委派至少提供：

```text
cwd: 绝对工作目录
目标: 单一、可验收的结果
范围: 允许读取和修改的最小文件/目录
禁止项: 不得触碰的文件、数据、配置或外部系统
备份: 按影响面执行的备份方式
验收: 要运行的命令、预期结果、日志路径
输出: 改动文件、验证结果、剩余风险；不要粘贴大段日志
```

pi 看不到 Codex 当前对话中的隐含上下文。所有必要事实必须写入 prompt。

## 6. 备份与验证

- L0：Git 可恢复时使用 Git；未跟踪全局配置使用 `.bak.N`。
- L1：每个目标文件使用同目录 `.bak.N`。
- L2：备份全部改动文件，并列出恢复清单。
- L3：先建立 Git 分支/提交或完整副本；数据库、数据目录、配置分别备份。

测试命令统一使用：

```text
-q --tb=short
```

完整日志落盘到项目的 `data/outputs/tmp`。只读取失败摘要、计数和末尾约 20 行。

## 7. pi 返回后的强制复核

Codex 必须：

1. 查看实际 diff。
2. 检查是否越界。
3. 重新运行对应验证，不把 pi 自述当验证证据。
4. 检查服务启动、接口或页面 smoke（适用时）。
5. 报告改动文件、验证结果和剩余风险。

## 8. 安全边界

`bash` 和 `powershell` 不是沙箱。授予它们就等于授予写入、删除和执行能力。发布、鉴权、数据库迁移和核心计算必须由 Codex 主代理控制。

<!-- CODEX_PI_KIT:END -->
