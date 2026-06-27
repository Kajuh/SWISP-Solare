-- =============================================================================
-- Solare Arena — mudanças:
--   1. Pontuação FIXA (não é mais ELO):
--        Vitória: +win_points (padrão 20) para cada jogador do time
--        Derrota: -loss_points + round_point * (rounds vencidos)  (padrão -20, +5/round)
--   2. Evento = partidas 3v3 aleatórias e independentes (sem chaveamento):
--        draw_random_match() sorteia 6 participantes em 2 times de 3,
--        SEM repetir classe dentro do mesmo time.
--
-- Rode no SQL Editor DEPOIS dos 0001..0004.
-- =============================================================================

-- Config de pontuação por evento e por partida
alter table public.tournaments
  add column if not exists win_points  int not null default 20,
  add column if not exists loss_points int not null default 20;

alter table public.matches
  add column if not exists win_points  int not null default 20,
  add column if not exists loss_points int not null default 20;

-- ---------------------------------------------------------------------------
-- Recalcula a pontuação (fixa) de uma partida.
--   vencedor: +win_points    |    perdedor: -loss_points + round_point*rounds_vencidos
-- Rating nunca fica negativo (piso em 0).
-- ---------------------------------------------------------------------------
create or replace function public.apply_match_result(p_match_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare
  m public.matches%rowtype;
  rec record;
  parent_round int; parent_pos int; win_team_id uuid; parent_id uuid;
begin
  if not public.is_admin() then raise exception 'Apenas administradores podem aplicar resultados.'; end if;

  select * into m from public.matches where id = p_match_id for update;
  if not found then raise exception 'Partida % não encontrada.', p_match_id; end if;
  if m.status = 'completed' then raise exception 'Esta partida já foi finalizada.'; end if;
  if m.winner is null then raise exception 'Defina o resultado antes de aplicar.'; end if;

  -- (legado) partida com times de bracket sem escalação: popula de tournament_team_members
  if m.team_a_id is not null and not exists (select 1 from public.match_players where match_id = m.id) then
    insert into public.match_players (match_id, player_id, team)
    select m.id, tm.player_id, 'A' from public.tournament_team_members tm where tm.team_id = m.team_a_id;
    insert into public.match_players (match_id, player_id, team)
    select m.id, tm.player_id, 'B' from public.tournament_team_members tm where tm.team_id = m.team_b_id;
  end if;

  for rec in
    select mp.id as mp_id, mp.player_id, mp.team, p.rating as cur
    from public.match_players mp join public.players p on p.id = mp.player_id
    where mp.match_id = m.id
  loop
    declare
      won boolean := (rec.team = m.winner);
      loser_rounds int := case when rec.team = 'A' then m.rounds_a else m.rounds_b end;
      d int := case when won
                    then m.win_points
                    else (-m.loss_points + m.round_point * loser_rounds) end;
      new_rate int := greatest(rec.cur + d, 0);
    begin
      update public.players set rating = new_rate,
        wins = wins + (case when won then 1 else 0 end),
        losses = losses + (case when won then 0 else 1 end)
      where id = rec.player_id;
      update public.match_players set rating_before = rec.cur, rating_after = new_rate, delta = (new_rate - rec.cur)
        where id = rec.mp_id;
      insert into public.rating_history (player_id, match_id, rating_before, rating_after, delta)
        values (rec.player_id, m.id, rec.cur, new_rate, (new_rate - rec.cur));
    end;
  end loop;

  update public.matches set status = 'completed', played_at = now() where id = m.id;

  -- (legado) avanço de bracket, se a partida fizer parte de um
  if m.tournament_id is not null and m.bracket_round is not null then
    win_team_id := case when m.winner = 'A' then m.team_a_id else m.team_b_id end;
    parent_round := m.bracket_round + 1; parent_pos := m.bracket_position / 2;
    select id into parent_id from public.matches
      where tournament_id = m.tournament_id and bracket_round = parent_round and bracket_position = parent_pos;
    if parent_id is not null then
      if (m.bracket_position % 2) = 0 then update public.matches set team_a_id = win_team_id where id = parent_id;
      else update public.matches set team_b_id = win_team_id where id = parent_id; end if;
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Partida avulsa (Bo5) — pontuação fixa
-- ---------------------------------------------------------------------------
drop function if exists public.create_ranked_match(uuid[], uuid[], text[], int, int);
create or replace function public.create_ranked_match(
  p_team_a uuid[], p_team_b uuid[], p_round_winners text[],
  p_win_points int default 20, p_loss_points int default 20, p_round_point int default 5
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

  insert into public.matches (winner, rounds_a, rounds_b, win_points, loss_points, round_point, best_of, status, created_by)
    values (case when ra > rb then 'A' else 'B' end, ra, rb, p_win_points, p_loss_points, p_round_point, 5, 'pending', auth.uid())
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
-- Sorteia a próxima partida 3v3 de um evento, a partir dos participantes.
-- Totalmente aleatório, mas SEM repetir classe dentro do mesmo time.
-- Só pode haver uma partida pendente por vez (lance o resultado antes de sortear outra).
-- ---------------------------------------------------------------------------
create or replace function public.draw_random_match(p_tournament_id uuid, p_team_size int default 3)
returns uuid language plpgsql security definer set search_path = public
as $$
declare
  rec record;
  team_a uuid[] := '{}'; team_b uuid[] := '{}';
  cls_a text[] := '{}'; cls_b text[] := '{}';
  new_id uuid; pid uuid; wp int; lp int; rp int; total int;
begin
  if not public.is_admin() then raise exception 'Apenas administradores.'; end if;
  if exists (select 1 from public.matches where tournament_id = p_tournament_id and status = 'pending') then
    raise exception 'Finalize a partida atual antes de sortear outra.';
  end if;

  select count(*) into total from public.tournament_participants where tournament_id = p_tournament_id;
  if total < (p_team_size * 2) then
    raise exception 'Participantes insuficientes: precisa de pelo menos % para uma partida.', p_team_size * 2;
  end if;

  -- monta dois times, preferindo o A, sem repetir classe dentro de cada time
  for rec in
    select p.id, p.game_class
    from public.tournament_participants tp join public.players p on p.id = tp.player_id
    where tp.tournament_id = p_tournament_id
    order by random()
  loop
    if coalesce(array_length(team_a,1),0) < p_team_size and not (rec.game_class = any(cls_a)) then
      team_a := array_append(team_a, rec.id); cls_a := array_append(cls_a, rec.game_class);
    elsif coalesce(array_length(team_b,1),0) < p_team_size and not (rec.game_class = any(cls_b)) then
      team_b := array_append(team_b, rec.id); cls_b := array_append(cls_b, rec.game_class);
    end if;
    exit when coalesce(array_length(team_a,1),0) = p_team_size and coalesce(array_length(team_b,1),0) = p_team_size;
  end loop;

  if coalesce(array_length(team_a,1),0) < p_team_size or coalesce(array_length(team_b,1),0) < p_team_size then
    raise exception 'Não consegui montar 2 times de % sem repetir classe. Adicione mais participantes ou mais variedade de classes.', p_team_size;
  end if;

  select win_points, loss_points, round_point into wp, lp, rp
    from public.tournaments where id = p_tournament_id;

  insert into public.matches (tournament_id, win_points, loss_points, round_point, best_of, status, created_by)
    values (p_tournament_id, wp, lp, rp, 5, 'pending', auth.uid())
    returning id into new_id;

  foreach pid in array team_a loop
    insert into public.match_players (match_id, player_id, team) values (new_id, pid, 'A');
  end loop;
  foreach pid in array team_b loop
    insert into public.match_players (match_id, player_id, team) values (new_id, pid, 'B');
  end loop;

  return new_id;
end;
$$;
