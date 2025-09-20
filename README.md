# GitHub Secure Defaults Toolkit

Bootstrap opinionated security settings across every repository in a GitHub organization. The included Bash script orchestrates GitHub CLI calls to enable Dependabot, lock down branches, and set up protective tag rules so you can converge on a hardened baseline with one command.

## Prerequisites
- **GitHub CLI (`gh`)** authenticated with an account that can administer every repository in the target org (requires `repo`, `read:org`, and admin rights for enforcement changes).
- **`jq`** for JSON processing (the script shells out to it).
- **`make`** (optional) if you prefer invoking the workflow via `make secure:repo`; otherwise call the script directly.
- Permissions or plan features for any setting you want to enable (e.g., Advanced Security, repository rulesets). The script logs and skips features that your plan does not support.

## Setup
1. Install the prerequisites and run `gh auth login`.
2. Clone this repository and `cd` into it.
3. Export the organization you want to process: `export ORG=my-org`.
4. (Optional) Edit `secure-defaults-git.sh` to match your CI checks or enforcement preferences before running it at scale.

## Usage
```bash
# Run via make (recommended for convenience)
ORG=my-org make secure:repo

# Or call the script directly
ORG=my-org bash secure-defaults-git.sh
```
The script iterates every repository returned by `gh repo list "$ORG"` and applies the following:
- Enables Dependabot vulnerability alerts and automated security fixes.
- Enables Advanced Security, secret scanning, and push protection **only for public repos** (private repos are skipped unless your plan permits it).
- Enforces branch protection on each default branch with:
  - Required status checks (`ci/test`, `ci/lint`, `ci/build` by default—adjust these to your CI jobs).
  - Admin enforcement and one approving review.
  - Disabled force pushes and branch deletions.
  - Linear history requirement.
- Sets required signed commits for public repositories where Advanced Security is applied.
- Creates or updates a repository ruleset named "Protect version tags" that blocks deletion or modification of tags matching `refs/tags/v*` when rulesets are available. Orgs without ruleset support will simply log a skip.

## Customizing Enforcement
- **Status checks**: update the `REQUIRED_CHECKS` JSON array in the script to reflect your actual workflow names.
- **Review policy**: adjust the `required_pull_request_reviews` block for stricter or looser review rules.
- **Tag protections**: change the include/exclude patterns or rule types in the ruleset payload to fit your release naming scheme.
- **Scope filtering**: tweak the `gh repo list` call (e.g., add `--visibility private`) if you want to process a subset of repositories at a time.

## Interpreting Failures & Logs
- `HTTP 403` typically means the organization plan lacks access (e.g., Advanced Security) or the authenticated user is missing admin rights. The script logs the error and continues.
- `HTTP 422` during branch protection usually means the repository does not have the specified status checks configured. Review your workflow names or disable the requirement.
- `Repository rulesets unavailable` indicates the org/repo can't use rulesets yet (often due to plan tier). Tag rules will stay unchanged.
- Re-run the script safely; each API call is idempotent and either updates existing settings or logs the lack of support.

## Tips for Rolling Out
- Test on a staging org or a small repo subset first (e.g., copy the script and temporarily limit `REPOS` to a known list) before applying to production.
- Keep an eye on rate limits if your org hosts hundreds of repos; `gh api` surfaces remaining quota in verbose mode.
- Commit any local tweaks (status checks, bypass actors, etc.) so future runs stay consistent across administrators.

## Troubleshooting
- Run with `bash -x secure-defaults-git.sh` to trace the exact command that fails when diagnosing issues.
- If you need to remove protections, use the corresponding GitHub API endpoints or GitHub UI; the script currently only enforces settings.

## Contributing
Feel free to adjust the defaults to match your organization’s policies and submit improvements via pull request.
