CI and local pre-commit hooks

1) CI (GitHub Actions)
- A workflow `/.github/workflows/ci.yml` runs `flutter analyze` and `flutter test --coverage` on pushes and PRs to `main` and `migration`.

2) Local pre-commit hook
- Run `scripts/install-hooks.sh` to install the pre-commit hook into `.git/hooks/pre-commit`.
- The hook will run `flutter analyze` and `flutter test --coverage` before each commit. If any step fails, the commit is aborted.

Usage:

```bash
./scripts/install-hooks.sh
```
