# Kafka module contract

Requires topics to be grouped by event domain with explicit schema versions,
partition-key contracts, retry topics, and DLQs. Consumers remain idempotent
under at-least-once delivery. Concrete topic names, partitions, replication,
retention, broker topology, authentication, and Usage-event retry schedules are
reviewed environment decisions.

