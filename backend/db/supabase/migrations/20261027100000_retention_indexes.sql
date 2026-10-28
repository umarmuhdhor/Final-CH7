-- Fase 12 security review follow-up (PR #20 comment, MEDIUM).

-- Retention walks old scans oldest first, once without and once with a screenshot. On scans_created
-- each walk steps over every old row of the other kind; with a backlog that can reach the role's
-- statement_timeout every day and never clear. One partial index per walk.
create index scans_plain_created on scans(created_at, id) where screenshot_path is null;
create index scans_shot_created on scans(created_at, id) where screenshot_path is not null;
