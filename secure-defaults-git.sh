#!/usr/bin/env bash
set -euo pipefail

: "${ORG:?Set ORG env var, e.g. export ORG='my-org'}"

# Fetch all repos in the org (adjust --visibility if you want only private/public/internal)
mapfile -t REPOS < <(gh repo list "$ORG" --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner')

echo "Found ${#REPOS[@]} repos in $ORG"

for REPO in "${REPOS[@]}"; do
  echo "=== Securing $REPO ==="

  repo_meta=$(gh repo view "$REPO" --json defaultBranchRef,visibility)
  DEFAULT_BRANCH=$(jq -r '.defaultBranchRef.name // ""' <<<"$repo_meta")
  VISIBILITY=$(jq -r '.visibility' <<<"$repo_meta")

  # Dependabot alerts & security updates
  gh api -X PUT "repos/$REPO/vulnerability-alerts" >/dev/null || true
  gh api -X PUT "repos/$REPO/automated-security-fixes" >/dev/null || true

  # Skip advanced security features unless the repository is public.
  if [[ "$VISIBILITY" == "PUBLIC" ]]; then
    gh api -X PATCH "repos/$REPO" -f security_and_analysis='{
      "advanced_security": {"status":"enabled"},
      "secret_scanning": {"status":"enabled"},
      "secret_scanning_push_protection": {"status":"enabled"}
    }' >/dev/null || true

    gh api -X PUT "repos/$REPO/branches/$DEFAULT_BRANCH/protection/required_signatures" \
      -H "Accept: application/vnd.github+json" >/dev/null || true
  else
    echo "Skipping GitHub Advanced Security configuration for $REPO (visibility: $VISIBILITY)"
  fi

  # --- Branch protection on default branch ---
  if [[ -z "$DEFAULT_BRANCH" ]]; then
    echo "No default branch reported for $REPO; skipping branch protection."
  else
    REQUIRED_CHECKS='["ci/test","ci/lint","ci/build"]'
    BRANCH_PROTECTION_PAYLOAD=$(jq -n \
      --argjson checks "$REQUIRED_CHECKS" \
      '{
        required_status_checks: {strict: true, contexts: $checks},
        enforce_admins: true,
        required_pull_request_reviews: {
          dismiss_stale_reviews: true,
          require_code_owner_reviews: false,
          required_approving_review_count: 1
        },
        restrictions: null,
        allow_force_pushes: false,
        allow_deletions: false,
        required_linear_history: true,
        block_creations: true
      }')

    if ! gh api -X PUT \
      "repos/$REPO/branches/$DEFAULT_BRANCH/protection" \
      -H "Accept: application/vnd.github+json" \
      --input <(printf '%s' "$BRANCH_PROTECTION_PAYLOAD") >/dev/null; then
      echo "Branch protection configuration failed for $REPO (visibility: $VISIBILITY); skipping."
    fi
  fi

  # --- Protect release tags like v1.2.3 using repository rulesets ---
  TAG_RULESET_NAME="Protect version tags"
  TAG_RULESET_PAYLOAD=$(jq -n \
    --arg name "$TAG_RULESET_NAME" \
    '{
      name: $name,
      target: "tag",
      enforcement: "active",
      bypass_actors: [],
      conditions: {
        ref_name: {
          include: ["refs/tags/v*"],
          exclude: []
        }
      },
      rules: [
        {
          type: "deletion"
        },
        {
          type: "update",
          parameters: {
            update_allows_fetch_and_merge: false
          }
        }
      ]
    }')

  if ruleset_listing=$(gh api "repos/$REPO/rulesets" 2>/dev/null); then
    existing_ruleset_id=$(jq -r --arg name "$TAG_RULESET_NAME" \
      '.[] | select(.name == $name and .target == "tag") | .id' <<<"$ruleset_listing" | head -n1)

    if [[ -n "$existing_ruleset_id" ]]; then
      if ! gh api -X PATCH "repos/$REPO/rulesets/$existing_ruleset_id" \
        -H "Accept: application/vnd.github+json" \
        --input <(printf '%s' "$TAG_RULESET_PAYLOAD") >/dev/null; then
        echo "Tag ruleset update failed for $REPO; skipping."
      fi
    else
      if ! gh api -X POST "repos/$REPO/rulesets" \
        -H "Accept: application/vnd.github+json" \
        --input <(printf '%s' "$TAG_RULESET_PAYLOAD") >/dev/null; then
        echo "Tag ruleset creation failed for $REPO; skipping."
      fi
    fi
  else
    echo "Repository rulesets unavailable for $REPO; skipping tag ruleset setup."
  fi

  echo "✔ $REPO secured (default branch: $DEFAULT_BRANCH)"
done

echo "All done."
