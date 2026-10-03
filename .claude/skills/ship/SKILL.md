---
name: ship
description: Ship the current changes — create a branch if on main, run tests, commit with Conventional Commits, push, and open a PR against main. Use when the user asks to ship, commit and open a PR, or "push + PR".
---

# Ship changes via branch + PR

`main` is protected: never commit or push to it, and never merge PRs yourself. Follow these steps in order and stop on any failure.

## 1. Branch

```bash
git branch --show-current
git status --short
```

- If the current branch is `main`, create a branch named `<type>/<short-kebab-topic>` (e.g. `feat/island-panel`, `fix/notch-height`) from up-to-date main:
  ```bash
  git fetch origin && git switch -c <type>/<topic> origin/main
  ```
  Uncommitted changes carry over to the new branch.
- If already on a feature branch, keep using it.
- If there are no changes to commit and nothing unpushed, stop and tell the user.

## 2. Test

Run the same command CI uses and stop if it fails (report the failing tests; do not commit):

```bash
xcodebuild test -project thenotch.xcodeproj -scheme thenotch -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -v 'linkd.autoShortcut' | tail -30
```

## 3. Stage

Stage only files that belong to this change, by explicit path. Never use `git add -A` / `git add .`. Never stage `docs/` (the maintainer's private planning notes), `xcuserdata/`, build output, or secrets.

## 4. Commit

Conventional Commits: `<type>(<optional scope>): <imperative summary>` — lowercase type, summary ≤ 72 chars, no trailing period.

- Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `ci`, `build`, `chore`, `style`.
- Body (wrapped at 72): what changed and **why**. Use `BREAKING CHANGE:` footer when applicable.
- One logical change per commit; split unrelated changes into separate commits.

Pass the message via heredoc so formatting is preserved:

```bash
git commit -F - <<'EOF'
feat(window): add borderless island panel

Explain why here.

Co-Authored-By: ...
EOF
```

## 5. Push

```bash
git push -u origin HEAD
```

## 6. Open the PR

Requires `gh` to be authenticated (`gh auth status`). If it is not, stop and ask the user to run `! gh auth login`.

If a PR already exists for this branch (`gh pr view --json url`), just report its URL — the push updated it. Otherwise:

```bash
gh pr create --base main --title "<same as the commit summary, or a summary of all commits>" --body-file - <<'EOF'
## Summary
- ...

## Test plan
- [x] `xcodebuild test` passes locally
- [ ] ...
EOF
```

The body follows `.github/pull_request_template.md`.

## 7. Report

Give the user the PR URL and say that CI (`build-and-test`) must pass before they merge. Do **not** merge the PR, enable auto-merge, or bypass branch protection.
