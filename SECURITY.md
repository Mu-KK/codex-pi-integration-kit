# Security Policy

## Reporting a vulnerability

Please report security issues privately to the repository maintainer through
GitHub's private vulnerability reporting feature. Do not open a public issue
containing credentials, private network details, or a working exploit.

## Credential handling

This repository must never contain API keys, bearer tokens, private keys,
corporate certificates, or authenticated session data.

- Provider secrets belong only in the local pi credential store.
- Do not paste secrets into issues, pull requests, screenshots, or logs.
- Rotate a credential immediately if it is accidentally committed.
- Review pull requests for files covered by `.gitignore` before merging.

## Delegation is not a sandbox

pi-delegate-mcp defaults to the read-only tools `read`, `grep`, `find`, and
`ls`. This kit may allow `bash`, `powershell`, `edit`, and `write` as an upper
bound for explicit delegation. Those tools can modify or delete files with the
permissions of the current Windows user.

Keep per-task tool lists narrow. In particular, L3 work must use only
`read,grep,find,ls` and must be performed by the primary Codex agent.
