-- Fase 10 verdicts (R2 §5, D-alief-25).
create extension if not exists pgtap with schema extensions;

begin;
select plan(6);

select col_type_is('public', 'verdicts', 'global_eligible', 'boolean', 'verdicts.global_eligible is boolean');
select col_not_null('public', 'verdicts', 'global_eligible', 'verdicts.global_eligible is not null');
select col_default_is('public', 'verdicts', 'global_eligible', 'false', 'verdicts.global_eligible defaults to false');
select has_index('public', 'verdicts', 'verdicts_eligible_domain', 'index for counting eligible families per domain');

select has_check('public', 'verdicts', 'verdicts has a check constraint');
select throws_ok(
  $$insert into verdicts (owner_id, domain, value, by_device_id, by_name, global_eligible)
    values ('x', 'a.example', 'safe', 'x', 'X', true)$$,
  '23514', null, 'only not_safe verdicts can be eligible');

select * from finish();
rollback;
