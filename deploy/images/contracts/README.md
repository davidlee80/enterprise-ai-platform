# Image tag and traceability contracts

These contracts implement the `TBD-013` development boundary without selecting
an image Tag format.

- `image-tag-policy.v1.schema.json` is the versioned configuration entry point
  for a later Tag template, components, normalization, mutable aliases,
  branches, prereleases, and promotion.
- `image-publication-record.v1.schema.json` binds a build to its immutable image
  digest, source repository, source revision, source/release version, build ID,
  timestamp, and matching OCI labels.
- `image-traceability-boundary.v1.json` keeps the current Tag policy null while
  making digest/source/version evidence mandatory.

A Tag is only a locator. Production identity and rollback use a previously
verified immutable digest and matching publication record. A release may be
recorded by digest without selecting a Tag convention; publishing a release Tag
requires a reviewed Tag-policy revision. Test-only Tags do not establish a
production naming recommendation.

Run from the repository root:

```powershell
pwsh -NoLogo -NoProfile -File ./deploy/images/image-traceability.conformance.ps1
pwsh -NoLogo -NoProfile -File ./scripts/task.ps1 test-tbd-013
```
