#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 Mercury Technologies, Inc.
#
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Wrapper script to call nix"""

import argparse
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, add_help=False, fromfile_prefix_chars="@"
    )
    parser.add_argument(
        "--buck2-output",
        required=True,
        help="Output path file (text file that will contain the nix store path)",
    )
    parser.add_argument(
        "--nix-output-path",
        required=False,
        help="Known nix output path to write to the output file (bypasses --print-out-paths)",
    )

    args, nix_args = parser.parse_known_args()
    cmd = [
        "nix",
        *nix_args,
        "--print-build-logs",
        "--show-trace",
        # --no-update-lock-file: if the flake.lock file does not match the flake.nix, error out.
        # This prevents highly baffling behaviour that should be done by the user rather than by buck2.
        "--no-update-lock-file",
        # Don't use flake registries if someone omits something from `inputs.*` but puts it in `outputs` args.
        "--no-use-registries",
        # Build without creating a GC-root symlink; the output path is either
        # passed via --nix-output-path or captured from --print-out-paths.
        "--no-link",
    ]

    if args.nix_output_path is None:
        cmd.append("--print-out-paths")

    # NOTE 1: We time-out nix build.
    # We assume nix dependencies are all already previously populated
    # in the cache in update cache CI.
    # If we can detect the nix cache-miss more directly from the Nix CLI
    # interface, that would be better though the timeout test is
    # practically useful.

    # disabled for now until nix cache problem solved.
    # timeout_seconds = 30

    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=sys.stderr.buffer,  # timeout=timeout_seconds # TODO: disabled for now until nix cache problem solved
    )

    if result.returncode != 0:
        return result.returncode

    if args.nix_output_path is not None:
        nix_path = args.nix_output_path.encode()
    else:
        # Take the first output path printed (the 'out' output).
        nix_path = result.stdout.split(b"\n")[0].strip()

    with open(args.buck2_output, "wb") as f:
        f.write(nix_path)

    return 0


if __name__ == "__main__":
    main()
