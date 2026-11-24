#!/usr/bin/env bash
set -euo pipefail

container="${1:?Pass the name of a disposable PostgreSQL container}"
psql_in_container() {
  docker exec -i "$container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres
}

# Minimal Supabase auth interfaces for the isolated PostgreSQL test.
psql_in_container <<'SQL'
create role authenticated;
create role anon;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to authenticated;
insert into auth.users values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002');
SQL
psql_in_container < jeonse-supabase.sql

# Seed records in the old format before migration to test the backfill.
psql_in_container <<'SQL'
insert into public.jeonse_workspaces(user_id, payload, version) values
 ('00000000-0000-0000-0000-000000000001',
  '{"items":[{"id":"a","name":"첫 집","checks":{"water":"문제 없음"}},{"id":"b","name":"둘째 집","checks":{"water":"문제 있음"}}],"chosen":"b"}', 4),
 ('00000000-0000-0000-0000-000000000002',
  '{"items":[{"id":"a","name":"다른 계정","checks":{"water":"미확인"}}]}', 1);
SQL
psql_in_container < 001-listings-and-visit-checks.sql
psql_in_container < 001-listings-and-visit-checks.sql

psql_in_container <<'SQL'
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
do $$
declare snapshot record;
begin
  select * into strict snapshot from public.jeonse_read_workspace();
  if snapshot.version <> 4 or snapshot.payload is distinct from
      '{"items":[{"id":"a","name":"첫 집","checks":{"water":"문제 없음"}},{"id":"b","name":"둘째 집","checks":{"water":"문제 있음"}}],"chosen":"b"}'::jsonb then
    raise exception 'Backfill changed the original listing data, ordering or version';
  end if;
  if (select count(*) from public.jeonse_listings) <> 2
     or (select count(*) from public.jeonse_visit_checks) <> 2 then
    raise exception 'Another account can see the listings or checks';
  end if;

  update public.jeonse_workspaces set
    version = 5, payload = '{"items":[{"id":"b","name":"둘째 집","checks":{"leak":"문제 있음"}},{"id":"c","name":"새 매물","checks":{}}]}'::jsonb
    where user_id = auth.uid() and version = 4;
  select * into strict snapshot from public.jeonse_read_workspace();
  if snapshot.version <> 5 or snapshot.payload is distinct from
     '{"items":[{"id":"b","name":"둘째 집","checks":{"leak":"문제 있음"}},{"id":"c","name":"새 매물","checks":{}}]}'::jsonb
     or (select count(*) from public.jeonse_visit_checks) <> 1 then
    raise exception 'Saving did not synchronize updates and deletions';
  end if;

  update public.jeonse_workspaces set version = 5, payload = '{"items":[]}'
    where user_id = auth.uid() and version = 4;
  if found then raise exception 'An out-of-date save overwrote current data'; end if;
  if has_table_privilege('authenticated','public.jeonse_visit_checks','INSERT')
     or has_function_privilege('anon','public.jeonse_read_workspace()','EXECUTE') then
    raise exception 'Permissions allow a direct write or anonymous read';
  end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
do $$
begin
  if (select payload #>> '{items,0,name}' from public.jeonse_read_workspace())
     is distinct from '다른 계정' then
    raise exception 'An update affected another account';
  end if;
end $$;
SQL
