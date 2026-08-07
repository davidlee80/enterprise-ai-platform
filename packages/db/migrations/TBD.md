# Pending business-table schema decisions

`TASK-M1-001` must not invent fields or constraints that Volume 8 did not define.
The following required business tables therefore remain non-executable migration
skeleton items until their owning domain design and ADR confirm the schema:

| Required concept | Status and required decision |
|---|---|
| `user` | Table name, identity fields, tenant relationship, lifecycle, and retention are TBD. The SQL identifier also requires an explicit naming decision. |
| `role` | Scope, permissions relationship, tenant/global semantics, and lifecycle are TBD. |
| `api_key` | Hash/reference fields, tenant/subject relationship, rotation, expiry, and retention are TBD; plaintext keys are forbidden. |
| `provider` | Boundary relative to `provider_endpoint`, lifecycle fields, and version model are TBD. |
| `provider_capability` | Field types for support level, limits, context length, tool calling, multimodal limits, and capability version require domain review under `REQ-DB-004`. |
| `model` / `model_mapping` | Canonical model, alias, capability, Provider mapping, lifecycle, and version fields are TBD. |
| `route_policy` | Policy ownership, revision, publication, rollback, and strategy representation are TBD. |
| `usage` | Event-derived aggregation keys, buckets, pricing version, and retention are TBD; synchronous request-path aggregation is forbidden by `REQ-DB-005`. |
| `audit_event` | Actor, target, revision, evidence, immutability, and retention fields require Audit domain review under `REQ-DB-006`. |

The Outbox schema is implemented by `TASK-M1-002` in
`000002_outbox.up.sql`; broker and retry/DLQ policy decisions remain TBD.

None of these placeholders authorizes an empty table or guessed production
column.
