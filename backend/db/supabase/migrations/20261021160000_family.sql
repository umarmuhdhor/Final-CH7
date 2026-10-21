-- Fase 08 family (D-alief-B06).
-- join_attempts keeps only sha256('join:<ip or IPv6 /64>'), like rate_limit_hits (D-alief-B02):
-- no raw IP address is stored. The table is empty everywhere when this runs.

drop index if exists join_attempts_ip_time;
alter table join_attempts drop column ip;
alter table join_attempts add column ip_hash bytea;
create index join_attempts_ip_time on join_attempts(ip_hash, attempted_at desc);

-- Retention deletes (fase 12, R2 §6) filter on time only.
create index join_attempts_time on join_attempts(attempted_at);
create index family_codes_expires on family_codes(expires_at);
