# Performance regression harness

This harness separates measurement evidence from production thresholds.
`performance-profile.v1.schema.json` requires workload size, concurrency, token
distributions, and optional success/latency/TTFT limits. The evaluator operates
in measure-only mode when limits are null and becomes a fail-closed regression
gate only after a reviewed profile is published.

The conformance suite verifies percentile calculation, configured threshold
failure, and the unconfigured production guard. A deployed load-driver adapter
and real environment evidence remain required before `TASK-M4-004` or
production capacity acceptance can be marked complete.
