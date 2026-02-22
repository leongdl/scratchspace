---
inclusion: always
---

# No Credentials in Git

- NEVER stage, commit, or write credentials, secrets, API keys, tokens, or private keys into any tracked file.
- This includes AWS access keys, session tokens, HuggingFace tokens, PEM files, and any other sensitive material.
- If you detect credentials in a file that is or could be tracked by git, immediately warn the user and refuse to proceed until the credentials are removed.
- Always ensure credential files (e.g. `creds.sh`, `*.pem`, `*.key`) are listed in `.gitignore` before any git operations.
- When writing Dockerfiles or scripts that need credentials, use build args, environment variables, or runtime mounts — never hardcode secrets.
