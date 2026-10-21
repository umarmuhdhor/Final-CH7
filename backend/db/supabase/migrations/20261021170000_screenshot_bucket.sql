-- Fase 09 scans (R3 §4, D-alief-B07).
-- The Worker already checks size and magic bytes; the bucket enforces the same limits
-- so an object that skips the Worker (or a Worker bug) cannot store anything else.
-- 153600 = SCREENSHOT_MAX_BYTES in backend/api/wrangler.jsonc.
update storage.buckets
set file_size_limit = 153600,
    allowed_mime_types = array['image/jpeg', 'image/png']
where id = 'screenshots';
