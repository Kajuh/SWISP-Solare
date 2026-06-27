-- =============================================================================
-- Solare Arena — mudanças:
--   1. Especialização (sucessao/awakening/ascensao) + auto-cadastro público
--   2. Participantes do torneio -> times aleatórios (ou manuais) -> chave aleatória
--   3. Bo5: guarda os rounds e dá bônus de pontos por round vencido
--
-- Rode este arquivo no SQL Editor DEPOIS dos 0001/0002/0003.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Especialização do jogador + auto-cadastro público
-- ---------------------------------------------------------------------------
alter table public.players
  add column if not exists specialization text
  check (specialization in ('sucessao','awakening','ascensao'));

-- Cadastro feito pelo próprio jogador (sem login). Roda como SECURITY DEFINER,
-- então controla exatamente o que entra: rating sempre 1000, sem trapaça.
create or replace function public.register_player(
  p_nick text, p_class text, p_spec text
) returns uuid language plpgsql security definer set search_path = public
as $$
declare new_id uuid;
begin
  if p_nick is null or length(trim(p_nick)) = 0 then
    raise exception 'Informe o nick.';
  end if;
  if p_spec not in ('sucessao','awakening','ascensao') then
    raise exception 'Especialização inválida.';
  end if;
  if not exists (select 1 from public.classes where name = p_class) then
    raise exception 'Classe inválida.';
  end if;

  insert into public.players (nick, game_class, specialization, rating, wins, losses)
    values (trim(p_nick), p_class, p_spec, 1000, 0, 0)
    returning id into new_id;
  return new_id;
exception when unique_violation then
  raise exception 'Já existe um jogador com esse nick.';
end;
$$;

grant execute on function public.register_player(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Bo5 + pontos por round
-- ---------------------------------------------------------------------------
alter table public.tournaments
  add column if not exists round_point int not null default 5;

alter table public.matches
  add column if not exists best_of     int not null default 5,
  add column if not exists rounds_a    int not null default 0,
  add column if not exists rounds_b    int not null default 0,
  add column if not exists round_point int not null default 5;

-- Resultado de cada round (placar detalhado do Bo5)
create table if not exists public.match_rounds (
  match_id uuid not null references public.matches(id) on delete cascade,
  round_no int  not null,
  winner   text not null check (winner in ('A','B')),
  primary key (match_id, round_no)
);

-- ---------------------------------------------------------------------------
-- 3. Participantes do torneio (pool de jogadores antes de formar os times)
-- ---------------------------------------------------------------------------
create table if not exists public.tournament_participants (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  player_id     uuid not null references public.players(id) on delete cascade,
  primary key (tournament_id, player_id)
);

-- ---------------------------------------------------------------------------
-- RLS das tabelas novas: leitura pública, escrita só admin
-- ---------------------------------------------------------------------------
alter table public.match_rounds            enable row level security;
alter table public.tournament_participants enable row level security;

do $$ declare t text;
begin
  foreach t in array array['match_rounds','tournament_participants'] loop
    execute format('drop policy if exists "%1$s_read" on public.%1$s;
       create policy "%1$s_read" on public.%1$s for select using (true);', t);
    execute format('drop policy if exists "%1$s_write" on public.%1$s;
       create policy "%1$s_write" on public.%1$s for all
         using (public.is_admin()) with check (public.is_admin());', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Recalcula o ELO: ELO da partida (média dos times) + bônus por round vencido
-- ---------------------------------------------------------------------------
create or replace function public.apply_match_result(p_match_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare
  m public.matches%rowtype;
  avg_a numeric; avg_b numeric; expected_a numeric; expected_b numeric;
  s_a numeric; s_b numeric; base_a int; base_b int; rec record;
  parent_round int; parent_pos int; win_team_id uuid; parent_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Apenas administradores podem aplicar resultados.';
  end if;

  select * into m from public.matches where id = p_match_id for update;
  if not found then raise exception 'Partida % não encontrada.', p_match_id; end if;
  if m.status = 'completed' then raise exception 'Esta partida já foi finalizada.'; end if;
  if m.winner is null then raise exception 'Defina o resultado antes de aplicar.'; end if;

  -- Partida de torneio sem escalação: gera a partir dos membros dos times
  if m.team_a_id is not null and not exists (select 1 from public.match_players where match_id = m.id) then
    insert into public.match_players (match_id, player_id, team)
    select m.id, tm.player_id, 'A' from public.tournament_team_members tm where tm.team_id = m.team_a_id;
    insert into public.match_players (match_id, player_id, team)
    select m.id, tm.player_id, 'B' from public.tournament_team_members tm where tm.team_id = m.team_b_id;
  end if;

  select avg(p.rating) into avg_a from public.match_players mp
    join public.players p on p.id = mp.player_id where mp.match_id = m.id and mp.team = 'A';
  select avg(p.rating) into avg_b from public.match_players mp
    join public.players p on p.id = mp.player_id where mp.match_id = m.id and mp.team = 'B';
  if avg_a is null or avg_b is null then
    raise exception 'Escalação incompleta: cada lado precisa de ao menos 1 jogador.';
  end if;

  -- componente ELO (vitória/derrota pela média dos times)
  expected_a := 1.0 / (1.0 + power(10.0, (avg_b - avg_a) / 400.0));
  expected_b := 1.0 - expected_a;
  s_a := case when m.winner = 'A' then 1 else 0 end;
  s_b := 1 - s_a;
  base_a := round(m.k_factor * (s_a - expected_a));
  base_b := round(m.k_factor * (s_b - expected_b));

  for rec in
    select mp.id as mp_id, mp.player_id, mp.team, p.rating as cur
    from public.match_players mp join public.players p on p.id = mp.player_id
    where mp.match_id = m.id
  loop
    declare
      -- ELO da partida + (pontos por round) x (rounds vencidos pelo time)
      d int := (case when rec.team = 'A' then base_a else base_b end)
             + (m.round_point * (case when rec.team = 'A' then m.rounds_a else m.rounds_b end));
      won boolean := (rec.team = m.winner);
      new_rate int := rec.cur + d;
    begin
      update public.players set rating = new_rate,
        wins = wins + (case when won then 1 else 0 end),
        losses = losses + (case when won then 0 else 1 end)
      where id = rec.player_id;
      update public.match_players set rating_before = rec.cur, rating_after = new_rate, delta = d
        where id = rec.mp_id;
      insert into public.rating_history (player_id, match_id, rating_before, rating_after, delta)
        values (rec.player_id, m.id, rec.cur, new_rate, d);
    end;
  end loop;

  update public.matches set status = 'completed', played_at = now() where id = m.id;

  -- avança o vencedor no chaveamento
  if m.tournament_id is not null and m.bracket_round is not null then
    win_team_id := case when m.winner = 'A' then m.team_a_id else m.team_b_id end;
    parent_round := m.bracket_round + 1;
    parent_pos := m.bracket_position / 2;
    select id into parent_id from public.matches
      where tournament_id = m.tournament_id and bracket_round = parent_round and bracket_position = parent_pos;
    if parent_id is not null then
      if (m.bracket_position % 2) = 0 then
        update public.matches set team_a_id = win_team_id where id = parent_id;
      else
        update public.matches set team_b_id = win_team_id where id = parent_id;
      end if;
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Registrar partida avulsa (Bo5). Recebe o vencedor de cada round em ordem,
-- ex.: ARRAY['A','B','A','A']  -> 3 x 1 para o time A.
-- ---------------------------------------------------------------------------
drop function if exists public.create_ranked_match(uuid[], uuid[], text, int);
create or replace function public.create_ranked_match(
  p_team_a uuid[], p_team_b uuid[], p_round_winners text[],
  p_k int default 32, p_round_point int default 5
) returns uuid language plpgsql security definer set search_path = public
as $$
declare new_id uuid; pid uuid; ra int; rb int; rno int;
begin
  if not public.is_admin() then raise exception 'Apenas administradores podem registrar partidas.'; end if;
  if array_length(p_team_a,1) is null or array_length(p_team_b,1) is null then
    raise exception 'Cada time precisa de ao menos um jogador.';
  end if;
  if p_team_a && p_team_b then raise exception 'Um jogador não pode estar nos dois times.'; end if;

  ra := (select count(*) from unnest(p_round_winners) x where x = 'A');
  rb := (select count(*) from unnest(p_round_winners) x where x = 'B');
  if ra = rb then raise exception 'O placar não pode terminar empatado.'; end if;

  insert into public.matches (winner, rounds_a, rounds_b, k_factor, round_point, best_of, status, created_by)
    values (case when ra > rb then 'A' else 'B' end, ra, rb, p_k, p_round_point, 5, 'pending', auth.uid())
    returning id into new_id;

  foreach pid in array p_team_a loop
    insert into public.match_players (match_id, player_id, team) values (new_id, pid, 'A');
  end loop;
  foreach pid in array p_team_b loop
    insert into public.match_players (match_id, player_id, team) values (new_id, pid, 'B');
  end loop;

  for rno in 1..coalesce(array_length(p_round_winners,1),0) loop
    insert into public.match_rounds (match_id, round_no, winner) values (new_id, rno, p_round_winners[rno]);
  end loop;

  perform public.apply_match_result(new_id);
  return new_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lançar resultado de uma partida JÁ existente (usado no chaveamento do torneio)
-- ---------------------------------------------------------------------------
create or replace function public.set_match_result(p_match_id uuid, p_round_winners text[])
returns void language plpgsql security definer set search_path = public
as $$
declare ra int; rb int; rno int;
begin
  if not public.is_admin() then raise exception 'Apenas administradores.'; end if;
  ra := (select count(*) from unnest(p_round_winners) x where x = 'A');
  rb := (select count(*) from unnest(p_round_winners) x where x = 'B');
  if ra = rb then raise exception 'O placar não pode terminar empatado.'; end if;

  delete from public.match_rounds where match_id = p_match_id;
  for rno in 1..coalesce(array_length(p_round_winners,1),0) loop
    insert into public.match_rounds (match_id, round_no, winner) values (p_match_id, rno, p_round_winners[rno]);
  end loop;

  update public.matches
    set rounds_a = ra, rounds_b = rb, winner = case when ra > rb then 'A' else 'B' end
    where id = p_match_id;

  perform public.apply_match_result(p_match_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Formar times automaticamente (aleatório) a partir dos participantes.
-- p_team_size = 3 (3v3). Sobra vira um time menor (ajuste manual se quiser).
-- ---------------------------------------------------------------------------
create or replace function public.form_teams_random(p_tournament_id uuid, p_team_size int default 3)
returns void language plpgsql security definer set search_path = public
as $$
declare ids uuid[]; n int; i int; team_no int := 0; team_id uuid;
begin
  if not public.is_admin() then raise exception 'Apenas administradores.'; end if;
  if exists (select 1 from public.matches where tournament_id = p_tournament_id) then
    raise exception 'O chaveamento já foi gerado; não dá pra refazer os times.';
  end if;

  delete from public.tournament_teams where tournament_id = p_tournament_id;

  select array_agg(player_id order by random()) into ids
    from public.tournament_participants where tournament_id = p_tournament_id;
  n := coalesce(array_length(ids,1), 0);
  if n < p_team_size then raise exception 'Participantes insuficientes para formar um time.'; end if;

  i := 1;
  while i <= n loop
    if ((i - 1) % p_team_size) = 0 then
      team_no := team_no + 1;
      insert into public.tournament_teams (tournament_id, name, seed)
        values (p_tournament_id, 'Time ' || team_no, team_no)
        returning id into team_id;
    end if;
    insert into public.tournament_team_members (team_id, player_id) values (team_id, ids[i]);
    i := i + 1;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Gera o chaveamento. p_shuffle = true (padrão) embaralha os times;
-- false respeita a ordem de seed (montagem manual).
-- ---------------------------------------------------------------------------
drop function if exists public.generate_bracket(uuid);
create or replace function public.generate_bracket(p_tournament_id uuid, p_shuffle boolean default true)
returns void language plpgsql security definer set search_path = public
as $$
declare
  n int; sz int := 1; rounds int := 0; r int; num int; pos int;
  team_ids uuid[]; parent uuid;
begin
  if not public.is_admin() then raise exception 'Apenas administradores podem gerar o chaveamento.'; end if;
  if exists (select 1 from public.matches where tournament_id = p_tournament_id) then
    raise exception 'Este torneio já tem partidas geradas.';
  end if;

  if p_shuffle then
    select array_agg(id order by random()) into team_ids
      from public.tournament_teams where tournament_id = p_tournament_id;
  else
    select array_agg(id order by coalesce(seed, 1000000), created_at) into team_ids
      from public.tournament_teams where tournament_id = p_tournament_id;
  end if;

  n := coalesce(array_length(team_ids,1), 0);
  if n < 2 then raise exception 'Forme ao menos 2 times antes de gerar o chaveamento.'; end if;

  while sz < n loop sz := sz * 2; end loop;
  while (2 ^ rounds) < sz loop rounds := rounds + 1; end loop;

  for r in 1..rounds loop
    num := sz / (2 ^ r);
    for pos in 0..(num - 1) loop
      insert into public.matches (tournament_id, bracket_round, bracket_position, k_factor, round_point, status)
      select p_tournament_id, r, pos, t.k_factor, t.round_point, 'pending'
      from public.tournaments t where t.id = p_tournament_id;
    end loop;
  end loop;

  for r in 1..n loop
    declare k int := r - 1; mpos int := (r - 1) / 2; tid uuid := team_ids[r];
    begin
      if (k % 2) = 0 then
        update public.matches set team_a_id = tid
          where tournament_id = p_tournament_id and bracket_round = 1 and bracket_position = mpos;
      else
        update public.matches set team_b_id = tid
          where tournament_id = p_tournament_id and bracket_round = 1 and bracket_position = mpos;
      end if;
    end;
  end loop;

  -- byes (time sozinho avança sem alterar ELO)
  for r in 0..(sz / 2 - 1) loop
    declare m_id uuid; a_id uuid; b_id uuid; win_id uuid; ppos int := r / 2;
    begin
      select id, team_a_id, team_b_id into m_id, a_id, b_id from public.matches
        where tournament_id = p_tournament_id and bracket_round = 1 and bracket_position = r;
      if (a_id is null) <> (b_id is null) then
        win_id := coalesce(a_id, b_id);
        update public.matches set status = 'completed',
            winner = case when a_id is not null then 'A' else 'B' end, played_at = now()
          where id = m_id;
        select id into parent from public.matches
          where tournament_id = p_tournament_id and bracket_round = 2 and bracket_position = ppos;
        if parent is not null then
          if (r % 2) = 0 then update public.matches set team_a_id = win_id where id = parent;
          else update public.matches set team_b_id = win_id where id = parent; end if;
        end if;
      end if;
    end;
  end loop;

  update public.tournaments set status = 'active' where id = p_tournament_id;
end;
$$;
