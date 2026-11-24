begin;

-- Serialize the backfill with saves from the current web app.
lock table public.jeonse_workspaces in share row exclusive mode;

create table if not exists public.jeonse_listings (
  user_id uuid not null references public.jeonse_workspaces(user_id) on delete cascade,
  listing_id text not null check (listing_id <> ''),
  position integer not null check (position > 0),
  details jsonb not null check (jsonb_typeof(details) = 'object'),
  primary key (user_id, listing_id)
);

create table if not exists public.jeonse_visit_checks (
  user_id uuid not null,
  listing_id text not null,
  check_key text not null check (check_key <> ''),
  result jsonb not null,
  primary key (user_id, listing_id, check_key),
  foreign key (user_id, listing_id)
    references public.jeonse_listings(user_id, listing_id) on delete cascade
);

alter table public.jeonse_listings enable row level security;
alter table public.jeonse_visit_checks enable row level security;
revoke all on public.jeonse_listings, public.jeonse_visit_checks from public, anon, authenticated;
grant select on public.jeonse_listings, public.jeonse_visit_checks to authenticated;

drop policy if exists listings_read_own on public.jeonse_listings;
create policy listings_read_own on public.jeonse_listings
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists visit_checks_read_own on public.jeonse_visit_checks;
create policy visit_checks_read_own on public.jeonse_visit_checks
  for select to authenticated using ((select auth.uid()) = user_id);

-- Keep the original payload for deployed clients and rollback. Update both
-- related tables inside the same transaction as each version-checked save.
create or replace function public.jeonse_update_listing_tables()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.jeonse_listings l
    where l.user_id = new.user_id
      and not exists (
        select 1 from jsonb_array_elements(new.payload -> 'items') as source(item)
        where source.item ->> 'id' = l.listing_id
      );

  insert into public.jeonse_listings as l (user_id, listing_id, position, details)
    select new.user_id, source.item ->> 'id', source.ordinality::integer,
           source.item - 'id' - 'checks'
    from jsonb_array_elements(new.payload -> 'items') with ordinality as source(item, ordinality)
  on conflict (user_id, listing_id) do update
    set position = excluded.position, details = excluded.details
    where (l.position, l.details) is distinct from (excluded.position, excluded.details);

  delete from public.jeonse_visit_checks c
    where c.user_id = new.user_id
      and not exists (
        select 1
        from jsonb_array_elements(new.payload -> 'items') as source(item)
        where source.item ->> 'id' = c.listing_id
          and (source.item -> 'checks') ? c.check_key
      );

  insert into public.jeonse_visit_checks as c (user_id, listing_id, check_key, result)
    select new.user_id, source.item ->> 'id', check_entry.key, check_entry.value
    from jsonb_array_elements(new.payload -> 'items') as source(item)
    cross join lateral jsonb_each(
      case when jsonb_typeof(source.item -> 'checks') = 'object'
      then source.item -> 'checks' else '{}'::jsonb end
    ) as check_entry(key, value)
  on conflict (user_id, listing_id, check_key) do update
    set result = excluded.result
    where c.result is distinct from excluded.result;
  return new;
end;
$$;

revoke all on function public.jeonse_update_listing_tables() from public, anon, authenticated;

drop trigger if exists jeonse_sync_listing_tables on public.jeonse_workspaces;
create trigger jeonse_sync_listing_tables
  after insert or update of payload on public.jeonse_workspaces
  for each row execute function public.jeonse_update_listing_tables();

update public.jeonse_workspaces set payload = payload;

create or replace function public.jeonse_read_workspace()
returns table(payload jsonb, version integer)
language sql stable security invoker set search_path = ''
as $$
  select (w.payload - 'items') || jsonb_build_object('items', coalesce((
    select jsonb_agg(
      l.details || jsonb_build_object('id', l.listing_id, 'checks', coalesce((
        select jsonb_object_agg(c.check_key, c.result)
        from public.jeonse_visit_checks c
        where c.user_id = l.user_id and c.listing_id = l.listing_id
      ), '{}'::jsonb))
      order by l.position
    )
    from public.jeonse_listings l
    where l.user_id = w.user_id
  ), '[]'::jsonb)), w.version
  from public.jeonse_workspaces w
  where w.user_id = (select auth.uid());
$$;

revoke all on function public.jeonse_read_workspace() from public, anon, authenticated;
grant execute on function public.jeonse_read_workspace() to authenticated;

commit;
