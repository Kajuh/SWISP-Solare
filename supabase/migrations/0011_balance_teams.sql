-- =============================================================================
-- Solare Arena — sorteio com TIMES BALANCEADOS.
--   QUEM joga continua vindo do rodízio justo (menos confrontos primeiro).
--   COMO os 6 são divididos passa a buscar o equilíbrio: entre todas as
--   divisões válidas (sem repetir classe no time), escolhe a que deixa as
--   MÉDIAS de pontos dos dois times mais próximas. Evita fortes de um lado só.
--
-- Rode no SQL Editor depois dos 0001..0010. (Substitui a draw_random_match.)
-- =============================================================================
create or replace function public.draw_random_match(p_tournament_id uuid, p_team_size int default 3)
returns uuid language plpgsql security definer set search_path = public
as $$
declare
  rec record;
  team_a uuid[] := '{}'; team_b uuid[] := '{}';
  cls_a text[] := '{}'; cls_b text[] := '{}';
  sel_id uuid[] := '{}'; sel_rt int[] := '{}'; sel_cl text[] := '{}';
  new_id uuid; pid uuid; wp int; lp int; rp int; total_p int;
  i int; j int; k int; oth int[]; suma int; total int;
  best_diff int; best_a int[];
begin
  if not public.is_admin() then raise exception 'Apenas administradores.'; end if;
  if exists (select 1 from public.matches where tournament_id = p_tournament_id and status = 'pending') then
    raise exception 'Finalize o confronto atual antes de sortear outro.';
  end if;

  select count(*) into total_p from public.tournament_participants where tournament_id = p_tournament_id;
  if total_p < (p_team_size * 2) then
    raise exception 'Participantes insuficientes: precisa de pelo menos % para um confronto.', p_team_size * 2;
  end if;

  -- 1) Seleção dos jogadores: rodízio justo (menos jogos primeiro) + aleatório,
  --    garantindo um conjunto válido (sem repetir classe em cada time provisório).
  for rec in
    select p.id, p.game_class, p.rating
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
      sel_id := array_append(sel_id, rec.id); sel_rt := array_append(sel_rt, rec.rating); sel_cl := array_append(sel_cl, rec.game_class);
    elsif coalesce(array_length(team_b,1),0) < p_team_size and not (rec.game_class = any(cls_b)) then
      team_b := array_append(team_b, rec.id); cls_b := array_append(cls_b, rec.game_class);
      sel_id := array_append(sel_id, rec.id); sel_rt := array_append(sel_rt, rec.rating); sel_cl := array_append(sel_cl, rec.game_class);
    end if;
    exit when coalesce(array_length(team_a,1),0) = p_team_size and coalesce(array_length(team_b,1),0) = p_team_size;
  end loop;

  if coalesce(array_length(team_a,1),0) < p_team_size or coalesce(array_length(team_b,1),0) < p_team_size then
    raise exception 'Não consegui montar 2 times de % sem repetir classe. Adicione mais participantes ou mais variedade de classes.', p_team_size;
  end if;

  -- 2) Balanceamento (3v3): entre todas as divisões válidas dos 6 escolhidos,
  --    escolhe a que deixa a soma do time A mais perto da metade (médias iguais).
  if p_team_size = 3 and array_length(sel_id,1) = 6 then
    total := sel_rt[1] + sel_rt[2] + sel_rt[3] + sel_rt[4] + sel_rt[5] + sel_rt[6];
    best_diff := null;
    for i in 1..4 loop
      for j in i+1..5 loop
        for k in j+1..6 loop
          oth := array(select g from generate_series(1,6) g where g <> i and g <> j and g <> k);
          if sel_cl[i] <> sel_cl[j] and sel_cl[i] <> sel_cl[k] and sel_cl[j] <> sel_cl[k]
             and sel_cl[oth[1]] <> sel_cl[oth[2]] and sel_cl[oth[1]] <> sel_cl[oth[3]] and sel_cl[oth[2]] <> sel_cl[oth[3]] then
            suma := sel_rt[i] + sel_rt[j] + sel_rt[k];
            if best_diff is null or abs(2 * suma - total) < best_diff then
              best_diff := abs(2 * suma - total);
              best_a := array[i, j, k];
            end if;
          end if;
        end loop;
      end loop;
    end loop;

    if best_a is not null then
      oth := array(select g from generate_series(1,6) g where g <> best_a[1] and g <> best_a[2] and g <> best_a[3]);
      team_a := array[sel_id[best_a[1]], sel_id[best_a[2]], sel_id[best_a[3]]];
      team_b := array[sel_id[oth[1]], sel_id[oth[2]], sel_id[oth[3]]];
    end if;
  end if;

  -- 3) Cria o confronto com a divisão balanceada
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
