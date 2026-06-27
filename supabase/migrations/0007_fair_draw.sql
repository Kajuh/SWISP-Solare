-- =============================================================================
-- Solare Arena — sorteio com rodízio justo (por Partida):
--   Quem jogou MENOS confrontos nesta Partida tem prioridade no próximo sorteio.
--   Empate -> aleatório. 1º confronto (todos com 0 jogos) é 100% aleatório.
--   A contagem é por Partida (tournament_id): cada Partida nova recomeça do zero.
--   Continua valendo: não repetir classe dentro do mesmo time.
--
-- Rode no SQL Editor depois dos 0001..0006. (Substitui a draw_random_match.)
-- =============================================================================
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
    raise exception 'Finalize o confronto atual antes de sortear outro.';
  end if;

  select count(*) into total from public.tournament_participants where tournament_id = p_tournament_id;
  if total < (p_team_size * 2) then
    raise exception 'Participantes insuficientes: precisa de pelo menos % para um confronto.', p_team_size * 2;
  end if;

  -- Ordena os participantes por quantos confrontos já jogaram NESTA Partida
  -- (menos jogos primeiro) e, em empate, aleatório. Depois monta 2 times sem
  -- repetir classe, preferindo o A.
  for rec in
    select p.id, p.game_class
    from public.tournament_participants tp
    join public.players p on p.id = tp.player_id
    left join (
      select mp.player_id, count(*) as n
      from public.match_players mp
      join public.matches m on m.id = mp.match_id
      where m.tournament_id = p_tournament_id
      group by mp.player_id
    ) plays on plays.player_id = p.id
    where tp.tournament_id = p_tournament_id
    order by coalesce(plays.n, 0) asc, random()
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
