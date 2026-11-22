# PI Playbook

> 本文件是 `AGENTS.md` 的配套细则，只在需要调用 pi 时读取。

## 1. 版本基线

```text
Node.js >= 22.19.0
@earendil-works/pi-coding-agent 1.5.0
pi-delegate-mcp 0.1.1
```

先核实实际版本，不根据旧记忆推断能力。

## 2. 分级规则

- L0/L1：默认交给 CLI pi。
- L2：Codex 负责架构、集成和最终验证；pi 只做可独立验收的机械子任务。
- L3：pi 不执行修改，只允许只读复审。

## 3. MCP 调用

第一次调用必须是：

```text
init
```

推荐流程：

```text
init
  -> spawn
  -> status
  -> steer（任务跑偏时）
  -> follow_up（完成后继续）
  -> sessions（批量查看）
```

`spawn` 参数建议：

```json
{
  "id": "task-id",
  "label": "short-purpose",
  "cwd": "C:\\absolute\\path",
  "tools": ["read", "grep", "find", "ls"],
  "prompt": "包含目标、范围、禁止项、验收命令和输出格式的完整任务"
}
```

不要：

- 长任务使用阻塞式 `run`。
- 省略 `cwd`。
- 省略工具白名单。
- 在 prompt 中依赖 Codex 对话里的隐含上下文。
- 在 pi 内继续启动 pi。

## 4. CLI 调用

只读：

```powershell
& "<PI_CMD>" -p `
  --no-extensions --no-mcp `
  --tools read,grep,find,ls `
  --session-id "review-20261118" `
  "只读复核指定范围，返回问题、证据和建议，不修改文件。"
```

允许修改：

```powershell
& "<PI_CMD>" -p `
  --no-extensions --no-mcp `
  --tools read,edit,write,powershell,grep,find,ls `
  --session-id "mechanical-20261118" `
  "按以下范围和验收标准完成任务：<完整任务说明>"
```

## 5. 模型选择

- 简单/机械任务优先使用轻量模型。
- 轻量模型明显不足时才升级到更强模型。
- 模型名必须是实际可解析的 `provider/modelId`。
- 不要静默回退到未声明模型。

自定义 OpenAI-compatible provider 的模型引用格式为：

```text
<provider-id>/<model-id>
```

启用 `PI_DELEGATE_STRICT_SCOPE=1` 时，模型还必须出现在 pi
`settings.json` 的 `enabledModels` 中。不可用模型会硬失败，不会静默回退。

## 6. 会话管理

- 同一任务复用稳定 `session-id`。
- 独立任务使用新会话。
- 完成后的继续工作使用 MCP `follow_up` 或 CLI 同 session id。
- 已结束会话不会自动进入 Codex 上下文。

## 7. 工具权限

pi 内置工具：

```text
read
bash
powershell
edit
write
grep
find
ls
```

只读默认集：

```text
read,grep,find,ls
```

MCP 服务的 `PI_DELEGATE_ALLOW_TOOLS` 是允许上限。单次调用仍应使用 `tools` 进一步收窄。

## 8. 复核

pi 返回后必须检查：

1. 实际 diff。
2. 越界修改。
3. 新增文件和备份。
4. 测试命令与结果。
5. 日志路径和末尾错误。
6. 服务、接口或页面 smoke。

不得把 pi 的自述当成测试通过证据。
