# SPDX-FileCopyrightText: 2026 Mercury Technologies, Inc.
#
# SPDX-License-Identifier: MIT OR Apache-2.0

# template for GHCi

set -eo pipefail

DIR=$(dirname "$0")

# binutils_path: <binutils_path>
# ghci_lib_path: <ghci_lib_path>
# cc_path: <cc_path>
# cpp_path: <cpp_path>
# cxx_path: <cxx_path>
# ghci_packager: <ghci_packager>
# ghci_ghc_path: <ghci_ghc_path>

# Add plugin tools to PATH if present
PLUGIN_TOOLS_DIR="$DIR/<name>.plugin-tools"
if [ -d "$PLUGIN_TOOLS_DIR" ]; then
  export PATH="$PLUGIN_TOOLS_DIR:$PATH"
fi

# Ensure a valid TMPDIR for GHC compilation (e.g., when loading sources in GHCi).
# nix-shell may set TMPDIR to a session-specific directory that doesn't
# exist when the script is executed by another process (e.g., buck2 test).
if [ -n "$TMPDIR" ] && [ ! -d "$TMPDIR" ]; then
  export TMPDIR=/tmp
fi

exec <user_ghci_path> <package_dbs> <compiler_flags> -ghci-script "$DIR/<start_ghci>" "$DIR/<squashed_so>" "$@"
