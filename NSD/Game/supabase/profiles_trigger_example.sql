-- Example: auto-create a public.profiles row when a new auth user signs up.
-- Run in the Supabase SQL editor (or migrate). Adjust column list to match your profiles table.
--
-- If profiles has no display_name column yet:
--   alter table public.profiles add column if not exists display_name text;
--
-- Recommended when the Love launcher cannot POST profiles (strict RLS). The launcher will
-- still try POST first; if that fails, apply this trigger so new users get a row.

-- Expects public.profiles to include a text column display_name (nullable is fine).
-- Copies display_name from auth signup metadata: options.data.display_name -> raw_user_meta_data.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  dn text;
begin
  dn := nullif(trim(coalesce(new.raw_user_meta_data->>'display_name', '')), '');
  insert into public.profiles (id, display_name)
  values (new.id, dn)
  on conflict (id) do update set
    display_name = coalesce(nullif(trim(public.profiles.display_name), ''), excluded.display_name);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
