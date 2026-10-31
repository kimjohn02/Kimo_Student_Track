-- ====================================================================
-- SUPABASE DATABASE SCHEMA FOR KEITASK STUDENT TRACKER
-- ====================================================================
-- Run this script in your Supabase Dashboard:
-- 1. Go to https://supabase.com/dashboard/project/_/sql/new
-- 2. Paste this entire script and click "Run"
-- ====================================================================

-- 1. PROFILES TABLE (Mirrors and extends auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  name text,
  role text default 'student', -- 'student', 'professor', 'admin', 'user'
  profile_image text,          -- Cloudinary secure URL
  points integer default 0,
  is_approved boolean default true,
  enrolled_course_ids text[] default '{}',
  teaching_course_ids text[] default '{}',
  phone_number text,
  is_banned boolean default false,
  notifications_enabled boolean default true,
  fcm_token text,
  created_at timestamp with time zone default timezone('utc'::text, now()),
  updated_at timestamp with time zone default timezone('utc'::text, now())
);

-- Index for fast user queries
create index if not exists idx_profiles_role on public.profiles(role);
create index if not exists idx_profiles_points on public.profiles(points desc);

-- 2. AUTOMATIC PROFILE CREATION TRIGGER ON SIGNUP
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (
    id,
    email,
    name,
    role,
    profile_image,
    is_approved
  )
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'role', 'student'),
    new.raw_user_meta_data->>'profile_image',
    case
      when coalesce(new.raw_user_meta_data->>'role', 'student') = 'professor' then false
      else true
    end
  )
  on conflict (id) do update set
    email = excluded.email,
    name = coalesce(excluded.name, profiles.name),
    profile_image = coalesce(excluded.profile_image, profiles.profile_image);
  return new;
end;
$$ language plpgsql security definer;

-- Drop trigger if exists and recreate
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 3. TASKS TABLE
create table if not exists public.tasks (
  id text primary key,
  title text not null,
  description text default '',
  status text default 'pending', -- 'pending', 'approved', 'completed', 'rejected', 'resubmitted', 'assigned'
  assignees jsonb default '[]'::jsonb,
  assignee_names jsonb default '[]'::jsonb,
  due_date timestamp with time zone,
  creator text,
  rejection_reason text,
  completed_at timestamp with time zone,
  bookmarked_by jsonb default '[]'::jsonb,
  requested_assignee_names jsonb default '[]'::jsonb,
  course_id text,
  type text,
  weight numeric,
  grades jsonb default '{}'::jsonb,
  attachments jsonb default '[]'::jsonb,      -- Cloudinary image/file URLs attached to task
  completion_status jsonb default '{}'::jsonb,
  submissions jsonb default '{}'::jsonb,        -- Map of userId -> array of Cloudinary URLs
  created_at timestamp with time zone default timezone('utc'::text, now()),
  updated_at timestamp with time zone default timezone('utc'::text, now())
);

create index if not exists idx_tasks_status on public.tasks(status);
create index if not exists idx_tasks_creator on public.tasks(creator);

-- 4. REALTIME ENABLEMENT
-- Allows Flutter app to receive instant live stream updates
alter publication supabase_realtime add table public.profiles;
alter publication supabase_realtime add table public.tasks;

-- 5. ROW LEVEL SECURITY (RLS) POLICIES
alter table public.profiles enable row level security;
alter table public.tasks enable row level security;

-- Profiles policies:
drop policy if exists "Profiles are viewable by authenticated users" on public.profiles;
create policy "Profiles are viewable by authenticated users"
  on public.profiles for select
  to authenticated
  using (true);

drop policy if exists "Users can update their own profile or admin can update any" on public.profiles;
create policy "Users can update their own profile or admin can update any"
  on public.profiles for update
  to authenticated
  using (
    auth.uid() = id or
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'admin'
    )
  );

drop policy if exists "Allow profile insertion by authenticated users or triggers" on public.profiles;
create policy "Allow profile insertion by authenticated users or triggers"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id or true);

-- Tasks policies:
drop policy if exists "Tasks are viewable by authenticated users" on public.tasks;
create policy "Tasks are viewable by authenticated users"
  on public.tasks for select
  to authenticated
  using (true);

drop policy if exists "Authenticated users can create tasks" on public.tasks;
create policy "Authenticated users can create tasks"
  on public.tasks for insert
  to authenticated
  with check (true);

drop policy if exists "Authenticated users can update tasks" on public.tasks;
create policy "Authenticated users can update tasks"
  on public.tasks for update
  to authenticated
  using (true);

drop policy if exists "Authenticated users can delete tasks" on public.tasks;
create policy "Authenticated users can delete tasks"
  on public.tasks for delete
  to authenticated
  using (true);
