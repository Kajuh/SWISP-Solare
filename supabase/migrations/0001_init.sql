-- =============================================================================
-- Solare Arena — schema inicial
-- Dashboard de campeonatos 3v3 (Arena of Solare / Black Desert) com ranking ELO.
--
-- Como usar:
--   Supabase > SQL Editor > cole este arquivo inteiro e rode (Run).
--   Depois rode 0002_seed_classes.sql para popular a lista de classes.
-- =============================================================================

-- Necessário para gen_random_uuid()
create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- Tabela de classes do Black Desert (usada no dropdown de cadastro)
-- -----------------------------------------------------------------------------
create table if not exists public.classes (
  name        text primary key,
  sort_order  int not null default 0
);

-- -----------------------------------------------------------------------------
-- Admins: quem pode escrever (registrar partidas, criar jogadores/torneios).
-- O id vem de auth.users (Supabase Auth).
-- -----------------------------------------------------------------------------
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins a where a.user_id = auth.uid());
$$;

-- -----------------------------------------------------------------------------
-- Jogadores
-- -----------------------------------------------------------------------------
create table if not exists public.players (
  id          uuid primary key default gen_random_uuid(),
  nick        text not null unique,
  game_class  text not null references public.classes(name),
  rating      int  not null default 1000,
  wins        int  not null default 0,
  losses      int  not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists players_rating_idx on public.players (rating desc);

-- -----------------------------------------------------------------------------
-- Torneios
-- -----------------------------------------------------------------------------
create table if not exists public.tournaments (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  format      text not null default 'single_elim' check (format in ('single_elim','round_robin')),
  status      text not null default 'draft' check (status in ('draft','active','finished')),
  k_factor    int  not null default 32,
  created_at  timestamptz not null default now()
);

-- Times de um torneio (3 jogadores agrupados com um nome, só dentro do torneio)
create table if not exists public.tournament_teams (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  name          text not null,
  seed          int,
  created_at    timestamptz not null default now()
);

create table if not exists public.tournament_team_members (
  team_id   uuid not null references public.tournament_teams(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  primary key (team_id, player_id)
);

-- -----------------------------------------------------------------------------
-- Partidas (3v3). Avulsas (ranqueadas) têm tournament_id nulo e a escalação
-- vive em match_players. Partidas de torneio referenciam tournament_teams.
-- -----------------------------------------------------------------------------
create table if not exists public.matches (
  id               uuid primary key default gen_random_uuid(),
  tournament_id    uuid references public.tournaments(id) on delete set null,
  bracket_round    int,
  bracket_position int,
  team_a_id        uuid references public.tournament_teams(id) on delete set null,
  team_b_id        uuid references public.tournament_teams(id) on delete set null,
  winner           text check (winner in ('A','B')),
  status           text not null default 'pending' check (status in ('pending','completed')),
  k_factor         int  not null default 32,
  played_at        timestamptz,
  created_at       timestamptz not null default now(),
  created_by       uuid references auth.users(id) on delete set null
);

create index if not exists matches_tournament_idx on public.matches (tournament_id);

-- Escalação + resultado por jogador numa partida
create table if not exists public.match_players (
  id            uuid primary key default gen_random_uuid(),
  match_id      uuid not null references public.matches(id) on delete cascade,
  player_id     uuid not null references public.players(id) on delete cascade,
  team          text not null check (team in ('A','B')),
  rating_before int,
  rating_after  int,
  delta         int,
  unique (match_id, player_id)
);

create index if not exists match_players_player_idx on public.match_players (player_id);

-- Histórico de rating para o gráfico de evolução
create table if not exists public.rating_history (
  id            uuid primary key default gen_random_uuid(),
  player_id     uuid not null references public.players(id) on delete cascade,
  match_id      uuid references public.matches(id) on delete set null,
  rating_before int not null,
  rating_after  int not null,
  delta         int not null,
  created_at    timestamptz not null default now()
);

create index if not exists rating_history_player_idx on public.rating_history (player_id, created_at);

-- =============================================================================
-- Função central: aplica o resultado de uma partida e recalcula o ELO.
--
-- - Roda no servidor (ninguém recalcula no navegador).
-- - É idempotente: se a partida já foi 'completed', levanta erro.
-- - ELO de TIME: usa a média de rating de cada lado; todos do mesmo time
--   recebem o mesmo delta. Favorito que vence ganha pouco; zebra ganha muito.
-- - Se for partida de torneio (tem team_a_id/team_b_id) e ainda não houver
--   escalação em match_players, ela é gerada a partir dos membros dos times.
-- - Para partidas de torneio, avança o vencedor no chaveamento.
-- =============================================================================
create or replace function public.apply_match_result(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  m            public.matches%rowtype;
  avg_a        numeric;
  avg_b        numeric;
  expected_a   numeric;
  expected_b   numeric;
  s_a          numeric;
  s_b          numeric;
  delta_a      int;
  delta_b      int;
  rec          record;
  parent_round int;
  parent_pos   int;
  win_team_id  uuid;
  parent_id    uuid;
begin
  if not public.is_admin() then
    raise exception 'Apenas administradores podem aplicar resultados.';
  end if;

  -- Trava a linha para evitar aplicação concorrente/dupla
  select * into m from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'Partida % não encontrada.', p_match_id;
  end if;
  if m.status = 'completed' then
    raise exception 'Esta partida já foi finalizada.';
  end if;
  if m.winner is null then
    raise exception 'Defina o vencedor (A ou B) antes de aplicar o resultado.';
  end if;

  -- Partida de torneio sem escalação: gera match_players a partir dos times
  if m.team_a_id is not null and not exists (
       select 1 from public.match_players where match_id = m.id
     ) then
    insert into public.match_players (match_id, player_id, team)
    select m.id, tm.player_id, 'A'
    from public.tournament_team_members tm where tm.team_id = m.team_a_id;

    insert into public.match_players (match_id, player_id, team)
    select m.id, tm.player_id, 'B'
    from public.tournament_team_members tm where tm.team_id = m.team_b_id;
  end if;

  -- Médias de rating de cada lado (rating atual do jogador)
  select avg(p.rating) into avg_a
  from public.match_players mp join public.players p on p.id = mp.player_id
  where mp.match_id = m.id and mp.team = 'A';

  select avg(p.rating) into avg_b
  from public.match_players mp join public.players p on p.id = mp.player_id
  where mp.match_id = m.id and mp.team = 'B';

  if avg_a is null or avg_b is null then
    raise exception 'Escalação incompleta: cada lado precisa de ao menos 1 jogador.';
  end if;

  -- ELO
  expected_a := 1.0 / (1.0 + power(10.0, (avg_b - avg_a) / 400.0));
  expected_b := 1.0 - expected_a;
  s_a := case when m.winner = 'A' then 1 else 0 end;
  s_b := 1 - s_a;
  delta_a := round(m.k_factor * (s_a - expected_a));
  delta_b := round(m.k_factor * (s_b - expected_b));

  -- Aplica para cada jogador
  for rec in
    select mp.id as mp_id, mp.player_id, mp.team, p.rating as cur
    from public.match_players mp join public.players p on p.id = mp.player_id
    where mp.match_id = m.id
  loop
    declare
      d        int := case when rec.team = 'A' then delta_a else delta_b end;
      won      boolean := (rec.team = m.winner);
      new_rate int := rec.cur + d;
    begin
      update public.players
        set rating = new_rate,
            wins   = wins   + (case when won then 1 else 0 end),
            losses = losses + (case when won then 0 else 1 end)
        where id = rec.player_id;

      update public.match_players
        set rating_before = rec.cur, rating_after = new_rate, delta = d
        where id = rec.mp_id;

      insert into public.rating_history (player_id, match_id, rating_before, rating_after, delta)
      values (rec.player_id, m.id, rec.cur, new_rate, d);
    end;
  end loop;

  update public.matches
    set status = 'completed', played_at = now()
    where id = m.id;

  -- Avança o vencedor no chaveamento (single elimination)
  if m.tournament_id is not null and m.bracket_round is not null then
    win_team_id := case when m.winner = 'A' then m.team_a_id else m.team_b_id end;
    parent_round := m.bracket_round + 1;
    parent_pos   := m.bracket_position / 2;  -- divisão inteira

    select id into parent_id from public.matches
    where tournament_id = m.tournament_id
      and bracket_round = parent_round
      and bracket_position = parent_pos;

    if parent_id is not null then
      -- posição par -> slot A do pai; ímpar -> slot B
      if (m.bracket_position % 2) = 0 then
        update public.matches set team_a_id = win_team_id where id = parent_id;
      else
        update public.matches set team_b_id = win_team_id where id = parent_id;
      end if;
    end if;
  end if;
end;
$$;

-- =============================================================================
-- Row Level Security: leitura pública, escrita só para admin.
-- =============================================================================
alter table public.classes                 enable row level security;
alter table public.players                  enable row level security;
alter table public.tournaments              enable row level security;
alter table public.tournament_teams         enable row level security;
alter table public.tournament_team_members  enable row level security;
alter table public.matches                  enable row level security;
alter table public.match_players            enable row level security;
alter table public.rating_history           enable row level security;
alter table public.admins                   enable row level security;

-- Leitura pública (ranking aberto a todos, sem login)
do $$
declare t text;
begin
  foreach t in array array[
    'classes','players','tournaments','tournament_teams',
    'tournament_team_members','matches','match_players','rating_history'
  ] loop
    execute format(
      'drop policy if exists "%1$s_read" on public.%1$s;
       create policy "%1$s_read" on public.%1$s for select using (true);', t);
  end loop;
end $$;

-- Escrita só para admin
do $$
declare t text;
begin
  foreach t in array array[
    'classes','players','tournaments','tournament_teams',
    'tournament_team_members','matches','match_players'
  ] loop
    execute format(
      'drop policy if exists "%1$s_write" on public.%1$s;
       create policy "%1$s_write" on public.%1$s for all
         using (public.is_admin()) with check (public.is_admin());', t);
  end loop;
end $$;

-- rating_history é escrito só pela função (security definer); ninguém edita direto
drop policy if exists "rating_history_write" on public.rating_history;
create policy "rating_history_write" on public.rating_history for all
  using (false) with check (false);

-- admins: cada um vê a própria linha (e admins veem todos)
drop policy if exists "admins_read" on public.admins;
create policy "admins_read" on public.admins for select
  using (user_id = auth.uid() or public.is_admin());

-- =============================================================================
-- Realtime: o ranking (LeaderboardView) recarrega ao vivo quando o rating muda.
-- Adiciona a tabela à publicação do Supabase (ignora se já estiver / se rodar
-- fora do Supabase, onde a publicação não existe).
-- =============================================================================
do $$
begin
  alter publication supabase_realtime add table public.players;
exception
  when duplicate_object then null;   -- tabela já está na publicação
  when undefined_object then null;   -- publicação não existe (Postgres fora do Supabase)
end $$;
