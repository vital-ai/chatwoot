#!/usr/bin/env bash
# Keeps vital-ai/chatwoot's copies of upstream in sync with chatwoot/chatwoot:
#   - fast-forwards develop and master (nothing else, never forced, never deleted);
#   - pushes upstream's new release tags (v*), never moving or deleting one;
#   - disables any upstream workflow that has become active in the fork, and cancels any run it started.
# It never reads, writes or deletes vital/ branches, vital-keycloak-sso, vital-keycloak-auth or fork-sync.
#
# In the Action, SYNC_TOKEN is a fine-grained token for vital-ai/chatwoot (Contents, Workflows and Actions write).
# Locally it uses your own git and gh credentials. DRY_RUN=1 reports without pushing.
set -euo pipefail

FORK_REPO=${FORK_REPO:-vital-ai/chatwoot}
UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/chatwoot/chatwoot.git}
BRANCHES=(develop master)          # the only branches this script may push
TAG_PATTERN='v*'                   # the only tags this script may push
KEEP_WORKFLOW=.github/workflows/upstream_sync.yml
DRY_RUN=${DRY_RUN:-0}
WORK=${WORK:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/chatwoot-upstream-sync}

git_auth=()
if [ -n "${SYNC_TOKEN:-}" ]; then
  basic=$(printf 'x-access-token:%s' "$SYNC_TOKEN" | base64 | tr -d '\n')
  git_auth=(-c "http.https://github.com/.extraheader=AUTHORIZATION: basic $basic")
  export GH_TOKEN="$SYNC_TOKEN"
fi
g() { git "${git_auth[@]}" -C "$WORK" "$@"; }

if [ ! -d "$WORK/.git" ] && [ ! -f "$WORK/HEAD" ]; then
  git init -q --bare "$WORK"
fi
g remote remove fork 2>/dev/null || true
g remote remove upstream 2>/dev/null || true
g remote add fork "https://github.com/$FORK_REPO.git"
g remote add upstream "$UPSTREAM_URL"

echo "Fetching upstream and the fork's copies..."
for b in "${BRANCHES[@]}"; do
  g fetch -q --no-tags upstream "+refs/heads/$b:refs/remotes/upstream/$b"
  g fetch -q --no-tags fork "+refs/heads/$b:refs/remotes/fork/$b"
done
g fetch -q upstream "+refs/tags/$TAG_PATTERN:refs/upstream-tags/$TAG_PATTERN" --no-tags
g fetch -q fork "+refs/tags/*:refs/fork-tags/*" --no-tags

failed=0
refspecs=()
for b in "${BRANCHES[@]}"; do
  up=$(g rev-parse "refs/remotes/upstream/$b"); mine=$(g rev-parse "refs/remotes/fork/$b")
  if [ "$up" = "$mine" ]; then
    echo "$b: up to date ($up)"
  elif g merge-base --is-ancestor "$mine" "$up"; then
    echo "$b: fast-forward ${mine:0:12} -> ${up:0:12} ($(g rev-list --count "$mine..$up") commits)"
    refspecs+=("$up:refs/heads/$b")
  else
    echo "::error::$b has diverged from upstream (fork ${mine:0:12}, upstream ${up:0:12}); not forcing. Look at it by hand."
    failed=1
  fi
done

new_tags=0
while read -r tag; do
  [ -n "$tag" ] || continue
  up=$(g rev-parse "refs/upstream-tags/$tag")
  if mine=$(g rev-parse -q --verify "refs/fork-tags/$tag"); then
    if [ "$up" != "$mine" ]; then
      echo "::warning::tag $tag differs between upstream and the fork; left as it is in the fork."
    fi
  else
    refspecs+=("refs/upstream-tags/$tag:refs/tags/$tag")
    new_tags=$((new_tags + 1))
  fi
done < <(g for-each-ref --format='%(refname:lstrip=2)' "refs/upstream-tags/")
echo "New tags: $new_tags"

if [ ${#refspecs[@]} -gt 0 ]; then
  if [ "$DRY_RUN" = 1 ]; then
    echo "DRY_RUN: would push ${#refspecs[@]} refs"
  else
    # Plain push: a non-fast-forward is refused by git, never forced. Branches go first, tags in batches.
    branch_specs=(); tag_specs=()
    for r in "${refspecs[@]}"; do case "$r" in *:refs/heads/*) branch_specs+=("$r");; *) tag_specs+=("$r");; esac; done
    [ ${#branch_specs[@]} -gt 0 ] && g push -q fork "${branch_specs[@]}"
    for ((i = 0; i < ${#tag_specs[@]}; i += 50)); do g push -q fork "${tag_specs[@]:i:50}"; done
    echo "Pushed ${#branch_specs[@]} branches and ${#tag_specs[@]} tags."
  fi
fi

# Upstream's workflows must not run in the fork: disable any that is active, except this one.
if command -v gh >/dev/null; then
  gh api "repos/$FORK_REPO/actions/workflows" --paginate --jq '.workflows[] | select(.state == "active") | "\(.id) \(.path)"' |
    while read -r id path; do
      [ "$path" = "$KEEP_WORKFLOW" ] && continue
      if [ "$DRY_RUN" = 1 ]; then echo "DRY_RUN: would disable $path"; else gh api -X PUT "repos/$FORK_REPO/actions/workflows/$id/disable" >/dev/null && echo "Disabled workflow $path"; fi
    done
fi

# A workflow file upstream has just added can start on the push above before it's disabled: cancel any such run.
if command -v gh >/dev/null && [ "$DRY_RUN" != 1 ]; then
  for status in queued in_progress waiting requested pending; do
    gh api "repos/$FORK_REPO/actions/runs?status=$status&per_page=100" --jq '.workflow_runs[] | "\(.id) \(.path)"' |
      while read -r id path; do
        [ "${path%%@*}" = "$KEEP_WORKFLOW" ] && continue
        gh api -X POST "repos/$FORK_REPO/actions/runs/$id/cancel" >/dev/null 2>&1 && echo "Cancelled run $id ($path)"
      done
  done
fi

exit $failed
