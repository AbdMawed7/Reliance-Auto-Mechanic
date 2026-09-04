create extension if not exists pgcrypto;

create table if not exists public.repairs (
  id uuid primary key default gen_random_uuid(),
  ro_number text unique not null,
  year text,
  make text,
  model text,
  customer_name text,
  customer_phone text,
  technician text,
  status text not null default 'Repair In Progress',
  internal_notes text default '',
  share_token uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table if not exists public.repair_updates (
  id uuid primary key default gen_random_uuid(),
  repair_id uuid not null references public.repairs(id) on delete cascade,
  update_text text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.repair_media (
  id uuid primary key default gen_random_uuid(),
  repair_id uuid not null references public.repairs(id) on delete cascade,
  media_type text not null check (media_type in ('image','video')),
  storage_path text not null,
  caption text default '',
  created_at timestamptz not null default now()
);

alter table public.repairs enable row level security;
alter table public.repair_updates enable row level security;
alter table public.repair_media enable row level security;

create policy "staff read repairs" on public.repairs for select to authenticated using (true);
create policy "staff insert repairs" on public.repairs for insert to authenticated with check (true);
create policy "staff update repairs" on public.repairs for update to authenticated using (true) with check (true);
create policy "staff delete repairs" on public.repairs for delete to authenticated using (true);

create policy "staff read updates" on public.repair_updates for select to authenticated using (true);
create policy "staff insert updates" on public.repair_updates for insert to authenticated with check (true);
create policy "staff update updates" on public.repair_updates for update to authenticated using (true) with check (true);
create policy "staff delete updates" on public.repair_updates for delete to authenticated using (true);

create policy "staff read media" on public.repair_media for select to authenticated using (true);
create policy "staff insert media" on public.repair_media for insert to authenticated with check (true);
create policy "staff update media" on public.repair_media for update to authenticated using (true) with check (true);
create policy "staff delete media" on public.repair_media for delete to authenticated using (true);

insert into storage.buckets (id, name, public)
values ('repair-media','repair-media',true)
on conflict (id) do update set public = true;

create policy "staff upload repair media" on storage.objects for insert to authenticated with check (bucket_id = 'repair-media');
create policy "staff view repair media" on storage.objects for select to authenticated using (bucket_id = 'repair-media');
create policy "staff update repair media" on storage.objects for update to authenticated using (bucket_id = 'repair-media') with check (bucket_id = 'repair-media');
create policy "staff delete repair media" on storage.objects for delete to authenticated using (bucket_id = 'repair-media');

create or replace function public.get_customer_repair(p_token uuid)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select jsonb_build_object(
    'repair', jsonb_build_object(
      'ro_number', r.ro_number,
      'year', r.year,
      'make', r.make,
      'model', r.model,
      'status', r.status,
      'technician', r.technician
    ),
    'updates', coalesce((
      select jsonb_agg(jsonb_build_object('text', u.update_text, 'created_at', u.created_at) order by u.created_at desc)
      from public.repair_updates u where u.repair_id = r.id
    ), '[]'::jsonb),
    'media', coalesce((
      select jsonb_agg(jsonb_build_object('type', m.media_type, 'path', m.storage_path, 'caption', m.caption, 'created_at', m.created_at) order by m.created_at desc)
      from public.repair_media m where m.repair_id = r.id
    ), '[]'::jsonb)
  )
  from public.repairs r
  where r.share_token = p_token
  limit 1;
$$;

grant execute on function public.get_customer_repair(uuid) to anon, authenticated;
