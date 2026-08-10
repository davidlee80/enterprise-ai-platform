# Versioning status

`REQ-REP-006` and `REQ-REL-001` require traceable component/API versions and
SemVer-compatible releases. During repository bootstrap, every file is
traceable to its Git revision.

The following production decision remains open and must be settled by ADR before
the first component release:

- Whether the monorepo uses a unified version or independently versioned
  components (`REQ-REP-006`, TBD by the requirements document).

Until that decision is made, no file in this repository may describe either
model as the platform standard. Rollback for bootstrap-only documentation and
metadata is a Git revert. Runtime, configuration, API, and database rollback
procedures are owned by their later implementation tasks.

Image publication traceability is independent of the unresolved component
version topology. The versioned
[`publication record`](../deploy/images/contracts/image-publication-record.v1.schema.json)
binds source revision and source/release version to OCI labels and an immutable
digest. The exact Image Tag composition remains `TBD-013`; Tags are locators,
while production identity and rollback use verified digests.

API, model-alias, configuration-field, and capability retirement uses the
versioned [`deprecation boundary`](contracts/deprecation/README.md). A scheduled
deprecation must publish explicit start and end timestamps and retain the prior
contract until the configured end. The production duration, notification and
post-window enforcement rules remain `TBD-015`; no default number of days is
defined by this repository.
