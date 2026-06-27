-- Lista de classes do Black Desert (ajuste/adicione à vontade).
insert into public.classes (name, sort_order) values
  ('Warrior', 1), ('Ranger', 2), ('Sorceress', 3), ('Berserker', 4),
  ('Tamer', 5), ('Musa', 6), ('Maehwa', 7), ('Valkyrie', 8),
  ('Kunoichi', 9), ('Ninja', 10), ('Wizard', 11), ('Witch', 12),
  ('Dark Knight', 13), ('Striker', 14), ('Mystic', 15), ('Lahn', 16),
  ('Archer', 17), ('Shai', 18), ('Guardian', 19), ('Hashashin', 20),
  ('Nova', 21), ('Sage', 22), ('Corsair', 23), ('Drakania', 24),
  ('Woosa', 25), ('Maegu', 26), ('Scholar', 27), ('Dosa', 28),
  ('Deadeye', 29), ('Wukong', 30), ('Seraph', 31)
on conflict (name) do nothing;
