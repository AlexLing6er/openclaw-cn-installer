# Security & Privacy

## Data handling

This repository is designed to avoid committing personal/sensitive local data.

- Local memory/state directories are ignored.
- Credential-like files are ignored by default.
- No API keys/tokens should be committed.

## Before pushing

Run a quick local check:

```bash
git status
git ls-files
```

Optional secret grep:

```bash
grep -RInE "(AKIA|BEGIN [A-Z ]*PRIVATE KEY|ghp_|xoxb-|token|password)" $(git ls-files) || true
```

## Reporting

If sensitive data is accidentally committed:

1. Revoke/rotate exposed credentials immediately.
2. Remove files from history (filter-repo/BFG) if needed.
3. Force-push cleaned history.
