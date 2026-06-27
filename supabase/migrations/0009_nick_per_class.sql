-- =============================================================================
-- Solare Arena — permite o mesmo nick em classes diferentes.
--   Antes: nick era único (1 personagem por nick).
--   Agora: único por (nick + classe). Bloqueia só nick repetido NA MESMA classe;
--          o mesmo nick pode ter vários personagens de classes diferentes.
--
-- Rode no SQL Editor depois dos 0001..0008.
-- =============================================================================

-- 1. Remove qualquer restrição UNIQUE que seja só na coluna (nick)
do $$
declare c text;
begin
  for c in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace ns on ns.oid = rel.relnamespace
    where ns.nspname = 'public' and rel.relname = 'players' and con.contype = 'u'
      and (
        select array_agg(att.attname)
        from unnest(con.conkey) k
        join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k
      ) = array['nick']
  loop
    execute format('alter table public.players drop constraint %I', c);
  end loop;
end $$;

-- 2. Nova restrição: único por nick + classe
alter table public.players drop constraint if exists players_nick_class_key;
alter table public.players add constraint players_nick_class_key unique (nick, game_class);

-- 3. Atualiza a mensagem de erro do cadastro
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
  raise exception 'Você já tem um personagem com esse nick nessa classe.';
end;
$$;
