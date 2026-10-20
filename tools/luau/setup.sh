#!/usr/bin/env bash
# Rebuild the Luau toolchain from the tarball committed in this branch.
#
#   bash tools/luau/setup.sh
#
# The sandbox (and any fresh clone) has no Luau binary, no node_modules and no
# guarantee that npm is reachable. The pinned package is 2.7 MB, so it lives in
# vendor/ and this script only has to unpack it. Idempotent: it exits 0 when
# the toolchain is already usable.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

VERSION="0.739.0"
TARBALL="vendor/luau-rs-luau-${VERSION}.tgz"
MODULE_DIR="node_modules/@luau-rs/luau"
BIN_DIR="bin"

if [ ! -f "$TARBALL" ]; then
    echo "missing $TARBALL: the vendored package was not committed" >&2
    exit 1
fi
command -v node >/dev/null 2>&1 || {
    echo "node is required to run the wasm Luau toolchain" >&2
    exit 1
}

if [ ! -f "$MODULE_DIR/package.json" ]; then
    mkdir -p "$MODULE_DIR"
    # --strip-components=1 removes the leading "package/" directory.
    tar -xzf "$TARBALL" -C "$MODULE_DIR" --strip-components=1
fi

mkdir -p "$BIN_DIR"
cat >"$BIN_DIR/luau" <<'EOF'
#!/usr/bin/env bash
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/run.mjs" "$@"
EOF
cat >"$BIN_DIR/luau-compile" <<'EOF'
#!/usr/bin/env bash
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/compile.mjs" "$@"
EOF
chmod +x "$BIN_DIR/luau" "$BIN_DIR/luau-compile"

"$BIN_DIR/luau" --version >/dev/null 2>&1 || true
echo "Luau toolchain ready: $BIN_DIR/luau ($VERSION)"
