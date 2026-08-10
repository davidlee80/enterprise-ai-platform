# Ownership metadata

Every application and shared package README records these required fields:

- Owner
- SLO
- Runbook
- Upgrade window
- Data-retention responsibility, when applicable

The owning organization name is `TBD-018`. Upgrade windows and retention duties
must be assigned when a component receives a runtime or persistent-data
responsibility; this bootstrap does not invent production assignments.

[`ownership-catalog.v1.json`](ownership-catalog.v1.json) is the machine-readable
inventory for all applications and shared packages. It preserves every required
metadata field while keeping owner references, organization names, and team
topology unconfigured. A placeholder is not a production assignment.
