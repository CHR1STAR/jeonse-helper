begin;

create table if not exists public.jeonse_workspaces (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null check (
    jsonb_typeof(payload) = 'object'
    and jsonb_typeof(payload -> 'items') is not distinct from 'array'
  ),
  version integer not null default 1 check (version > 0)
);

alter table public.jeonse_workspaces enable row level security;
revoke all on public.jeonse_workspaces from public, anon, authenticated;
grant select on public.jeonse_workspaces to authenticated;
grant insert (user_id, payload) on public.jeonse_workspaces to authenticated;
grant update (payload, version) on public.jeonse_workspaces to authenticated;

drop policy if exists workspace_read_own on public.jeonse_workspaces;
create policy workspace_read_own on public.jeonse_workspaces
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists workspace_insert_own on public.jeonse_workspaces;
create policy workspace_insert_own on public.jeonse_workspaces
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists workspace_update_own on public.jeonse_workspaces;
create policy workspace_update_own on public.jeonse_workspaces
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

commit;
