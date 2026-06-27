-- =============================================================================
-- RESET dos dados de teste do Solare Arena.
-- Apaga jogadores, partidas, torneios e histórico — deixa tudo zerado.
--
-- PRESERVA: a estrutura (tabelas/funções/RLS), a lista de CLASSES e os ADMINS
-- (seu login continua funcionando).
--
-- Rode no Supabase > SQL Editor. Reversível? NÃO — os dados somem de vez.
-- =============================================================================
truncate table
  public.match_rounds,
  public.rating_history,
  public.match_players,
  public.matches,
  public.tournament_team_members,
  public.tournament_teams,
  public.tournament_participants,
  public.tournaments,
  public.players
restart identity cascade;
