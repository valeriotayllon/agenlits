-- ==============================================================================
-- AGENLITS - MIGRATION MESTRE UNIFICADA (20260917000000)
-- ==============================================================================

create extension if not exists btree_gist;
create extension if not exists pgcrypto;

-- 1. TABELA BARBERSHOPS
create table if not exists public.barbershops (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  slug text not null unique,
  phone text,
  document_type text check (document_type in ('cpf', 'cnpj')),
  document_number text,
  avatar_url text,
  photos jsonb default '[]'::jsonb,
  timezone text default 'America/Sao_Paulo' not null,
  created_at timestamptz default timezone('utc'::text, now()) not null
);

create unique index if not exists barbershops_slug_idx on public.barbershops (slug);

-- 2. TABELA SERVICES (PADRONIZADA EM price_cents E SOFT DELETE)
create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  barbershop_id uuid not null references public.barbershops(id) on delete cascade,
  name text not null,
  category text default 'Geral',
  price_cents integer not null check (price_cents >= 0),
  duration_minutes integer not null default 30 check (duration_minutes > 0),
  is_active boolean not null default true,
  created_at timestamptz default timezone('utc'::text, now()) not null
);

create index if not exists idx_services_shop_active on public.services (barbershop_id, is_active);

-- 3. TABELA BARBERS (EXPANDIDA COM LOGIN, HORÁRIO PRÓPRIO E DIAS DE FOLGA)
create table if not exists public.barbers (
  id uuid primary key default gen_random_uuid(),
  barbershop_id uuid not null references public.barbershops(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null unique,
  name text not null,
  phone text,
  commission_percentage numeric(5,2) default 0.00 check (commission_percentage >= 0 and commission_percentage <= 100),
  avatar_url text,
  is_active boolean not null default true,
  work_start time default '08:00',
  work_end time default '19:00',
  off_days integer[] default array[0], -- 0 = Domingo
  created_at timestamptz default timezone('utc'::text, now()) not null
);

create index if not exists idx_barbers_shop_user on public.barbers (barbershop_id, user_id);

-- 4. TABELA BARBER_SERVICES (VÍNCULO DE QUAIS SERVIÇOS CADA PROFISSIONAL EXECUTA)
create table if not exists public.barber_services (
  barber_id uuid not null references public.barbers(id) on delete cascade,
  service_id uuid not null references public.services(id) on delete cascade,
  primary key (barber_id, service_id)
);

-- 5. TABELA BUSINESS_HOURS COM CONSTRAINT ÚNICA
create table if not exists public.business_hours (
  id uuid primary key default gen_random_uuid(),
  barbershop_id uuid not null references public.barbershops(id) on delete cascade,
  day_of_week integer not null check (day_of_week between 0 and 6),
  open_time text not null default '08:00',
  close_time text not null default '19:00',
  is_closed boolean not null default false,
  constraint business_hours_barbershop_day_unique unique (barbershop_id, day_of_week)
);

-- 6. TABELA CLIENTS
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid references auth.users(id) on delete set null,
  name text not null,
  email text,
  phone text,
  created_at timestamptz default timezone('utc'::text, now()) not null
);

-- 7. TABELA TIME_BLOCKS
create table if not exists public.time_blocks (
  id uuid primary key default gen_random_uuid(),
  barbershop_id uuid not null references public.barbershops(id) on delete cascade,
  barber_id uuid references public.barbers(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text,
  created_at timestamptz default timezone('utc'::text, now()) not null
);

-- 8. TABELA APPOINTMENTS COM HISTÓRICO PRESERVADO E RESTRIÇÃO GIST
create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  barbershop_id uuid not null references public.barbershops(id) on delete cascade,
  barber_id uuid references public.barbers(id) on delete set null,
  service_id uuid not null references public.services(id) on delete restrict,
  client_id uuid references public.clients(id) on delete set null,
  client_name text not null,
  client_phone text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  price_cents integer not null check (price_cents >= 0),
  status text not null default 'confirmed' 
    check (status in ('pending', 'confirmed', 'done', 'cancelled', 'no_show')),
  cancellation_reason text,
  notes text,
  created_at timestamptz default timezone('utc'::text, now()) not null,

  constraint no_overlapping_appointments exclude using gist (
    barber_id with =,
    tstzrange(starts_at, ends_at) with &&
  ) where (status in ('pending', 'confirmed'))
);

create index if not exists idx_appointments_shop_starts on public.appointments (barbershop_id, starts_at);
create index if not exists idx_appointments_client on public.appointments (client_id);

-- 9. TABELA BARBERSHOP_PHOTOS
create table if not exists public.barbershop_photos (
  id uuid primary key default gen_random_uuid(),
  barbershop_id uuid not null references public.barbershops(id) on delete cascade,
  url text not null,
  category text default 'Trabalho Realizado',
  caption text,
  created_at timestamptz default timezone('utc'::text, now()) not null
);

-- 10. TABELA PLATFORM_ADMINS
create table if not exists public.platform_admins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade unique,
  created_at timestamptz default timezone('utc'::text, now()) not null
);

-- ==============================================================================
-- BUCKET DE STORAGE UNIFICADO
-- ==============================================================================
insert into storage.buckets (id, name, public)
values ('barbershop-assets', 'barbershop-assets', true)
on conflict (id) do update set public = true;

-- ==============================================================================
-- VIEWS PÚBLICAS SANITIZADAS (LGPD)
-- ==============================================================================
create or replace view public.public_barbershops as
select
  id,
  name,
  slug,
  phone,
  avatar_url,
  photos,
  timezone,
  created_at
from public.barbershops;

grant select on public.public_barbershops to anon, authenticated;

-- ==============================================================================
-- POLÍTICAS RLS (ROW LEVEL SECURITY)
-- ==============================================================================
alter table public.barbershops enable row level security;
alter table public.services enable row level security;
alter table public.barbers enable row level security;
alter table public.barber_services enable row level security;
alter table public.business_hours enable row level security;
alter table public.clients enable row level security;
alter table public.time_blocks enable row level security;
alter table public.appointments enable row level security;
alter table public.barbershop_photos enable row level security;
alter table public.platform_admins enable row level security;

-- Função Helper is_platform_admin
create or replace function public.is_platform_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.platform_admins
    where user_id = auth.uid()
  );
$$;

-- RLS: platform_admins
drop policy if exists "Admin le a si mesmo" on public.platform_admins;
create policy "Admin le a si mesmo" on public.platform_admins for select using (auth.uid() = user_id);

-- RLS: barbershops
drop policy if exists "Dono gerencia sua propria barbearia" on public.barbershops;
drop policy if exists "Dono cadastra barbearia" on public.barbershops;
drop policy if exists "Platform Admin gerencia todas as barbearias" on public.barbershops;

create policy "Dono cadastra barbearia" on public.barbershops for insert with check (owner_id = auth.uid());
create policy "Dono gerencia sua propria barbearia" on public.barbershops for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "Platform Admin gerencia todas as barbearias" on public.barbershops for all using (public.is_platform_admin());

-- RLS: services (Catálogo público lê ativos, dono gerencia)
drop policy if exists "Leitura publica de servicos ativos" on public.services;
drop policy if exists "Dono gerencia seus servicos" on public.services;
create policy "Leitura publica de servicos ativos" on public.services for select using (is_active = true or exists (select 1 from public.barbershops b where b.id = services.barbershop_id and b.owner_id = auth.uid()));
create policy "Dono gerencia seus servicos" on public.services for all using (exists (select 1 from public.barbershops b where b.id = services.barbershop_id and b.owner_id = auth.uid()));

-- RLS: barbers (Dono gerencia, barbeiro logado vê seu perfil)
drop policy if exists "Leitura publica de barbeiros ativos" on public.barbers;
drop policy if exists "Dono gerencia barbeiros" on public.barbers;
drop policy if exists "Barbeiro ve a si mesmo" on public.barbers;
create policy "Leitura publica de barbeiros ativos" on public.barbers for select using (is_active = true or user_id = auth.uid() or exists (select 1 from public.barbershops b where b.id = barbers.barbershop_id and b.owner_id = auth.uid()));
create policy "Dono gerencia barbeiros" on public.barbers for all using (exists (select 1 from public.barbershops b where b.id = barbers.barbershop_id and b.owner_id = auth.uid()));
create policy "Barbeiro ve a si mesmo" on public.barbers for select using (user_id = auth.uid());

-- RLS: barber_services
drop policy if exists "Leitura publica de barber_services" on public.barber_services;
drop policy if exists "Dono gerencia barber_services" on public.barber_services;
create policy "Leitura publica de barber_services" on public.barber_services for select using (true);
create policy "Dono gerencia barber_services" on public.barber_services for all using (exists (select 1 from public.barbers b join public.barbershops s on s.id = b.barbershop_id where b.id = barber_services.barber_id and s.owner_id = auth.uid()));

-- RLS: business_hours
drop policy if exists "Leitura publica business_hours" on public.business_hours;
drop policy if exists "Dono gerencia business_hours" on public.business_hours;
create policy "Leitura publica business_hours" on public.business_hours for select using (true);
create policy "Dono gerencia business_hours" on public.business_hours for all using (exists (select 1 from public.barbershops b where b.id = business_hours.barbershop_id and b.owner_id = auth.uid()));

-- RLS: clients (Isolamento Multi-tenant estrito)
drop policy if exists "Leitura segura e isolada de clientes" on public.clients;
drop policy if exists "Insercao de clientes" on public.clients;
drop policy if exists "Atualizacao de clientes" on public.clients;
create policy "Leitura segura e isolada de clientes" on public.clients for select using (
  (auth.uid() is not null and auth.uid() = auth_user_id)
  or exists (
    select 1 from public.appointments a
    join public.barbershops b on b.id = a.barbershop_id
    where b.owner_id = auth.uid()
      and (a.client_id = clients.id or (clients.phone is not null and clients.phone <> '' and a.client_phone = clients.phone))
  )
  or public.is_platform_admin()
);
create policy "Insercao de clientes" on public.clients for insert with check (auth.uid() = auth_user_id or auth_user_id is null);
create policy "Atualizacao de clientes" on public.clients for update using (auth.uid() = auth_user_id or public.is_platform_admin());

-- RLS: appointments (Dono gerencia, Barbeiro vinculado vê sua agenda, Cliente vê seus agendamentos)
drop policy if exists "Dono gerencia appointments" on public.appointments;
drop policy if exists "Barbeiro ve seus agendamentos" on public.appointments;
drop policy if exists "Cliente ve seus agendamentos" on public.appointments;
revoke insert on public.appointments from anon, authenticated;

create policy "Dono gerencia appointments" on public.appointments for all using (
  exists (select 1 from public.barbershops b where b.id = appointments.barbershop_id and b.owner_id = auth.uid())
  or public.is_platform_admin()
);

create policy "Barbeiro ve seus agendamentos" on public.appointments for select using (
  exists (select 1 from public.barbers b where b.id = appointments.barber_id and b.user_id = auth.uid())
);

create policy "Cliente ve seus agendamentos" on public.appointments for select using (
  exists (select 1 from public.clients c where c.id = appointments.client_id and c.auth_user_id = auth.uid())
);

-- RLS: Storage (Isolado pelo auth.uid())
drop policy if exists "Leitura publica de assets" on storage.objects;
drop policy if exists "Dono faz upload em sua pasta" on storage.objects;
drop policy if exists "Dono altera seus arquivos" on storage.objects;
drop policy if exists "Dono deleta seus arquivos" on storage.objects;

create policy "Leitura publica de assets" on storage.objects for select using (bucket_id = 'barbershop-assets');
create policy "Dono faz upload em sua pasta" on storage.objects for insert with check (bucket_id = 'barbershop-assets' and auth.role() = 'authenticated' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Dono altera seus arquivos" on storage.objects for update using (bucket_id = 'barbershop-assets' and auth.role() = 'authenticated' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Dono deleta seus arquivos" on storage.objects for delete using (bucket_id = 'barbershop-assets' and auth.role() = 'authenticated' and (storage.foldername(name))[1] = auth.uid()::text);

-- ==============================================================================
-- TRIGGER PARA CONFIRMAÇÃO DE E-MAIL E CADASTRO SEGURO AUTOMÁTICO
-- ==============================================================================
create or replace function public.handle_new_shop_owner()
returns trigger
language plpgsql
security definer
as $$
declare
  v_shop_name text;
  v_shop_slug text;
  v_phone text;
  v_doc_type text;
  v_doc_num text;
begin
  v_shop_name := new.raw_user_meta_data->>'barbershop_name';
  v_shop_slug := new.raw_user_meta_data->>'barbershop_slug';
  v_phone := new.raw_user_meta_data->>'phone';
  v_doc_type := new.raw_user_meta_data->>'document_type';
  v_doc_num := new.raw_user_meta_data->>'document_number';

  if v_shop_name is not null and v_shop_slug is not null then
    insert into public.barbershops (
      owner_id, name, slug, phone, document_type, document_number, timezone
    ) values (
      new.id, v_shop_name, v_shop_slug, v_phone, v_doc_type, v_doc_num, 'America/Sao_Paulo'
    )
    on conflict (slug) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_shop on auth.users;
create trigger on_auth_user_created_shop
  after insert on auth.users
  for each row execute function public.handle_new_shop_owner();

-- ==============================================================================
-- RPC: VALIDAÇÃO DE SLUG EM TEMPO REAL
-- ==============================================================================
create or replace function public.check_slug_available(
  p_slug text,
  p_current_shop_id uuid default null
)
returns jsonb
language plpgsql
security definer
stable
as $$
declare
  v_reserved text[] := array['admin', 'login', 'api', 'painel', 'explorar', 'agendar', 'cliente', 'servicos', 'fotos', 'horarios', 'barbeiros', 'cadastro', 'perfil'];
  v_clean_slug text;
  v_exists boolean;
begin
  v_clean_slug := lower(trim(p_slug));

  if v_clean_slug = any(v_reserved) then
    return jsonb_build_object('available', false, 'reason', 'Este link é reservado pelo sistema.');
  end if;

  if length(v_clean_slug) < 3 then
    return jsonb_build_object('available', false, 'reason', 'O link deve ter no mínimo 3 caracteres.');
  end if;

  select exists (
    select 1 from public.barbershops
    where slug = v_clean_slug
      and (p_current_shop_id is null or id <> p_current_shop_id)
  ) into v_exists;

  if v_exists then
    return jsonb_build_object('available', false, 'reason', 'Este link já está em uso por outro estabelecimento.');
  end if;

  return jsonb_build_object('available', true, 'slug', v_clean_slug);
end;
$$;

grant execute on function public.check_slug_available(text, uuid) to anon, authenticated;

-- ==============================================================================
-- RPC: ATUALIZAÇÃO DO CICLO DE VIDA DO AGENDAMENTO
-- ==============================================================================
create or replace function public.change_appointment_status(
  p_appointment_id uuid,
  p_new_status text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_shop_id uuid;
  v_client_id uuid;
  v_client_phone text;
  v_current_status text;
begin
  if p_new_status not in ('pending', 'confirmed', 'done', 'cancelled', 'no_show') then
    raise exception 'Status inválido informado: %', p_new_status;
  end if;

  select barbershop_id, client_id, client_phone, status
    into v_shop_id, v_client_id, v_client_phone, v_current_status
  from public.appointments
  where id = p_appointment_id;

  if not found then
    raise exception 'Agendamento não encontrado.';
  end if;

  if not (
    exists (select 1 from public.barbershops b where b.id = v_shop_id and b.owner_id = auth.uid())
    or public.is_platform_admin()
    or (
      p_new_status = 'cancelled' and exists (
        select 1 from public.clients c where c.id = v_client_id and c.auth_user_id = auth.uid()
      )
    )
  ) then
    raise exception 'Permissão negada para alterar o status deste agendamento.';
  end if;

  update public.appointments
  set status = p_new_status,
      cancellation_reason = coalesce(p_reason, cancellation_reason)
  where id = p_appointment_id;

  return jsonb_build_object('success', true, 'new_status', p_new_status);
end;
$$;

grant execute on function public.change_appointment_status(uuid, text, text) to anon, authenticated;

-- ==============================================================================
-- RPC: DISPONIBILIDADE REAL REFINADA (barber_services + duration)
-- ==============================================================================
create or replace function public.get_available_slots(
  p_shop_id uuid,
  p_barber_id uuid,
  p_service_id uuid,
  p_date date
)
returns table (
  slot_time text
)
language plpgsql
security definer
stable
as $$
declare
  v_dow int;
  v_is_closed boolean;
  v_open_time time;
  v_close_time time;
  v_duration int;
  v_tz text;
  v_curr_slot_start timestamptz;
  v_curr_slot_end timestamptz;
  v_day_close_ts timestamptz;
  v_now_ts timestamptz;
  v_slot_step interval := interval '30 minutes';
begin
  select coalesce(timezone, 'America/Sao_Paulo') into v_tz
  from public.barbershops where id = p_shop_id;

  if v_tz is null then v_tz := 'America/Sao_Paulo'; end if;

  select coalesce(duration_minutes, 30) into v_duration
  from public.services
  where id = p_service_id and barbershop_id = p_shop_id and is_active = true;

  if v_duration is null then v_duration := 30; end if;

  v_dow := extract(dow from p_date);

  select is_closed, open_time::time, close_time::time
    into v_is_closed, v_open_time, v_close_time
  from public.business_hours
  where barbershop_id = p_shop_id and day_of_week = v_dow;

  if v_is_closed is null then
    if v_dow = 0 then
      v_is_closed := true;
    else
      v_is_closed := false;
      v_open_time := '08:00'::time;
      v_close_time := '19:00'::time;
    end if;
  end if;

  if v_is_closed or v_open_time is null or v_close_time is null then
    return;
  end if;

  v_curr_slot_start := (p_date || ' ' || v_open_time)::timestamp at time zone v_tz;
  v_day_close_ts := (p_date || ' ' || v_close_time)::timestamp at time zone v_tz;
  v_now_ts := now() at time zone v_tz;

  if v_duration < 30 then
    v_slot_step := (v_duration || ' minutes')::interval;
  end if;

  while (v_curr_slot_start + (v_duration || ' minutes')::interval) <= v_day_close_ts loop
    v_curr_slot_end := v_curr_slot_start + (v_duration || ' minutes')::interval;

    if (v_curr_slot_start <= (v_now_ts + interval '10 minutes')) and (p_date = (v_now_ts::date)) then
      v_curr_slot_start := v_curr_slot_start + v_slot_step;
      continue;
    end if;

    if exists (
      select 1 from public.time_blocks tb
      where tb.barbershop_id = p_shop_id
        and (p_barber_id is null or tb.barber_id is null or tb.barber_id = p_barber_id)
        and tstzrange(tb.starts_at, tb.ends_at) && tstzrange(v_curr_slot_start, v_curr_slot_end)
    ) then
      v_curr_slot_start := v_curr_slot_start + v_slot_step;
      continue;
    end if;

    if p_barber_id is not null then
      if exists (
        select 1 from public.appointments a
        where a.barbershop_id = p_shop_id
          and a.barber_id = p_barber_id
          and a.status in ('confirmed', 'pending')
          and tstzrange(a.starts_at, a.ends_at) && tstzrange(v_curr_slot_start, v_curr_slot_end)
      ) then
        v_curr_slot_start := v_curr_slot_start + v_slot_step;
        continue;
      end if;
    else
      if exists (
        select 1 from public.barbers b
        where b.barbershop_id = p_shop_id
          and b.is_active = true
          and (v_dow <> any(coalesce(b.off_days, array[]::integer[])))
          and (
            not exists (select 1 from public.barber_services bs where bs.barber_id = b.id)
            or exists (select 1 from public.barber_services bs where bs.barber_id = b.id and bs.service_id = p_service_id)
          )
          and not exists (
            select 1 from public.appointments a
            where a.barber_id = b.id
              and a.status in ('confirmed', 'pending')
              and tstzrange(a.starts_at, a.ends_at) && tstzrange(v_curr_slot_start, v_curr_slot_end)
          )
      ) then
        slot_time := to_char(v_curr_slot_start at time zone v_tz, 'HH24:MI');
        return next;
      else
        v_curr_slot_start := v_curr_slot_start + v_slot_step;
        continue;
      end if;
    end if;

    slot_time := to_char(v_curr_slot_start at time zone v_tz, 'HH24:MI');
    return next;

    v_curr_slot_start := v_curr_slot_start + v_slot_step;
  end loop;

  return;
end;
$$;

grant execute on function public.get_available_slots(uuid, uuid, uuid, date) to anon, authenticated;

-- ==============================================================================
-- RPC: CRIAÇÃO SEGURA COM PREÇO EM CENTAVOS E ALOCAÇÃO INTELIGENTE
-- ==============================================================================
create or replace function public.book_appointment(
  p_barbershop_id uuid,
  p_barber_id uuid,
  p_service_id uuid,
  p_client_name text,
  p_client_phone text,
  p_starts_at timestamptz,
  p_client_id uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_duration int;
  v_price_cents int;
  v_ends_at timestamptz;
  v_assigned_barber_id uuid := p_barber_id;
  v_appointment_id uuid;
  v_dow int;
begin
  if p_client_name is null or trim(p_client_name) = '' then
    raise exception 'O nome do cliente é obrigatório.';
  end if;

  if p_client_phone is null or trim(p_client_phone) = '' then
    raise exception 'O WhatsApp do cliente é obrigatório.';
  end if;

  select coalesce(duration_minutes, 30), price_cents
    into v_duration, v_price_cents
  from public.services
  where id = p_service_id and barbershop_id = p_barbershop_id and is_active = true;

  if not found then
    raise exception 'Serviço não encontrado ou inativo no estabelecimento.';
  end if;

  v_ends_at := p_starts_at + (v_duration || ' minutes')::interval;
  v_dow := extract(dow from p_starts_at);

  if v_assigned_barber_id is null then
    select b.id into v_assigned_barber_id
    from public.barbers b
    where b.barbershop_id = p_barbershop_id
      and b.is_active = true
      and (v_dow <> any(coalesce(b.off_days, array[]::integer[])))
      and (
        not exists (select 1 from public.barber_services bs where bs.barber_id = b.id)
        or exists (select 1 from public.barber_services bs where bs.barber_id = b.id and bs.service_id = p_service_id)
      )
      and not exists (
        select 1 from public.appointments a
        where a.barber_id = b.id
          and a.status in ('confirmed', 'pending')
          and tstzrange(a.starts_at, a.ends_at) && tstzrange(p_starts_at, v_ends_at)
      )
      and not exists (
        select 1 from public.time_blocks tb
        where tb.barbershop_id = p_barbershop_id
          and (tb.barber_id is null or tb.barber_id = b.id)
          and tstzrange(tb.starts_at, tb.ends_at) && tstzrange(p_starts_at, v_ends_at)
      )
    order by random()
    limit 1;

    if v_assigned_barber_id is null and exists (
      select 1 from public.barbers where barbershop_id = p_barbershop_id and is_active = true
    ) then
      raise exception 'Nenhum profissional disponível para este serviço neste horário.';
    end if;
  end if;

  if exists (
    select 1 from public.time_blocks tb
    where tb.barbershop_id = p_barbershop_id
      and (tb.barber_id is null or v_assigned_barber_id is null or tb.barber_id = v_assigned_barber_id)
      and tstzrange(tb.starts_at, tb.ends_at) && tstzrange(p_starts_at, v_ends_at)
  ) then
    raise exception 'Este horário coincide com um bloqueio ou intervalo de atendimento.';
  end if;

  insert into public.appointments (
    barbershop_id,
    barber_id,
    service_id,
    client_id,
    client_name,
    client_phone,
    starts_at,
    ends_at,
    price_cents,
    notes,
    status
  ) values (
    p_barbershop_id,
    v_assigned_barber_id,
    p_service_id,
    p_client_id,
    p_client_name,
    p_client_phone,
    p_starts_at,
    v_ends_at,
    v_price_cents,
    p_notes,
    'confirmed'
  )
  returning id into v_appointment_id;

  return jsonb_build_object(
    'success', true,
    'appointment_id', v_appointment_id,
    'barber_id', v_assigned_barber_id,
    'price_cents', v_price_cents,
    'starts_at', p_starts_at,
    'ends_at', v_ends_at
  );
exception
  when exclusion_violation then
    raise exception 'Este horário acabou de ser reservado por outro cliente. Por favor, escolha outro momento.';
end;
$$;

grant execute on function public.book_appointment(uuid, uuid, uuid, text, text, timestamptz, uuid, text) to anon, authenticated;
