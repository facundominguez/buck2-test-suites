# SPDX-FileCopyrightText: 2026 Mercury Technologies, Inc.
#
# SPDX-License-Identifier: MIT OR Apache-2.0

# Custom execution platforms for remote execution (RE) and local-only builds.
#

def _local_execution_platform(ctx: AnalysisContext) -> list[Provider]:
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
            # Without this, buck2 silently runs `WorkerRunInfo` actions one-shot
            # instead. The `build.use_persistent_workers` buckconfig buck2
            # documents is unimplemented in OSS, so this is the only knob.
            use_persistent_workers = True,
            remote_enabled = False,
            remote_cache_enabled = False,
            allow_cache_uploads = False,
            use_limited_hybrid = False,
        ),
    )

    return [
        DefaultInfo(),
        platform,
        PlatformInfo(label = str(name), configuration = cfg),
        ExecutionPlatformRegistrationInfo(platforms = [platform], fallback = "error"),
    ]

local_execution_platform = rule(
    impl = _local_execution_platform,
    attrs = {
        "cpu_configuration": attrs.dep(providers = [ConfigurationInfo]),
        "os_configuration": attrs.dep(providers = [ConfigurationInfo]),
    },
)

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

def _remote_execution_platform_impl(ctx):
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
            # Without this, buck2 silently runs `WorkerRunInfo` actions one-shot
            # instead. The `build.use_persistent_workers` buckconfig buck2
            # documents is unimplemented in OSS, so this is the only knob.
            use_persistent_workers = True,
            use_windows_path_separators = ctx.attrs.use_windows_path_separators,
        ),
    )

    return [
        DefaultInfo(),
        platform,
        PlatformInfo(label = str(name), configuration = cfg),
        ExecutionPlatformRegistrationInfo(platforms = [platform]),
    ]

remote_execution_platform = rule(
    impl = _remote_execution_platform_impl,
    attrs = {
        "cpu_configuration": attrs.dep(providers = [ConfigurationInfo]),
        "os_configuration": attrs.dep(providers = [ConfigurationInfo]),
        "use_windows_path_separators": attrs.bool(),
    },
)
