# Terraform conformance fixtures

`valid-configuration.tfvars.json` contains non-production documentation values
used only to exercise module validation and composition. Reserved documentation
addresses, `.invalid` DNS names, `fixture-*` identifiers, and `ref://fixture`
references must never be promoted or treated as platform defaults.

The fixture contains no credential or key material. Real environment variable
files remain separately reviewed, uncommitted inputs to dev/stage/prod roots.

