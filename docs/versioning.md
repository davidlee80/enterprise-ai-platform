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

