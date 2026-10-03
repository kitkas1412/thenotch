---
name: ship
description: Ship the current changes — create a branch if on main, run tests, commit with Conventional Commits, and push the branch (the user opens the PR themselves). Use when the user asks to ship, or to commit and push.
---

# Ship changes on a branch

`main` is protected: never commit or push to it, and never open or merge PRs yourself. Follow these steps in order and stop on any failure.

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

## 6. Report — do not open the PR

Do **not** create the pull request (no `gh pr create`); the maintainer opens it on GitHub. Give the user:

- The branch name and the commit(s) pushed.
- The "Create a pull request" link printed by `git push`, i.e. `https://github.com/kitkas1412/thenotch/pull/new/<branch>` (if the branch already has an open PR, say the push updated it instead).
- A ready-to-paste PR title (Conventional Commits, same as the commit summary or a summary of all commits) and body following `.github/pull_request_template.md`:

```markdown
## Summary
- ...

## Test plan
- [x] `xcodebuild test` passes locally
- [ ] ...
```

Remind them that CI (`build-and-test`) must pass before merging. Never merge, enable auto-merge, or bypass branch protection.
