-- ==============================================================================
-- TOKYO STREET 3.ª EDICIÓN — SEED DE DATOS OFICIALES Y AMBIENTE DE PRUEBAS
-- ==============================================================================
-- Ubicación: Club Sportivo Floresta — Av. Colón 471, San Miguel de Tucumán
-- Fecha: Domingo 13 de diciembre de 2026, 13:00 a 21:00 hs.
-- ==============================================================================

-- 1. Configuración del Festival
insert into public.event_settings (
  id,
  event_name,
  stamps_target,
  prize_cap,
  game_status,
  qr_ttl_seconds,
  code_ttl_seconds,
  privacy_version
) values (
  1,
  'Tokyo Street — 3.ª edición',
  15,
  100,
  'open',
  75,
  60,
  'v1'
)
on conflict (id) do update set
  event_name = excluded.event_name,
  stamps_target = excluded.stamps_target,
  prize_cap = excluded.prize_cap,
  game_status = excluded.game_status,
  qr_ttl_seconds = excluded.qr_ttl_seconds,
  code_ttl_seconds = excluded.code_ttl_seconds,
  privacy_version = excluded.privacy_version;

-- 2. Carga de los 70 Stands Oficiales
insert into public.stands (id, number, name, category, contact_name, status) values
  (1, 1, 'Akarumi Yume Manga Café', 'Manga', 'Akarumi Yume', 'active'),
  (2, 2, 'Neo Tokyo Store', 'Figuras & Coleccionables', 'Lucas R.', 'active'),
  (3, 3, 'Shonen Jump Corner', 'Manga', 'Marcos Manga', 'active'),
  (4, 4, 'K-Pop Universe Tucumán', 'K-Pop', 'Valeria K.', 'active'),
  (5, 5, 'Hallyu Wave Store', 'K-Pop', 'Camila H.', 'active'),
  (6, 6, 'Cosplay Forge Tucumán', 'Cosplay', 'Jony Cosplay', 'active'),
  (7, 7, 'Cyberpunk Atelier', 'Indumentaria', 'Nico Cyber', 'active'),
  (8, 8, 'Studio Ghibli Rincón Mágico', 'Accesorios', 'Paula Ghibli', 'active'),
  (9, 9, 'Sakura Craft Bijoux', 'Accesorios', 'Flor Sakura', 'active'),
  (10, 10, 'Demon Slayer Armory', 'Figuras & Coleccionables', 'Tanjiro Tuc', 'active'),
  (11, 11, 'Genshin & Star Rail Vault', 'Accesorios', 'Lumine T.', 'active'),
  (12, 12, 'Pixel Heart Tucumán', 'Ilustración', 'Sofi Pixel', 'active'),
  (13, 13, 'Mecha Garage 01', 'Figuras & Coleccionables', 'Shinji G.', 'active'),
  (14, 14, 'Neko Maid Corner', 'Accesorios', 'Mika Neko', 'active'),
  (15, 15, 'Tinta Callejera Studio', 'Ilustración', 'Ezequiel Art', 'active'),
  (16, 16, 'Chibi Galaxy', 'Ilustración', 'Belén Chibi', 'active'),
  (17, 17, 'Akira Cyber Prints', 'Ilustración', 'Kaneda Tuc', 'active'),
  (18, 18, 'Pastel Goth Wonders', 'Indumentaria', 'Rocío Goth', 'active'),
  (19, 19, 'J-Rock Apparel', 'Indumentaria', 'Gabi Visual', 'active'),
  (20, 20, 'Vocaloid & Friends', 'Accesorios', 'Miku Fan Tuc', 'active'),
  (21, 21, 'Ramen & Roll Merch', 'Merchandising', 'Mariano R.', 'active'),
  (22, 22, 'Dragon Ball Legacy', 'Juguetes', 'Goku Tucumano', 'active'),
  (23, 23, 'One Piece Grand Line', 'Merchandising', 'Luffy Tuc', 'active'),
  (24, 24, 'Jujutsu Realm', 'Indumentaria', 'Gojo Satoru', 'active'),
  (25, 25, 'Chainsaw Denji Goods', 'Accesorios', 'Denji Pochita', 'active'),
  (26, 26, 'Pokemon Center Tucumano', 'Juguetes', 'Ash K.', 'active'),
  (27, 27, 'Bleach Soul Society', 'Cosplay', 'Ichigo K.', 'active'),
  (28, 28, 'Kawaii Bento Box', 'Accesorios', 'Yuki Bento', 'active'),
  (29, 29, 'Oishii Ramen Bar', 'Gastronomía', 'Chef Kenji', 'active'),
  (30, 30, 'Takoyaki Osaka Express', 'Gastronomía', 'Osaka Street', 'active'),
  (31, 31, 'Taiyaki & Waffles Dorados', 'Gastronomía', 'Taiyaki Dulce', 'active'),
  (32, 32, 'Boba Bubble Tea Lab', 'Gastronomía', 'Boba Lab', 'active'),
  (33, 33, 'Onigiri House Tucumán', 'Gastronomía', 'Onigiri San', 'active'),
  (34, 34, 'Dango Dulce Tradicional', 'Gastronomía', 'Dango Tradición', 'active'),
  (35, 35, 'Gyoza Samurai', 'Gastronomía', 'Gyoza Master', 'active'),
  (36, 36, 'Matcha Point', 'Gastronomía', 'Matcha Bar', 'active'),
  (37, 37, 'K-Street Food Corndogs', 'Gastronomía', 'Corndogs Tuc', 'active'),
  (38, 38, 'Mochi Cloud Pastelería', 'Gastronomía', 'Mochi Cloud', 'active'),
  (39, 39, 'Tokyo Crepes Harajuku', 'Gastronomía', 'Crepes Harajuku', 'active'),
  (40, 40, 'Banzai Snacks Importados', 'Gastronomía', 'Banzai Market', 'active'),
  (41, 41, 'Retro Arcade Station', 'Juguetes', 'Arcade Tuc', 'active'),
  (42, 42, 'Smash Bros Tucumán League', 'Merchandising', 'Smash League', 'active'),
  (43, 43, 'Yu-Gi-Oh! Duelist Den', 'Juguetes', 'Yugi Duel', 'active'),
  (44, 44, 'Magic The Gathering Tucumán', 'Juguetes', 'MTG Tucumán', 'active'),
  (45, 45, 'Nintendo Zone Cuyo/Norte', 'Merchandising', 'Zelda Zone', 'active'),
  (46, 46, 'PlayStation Classic Haven', 'Merchandising', 'PS Nostalgia', 'active'),
  (47, 47, 'Dark Souls & Elden Ring Forge', 'Figuras & Coleccionables', 'Tarnished Forge', 'active'),
  (48, 48, 'Final Fantasy Crystal Shop', 'Accesorios', 'Crystal Shop', 'active'),
  (49, 49, 'League of Legends Hextech', 'Figuras & Coleccionables', 'Hextech Lab', 'active'),
  (50, 50, 'Valorant Radiant Store', 'Indumentaria', 'Radiant Merch', 'active'),
  (51, 51, 'Indie Games Showcase', 'Ilustración', 'Indie Devs', 'active'),
  (52, 52, 'Speedrunner Merch', 'Accesorios', 'Speedrun Tuc', 'active'),
  (53, 53, 'Kitsune Mask Works', 'Artesanía', 'Kitsune Studio', 'active'),
  (54, 54, 'Origami Master Tucumán', 'Artesanía', 'Origami Master', 'active'),
  (55, 55, 'Bonsai & Jardín Zen', 'Artesanía', 'Bonsai Tuc', 'active'),
  (56, 56, 'Caligrafía Shodo & Sellos Hanko', 'Artesanía', 'Shodo Master', 'active'),
  (57, 57, 'Kimono & Yukata Vintage', 'Indumentaria', 'Kimono Vintage', 'active'),
  (58, 58, 'Gothic Lolita Boutique', 'Indumentaria', 'Lolita Tuc', 'active'),
  (59, 59, 'Harajuku Decora Shop', 'Accesorios', 'Decora Kei', 'active'),
  (60, 60, 'Inciensos & Sahumerios de Kioto', 'Accesorios', 'Kioto Zen', 'active'),
  (61, 61, 'Tazas & Cerámica Nipona', 'Artesanía', 'Cerámica Zen', 'active'),
  (62, 62, 'Banderas Koinobori & Decoración', 'Accesorios', 'Koinobori Fest', 'active'),
  (63, 63, 'Manga Usado & Rarezas Coleccionables', 'Manga', 'Rare Manga', 'active'),
  (64, 64, 'Papelería Japonesa & Bullet Journal', 'Accesorios', 'Washi Tape Tuc', 'active'),
  (65, 65, 'Furoshiki Telas Ecológicas', 'Artesanía', 'Furoshiki Eco', 'active'),
  (66, 66, 'K-Beauty & Skin Care Tucumán', 'Accesorios', 'K-Beauty Tuc', 'active'),
  (67, 67, 'Luces Neón Tokyo Nights', 'Artesanía', 'Neon Nights', 'active'),
  (68, 68, 'Chapas Vintage & Patentes Japonesas', 'Merchandising', 'Vintage Plates', 'active'),
  (69, 69, 'Stickers Holográficos Tucumán', 'Ilustración', 'Holo Stickers', 'active'),
  (70, 70, 'Tokyo Street Centro de Informes & Sello Bonus', 'Organización', 'Sahra & Martín', 'active')
on conflict (id) do update set
  number = excluded.number,
  name = excluded.name,
  category = excluded.category,
  contact_name = excluded.contact_name,
  status = excluded.status;

-- Resetear el sequence de stands al ID máximo cargado
select setval(pg_get_serial_sequence('public.stands', 'id'), coalesce(max(id), 1)) from public.stands;
