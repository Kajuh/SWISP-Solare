-- =============================================================================
-- Solare Arena — ferramentas de gestão (somente admin):
--   1. delete_match(id)  -> remove uma partida e REVERTE os pontos/W-L dela
--   2. reset_scores()    -> zera pontuação (volta todos pra 1000) e apaga
--                           partidas/eventos, MAS mantém os jogadores cadastrados
--   3. reset_all()       -> apaga TUDO (jogadores, partidas, eventos)
--
-- Mantêm sempre: classes e admins (seu login).
-- Rode no SQL Editor depois dos 0001..0005.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Remove uma partida. Se ela já estava finalizada, desfaz o efeito na pontuação
-- (subtrai o delta que cada jogador recebeu) e nas vitórias/derrotas.
-- ---------------------------------------------------------------------------
create or replace function public.delete_match(p_match_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare m public.matches%rowtype; rh record;
begin
  if not public.is_admin() then raise exception 'Apenas administradores.'; end if;

  select * into m from public.matches where id = p_match_id;
  if not found then raise exception 'Partida não encontrada.'; end if;

  if m.status = 'completed' then
    -- reverte os pontos (delta já é o valor real aplicado, com piso de 0)
    for rh in select player_id, delta from public.rating_history where match_id = p_match_id loop
      update public.players set rating = greatest(rating - rh.delta, 0) where id = rh.player_id;
    end loop;
    -- reverte vitórias/derrotas
    update public.players p set wins = greatest(p.wins - 1, 0)
      from public.match_players mp
      where mp.match_id = p_match_id and mp.player_id = p.id and mp.team = m.winner;
    update public.players p set losses = greatest(p.losses - 1, 0)
      from public.match_players mp
      where mp.match_id = p_match_id and mp.player_id = p.id and mp.team <> m.winner;
  end if;

  delete from public.rating_history where match_id = p_match_id;
  delete from public.matches where id = p_match_id;  -- cascade: match_players, match_rounds
end;
$$;

-- ---------------------------------------------------------------------------
-- Zera a pontuação (nova temporada): mantém jogadores, volta todos pra 1000,
-- apaga partidas, histórico e eventos.
-- ---------------------------------------------------------------------------
create or replace function public.reset_scores()
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Apenas administradores.'; end if;
  delete from public.rating_history;
  delete from public.matches;       -- cascade: match_players, match_rounds
  delete from public.tournaments;   -- cascade: teams, members, participants
  update public.players set rating = 1000, wins = 0, losses = 0;
end;
$$;

-- ---------------------------------------------------------------------------
-- Apaga TUDO: jogadores, partidas, eventos e histórico.
-- Preserva classes e admins.
-- ---------------------------------------------------------------------------
create or replace function public.reset_all()
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Apenas administradores.'; end if;
  delete from public.rating_history;
  delete from public.matches;
  delete from public.tournaments;
  delete from public.players;        -- cascade: match_players, participants, team_members
end;
$$;
