# 可直接交给 Codex 的安装提示词

从仓库根目录启动 Codex，然后把下面整段提示词发给它。

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
