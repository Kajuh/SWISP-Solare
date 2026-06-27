-- =============================================================================
-- Solare Arena — permite o mesmo nick+classe em especializações diferentes.
--   Antes (0009): único por (nick + classe).
--   Agora: único por (nick + classe + especialização).
--   Bloqueia só quando nick, classe E especialização forem iguais.
--   Ex.: "Kaju" Warrior Sucessão e "Kaju" Warrior Awakening podem coexistir.
--
-- Rode no SQL Editor depois dos 0001..0009.
-- =============================================================================

alter table public.players drop constraint if exists players_nick_key;
alter table public.players drop constraint if exists players_nick_class_key;
alter table public.players drop constraint if exists players_nick_class_spec_key;
alter table public.players add constraint players_nick_class_spec_key unique (nick, game_class, specialization);

-- Atualiza a mensagem de erro do cadastro
create or replace function public.register_player(p_nick text, p_class text, p_spec text)
returns uuid language plpgsql security definer set search_path = public
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
  raise exception 'Você já tem um personagem com esse nick, classe e especialização.';
end;
$$;
