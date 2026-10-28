-- Fase 09 screenshots bucket limits (R3 §4, D-alief-B07).
create extension if not exists pgtap with schema extensions;

begin;
select plan(5);

select is((select public from storage.buckets where id = 'screenshots'), false, 'bucket screenshots stays private');
select is((select file_size_limit from storage.buckets where id = 'screenshots'), 153600::bigint,
  'screenshots objects are at most 150 KB');
select is((select allowed_mime_types from storage.buckets where id = 'screenshots'),
  array['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/x-icon'],
  'screenshots accepts only raster images: JPEG and PNG screenshots, favicons also GIF, WebP, ICO (no SVG)');

select has_index('public', 'scans', 'scans_owner_shot', 'index for the screenshot quota and dedupe');
select has_index('public', 'scans', 'scans_favicon_path', 'index for favicon path lookups per owner');

select * from finish();
rollback;
