-- Lista de classes do Black Desert (ordem alfabética).
insert into public.classes (name, sort_order) values
  ('Archer', 1), ('Berserker', 2), ('Corsair', 3), ('Dark Knight', 4),
  ('Deadeye', 5), ('Dosa', 6), ('Drakania', 7), ('Guardian', 8),
  ('Hashashin', 9), ('Kunoichi', 10), ('Lahn', 11), ('Maegu', 12),
  ('Maehwa', 13), ('Musa', 14), ('Mystic', 15), ('Ninja', 16),
  ('Nova', 17), ('Ranger', 18), ('Sage', 19), ('Scholar', 20),
  ('Seraph', 21), ('Shai', 22), ('Sorceress', 23), ('Striker', 24),
  ('Tamer', 25), ('Valkyrie', 26), ('Warrior', 27), ('Witch', 28),
  ('Wizard', 29), ('Woosa', 30), ('Wukong', 31)
on conflict (name) do nothing;
