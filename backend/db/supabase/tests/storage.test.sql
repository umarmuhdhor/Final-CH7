-- Fase 09 screenshots bucket limits (R3 §4, D-alief-B07).
create extension if not exists pgtap with schema extensions;

begin;
select plan(3);

select is((select public from storage.buckets where id = 'screenshots'), false, 'bucket screenshots stays private');
select is((select file_size_limit from storage.buckets where id = 'screenshots'), 153600::bigint,
  'screenshots objects are at most 150 KB');
select is((select allowed_mime_types from storage.buckets where id = 'screenshots'), array['image/jpeg', 'image/png'],
  'screenshots accepts only JPEG and PNG');

select * from finish();
rollback;
