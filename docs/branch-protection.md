# Branch Protection Checklist (Production)

Use this checklist when configuring branch/ruleset protection for `main`.

## 1) Protect `main`

Create a branch ruleset for `main` with:

- [ ] **Require a pull request before merging**
- [ ] **Require at least 1 approval** (2 if you want stricter policy)
- [ ] **Dismiss stale approvals on new commits**
- [ ] **Require conversation resolution before merge**
- [ ] **Require status checks to pass before merging**
- [ ] **Require branches to be up to date before merging**
- [ ] **Block force pushes**
- [ ] **Block branch deletion**

### Required status checks

After CI runs once, mark these checks as required:

- [ ] `CI / Build + Preflight`  
  (UI label can appear as just `Build + Preflight` depending on GitHub view)

## 2) Limit direct pushes

- [ ] Restrict push access to maintainers only (or no direct pushes at all)
- [ ] Keep normal development through pull requests
- [ ] If needed, add explicit bypass actors (small set only)

## 3) Recommended merge policy

- [ ] Enable **Squash merge**
- [ ] Optionally disable merge commits / rebase merges (team preference)
- [ ] Optionally require linear history

## 4) Tag protection for releases (`v*`)

Create a tag ruleset for `v*`:

- [ ] Restrict who can create release tags
- [ ] Allow only maintainers (and/or approved automation path)
- [ ] Keep accidental tag creation by contributors blocked

## 5) GitHub Actions permissions

In **Settings → Actions → General**:

- [ ] Set **Workflow permissions** to **Read and write** (needed for PR/tag automation)
- [ ] Enable **Allow GitHub Actions to create and approve pull requests**

## 6) Required secrets for release pipeline

In **Settings → Secrets and variables → Actions**, set:

- [ ] `APPLE_SIGNING_CERT_BASE64`
- [ ] `APPLE_SIGNING_CERT_PASSWORD`
- [ ] `APPLE_KEYCHAIN_PASSWORD`
- [ ] `APPLE_SIGN_IDENTITY`
- [ ] `APPLE_ID`
- [ ] `APPLE_TEAM_ID`
- [ ] `APPLE_APP_SPECIFIC_PASSWORD`

## 7) Quick validation

- [ ] Open a test PR and confirm required checks block merge until green
- [ ] Trigger `Version Bump` workflow and confirm PR creation works
- [ ] Create a `v*` tag from an authorized actor and confirm release workflow runs
