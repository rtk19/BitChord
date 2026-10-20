#!/usr/bin/env bash
# Merge the released source, preserving the iOS port on main. Conflicts stop
# the run; no generated translation or untested merge is published as an IPA.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
: "${TARGET_REPOSITORY:?Set TARGET_REPOSITORY to the destination owner/repo}"
upstream=kushagrasinghx/BitChord
tag=$(gh api "repos/$upstream/releases/latest" --jq .tag_name)
[[ -n "$tag" && "$tag" != null ]] || { echo 'No upstream release found.'; exit 1; }
git fetch "https://github.com/$upstream.git" "refs/tags/$tag"
released=$(git rev-parse FETCH_HEAD^{commit})
if git merge-base --is-ancestor "$released" HEAD; then
  echo "Upstream $tag is already incorporated."
  exit 0
fi
branch=automation/ios-upstream
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git switch -C "$branch"
if ! git merge --no-edit "$released"; then
  git merge --abort
  echo "::error::Upstream $tag conflicts with the iOS port. Resolve the merge before building."
  exit 1
fi
# The branch belongs only to this workflow. Lease prevents overwriting a
# concurrent update made after we observed the remote branch.
previous=$(git ls-remote origin "refs/heads/$branch" | cut -f1)
git push "--force-with-lease=refs/heads/$branch:$previous" origin "HEAD:refs/heads/$branch"
body=$(mktemp)
payload=$(mktemp)
trap 'rm -f "$body" "$payload"' EXIT
cat > "$body" <<EOF
Merge upstream release $tag ($released) into the iOS fork.

The port stays in this repository. Platform changes may need adaptation;
automatic merging cannot guarantee feature parity. Review the iOS build
and device playback checks before merging. Signed releases are built from main.
EOF
number=$(gh pr list --repo "$TARGET_REPOSITORY" --head "$branch" --state open --json number --jq '.[0].number // empty')
if [[ -n "$number" ]]; then
  python3 - "$body" "$payload" "$tag" <<'PY'
import json, pathlib, sys
json.dump({'title': 'iOS: integrate upstream ' + sys.argv[3], 'body': pathlib.Path(sys.argv[1]).read_text()}, open(sys.argv[2], 'w'))
PY
  gh api --method PATCH "repos/$TARGET_REPOSITORY/pulls/$number" --input "$payload" >/dev/null
else
  gh pr create --repo "$TARGET_REPOSITORY" --base main --head "$branch" --title "iOS: integrate upstream $tag" --body-file "$body"
fi
# GITHUB_TOKEN-created PRs do not fire pull_request workflows. Explicit
# workflow_dispatch does, so this branch receives its iOS validation build.
gh workflow run ios.yml --repo "$TARGET_REPOSITORY" --ref "$branch" -f distribution=simulator
