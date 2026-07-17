#!/usr/bin/env bash

set -euo pipefail

image="${1:?usage: tests/test-image.sh IMAGE}"
workspace="$(mktemp -d)"

cleanup() {
  exit_code=$?

  docker run --rm \
    --user root \
    --entrypoint sh \
    --volume "$workspace:/workspace" \
    "$image" \
    -c 'chmod -R a+rwX /workspace' \
    >/dev/null 2>&1 || true
  rm -rf -- "$workspace" || true

  return "$exit_code"
}
trap cleanup EXIT

usage="$(docker run --rm "$image" 2>&1)"
grep -F "bfg " <<<"$usage"
grep -F -- "--delete-files" <<<"$usage"

uid="$(docker run --rm --entrypoint sh "$image" -c 'id -u')"
if ((uid == 0)); then
  echo "expected the image to run as a non-root user" >&2
  exit 1
fi

docker run --rm --entrypoint sh "$image" -c '
  test "$HOME" = /home/bfg
  test "$PWD" = /home/bfg/workspace
  test -r /home/bfg/bfg.jar
'

git init --initial-branch=main "$workspace/source"
git -C "$workspace/source" config user.name "CI"
git -C "$workspace/source" config user.email "ci@example.invalid"
git -C "$workspace/source" config commit.gpgsign false

printf '%s\n' "super-secret" >"$workspace/source/credential.json"
printf '%s\n' "keep me" >"$workspace/source/keep.txt"
git -C "$workspace/source" add .
git -C "$workspace/source" commit -m "Add test files"

git clone --mirror "$workspace/source" "$workspace/repo.git"

# GitHub-hosted runners and the image use different UIDs. Make the fixture
# writable so the image's non-root user can rewrite the mounted repository.
chmod -R a+rwX "$workspace"

docker run --rm \
  --volume "$workspace:/home/bfg/workspace" \
  "$image" \
  --no-blob-protection --delete-files credential.json repo.git

git --git-dir="$workspace/repo.git" fsck --full --no-dangling

deleted_file_commits="$(
  git --git-dir="$workspace/repo.git" \
    log --all --format=%H -- credential.json
)"
if [[ -n "$deleted_file_commits" ]]; then
  echo "credential.json remains in reachable history" >&2
  exit 1
fi

kept_content="$(
  git --git-dir="$workspace/repo.git" \
    show refs/heads/main:keep.txt
)"
if [[ "$kept_content" != "keep me" ]]; then
  echo "unrelated file content changed during the rewrite" >&2
  exit 1
fi

while IFS= read -r ref; do
  if git --git-dir="$workspace/repo.git" grep -F "super-secret" "$ref"; then
    echo "secret content remains reachable from $ref" >&2
    exit 1
  fi
done < <(
  git --git-dir="$workspace/repo.git" \
    for-each-ref --format='%(refname)' refs/heads refs/tags
)
