# SPDX-FileCopyrightText: 2026 Mercury Technologies, Inc.
#
# SPDX-License-Identifier: MIT OR Apache-2.0

"""
Build rule for the GHC persistent worker binaries.

Picks pre-built binaries from ghc-persistent-worker/dist-newstyle to
decouple the worker's build system (cabal) from the buck2 build graph.
The user is responsible for building ghc-persistent-worker separately
(e.g., via `cabal build -fmwb` in a nix-shell).
"""

def _worker_binary_impl(ctx: AnalysisContext) -> list[Provider]:
    out = ctx.actions.declare_output(ctx.attrs.binary_name)

    # Copy the pre-built binary from dist-newstyle.
    # local_only because dist-newstyle is in [project] ignore and can't be
    # tracked by buck2's file watcher.
    copy_cmd = cmd_args(
        "bash", "-ec",
        """
        set -euo pipefail
        BINARY_NAME="$1"
        OUT="$2"
        SRC_SUBDIR="$3"

        PROJECT_ROOT="$(git rev-parse --show-toplevel)"
        SRC_DIR="$PROJECT_ROOT/$SRC_SUBDIR"

        # Find the pre-built binary in dist-newstyle
        BINARY=$(find "$SRC_DIR/dist-newstyle" -name "$BINARY_NAME" -type f -executable | grep "/build/$BINARY_NAME/$BINARY_NAME$" | head -1)
        if [ -z "$BINARY" ]; then
            echo "ERROR: Could not find pre-built binary $BINARY_NAME in $SRC_DIR/dist-newstyle" >&2
            echo "Please build ghc-persistent-worker first: nix-shell nix-shells/ghc-persistent-worker.nix --run 'cd ghc-persistent-worker && cabal build -fmwb'" >&2
            exit 1
        fi
        cp "$BINARY" "$OUT"
        chmod +x "$OUT"
        """,
        "--",
        ctx.attrs.binary_name,
        out.as_output(),
        ctx.attrs.src_subdir,
    )

    ctx.actions.run(copy_cmd, category = "copy_worker_binary", identifier = ctx.attrs.binary_name, local_only = True)

    return [
        DefaultInfo(default_output = out),
        RunInfo(args = cmd_args(out)),
    ]

worker_binary = rule(
    impl = _worker_binary_impl,
    attrs = {
        "binary_name": attrs.string(),
        "src_subdir": attrs.string(doc = "Path to source directory relative to project root"),
    },
)
