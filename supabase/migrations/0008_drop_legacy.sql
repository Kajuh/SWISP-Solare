-- =============================================================================
-- Solare Arena — limpeza: remove as funções de chaveamento (legado).
--
-- Não são mais usadas: as Partidas agora geram confrontos 3v3 aleatórios
-- (draw_random_match), sem bracket nem times fixos. Nada no app nem em outras
-- funções do banco depende delas, então remover é seguro.
--
-- Rode no SQL Editor depois dos 0001..0007.
-- =============================================================================
drop function if exists public.generate_bracket(uuid, boolean);
drop function if exists public.generate_bracket(uuid);
drop function if exists public.form_teams_random(uuid, int);
