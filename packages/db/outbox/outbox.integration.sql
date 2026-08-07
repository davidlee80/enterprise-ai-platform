-- CI-only integration test. Run after all migrations on an isolated database.

BEGIN;

INSERT INTO tenant (id, name, plan, status)
VALUES (
  '10000000-0000-0000-0000-000000000001',
  'outbox-ci-tenant',
  'ci',
  'active'
);

SELECT enqueue_outbox_event(
  '20000000-0000-0000-0000-000000000001',
  'OutboxIntegrationTest',
  1,
  '2026-08-07T00:00:00Z',
  '10000000-0000-0000-0000-000000000001',
  'ci-request',
  'ci-trace',
  'migration-ci',
  '{"kind":"ci"}'::jsonb
);

COMMIT;

DO $$
DECLARE
  claimed_count INT;
BEGIN
  SELECT count(*) INTO claimed_count
  FROM claim_outbox_events(
    'ci-worker',
    '30000000-0000-0000-0000-000000000001',
    10,
    '2026-08-07T00:01:00Z',
    '2026-08-07T00:02:00Z'
  );
  IF claimed_count <> 1 THEN
    RAISE EXCEPTION 'OUTBOX_CLAIM_COUNT_INVALID';
  END IF;

  IF NOT release_outbox_event(
    '20000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000001',
    '2026-08-07T00:01:30Z',
    'BROKER_UNAVAILABLE'
  ) THEN
    RAISE EXCEPTION 'OUTBOX_RELEASE_FAILED';
  END IF;

  SELECT count(*) INTO claimed_count
  FROM claim_outbox_events(
    'ci-worker',
    '30000000-0000-0000-0000-000000000002',
    10,
    '2026-08-07T00:01:31Z',
    '2026-08-07T00:02:31Z'
  );
  IF claimed_count <> 1 THEN
    RAISE EXCEPTION 'OUTBOX_RECLAIM_COUNT_INVALID';
  END IF;

  IF NOT mark_outbox_event_published(
    '20000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000002',
    '2026-08-07T00:01:32Z'
  ) THEN
    RAISE EXCEPTION 'OUTBOX_ACK_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM outbox_event
    WHERE event_id = '20000000-0000-0000-0000-000000000001'
      AND published_at = '2026-08-07T00:01:32Z'
      AND attempt_count = 2
      AND lease_token IS NULL
      AND last_reason_code IS NULL
  ) THEN
    RAISE EXCEPTION 'OUTBOX_FINAL_STATE_INVALID';
  END IF;
END;
$$;

DO $$
BEGIN
  BEGIN
    INSERT INTO tenant (id, name, plan, status)
    VALUES (
      '10000000-0000-0000-0000-000000000002',
      'outbox-rollback-probe',
      'ci',
      'active'
    );

    PERFORM enqueue_outbox_event(
      '20000000-0000-0000-0000-000000000002',
      'OutboxAtomicFailureTest',
      0,
      '2026-08-07T00:03:00Z',
      '10000000-0000-0000-0000-000000000002',
      NULL,
      NULL,
      'migration-ci',
      '{}'::jsonb
    );
  EXCEPTION
    WHEN check_violation THEN
      NULL;
  END;

  IF EXISTS (
    SELECT 1 FROM tenant
    WHERE id = '10000000-0000-0000-0000-000000000002'
  ) THEN
    RAISE EXCEPTION 'OUTBOX_ATOMIC_ROLLBACK_FAILED';
  END IF;
END;
$$;

