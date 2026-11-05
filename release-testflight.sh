#!/bin/bash
# release-testflight.sh — Created by dimaswisodewo on 04/11/2026.
set -euo pipefail

usage() {
    printf 'Usage: %s vMAJOR.MINOR.PATCH\nExample: %s v1.2.3\n' "$0" "$0"
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

if [[ $# -eq 1 && "$1" == '--help' ]]; then
    usage
    exit 0
fi
if [[ $# -ne 1 ]]; then
    usage >&2
    exit 1
fi
release_tag=$1
if [[ ! "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    usage >&2
    fail 'Use a numeric version such as v1.2.3.'
fi
command -v git >/dev/null || fail 'Install Git before releasing.'
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
repo_root=$(git rev-parse --show-toplevel) || fail 'Run the script from an Itera checkout.'
cd -- "$repo_root"
git remote get-url origin >/dev/null || fail 'Configure origin before releasing.'
git var GIT_AUTHOR_IDENT >/dev/null || fail 'Configure git user.name and user.email.'
git var GIT_COMMITTER_IDENT >/dev/null || fail 'Configure a Git committer name and email.'

for marker in MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD BISECT_START; do
    if [[ -e "$(git rev-parse --git-path "$marker")" ]]; then
        fail "Finish the active Git operation ($marker) before releasing."
    fi
done
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || fail 'Working tree has changes or untracked files. Commit or stash them first.'
if git show-ref --verify --quiet "refs/tags/$release_tag"; then
    fail "Local tag $release_tag already exists. Choose a new version, or follow the documented push-recovery instructions."
fi
printf 'Fetching production from origin...\n'
git ls-remote --exit-code --heads origin refs/heads/production >/dev/null && lookup_status=0 || lookup_status=$?
if [[ $lookup_status -eq 2 ]]; then
    fail 'origin/production does not exist. Create it from a reviewed release commit first.'
elif [[ $lookup_status -ne 0 ]]; then
    fail 'Cannot access origin. Check Git credentials, repository access, and network connectivity.'
fi
git fetch origin '+refs/heads/production:refs/remotes/origin/production' || fail 'Could not fetch production. Check credentials/network and whether the branch still exists.'
git ls-remote --exit-code --tags origin "refs/tags/$release_tag" >/dev/null && lookup_status=0 || lookup_status=$?
if [[ $lookup_status -eq 0 ]]; then
    fail "Remote tag $release_tag already exists. Choose a new version."
elif [[ $lookup_status -ne 2 ]]; then
    fail 'Could not check remote tags. Check credentials and connectivity.'
fi
release_commit=$(git rev-parse refs/remotes/origin/production)
if git show-ref --verify --quiet refs/heads/production; then
    git merge-base --is-ancestor refs/heads/production "$release_commit" || fail 'Local production is ahead of or diverged from origin/production. Integrate reviewed changes through your normal process first.'
fi
for required_file in .github/workflows/testflight.yml fastlane/Fastfile Gemfile Gemfile.lock project.yml; do
    git cat-file -e "$release_commit:$required_file" || fail "Production is missing $required_file. Merge the release configuration before tagging."
done
printf 'Switching to production...\n'
if git show-ref --verify --quiet refs/heads/production; then
    git switch production || fail 'Could not switch to production. If it is checked out in another worktree, run the script there (git worktree list).'
else
    git switch --track -c production origin/production || fail 'Could not create the local production tracking branch.'
fi
git merge --ff-only "$release_commit" || fail 'Could not fast-forward production. Inspect Git status before retrying.'
[[ "$(git rev-parse HEAD)" == "$release_commit" ]] || fail 'Production does not match the fetched remote commit.'
printf 'Release: %s\nCommit: %s\nDestination: origin (%s)\n' "$release_tag" "$release_commit" "$(git remote get-url origin)"
git tag -a "$release_tag" -m "TestFlight $release_tag" || fail 'Could not create the annotated tag. Check Git identity and tag-signing configuration.'
if ! git push origin "refs/tags/$release_tag:refs/tags/$release_tag"; then
    printf 'Error: Tag push failed. The local tag was retained.\nCheck the remote tag first:\n  git ls-remote --tags origin refs/tags/%s\nIf absent, fix credentials/network or tag rules, then retry:\n  git push origin refs/tags/%s:refs/tags/%s\nIf present, verify its target before doing anything else; never overwrite it automatically.\n' "$release_tag" "$release_tag" "$release_tag" >&2
    exit 1
fi
printf 'Release tag pushed; GitHub Actions will build and upload.\nMonitor: https://github.com/OneDihrection/Itera/actions\nThe build and TestFlight processing still need to complete.\n'
