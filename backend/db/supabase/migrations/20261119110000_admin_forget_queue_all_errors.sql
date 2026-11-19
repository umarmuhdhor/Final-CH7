-- EGM audit B13: admin.on_device_delete and admin.on_family_unlink (20261104085245_admin_scan_archive.sql)
-- queued a forget (admin.label_forget) only when a row was held (lock_not_available). Any other error inside
-- a block, for example a statement timeout or a check violation in admin._archive_forget, fell through to the
-- outer `exception when others then raise warning`: the account delete or unlink committed, and owner_ref,
-- page_title and fragment keys stayed in admin.scan_archive with no queue entry and no tombstone.
--
-- Fix: each inner block now queues the forget on ANY error (and says so in a warning), so the daily drain
-- (admin.on_forget_drain via snapshot_daily) retries it. The outer catch stays as the last resort, so
-- deleting your data still never fails because of the admin schema (SECURITY §3 P3). Bodies are otherwise
-- the ones of 20261104085245, unchanged.
-- Rollback: re-run the two function bodies of 20261104085245_admin_scan_archive.sql.

set local lock_timeout = '5s';

create or replace function admin.on_device_delete() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
declare
  v_ref    text;
  v_queued boolean := false;
begin
  begin
    v_ref := admin.owner_ref(old.id);
    begin
      -- SKIP LOCKED: rows a running analysis holds are left for the forget queue instead of waiting.
      with gone as (
        delete from admin.domain_labels where id in (
          select id from admin.domain_labels where owner_ref = v_ref or by_ref = v_ref for update skip locked)
        returning domain)
      insert into admin.domain_dirty (domain) select distinct domain from gone on conflict do nothing;
      if exists (select 1 from admin.domain_labels where owner_ref = v_ref or by_ref = v_ref) then
        insert into admin.label_forget (owner_ref, by_ref) values (v_ref, null);
        v_queued := true;
      end if;
    exception when others then
      -- Any failure, not only a held row, queues the forget: the drain (on_forget_drain) retries it.
      raise warning 'admin_trigger_queued on_device_delete labels % %', sqlstate, sqlerrm;
      insert into admin.label_forget (owner_ref, by_ref) values (v_ref, null);
      v_queued := true;
    end;
    begin
      perform admin._archive_forget(v_ref, null, clock_timestamp());
    exception when others then
      raise warning 'admin_trigger_queued on_device_delete archive % %', sqlstate, sqlerrm;
      if not v_queued then
        insert into admin.label_forget (owner_ref, by_ref) values (v_ref, null);
      end if;
    end;
  exception when others then
    raise warning 'admin_trigger_failed on_device_delete % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- 02a on_family_unlink + the pair's archive feedback (K11).
create or replace function admin.on_family_unlink() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
declare
  v_owner  text;
  v_by     text;
  v_queued boolean := false;
begin
  begin
    v_owner := admin.owner_ref(old.protected_id);
    v_by    := admin.owner_ref(old.guardian_id);
    begin
      with gone as (
        delete from admin.domain_labels where id in (
          select id from admin.domain_labels where owner_ref = v_owner and by_ref = v_by for update skip locked)
        returning domain)
      insert into admin.domain_dirty (domain) select distinct domain from gone on conflict do nothing;
      if exists (select 1 from admin.domain_labels where owner_ref = v_owner and by_ref = v_by) then
        insert into admin.label_forget (owner_ref, by_ref) values (v_owner, v_by);
        v_queued := true;
      end if;
    exception when others then
      raise warning 'admin_trigger_queued on_family_unlink labels % %', sqlstate, sqlerrm;
      insert into admin.label_forget (owner_ref, by_ref) values (v_owner, v_by);
      v_queued := true;
    end;
    begin
      perform admin._archive_forget(v_owner, v_by, clock_timestamp());
    exception when others then
      raise warning 'admin_trigger_queued on_family_unlink archive % %', sqlstate, sqlerrm;
      if not v_queued then
        insert into admin.label_forget (owner_ref, by_ref) values (v_owner, v_by);
      end if;
    end;
  exception when others then
    raise warning 'admin_trigger_failed on_family_unlink % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;
