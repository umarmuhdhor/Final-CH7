-- Fase 11 (D-alief-B11, D-alief-40): push_log keeps no notification text. The body repeated the
-- protected person's name in a second table and went stale after a rename; it can be rebuilt from
-- scan_id + pushText. result is limited to short codes, so a token or JWT can never be stored there.
alter table push_log drop column body;
-- Rows written before this migration (none expected) are dropped rather than failing the CHECK.
delete from push_log where result !~ '^(sent|logged|failed:([0-9]{3}( [A-Za-z]{1,64})?|timeout|network|config))$';
-- not valid + validate: the full-table check runs under SHARE UPDATE EXCLUSIVE, not ACCESS EXCLUSIVE.
alter table push_log add constraint push_log_result_format
  check (result ~ '^(sent|logged|failed:([0-9]{3}( [A-Za-z]{1,64})?|timeout|network|config))$') not valid;
alter table push_log validate constraint push_log_result_format;

-- The per-guardian push cap counts rows by (guardian, time): one index range scan.
create index push_log_device_created on push_log (to_device_id, created_at);
drop index push_log_device;
