# Capacity and N-1 validation boundary

This directory implements the configurable model and executable evaluator for
`REQ-OPS-002`, `REQ-OPS-003`, and `TASK-M5-003` without inventing production
numbers.

The profile requires RPS, concurrency, input/output token distributions, TTFT,
Provider quota, fallback amplification, and both Provider and Region N-1
scenarios. Production promotion requires a reviewed profile and evidence from a
real environment. The repository keeps `current_profile_ref` null; numbers in
the conformance suite are test fixtures only.
