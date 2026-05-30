# SPDX-FileCopyrightText: 2026 Mercury Technologies, Inc.
#
# SPDX-License-Identifier: MIT OR Apache-2.0

# Custom execution platform that enables remote execution (and remote caching)
# via bazel-remote or another REAPI-compatible backend.
#
# With local_enabled = True and remote_enabled = True (hybrid mode):
#   - Actions first attempt the remote executor (checks action cache, then executes)
#   - On Execution service errors (e.g. bazel-remote has no Execution service),
#     the hybrid executor falls back to local execution
#   - After local execution, allow_cache_uploads = True causes results to be
#     uploaded to the remote action cache
#   - Subsequent runs with --remote-only will find all actions in cache
#
# Usage:
#   First run (warm cache):  buck test buck2-haskell//tests/...
#   Second run (from cache): buck test --remote-only -j4 buck2-haskell//tests/...

def _re_platform_impl(ctx):
    constraints = dict()
    constraints.update(ctx.attrs.cpu_configuration[ConfigurationInfo].constraints)
    constraints.update(ctx.attrs.os_configuration[ConfigurationInfo].constraints)
    cfg = ConfigurationInfo(constraints = constraints, values = {})

    name = ctx.label.raw_target()
    platform = ExecutionPlatformInfo(
        label = name,
        configuration = cfg,
        executor_config = CommandExecutorConfig(
            local_enabled = True,
            remote_enabled = True,
            remote_execution_properties = {},
            remote_execution_use_case = "buck2-default",
            allow_cache_uploads = True,
            use_windows_path_separators = ctx.attrs.use_windows_path_separators,
        ),
    )

    return [
        DefaultInfo(),
        platform,
        PlatformInfo(label = str(name), configuration = cfg),
        ExecutionPlatformRegistrationInfo(platforms = [platform]),
    ]

_re_platform = rule(
    impl = _re_platform_impl,
    attrs = {
        "cpu_configuration": attrs.dep(providers = [ConfigurationInfo]),
        "os_configuration": attrs.dep(providers = [ConfigurationInfo]),
        "use_windows_path_separators": attrs.bool(),
    },
)

re_platform = _re_platform
