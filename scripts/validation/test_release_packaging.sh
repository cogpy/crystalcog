#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/project/scripts/release" "$tmp/fake-bin" "$tmp/project/bin"
cp "$root/scripts/release/build-binaries.sh" "$tmp/project/scripts/release/"
printf 'targets: {}\n' > "$tmp/project/shard.yml"
cat > "$tmp/fake-bin/crystal" <<'SH'
#!/usr/bin/env bash
set -eu
if [ "$1" = eval ]; then printf 'crystalcog\ncogserver\n'; else printf 'Crystal fixture\n'; fi
SH
cat > "$tmp/fake-bin/shards" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" > invoked-flags
if [ "${FIXTURE_FAIL:-0}" = 1 ]; then exit 42; fi
for target in crystalcog cogserver; do
  if [ "$target" = cogserver ] && [ "${FIXTURE_OMIT:-0}" = 1 ]; then continue; fi
  printf '#!/bin/sh\nprintf "fixture version\\n"\n' > "bin/$target"
  chmod +x "bin/$target"
done
SH
cat > "$tmp/fake-bin/file" <<'SH'
#!/usr/bin/env bash
if [ "${FIXTURE_ARCH_FAIL:-0}" = 1 ]; then echo 'ELF wrong-architecture'; else echo 'ELF 64-bit x86-64'; fi
SH
cat > "$tmp/fake-bin/uname" <<'SH'
#!/usr/bin/env bash
echo x86_64
SH
chmod +x "$tmp/fake-bin/"*
export PATH="$tmp/fake-bin:$PATH"
script="$tmp/project/scripts/release/build-binaries.sh"

bash "$script" dist/success > "$tmp/success.log"
[ -x "$tmp/project/dist/success/crystalcog" ]
[ -x "$tmp/project/dist/success/cogserver" ]
grep -q -- '--frozen --release --no-debug --error-trace' "$tmp/project/invoked-flags"
[ -s "$tmp/project/dist/success/BUILD-MANIFEST.txt" ]

if FIXTURE_FAIL=1 bash "$script" dist/failure > "$tmp/failure.log" 2>&1; then
  echo 'Packager hid the build failure' >&2; exit 1
fi
# A previous binary exists, but the next incomplete build must not use it.
printf '#!/bin/sh\n' > "$tmp/project/bin/cogserver"
chmod +x "$tmp/project/bin/cogserver"
if FIXTURE_OMIT=1 bash "$script" dist/missing > "$tmp/missing.log" 2>&1; then
  echo 'Packager accepted incomplete/stale output' >&2; exit 1
fi
grep -q 'Missing executable.*cogserver' "$tmp/missing.log"

if FIXTURE_ARCH_FAIL=1 bash "$script" dist/wrong-arch > "$tmp/arch.log" 2>&1; then
  echo 'Packager accepted the wrong architecture' >&2; exit 1
fi
grep -q 'Unexpected release binary architecture' "$tmp/arch.log"

RELEASE_BUILD_STATIC=true bash "$script" dist/static > "$tmp/static.log"
grep -q -- '--static' "$tmp/project/invoked-flags"
echo 'Release packaging: 5 deterministic cases passed'
