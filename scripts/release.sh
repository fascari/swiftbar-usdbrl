#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

build() (
  local source=$1 output=$2 arch=$3
  cd "$source"
  GOOS=darwin GOARCH="$arch" GOARM64=v8.0 GOAMD64=v1 CGO_ENABLED=0 \
    GOTOOLCHAIN=local GOWORK=off GOFLAGS='' go build -trimpath -buildvcs=false \
    -ldflags "-s -w -X main.version=$version" -o "$output" ./cmd
)

checksum() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

version=${1:-}
[[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/release.sh vX.Y.Z"
[ "$(git branch --show-current)" = main ] || die "release from main"
[ -z "$(git status --porcelain)" ] || die "working tree is not clean"
git rev-parse -q --verify "refs/tags/$version" >/dev/null && die "tag $version already exists"
toolchain=$(sed -n 's/^toolchain //p' go.mod)
[ "$(go env GOVERSION)" = "$toolchain" ] || die "build with $toolchain via mise"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/source"
git archive HEAD | tar -xf - -C "$work/source"
build_id=$(date -u +%Y%m%d.%H%M%S)
for arch in arm64 amd64; do
  binary="$work/usdbrl-darwin-$arch"
  build "$PWD" "$binary" "$arch"
  build "$work/source" "$work/rebuilt-$arch" "$arch"
  cmp -s "$binary" "$work/rebuilt-$arch" || die "clean rebuild differs for $arch"

  cpu=$arch
  [ "$arch" != amd64 ] || cpu=x86_64
  [ "$(file -b "$binary")" = "Mach-O 64-bit executable $cpu" ] ||
    die "unexpected binary format for $arch"
done

if [ "$(uname -m)" = arm64 ]; then
  [ "$("$work/usdbrl-darwin-arm64" --version)" = "$version" ] || die "arm64 version mismatch"
fi
if arch -x86_64 /usr/bin/true 2>/dev/null; then
  [ "$(arch -x86_64 "$work/usdbrl-darwin-amd64" --version)" = "$version" ] || die "amd64 version mismatch"
fi

arm_sum=$(checksum "$work/usdbrl-darwin-arm64")
amd_sum=$(checksum "$work/usdbrl-darwin-amd64")
bash scripts/build-converter.sh "$work/Converter.app" arm64
/usr/bin/ditto -c -k --keepParent "$work/Converter.app" "$work/converter.zip"
converter_sum=$(checksum "$work/converter.zip")
sed -E \
  -e "s|^readonly VERSION=.*|readonly VERSION='$version'|" \
  -e "s|^readonly PLUGIN_BUILD=.*|readonly PLUGIN_BUILD='$build_id'|" \
  -e "s|^readonly PLUGIN_SHA256_ARM64=.*|readonly PLUGIN_SHA256_ARM64='$arm_sum'|" \
  -e "s|^readonly PLUGIN_SHA256_AMD64=.*|readonly PLUGIN_SHA256_AMD64='$amd_sum'|" \
  -e "s|^readonly CONVERTER_SHA256=.*|readonly CONVERTER_SHA256='$converter_sum'|" install.sh > "$work/install.sh"
sed -i '' "s|^readonly RELEASE_ARCH=.*|readonly RELEASE_ARCH='arm64'|" "$work/install.sh"

mise run lint
mise run test
bash scripts/parity.sh
bash test/installer.sh "$work"

cat "$work/install.sh" > install.sh
git commit -q -m "Release $version" -- install.sh
git tag -a "$version" -m "$version"
git push -q origin main "$version"
gh release create "$version" install.sh "$work/usdbrl-darwin-arm64" "$work/converter.zip" --title "$version" --notes "$(
  cat <<EOF
Install or update:

\`\`\`bash
curl -fsSLO https://github.com/fascari/swiftbar-usdbrl/releases/download/$version/install.sh
bash install.sh
\`\`\`

This release supports Apple Silicon only. Intel support will be revisited.

Plugin SHA-256:

- Apple Silicon: \`$arm_sum\`
- Conversor: \`$converter_sum\`
EOF
)"
