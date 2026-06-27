-- =============================================================================
-- Funções auxiliares chamadas pelo front (RPC).
-- =============================================================================

-- Registra uma partida avulsa (ranqueada) 3v3 e já aplica o ELO, tudo numa
-- transação. Recebe os ids dos jogadores de cada lado e o vencedor.
create or replace function public.create_ranked_match(
  p_team_a uuid[],
  p_team_b uuid[],
  p_winner text,
  p_k int default 32
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  pid    uuid;
begin
  if not public.is_admin() then
    raise exception 'Apenas administradores podem registrar partidas.';
  end if;
  if p_winner not in ('A','B') then
    raise exception 'Vencedor inválido: use A ou B.';
  end if;
  if array_length(p_team_a, 1) is null or array_length(p_team_b, 1) is null then
    raise exception 'Cada time precisa de ao menos um jogador.';
  end if;
  if p_team_a && p_team_b then
    raise exception 'Um jogador não pode estar nos dois times.';
  end if;

  insert into public.matches (winner, k_factor, status, created_by)
  values (p_winner, p_k, 'pending', auth.uid())
  returning id into new_id;

  foreach pid in array p_team_a loop
    insert into public.match_players (match_id, player_id, team) values (new_id, pid, 'A');
  end loop;
  foreach pid in array p_team_b loop
    insert into public.match_players (match_id, player_id, team) values (new_id, pid, 'B');
  end loop;

  perform public.apply_match_result(new_id);
  return new_id;
end;
$$;

-- Gera o chaveamento (single elimination) de um torneio a partir dos seus times.
-- Só pode rodar uma vez (enquanto não há partidas criadas para o torneio).
create or replace function public.generate_bracket(p_tournament_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  n        int;
  sz       int := 1;
  rounds   int := 0;
  r        int;
  num      int;
  pos      int;
  team_ids uuid[];
  parent   uuid;
begin
  if not public.is_admin() then
    raise exception 'Apenas administradores podem gerar o chaveamento.';
  end if;

  if exists (select 1 from public.matches where tournament_id = p_tournament_id) then
    raise exception 'Este torneio já tem partidas geradas.';
  end if;

  -- times ordenados por seed (nulos por último) e depois criação
  select array_agg(id order by coalesce(seed, 1000000), created_at)
    into team_ids
  from public.tournament_teams where tournament_id = p_tournament_id;

  n := coalesce(array_length(team_ids, 1), 0);
  if n < 2 then
    raise exception 'Cadastre ao menos 2 times antes de gerar o chaveamento.';
  end if;

  -- menor potência de 2 >= n
  while sz < n loop sz := sz * 2; end loop;
  -- número de rodadas
  while (2 ^ rounds) < sz loop rounds := rounds + 1; end loop;

  -- cria todas as partidas (vazias) de cada rodada
  for r in 1..rounds loop
    num := sz / (2 ^ r);
    for pos in 0..(num - 1) loop
      insert into public.matches (tournament_id, bracket_round, bracket_position, k_factor, status)
      select p_tournament_id, r, pos, t.k_factor, 'pending'
      from public.tournaments t where t.id = p_tournament_id;
    end loop;
  end loop;

  -- posiciona os times na rodada 1 (índice k -> match k/2, slot A se par, B se ímpar)
  for r in 1..n loop
    declare
      k    int := r - 1;
      mpos int := k / 2;
      tid  uuid := team_ids[r];
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

  -- byes: rodada 1 com só um time presente -> avança sem alterar ELO
  for r in 0..(sz / 2 - 1) loop
    declare
      m_id   uuid; a_id uuid; b_id uuid;
      win_id uuid; ppos int := r / 2;
    begin
      select id, team_a_id, team_b_id into m_id, a_id, b_id
      from public.matches
      where tournament_id = p_tournament_id and bracket_round = 1 and bracket_position = r;

      if (a_id is null) <> (b_id is null) then  -- exatamente um presente
        win_id := coalesce(a_id, b_id);
        update public.matches
          set status = 'completed', winner = case when a_id is not null then 'A' else 'B' end,
              played_at = now()
          where id = m_id;

        select id into parent from public.matches
          where tournament_id = p_tournament_id and bracket_round = 2 and bracket_position = ppos;
        if parent is not null then
          if (r % 2) = 0 then
            update public.matches set team_a_id = win_id where id = parent;
          else
            update public.matches set team_b_id = win_id where id = parent;
          end if;
        end if;
      end if;
    end;
  end loop;

  update public.tournaments set status = 'active' where id = p_tournament_id;
end;
$$;
