# Contributing

1. Run `pwsh -NoProfile -File .\scripts\validate-kit.ps1`.
2. Test installer changes against an isolated temporary `CODEX_HOME` and
   `PI_CODING_AGENT_DIR`.
3. Never commit real credentials, local configuration, backups, or pi history.
4. Keep installs user-scoped and avoid administrator requirements.
5. Use Conventional Commits, for example:
   `fix(installer): preserve existing pi MCP configuration`.

Changes that broaden delegated tools require an explicit security rationale.
