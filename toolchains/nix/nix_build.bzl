# SPDX-FileCopyrightText: 2026 Mercury Technologies, Inc.
#
# SPDX-License-Identifier: MIT OR Apache-2.0

"""
Run a `nix build` command for a given `flake` and `attr` to build.
"""

def _make_bin_wrapper(ctx: AnalysisContext, nix_path_out: Artifact, binary: str) -> (Artifact, RunInfo):
    """Create an executable wrapper script that reads nix_path_out and execs the binary.

    Returns both the wrapper script artifact and a RunInfo that declares nix_path_out
    as a hidden dependency so buck2 materializes it before any action that uses this tool.
    """
    wrapper = ctx.actions.write(
        "wrapper_{}".format(binary),
        cmd_args(
            "#!/usr/bin/env bash\nexec \"$(cat '",
            nix_path_out,
            "')/bin/",
            binary,
            "\" \"$@\"\n",
            delimiter = "",
        ),
        is_executable = True,
    )
    # The hidden dependency ensures nix_path_out is materialized before any action
    # that uses this RunInfo as its executor.
    run_info = RunInfo(args = cmd_args(wrapper, hidden = [nix_path_out]))
    return wrapper, run_info

def _nix_build_impl(ctx: AnalysisContext):
    """
    calls nix build path:<flake-path>#<attr>

    Produces a text file `nix_path` containing the nix store path of the built
    derivation (e.g. `/nix/store/abc-ghc-9.4.8`). This is a regular file and
    can be uploaded to the remote action cache, unlike a symlink.
    """
    flake = ctx.attrs.flake
    attr = ctx.attrs.attr or ctx.label.name
    binary = ctx.attrs.binary
    binaries = ctx.attrs.binaries

    attr_suffix = attr
    if ctx.attrs.suffix:
        attr_suffix = cmd_args(attr, ctx.attrs.suffix, delimiter = "^")

    # Declare a text file output containing the nix store path.
    nix_path_out = ctx.actions.declare_output("nix_path")

    nix_build = cmd_args([
        "env",
        "--",  # this is needed to avoid "Spawning executable `nix` failed: Failed to spawn a process"
        "bash",
        "-o", "pipefail",
        "-ec",
        # Build the nix package (without creating a GC-root symlink), then
        # capture the output path into the declared output text file.
        "nix build --no-link --print-out-paths --print-build-logs --show-trace --no-update-lock-file --no-use-registries \"$1\" | head -1 | tr -d '\\n' > \"$2\"",
        "--",
        cmd_args(cmd_args(flake, attr_suffix, delimiter = "#"), absolute_prefix = "path:"),
        nix_path_out.as_output(),
    ])
    ctx.actions.run(nix_build, category = "nix_build", prefer_local = True, allow_cache_upload = True)

    run_info = []
    if binary:
        wrapper, wrapper_run_info = _make_bin_wrapper(ctx, nix_path_out, binary)
        run_info.append(wrapper_run_info)

    nix_dynamic_info = NixDynamicInfo(
        dynamic = _read_nix_path(ctx, nix_path_out),
    )

    sub_targets = {}
    for bin in binaries:
        bin_wrapper, bin_run_info = _make_bin_wrapper(ctx, nix_path_out, bin)
        sub_targets[bin] = [DefaultInfo(default_output = bin_wrapper), bin_run_info]

    return [
        DefaultInfo(
            default_output = nix_path_out,
            sub_targets = sub_targets,
        ),
        BinDirInfo(
            args = cmd_args(nix_path_out),
        ),
        # absolute nix path information will be recorded here. It is a dynamic value.
        nix_dynamic_info,
    ] + run_info

nix_build = rule(
    impl = _nix_build_impl,
    doc = """
        Run a `nix build` command for a given `flake` and `attr` to build.
    """,
    attrs = {
        "binary": attrs.option(attrs.string(), default = None),
        "binaries": attrs.list(attrs.string(), default = []),
        "deps": attrs.list(attrs.dep(), default = []),
        "flake": attrs.source(allow_directory = True),
        "attr": attrs.option(attrs.string(), doc = "name of the flake attribute, defaults to label name", default = None),
        "suffix": attrs.option(attrs.string(), default = None, doc = "out-link suffix, e.g. `lib`, used to provide a non-default output"),
    },
)

def _read_out_link_dynamic_impl(
        # starlark-lint-disable unused-argument
        actions: AnalysisActions,  # @unused
        read_link):
    nix_path = read_link.read_string()
    return [NixPathInfo(path = nix_path)]

_read_out_link_dynamic = dynamic_actions(
    impl = _read_out_link_dynamic_impl,
    attrs = {
        "read_link": dynattrs.artifact_value(),
    },
)

# FIXME(jadel): this is duplicate logic as in haskell/mercury_haskell.bzl. Needs to be DRY'd up eventually.
def _read_nix_path(ctx: AnalysisContext, nix_path_out: Artifact) -> DynamicValue:
    """Read the nix store path from the nix_path text file artifact."""
    return ctx.actions.dynamic_output_new(_read_out_link_dynamic(
        read_link = nix_path_out,
    ))

BinDirInfo = provider(
    doc = """Provides the path of the `/bin` directory of a derivation output.""",
    fields = {
        "args": provider_field(cmd_args),
    },
)

# FIXME(jadel): Unify with a dynamic for `NixDynamicDepsTset`.
NixDynamicInfo = provider(
    doc = """Provides nix-side dynamic information. Contains a NixPathInfo provider.""",
    fields = {
        "dynamic": DynamicValue,
    },
)

NixDynamicDepsTset = provider(
    doc = """Provides nix-side dynamic information. Contains a NixDepsTsetProvider provider.""",
    fields = {
        "dynamic": DynamicValue,
    },
)

NixPathInfo = provider(
    doc = """Provides the absolute /nix/store path.""",
    fields = {
        "path": str,
    },
)

# All of the output paths for a derivation.
NixDerivationInfo = record(
    derivation = NixPathInfo,
    outputs = dict[str, NixPathInfo],
)

def _project_path(path: NixDerivationInfo) -> list[str]:
    return [out.path for out in path.outputs.values()]

# All Nix output paths referenced by this target including transitively.
# Contains elements of type NixDerivationInfo.
# Does not keep track of outputs separately (FIXME?) and we just ref-scan for *all* output paths and prune afterwards.
NixDepsTset = transitive_set(json_projections = {"all_output_paths": _project_path})

NixDepsTsetProvider = provider(
    doc = """Provides a NixDepsTset.""",
    fields = {
        "deps": NixDepsTset,
    },
)

# One Nix package, effectively; with *buck2-level* Nix dependency info.
# The dependencies are not a comprehensive list of all of the dependencies at a
# Nix level and these will likely mirror the Nix level dependency structure to
# a degree.
# The Nix-level transitive closure of NixDepsTset here should include all possible Nix
# deps of the final target.
#
# The dependencies should include the package itself; this is only a packaging
# of the two parts together for convenience.
NixDependency = record(
    package = NixDerivationInfo,
    deps = NixDepsTset,
)
