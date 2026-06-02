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
# Worker RE platform (platforms//:worker_re):
#   - Combines the persistent GHC worker with the RE hybrid executor.
#   - GHC compilation actions use the persistent worker for local execution;
#     if an action can be served from the remote cache the worker is skipped
#     entirely.  After a local worker execution the result is uploaded to the
#     remote cache so that subsequent builds (on this machine or others) can
#     skip recompilation.
#   - Same RE connectivity requirements as platforms//:re.
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
            remote_enabled = ctx.attrs.remote_enabled,
            remote_execution_properties = {},
            remote_execution_use_case = "buck2-default",
            use_persistent_workers = ctx.attrs.use_persistent_workers,
            # Only allow cache uploads if remote execution is enabled.
            allow_cache_uploads = ctx.attrs.remote_enabled,
            use_windows_path_separators = ctx.attrs.use_windows_path_separators,
        ),
    )

    return [
        DefaultInfo(),
        platform,
        PlatformInfo(label = str(name), configuration = cfg),
        ExecutionPlatformRegistrationInfo(platforms = [platform]),
    ]

re_platform = rule(
    impl = _re_platform_impl,
    attrs = {
        "cpu_configuration": attrs.dep(providers = [ConfigurationInfo]),
        "os_configuration": attrs.dep(providers = [ConfigurationInfo]),
        "use_windows_path_separators": attrs.bool(),
        "remote_enabled": attrs.bool(default = True),
        "use_persistent_workers": attrs.bool(default = False),
    },
)

