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

fail() {
  echo "FAIL: $*" >&2
  return 1
}

setup_case() {
  local name="$1"

  case_dir="$workspace/$name"
  source_repo="$case_dir/source"
  mirror_repo="$case_dir/repo.git"

  mkdir -p "$case_dir"
  git init --quiet --initial-branch=main "$source_repo"
  git -C "$source_repo" config user.name "CI"
  git -C "$source_repo" config user.email "ci@example.invalid"
  git -C "$source_repo" config commit.gpgsign false
}

commit_fixture() {
  local message="$1"

  git -C "$source_repo" add -A
  git -C "$source_repo" commit --quiet -m "$message"
}

mirror_fixture() {
  git clone --quiet --mirror "$source_repo" "$mirror_repo"

  # GitHub-hosted runners and the image use different UIDs. Make the fixture
  # writable so the image's non-root user can rewrite the mounted repository.
  chmod -R a+rwX "$case_dir"
}

run_bfg() {
  docker run --rm \
    --volume "$case_dir:/home/bfg/workspace" \
    "$image" \
    "$@" repo.git
}

assert_repo_valid() {
  git --git-dir="$mirror_repo" fsck --full --no-dangling
}

assert_ref_content() {
  local ref="$1"
  local path="$2"
  local expected="$3"
  local actual

  actual="$(git --git-dir="$mirror_repo" show "$ref:$path")"
  [[ "$actual" == "$expected" ]] ||
    fail "$ref:$path contained '$actual', expected '$expected'"
}

assert_ref_missing() {
  local ref="$1"
  local path="$2"

  if git --git-dir="$mirror_repo" cat-file -e "$ref:$path" 2>/dev/null; then
    fail "$path remains reachable from $ref"
  fi
}

assert_no_path_history() {
  local path="$1"
  local commits

  commits="$(
    git --git-dir="$mirror_repo" \
      log --all --format=%H -- "$path"
  )"
  [[ -z "$commits" ]] || fail "$path remains in reachable history"
}

assert_no_reachable_text() {
  local text="$1"
  local ref

  while IFS= read -r ref; do
    if git --git-dir="$mirror_repo" grep -F "$text" "$ref"; then
      fail "'$text' remains reachable from $ref"
    fi
  done < <(
    git --git-dir="$mirror_repo" \
      for-each-ref --format='%(refname)' refs/heads refs/tags
  )
}

test_image_contract() {
  local usage
  local uid

  echo "==> image contract"

  usage="$(docker run --rm "$image" 2>&1)"
  grep -F "bfg " <<<"$usage"
  grep -F -- "--delete-files" <<<"$usage"

  uid="$(docker run --rm --entrypoint sh "$image" -c 'id -u')"
  ((uid != 0)) || fail "expected the image to run as a non-root user"

  docker run --rm --entrypoint sh "$image" -c '
    test "$HOME" = /home/bfg
    test "$PWD" = /home/bfg/workspace
    test -r /home/bfg/bfg.jar
  '
}

test_safe_rewrite() {
  local head_before
  local head_after
  local tree_before
  local tree_after

  echo "==> protected rewrite of historical content"
  setup_case "safe-rewrite"

  printf '%s\n' "super-secret" >"$source_repo/credential.json"
  printf '%s\n' "keep me" >"$source_repo/keep.txt"
  commit_fixture "Add historical credential"

  git -C "$source_repo" rm --quiet credential.json
  commit_fixture "Remove credential from current revision"
  mirror_fixture

  head_before="$(git --git-dir="$mirror_repo" rev-parse refs/heads/main)"
  tree_before="$(git --git-dir="$mirror_repo" rev-parse 'refs/heads/main^{tree}')"

  run_bfg --delete-files credential.json

  head_after="$(git --git-dir="$mirror_repo" rev-parse refs/heads/main)"
  tree_after="$(git --git-dir="$mirror_repo" rev-parse 'refs/heads/main^{tree}')"

  [[ "$head_before" != "$head_after" ]] ||
    fail "safe rewrite did not update history"
  [[ "$tree_before" == "$tree_after" ]] ||
    fail "safe rewrite changed the protected current tree"
  assert_ref_missing refs/heads/main credential.json
  assert_ref_content refs/heads/main keep.txt "keep me"
  assert_no_path_history credential.json
  assert_no_reachable_text "super-secret"
  assert_repo_valid
}

test_protected_head() {
  local head_before
  local head_after

  echo "==> current content remains protected by default"
  setup_case "protected-head"

  printf '%s\n' "super-secret" >"$source_repo/credential.json"
  printf '%s\n' "keep me" >"$source_repo/keep.txt"
  commit_fixture "Add current credential"
  mirror_fixture

  head_before="$(git --git-dir="$mirror_repo" rev-parse refs/heads/main)"

  run_bfg --delete-files credential.json

  head_after="$(git --git-dir="$mirror_repo" rev-parse refs/heads/main)"

  [[ "$head_before" == "$head_after" ]] ||
    fail "default protection unexpectedly changed the current commit"
  assert_ref_content refs/heads/main credential.json "super-secret"
  assert_ref_content refs/heads/main keep.txt "keep me"
  assert_repo_valid
}

test_unprotected_rewrite() {
  local head_before
  local head_after

  echo "==> unprotected rewrite of current content"
  setup_case "unprotected-rewrite"

  printf '%s\n' "super-secret" >"$source_repo/credential.json"
  printf '%s\n' "keep me" >"$source_repo/keep.txt"
  commit_fixture "Add current credential"
  mirror_fixture

  head_before="$(git --git-dir="$mirror_repo" rev-parse refs/heads/main)"

  run_bfg --no-blob-protection --delete-files credential.json

  head_after="$(git --git-dir="$mirror_repo" rev-parse refs/heads/main)"

  [[ "$head_before" != "$head_after" ]] ||
    fail "unprotected rewrite did not update the current commit"
  assert_ref_missing refs/heads/main credential.json
  assert_ref_content refs/heads/main keep.txt "keep me"
  assert_no_path_history credential.json
  assert_no_reachable_text "super-secret"
  assert_repo_valid
}

test_replace_text() {
  echo "==> replace sensitive text"
  setup_case "replace-text"

  printf '%s\n' \
    "password=super-secret" \
    "mode=production" \
    >"$source_repo/application.conf"
  printf '%s\n' "keep me" >"$source_repo/keep.txt"
  printf '%s\n' "super-secret" >"$case_dir/replacements.txt"
  commit_fixture "Add configuration containing a secret"
  mirror_fixture

  run_bfg \
    --no-blob-protection \
    --replace-text replacements.txt

  assert_ref_content \
    refs/heads/main \
    application.conf \
    $'password=***REMOVED***\nmode=production'
  assert_ref_content refs/heads/main keep.txt "keep me"
  assert_no_reachable_text "super-secret"
  assert_repo_valid
}

test_strip_large_blobs() {
  echo "==> strip blobs above a size threshold"
  setup_case "strip-large-blobs"

  awk 'BEGIN { for (i = 0; i < 2048; i++) printf "x" }' \
    >"$source_repo/large.bin"
  printf '%s\n' "small file" >"$source_repo/small.txt"
  commit_fixture "Add large and small files"
  mirror_fixture
  git --git-dir="$mirror_repo" repack -ad

  run_bfg \
    --no-blob-protection \
    --strip-blobs-bigger-than 1K

  assert_ref_missing refs/heads/main large.bin
  assert_ref_content refs/heads/main small.txt "small file"
  assert_no_path_history large.bin
  assert_repo_valid
}

test_glob_delete_across_refs() {
  local ref

  echo "==> delete matching files and folders across refs"
  setup_case "glob-delete"

  mkdir -p \
    "$source_repo/cache" \
    "$source_repo/nested/cache"
  printf '%s\n' "discard-root" >"$source_repo/root.log"
  printf '%s\n' "discard-cache" >"$source_repo/cache/generated.tmp"
  printf '%s\n' "discard-nested" >"$source_repo/nested/debug.log"
  printf '%s\n' "discard-deep-cache" >"$source_repo/nested/cache/data.tmp"
  printf '%s\n' "keep me" >"$source_repo/keep.txt"
  commit_fixture "Add files on main"

  git -C "$source_repo" tag before-feature
  git -C "$source_repo" checkout --quiet -b feature
  printf '%s\n' "discard-feature" >"$source_repo/feature.log"
  printf '%s\n' "feature content" >"$source_repo/feature.txt"
  commit_fixture "Add files on feature"
  git -C "$source_repo" checkout --quiet main
  mirror_fixture

  run_bfg \
    --no-blob-protection \
    --delete-files '*.log' \
    --delete-folders cache

  for ref in \
    refs/heads/main \
    refs/heads/feature \
    refs/tags/before-feature; do
    assert_ref_missing "$ref" root.log
    assert_ref_missing "$ref" cache/generated.tmp
    assert_ref_missing "$ref" nested/debug.log
    assert_ref_missing "$ref" nested/cache/data.tmp
    assert_ref_content "$ref" keep.txt "keep me"
  done

  assert_ref_missing refs/heads/feature feature.log
  assert_ref_content refs/heads/feature feature.txt "feature content"
  assert_no_path_history root.log
  assert_no_path_history cache/generated.tmp
  assert_no_path_history nested/debug.log
  assert_no_path_history nested/cache/data.tmp
  assert_no_path_history feature.log
  assert_no_reachable_text "discard-"
  assert_repo_valid
}

test_image_contract
test_safe_rewrite
test_protected_head
test_unprotected_rewrite
test_replace_text
test_strip_large_blobs
test_glob_delete_across_refs
