# PostgreSQL migrations

This directory contains ordered, forward-only PostgreSQL migrations. Executable
migrations use the `<version>_<name>.up.sql` filename convention and are applied
in lexical order. The convention is a repository bootstrap mechanism, not a
decision that a particular third-party migration product is the platform
standard; the production PostgreSQL migration tool remains TBD under
`REQ-DB-007`.

## Commands

Validate without a database:

```bash
pwsh -NoLogo -NoProfile -File ./scripts/migration.ps1 validate
```

Apply all pending migrations with an installed `psql` client:

```bash
export PGSERVICE="reviewed-service-name"
pwsh -NoLogo -NoProfile -File ./scripts/migration.ps1 up
```

Standard libpq `PG*` environment variables may be used instead of `PGSERVICE`.
The runner requires either `PGSERVICE` or `PGDATABASE`, never prints connection
values, and does not accept a database password or URL as a command-line
argument.

Check applied versions:

```bash
pwsh -NoLogo -NoProfile -File ./scripts/migration.ps1 status
```

## Forward and rollback policy

Every current migration is additive and runs in one transaction. If a statement
fails, PostgreSQL rolls back that transaction, so existing application reads keep
using the prior schema. Applied migration content is identified by SHA-256; a
changed file with an already-applied version fails with
`MIGRATION_CHECKSUM_MISMATCH`. For Outbox rollback, stop the publisher and retain
unpublished rows for a compatible forward recovery.

Production rollback does not execute automatic `DROP TABLE` down migrations.
Rollback means reverting the application to a compatible version while retaining
the additive schema, then delivering a reviewed forward repair. Destructive
cleanup is permitted only as a later contract phase after compatible deployment,
backfill, observation, and an approved rollback window.

The runner does not support concurrent migration processes. Locking strategy,
large-table batching/rate limits, online-index tooling, and production execution
product remain TBD and require an ADR before production use.

## Scope

Version `000001` contains only the technical `schema_migration` history table and
the three tables whose fields are specified by the requirements: `tenant`,
`provider_endpoint`, and `model_route`. Version `000002` adds the transactional
`outbox_event` and its language-neutral publisher coordination functions for
`TASK-M1-002`; see the [Outbox boundary](../outbox/README.md).

See [TBD.md](TBD.md) for the mandatory business tables whose fields have not yet
been confirmed.
