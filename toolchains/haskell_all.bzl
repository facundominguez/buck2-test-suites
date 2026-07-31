# SPDX-FileCopyrightText: 2026 Mercury Technologies, Inc.
#
# SPDX-License-Identifier: MIT OR Apache-2.0
"""
Functionality on "all" Haskell toolchain packages: building them all
"""

load(
    "@buck2-haskell//:toolchain.bzl",
    "DynamicHaskellToolchainPackageDbInfo",
    "HaskellToolchainInfo",
)
load("@toolchains//nix:nix_haskell_toolchain.bzl", "DynamicHaskellNixInfo")
load("@toolchains//nix:nix_upload.bzl", "upload_to_cache")

# FIXME(jadel): this is duplicate logic as in toolchains/nix_build.bzl. Needs to be DRY'd up eventually.
def _record_nix_path_dynamic_impl(actions, arg, pkg_deps, list_of_packages):
    package_db = pkg_deps.providers[DynamicHaskellToolchainPackageDbInfo].toolchain_packages

    cmd = cmd_args(arg.record_nix_path, "--output", list_of_packages)
    ks = package_db.keys()
    for k in ks:
        out_link = package_db[k].value.path
        cmd.add("--input", out_link)

    actions.run(cmd, category = "all_nix_packages")
    return []

_record_nix_path_dynamic = dynamic_actions(
    impl = _record_nix_path_dynamic_impl,
    attrs = {
        "arg": dynattrs.value(typing.Any),
        "pkg_deps": dynattrs.dynamic_value(),
        "list_of_packages": dynattrs.output(),
    },
)

def _haskell_toolchain_all_impl(ctx: AnalysisContext) -> list[Provider]:
    haskell_toolchain = ctx.attrs.toolchain[HaskellToolchainInfo]
    list_of_packages = ctx.actions.declare_output("all_haskell_nix_paths.txt")

    ctx.actions.dynamic_output_new(_record_nix_path_dynamic(
        arg = struct(
            record_nix_path = ctx.attrs._record_nix_path[RunInfo],
        ),
        pkg_deps = haskell_toolchain.packages.dynamic,
        list_of_packages = list_of_packages.as_output(),
    ))

    return [
        DefaultInfo(
            default_outputs = [list_of_packages],
        ),
    ]

haskell_toolchain_all = rule(
    impl = _haskell_toolchain_all_impl,
    attrs = {
        "_record_nix_path": attrs.dep(
            providers = [RunInfo],
            default = "toolchains//tools:record_nix_path",
        ),
        "toolchain": attrs.toolchain_dep(
            providers = [HaskellToolchainInfo],
        ),
        "allow_cache_upload": attrs.bool(default = True),
    },
)
