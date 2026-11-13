#!/usr/bin/env bash
# Compatible with the Bash 3.2 shipped by macOS. shard.yml is the source of truth.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
output=${1:?Usage: build-binaries.sh OUTPUT_DIRECTORY}
mkdir -p "$output"
output=$(cd "$output" && pwd)
manifest_dir=$(mktemp -d "${TMPDIR:-/tmp}/crystalcog-release.XXXXXX")
trap 'rm -rf "$manifest_dir"' EXIT

crystal eval 'require "yaml"; YAML.parse(File.read("shard.yml"))["targets"].as_h.each_key { |name| puts name.as_s }' > "$manifest_dir/targets"
[ -s "$manifest_dir/targets" ] || { echo "No release targets in shard.yml" >&2; exit 1; }
mkdir -p bin
while IFS= read -r target; do
  case "$target" in
    ''|*[!a-zA-Z0-9_-]*) echo "Invalid target name: $target" >&2; exit 1 ;;
  esac
  # A stale binary must not make an incomplete build look successful.
  rm -f "bin/$target" "$output/$target"
done < "$manifest_dir/targets"

if [ "${RELEASE_BUILD_STATIC:-false}" = true ]; then
  shards build --frozen --release --no-debug --static --error-trace
else
  shards build --frozen --release --no-debug --error-trace
fi

while IFS= read -r target; do
  [ -x "bin/$target" ] || { echo "Missing executable for declared target: $target" >&2; exit 1; }
  cp "bin/$target" "$output/$target"
done < "$manifest_dir/targets"

{
  crystal --version
  printf '\nBuild machine: %s\nStatic requested: %s\n\nDeclared targets:\n' "$(uname -m)" "${RELEASE_BUILD_STATIC:-false}"
  cat "$manifest_dir/targets"
} > "$output/BUILD-MANIFEST.txt"

# Check the actual architecture before an archive can be mislabeled/published.
architecture=$(file "$output/crystalcog")
case "$(uname -m):$architecture" in
  x86_64:*x86-64*|x86_64:*x86_64*|aarch64:*aarch64*|arm64:*arm64*) ;;
  *) echo "Unexpected release binary architecture: $architecture" >&2; exit 1 ;;
esac
"$output/crystalcog" --version
printf 'Packaged %s declared executables in %s\n' "$(wc -l < "$manifest_dir/targets" | tr -d ' ')" "$output"
