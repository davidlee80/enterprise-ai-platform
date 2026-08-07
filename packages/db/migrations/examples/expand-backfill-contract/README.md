# Expand / backfill / contract template

These `.sql.example` files are non-executable templates. Replace every angle-
bracket placeholder through a reviewed domain migration; never rename them to
`.up.sql` without an ADR, compatibility evidence, and task-specific tests.

1. `001-expand.sql.example` adds a nullable or otherwise backward-compatible
   structure while old and new application versions coexist.
2. `002-backfill.sql.example` copies data with reviewed batching, rate limits,
   observability, and restart semantics. Concrete thresholds remain TBD.
3. `003-contract.sql.example` removes the old representation only after the new
   code is fully deployed, backfill is verified, the rollback window has passed,
   and approval is recorded.

Production rollback during expand/backfill returns application traffic to the
compatible version and keeps additive schema. A failed contract phase requires a
reviewed forward repair or restoration plan; it must not be an unreviewed
destructive one-shot migration.

