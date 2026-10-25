-- PR-03 (issue #128): one 6-digit family code for the screen, the QR and the WhatsApp link, valid 30 min.
-- 4-digit codes are dropped with no transition (the app is not public yet). Every code alive right now
-- is at most 60 s old, so deleting them only makes an open invite screen fetch a new one.

delete from family_codes;
alter table family_codes drop constraint family_codes_code_check;
alter table family_codes alter column code type char(6);
alter table family_codes add constraint family_codes_code_check check (code ~ '^[0-9]{6}$');
