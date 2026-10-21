-- Fase 12 hardening (D-alief-B12; deferred from D-alief-B05).
-- Role-level timeouts: a stuck query or an open transaction never holds a pooled Hyperdrive
-- connection for long. They apply when a connection logs in, so pooled connections pick them up
-- as they recycle. Code sets tighter values with set_config(..., true) per transaction only.
alter role shoo_api set statement_timeout = '10s';
alter role shoo_api set idle_in_transaction_session_timeout = '15s';
alter role shoo_api set lock_timeout = '5s';

-- The Worker queues domains and recounts support; only a person approves or removes them
-- (SQL editor as postgres, D-alief-25, SECURITY T5). A compromised Worker can no longer publish
-- a domain to every extension's blocklist.
revoke insert, update on blocklist_entries from shoo_api;
grant insert (domain, families) on blocklist_entries to shoo_api;
grant update (families) on blocklist_entries to shoo_api;
