#!/bin/bash
# Publishes a release: pins the plugin version and checksum in install.sh, runs the smoke
# test, commits, tags, pushes and creates the GitHub release with both files as assets.
#
# Usage: scripts/release.sh vX.Y.Z

set -euo pipefail
cd "$(dirname "$0")/.."

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

version=${1:-}
[[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/release.sh vX.Y.Z"
[ "$(git branch --show-current)" = main ] || die "release from main"
[ -z "$(git status --porcelain)" ] || die "working tree is not clean"
git rev-parse -q --verify "refs/tags/$version" >/dev/null && die "tag $version already exists"

sed -i '' -E "s|^# <xbar.version>.*</xbar.version>$|# <xbar.version>$version</xbar.version>|" usdbrl.1m.sh
sum=$(shasum -a 256 usdbrl.1m.sh | awk '{ print $1 }')
sed -i '' -E \
  -e "s|^readonly VERSION=.*|readonly VERSION='$version'|" \
  -e "s|^readonly PLUGIN_SHA256=.*|readonly PLUGIN_SHA256='$sum'|" install.sh

bash -n install.sh
bash test/smoke.sh

git commit -q -am "Release $version"
git tag -a "$version" -m "$version"
git push -q origin main "$version"
gh release create "$version" install.sh usdbrl.1m.sh --title "$version" --notes "$(
  cat <<EOF
Install or update:

\`\`\`bash
curl -fsSLO https://github.com/fascari/swiftbar-usdbrl/releases/download/$version/install.sh
bash install.sh
\`\`\`

Plugin SHA-256: \`$sum\`
EOF
)"
