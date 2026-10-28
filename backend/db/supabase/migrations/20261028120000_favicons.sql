-- PR-05 favicons: the Worker downloads a scam site's favicon once when the scan arrives and stores
-- it next to the screenshot, so the app never contacts the scam host (SECURITY P9). Same lifecycle
-- as screenshots: retention on day 14, DELETE /devices/me, storage_tombstones (D-alief-B12).

-- '<owner_id>/<scan_id>-favicon.<png|ico|jpg|gif|webp>' in bucket screenshots. A scan of the same
-- owner + domain within 24 h points at the earlier scan's object (reuse, like screenshot dedupe).
alter table scans add column favicon_path text check (char_length(favicon_path) between 3 and 300);

-- Retention's "no other scan shares this path" probe and the tombstone drain look paths up per owner.
create index scans_favicon_path on scans(owner_id, favicon_path) where favicon_path is not null;

-- Retention walks: a scan with only a favicon still needs a Storage call, so it moves from the
-- plain walk to the stored-files walk. Same names, predicates widened (20261027100000).
drop index scans_plain_created;
drop index scans_shot_created;
create index scans_plain_created on scans(created_at, id) where screenshot_path is null and favicon_path is null;
create index scans_shot_created on scans(created_at, id) where screenshot_path is not null or favicon_path is not null;

-- The Worker checks type, size and magic bytes; the bucket enforces the types too, so nothing
-- else (SVG above all) can be stored even through a Worker bug. Size limit stays 150 KB.
update storage.buckets
set allowed_mime_types = array['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/x-icon']
where id = 'screenshots';
