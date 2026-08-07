# Redis module contract

Defines L2 shared-cache/atomic-state requirements and tenant/config-version key
isolation. L3 semantic cache is disabled unless a reviewed policy reference is
explicitly supplied. Topology, persistence, eviction, sizing, version, endpoint,
and credential delivery remain provider/environment decisions.

