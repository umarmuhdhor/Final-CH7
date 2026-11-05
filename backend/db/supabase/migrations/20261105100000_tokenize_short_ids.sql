-- Audit 5 Nov 2026: admin.tokenize_path left short ids readable to admins and AI-team exports
-- (/order/8841027, /u/budi1984). It now also replaces a segment of 5+ digits, and one of 6+ characters
-- of [A-Za-z0-9_.-] with a letter and at least 2 digits. /verify-account-now/step2 and /2026/11/05 stay.
create or replace function admin.tokenize_path(p_path text) returns text
language plpgsql volatile set search_path = admin, pg_temp as $$
declare
  v_seg  text;
  v_out  text[] := '{}';
  v_tok  text;
  v_ch   text;
begin
  if p_path is null then
    return null;
  end if;
  foreach v_seg in array string_to_array(p_path, '/') loop
    if (v_seg ~ '^[0-9A-Fa-f-]{16,}$' and length(regexp_replace(v_seg, '[^0-9A-Fa-f]', '', 'g')) >= 16)
       or (v_seg ~ '^[A-Za-z0-9_.-]{16,}$' and v_seg ~ '[0-9]' and v_seg ~ '[a-z]' and v_seg ~ '[A-Z]')
       or v_seg ~ '^[0-9]{5,}$'
       or (v_seg ~ '^[A-Za-z0-9_.-]{6,}$' and v_seg ~ '[A-Za-z]' and v_seg ~ '[0-9].*[0-9]') then
      v_tok := '';
      foreach v_ch in array regexp_split_to_array(v_seg, '') loop
        v_tok := v_tok || case
          when v_ch ~ '[0-9]' then chr(48 + floor(random() * 10)::int)
          when v_ch ~ '[a-z]' then chr(97 + floor(random() * 26)::int)
          when v_ch ~ '[A-Z]' then chr(65 + floor(random() * 26)::int)
          else v_ch end;
      end loop;
      v_out := v_out || v_tok;
    else
      v_out := v_out || v_seg;
    end if;
  end loop;
  return array_to_string(v_out, '/');
end $$;
