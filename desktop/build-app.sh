#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_root="$project_root/dist/desktop"
app="$output_root/DeepSeek Harness.app"
contents="$app/Contents"
resources="$contents/Resources"
runtime="$resources/runtime"

rm -rf "$output_root"
mkdir -p "$contents/MacOS" "$resources"

cd "$project_root"
pnpm run build
pnpm --ignore-scripts --config.inject-workspace-packages=true --filter dsh-jsonrpc-agent-pkg deploy --prod "$runtime"

swiftc \
  -parse-as-library \
  -O \
  -framework Cocoa \
  -framework WebKit \
  "$project_root/desktop/DeepSeekHarnessApp.swift" \
  -o "$contents/MacOS/DeepSeekHarness"

cp "$project_root/desktop/Info.plist" "$contents/Info.plist"
cp "$(command -v node)" "$resources/node"
strip -x "$resources/node"
gzip -9 "$resources/node"
chmod 755 "$contents/MacOS/DeepSeekHarness"

find "$runtime" -type d \( -name test -o -name tests -o -name docs \) -prune -exec rm -rf {} +
find "$runtime" -type f \( -name '*.map' -o -name '*.md' -o -name '*.i18n.yaml' -o -name '*.ts' \) -delete

node_pty=$(find "$runtime/node_modules/.pnpm" -maxdepth 1 -type d -name 'node-pty@*' -print -quit)
if [ -n "$node_pty" ]; then
  rm -rf \
    "$node_pty/node_modules/node-pty/prebuilds/darwin-x64" \
    "$node_pty/node_modules/node-pty/prebuilds/win32-arm64" \
    "$node_pty/node_modules/node-pty/prebuilds/win32-x64" \
    "$node_pty/node_modules/node-pty/src"
  find "$node_pty" -type f -name '*.pdb' -delete
  chmod 755 "$node_pty/node_modules/node-pty/prebuilds/darwin-arm64/spawn-helper"
fi

# These libraries are already bundled into the static browser assets and are
# never imported by the Node host. Keep their package directories so pnpm's
# internal links remain valid while removing the duplicate browser payload.
find "$runtime/node_modules/.pnpm" -maxdepth 1 -type d \
  \( -name '@shikijs+langs@*' -o -name '@shikijs+themes@*' -o -name 'shiki@*' -o -name 'katex@*' \) \
  -exec sh -c 'find "$1" -type f ! -name package.json -delete' _ {} \;

codesign --force --deep --sign - "$app"

size_kib=$(du -sk "$app" | awk '{print $1}')
max_kib=$((200 * 1024))
if [ "$size_kib" -gt "$max_kib" ]; then
  echo "Desktop bundle is over 200 MiB: $((size_kib / 1024)) MiB" >&2
  exit 1
fi
echo "Built $app ($((size_kib / 1024)) MiB)"
