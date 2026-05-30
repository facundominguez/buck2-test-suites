# SPDX-FileCopyrightText: 2026 Mercury Technologies, Inc.
#
# SPDX-License-Identifier: MIT OR Apache-2.0

# Custom execution platforms for remote execution (RE) and local-only builds.
#
# RE platform (hybrid mode, platforms//:re):
#   - Requires a running NativeLink (or compatible REAPI) server on the address
#     configured in [buck2_re_client].
#   - Checks the remote action cache before every action (including local-only ones
#     like nix_build, because allow_cache_uploads = True wraps them with a cache
#     lookup). If the RE server is unreachable, Buck2 retries the connection 10 times
#     with exponential back-off (~45 s total) and then FAILS the build — it does NOT
#     fall back to local.
#   - Per-action remote execution errors (after the session is established) do fall
#     back to local execution automatically.
#   - After local execution, results are uploaded to the remote cache.
#

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
