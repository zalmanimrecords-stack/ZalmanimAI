--
-- PostgreSQL database dump
--

\restrict j0z35Ngxhxg0f0zBF0gdbpPca9LvpFhIUntqTeYvNb2yCYJHPDktI80dTnj75pw

-- Dumped from database version 16.13 (Debian 16.13-1.pgdg13+1)
-- Dumped by pg_dump version 16.13 (Debian 16.13-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: artists; Type: TABLE DATA; Schema: public; Owner: label
--

INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (4, 'Yuval Garty', 'yrg.garty@gmail.com', 'Full name: Yuval Garty
soundcloud: https://soundcloud.app.goo.gl/22sJc', '2026-03-07 20:21:09.457814+00', '{"source_row": "4", "full_name": "Yuval Garty", "soundcloud": "https://soundcloud.app.goo.gl/22sJc", "artist_brand": "Tata Box"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (5, 'Maorazu86', 'maorazu86@gmail.com', 'Full name: Maorazu86', '2026-03-07 20:21:09.457814+00', '{"source_row": "2", "full_name": "Maorazu86"}', false, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (7, 'After Sunrise', 'durejkoartur@gmail.com', 'Full name: Artur Durejko
soundcloud: https://soundcloud.com/aftersunriseofficial
instagram: https://www.instagram.com/aftersunriseofficial/?hl=pl
spotify: https://open.spotify.com/artist/0Tb3D6JDQ2ECuoDsTRXUhx
address: Sikorskiego 27b/10', '2026-03-07 20:21:09.457814+00', '{"source_row": "28", "artist_brand": "After Sunrise", "full_name": "Artur Durejko", "soundcloud": "https://soundcloud.com/aftersunriseofficial", "facebook": "https://www.facebook.com/aftersunriseofficial/", "youtube": "https://www.youtube.com/@aftersunrise", "instagram": "https://www.instagram.com/aftersunriseofficial/?hl=pl", "spotify": "https://open.spotify.com/artist/0Tb3D6JDQ2ECuoDsTRXUhx", "apple_music": "https://music.apple.com/us/artist/after-sunrise/1116601153", "address": "Sikorskiego 27b/10"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (8, 'Alchemistry', 'alchemistryofficial@gmail.com', 'Full name: Victor Emmanuel Soledade Muniz
soundcloud: https://on.soundcloud.com/1FkAG
instagram: http://instagram.com/alchemistryofficial
spotify: https://open.spotify.com/artist/6FTLrNiRmrOw8DTWMDS6lo?si=US-4m6OuRyOtv5ZJ8eC59w', '2026-03-07 20:21:09.457814+00', '{"source_row": "22", "artist_brand": "Alchemistry", "full_name": "Victor Emmanuel Soledade Muniz", "soundcloud": "https://on.soundcloud.com/1FkAG", "youtube": "https://youtube.com/@alchemistryofficial", "tiktok": "https://www.tiktok.com/@alchemistryoffici", "instagram": "http://instagram.com/alchemistryofficial", "spotify": "https://open.spotify.com/artist/6FTLrNiRmrOw8DTWMDS6lo?si=US-4m6OuRyOtv5ZJ8eC59w", "apple_music": "https://music.apple.com/br/artist/alchemistry/1721216549"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (9, 'Arabesko', 'domenico.croce.wav@gmail.com', 'Full name: Domenico Croce
soundcloud: https://soundcloud.com/arabesko-926319085
instagram: https://www.instagram.com/arabesko_music/
spotify: https://open.spotify.com/intl-it/artist/3KvuqxaHDlZN9eeBkA8iiW?si=9tnqa37OQUSTG3jJt10YRg', '2026-03-07 20:21:09.457814+00', '{"source_row": "39", "artist_brand": "Arabesko", "full_name": "Domenico Croce", "soundcloud": "https://soundcloud.com/arabesko-926319085", "instagram": "https://www.instagram.com/arabesko_music/", "spotify": "https://open.spotify.com/intl-it/artist/3KvuqxaHDlZN9eeBkA8iiW?si=9tnqa37OQUSTG3jJt10YRg"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (11, 'Biowave', 'jovb007@gmail.com', 'Full name: Jovany lara
website: https://on.soundcloud.com/rKfjv4tAtEtdEm5UFE
address: 438 blackshaw', '2026-03-07 20:21:09.457814+00', '{"source_row": "33", "artist_brand": "Biowave", "full_name": "Jovany lara", "website": "https://on.soundcloud.com/rKfjv4tAtEtdEm5UFE", "address": "438 blackshaw"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (12, 'Bliz Nochi', 'booking@bliznochi.com', 'Full name: Oleg Dubin
website: http://bliznochi.com/
soundcloud: https://soundcloud.com/bliznochi
instagram: https://www.instagram.com/bliznochi/
spotify: https://open.spotify.com/artist/519nMF9DAHOrB40ESIUVnd', '2026-03-07 20:21:09.457814+00', '{"source_row": "18", "artist_brand": "Bliz Nochi", "full_name": "Oleg Dubin", "website": "http://bliznochi.com/", "soundcloud": "https://soundcloud.com/bliznochi", "instagram": "https://www.instagram.com/bliznochi/", "spotify": "https://open.spotify.com/artist/519nMF9DAHOrB40ESIUVnd"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (13, 'Byrd', 'conscioustechno@gmail.com', 'Full name: Daniel Byrd
soundcloud: https://soundcloud.com/byrdmp3
instagram: https://www.instagram.com/byrd.techno/
spotify: https://open.spotify.com/artist/4qL1kSi1Pco1fX3OHG7K7b?si=KvIIysfNRsCyGh48KlP8-w', '2026-03-07 20:21:09.457814+00', '{"source_row": "23", "artist_brand": "Byrd", "full_name": "Daniel Byrd", "soundcloud": "https://soundcloud.com/byrdmp3", "facebook": "https://www.facebook.com/djbyrd619x/", "youtube": "https://www.youtube.com/@byrd.techno", "instagram": "https://www.instagram.com/byrd.techno/", "spotify": "https://open.spotify.com/artist/4qL1kSi1Pco1fX3OHG7K7b?si=KvIIysfNRsCyGh48KlP8-w"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (33, 'Sefer Semir', 'Sefer', 'Full name: Semir Sefer
soundcloud: https://soundcloud.com/mirsevanferse
instagram: mirsevanferse', '2026-03-07 20:21:09.457814+00', '{"source_row": "26", "artist_brand": "Sefer Semir", "full_name": "Semir Sefer", "soundcloud": "https://soundcloud.com/mirsevanferse", "instagram": "mirsevanferse"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (6, 'SKAZKA - -AGADA', 'rubidervis@gmail.com', 'Full name: ×¨×•×‘×™ ×“×¨×•×™×¡', '2026-03-07 20:21:09.457814+00', '{"source_row": "6", "artist_brand": "SKAZKA - -AGADA", "full_name": "\u00d7\u00a8\u00d7\u2022\u00d7\u2018\u00d7\u2122 \u00d7\u201c\u00d7\u00a8\u00d7\u2022\u00d7\u2122\u00d7\u00a1", "facebook": "https://www.facebook.com/dervisrubi", "youtube": "https://www.youtube.com/user/rdervis00000000"}', false, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (10, 'Asya', 'djasyainfo@gmail.com', 'Full name: asaf almog
website: http://asafalmog.com
soundcloud: https://soundcloud.com/dj-asya
instagram: https://www.instagram.com/dj__asya/
spotify: https://open.spotify.com/artist/2Fuo4xlbRPRSycMN1tetog?si=LM8WtCGURBe0hx0C-bPKSQ', '2026-03-07 20:21:09.457814+00', '{"source_row": "12", "artist_brand": "Asya", "full_name": "asaf almog", "website": "http://asafalmog.com", "soundcloud": "https://soundcloud.com/dj-asya", "facebook": "https://www.facebook.com/XXASYA", "youtube": "https://www.youtube.com/channel/UCZ-kMQ9GjEKNEzFdGXH3d_Q", "instagram": "https://www.instagram.com/dj__asya/", "spotify": "https://open.spotify.com/artist/2Fuo4xlbRPRSycMN1tetog?si=LM8WtCGURBe0hx0C-bPKSQ", "artist_brands": ["Asya"]}', false, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (15, 'Clem B', 'clementbequart@icloud.com', 'Full name: CLEMENT BEQUART
website: https://www.beatport.com/artist/clem-b/63997
soundcloud: https://soundcloud.com/clemb', '2026-03-07 20:21:09.457814+00', '{"source_row": "24", "artist_brand": "Clem B", "full_name": "CLEMENT BEQUART", "website": "https://www.beatport.com/artist/clem-b/63997", "soundcloud": "https://soundcloud.com/clemb", "facebook": "https://www.facebook.com/photo/?fbid=10159983811274303&set=a.10150462076904303", "youtube": "https://yyoutu.be/Jg8t9Ic91VU?si=AuqvWyyaUJpq4of6", "apple_music": "CLEM B"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (16, 'Dennis AF', 'dennisaf.official@gmail.com', 'Full name: Daniel Sanchez
soundcloud: https://soundcloud.com/dennisaf-official
instagram: https://www.instagram.com/dennis_AF/
spotify: https://open.spotify.com/artist/064N1TFtTSuLKMQmLs6Gn6', '2026-03-07 20:21:09.457814+00', '{"source_row": "3", "artist_brand": "Dennis AF", "full_name": "Daniel Sanchez", "soundcloud": "https://soundcloud.com/dennisaf-official", "facebook": "https://www.facebook.com/DennisAF97", "twitter_1": "https://twitter.com/SIRDennis_AF", "youtube": "https://www.youtube.com/@Dennis_AF", "tiktok": "https://www.tiktok.com/@dennisafmusic", "instagram": "https://www.instagram.com/dennis_AF/", "spotify": "https://open.spotify.com/artist/064N1TFtTSuLKMQmLs6Gn6", "apple_music": "https://music.apple.com/us/artist/dennis-af/1197337593"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (17, 'Echonomika', 'echonomikamusic@gmail.com', 'Full name: Eytan Tsytkin & Dor Itzhaki
soundcloud: https://soundcloud.com/echonomikamusic
instagram: https://www.instagram.com/echo.nomika/?next=%2F
spotify: https://open.spotify.com/artist/5xg4AON991bCf3CI5JIBlM?si=VZ3RIyW9TsCe1k3MpzBaWQ
address: Ha Histadrut 14 Ness Ziona', '2026-03-07 20:21:09.457814+00', '{"source_row": "35", "artist_brand": "Echonomika", "full_name": "Eytan Tsytkin & Dor Itzhaki", "soundcloud": "https://soundcloud.com/echonomikamusic", "facebook": "https://www.facebook.com/profile.php?id=100092483164434", "youtube": "https://www.youtube.com/@EchoNomika", "instagram": "https://www.instagram.com/echo.nomika/?next=%2F", "spotify": "https://open.spotify.com/artist/5xg4AON991bCf3CI5JIBlM?si=VZ3RIyW9TsCe1k3MpzBaWQ", "apple_music": "https://music.apple.com/us/artist/echonomika/1687670232", "address": "Ha Histadrut 14 Ness Ziona"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (18, 'Fape', 'djfape@gmx.ch', 'Full name: Fabio Pesci
soundcloud: https://soundcloud.com/fabio_pescifape
instagram: @fape_musicofc
spotify: https://open.spotify.com/intl-de/artist/0mUErdzCy0ZGR3jQVlBwWz?si=We6hjTDEQl-ahEuFlvKCNg', '2026-03-07 20:21:09.457814+00', '{"source_row": "37", "artist_brand": "Fape", "full_name": "Fabio Pesci", "soundcloud": "https://soundcloud.com/fabio_pescifape", "youtube": "https://www.youtube.com/@fape_musicofc", "instagram": "@fape_musicofc", "spotify": "https://open.spotify.com/intl-de/artist/0mUErdzCy0ZGR3jQVlBwWz?si=We6hjTDEQl-ahEuFlvKCNg"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (19, 'Flow Theory', 'ashleyzadel@gmail.com', 'Full name: Ashley Zadel
website: https://www.flowtheory.dj
soundcloud: https://soundcloud.com/flow-theory
instagram: https://www.instagram.com/flowtheory.dj
spotify: https://open.spotify.com/artist/4Mol6g7I846XRmDNW1zh5l?si=1jPinHMQRzensx4X3auIxA
address: 2/12 Circular Ave, Sawtell, NSW, 2452, Australia', '2026-03-07 20:21:09.457814+00', '{"source_row": "30", "artist_brand": "Flow Theory", "full_name": "Ashley Zadel", "website": "https://www.flowtheory.dj", "soundcloud": "https://soundcloud.com/flow-theory", "facebook": "https://www.facebook.com/FlowTheory.DJ", "youtube": "https://www.youtube.com/@Flow-Theory", "tiktok": "https://www.tiktok.com/@flowtheory.dj", "instagram": "https://www.instagram.com/flowtheory.dj", "spotify": "https://open.spotify.com/artist/4Mol6g7I846XRmDNW1zh5l?si=1jPinHMQRzensx4X3auIxA", "apple_music": "https://music.apple.com/au/artist/flow-theory/324403096", "address": "2/12 Circular Ave, Sawtell, NSW, 2452, Australia"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (20, 'Gabriele Benvenuto', 'bevenutodistribuzione@gmail.com', 'Full name: Gabriele Benvenuto
soundcloud: https://soundcloud.com/user-950788651
instagram: gabriele benvenuto
spotify: https://open.spotify.com/intl-it/artist/3NncYkzgH96hBdKneNKAVE?si=XOuNiJ_TT-SUbisEORx2hg', '2026-03-07 20:21:09.457814+00', '{"source_row": "29", "artist_brand": "Gabriele Benvenuto", "full_name": "Gabriele Benvenuto", "soundcloud": "https://soundcloud.com/user-950788651", "instagram": "gabriele benvenuto", "spotify": "https://open.spotify.com/intl-it/artist/3NncYkzgH96hBdKneNKAVE?si=XOuNiJ_TT-SUbisEORx2hg"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (21, 'inspisica', 'inspisica@gmail.com', 'Full name: Viktor Inspisica
instagram: Inspisica
spotify: Inspisica', '2026-03-07 20:21:09.457814+00', '{"source_row": "20", "artist_brand": "inspisica", "full_name": "Viktor Inspisica", "instagram": "Inspisica", "spotify": "Inspisica", "apple_music": "Inspisica"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (23, 'Jabba 2.3', 'direction@made-festival.fr', 'Full name: RÃ©my Gourlaouen
soundcloud: https://soundcloud.com/jabba-2-3
instagram: https://www.instagram.com/jabba23/
spotify: Jabba 2.3', '2026-03-07 20:21:09.457814+00', '{"source_row": "19", "artist_brand": "Jabba 2.3", "full_name": "R\u00c3\u00a9my Gourlaouen", "soundcloud": "https://soundcloud.com/jabba-2-3", "facebook": "https://www.facebook.com/jabba23Musique", "tiktok": "https://www.tiktok.com/@djjabba23", "instagram": "https://www.instagram.com/jabba23/", "spotify": "Jabba 2.3", "apple_music": "Jabba 2.3"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (24, 'Jamh', 'jams-93@live.com', 'Full name: Jose Antonio MuÃ±oz Salcido', '2026-03-07 20:21:09.457814+00', '{"source_row": "5", "artist_brand": "Jamh", "full_name": "Jose Antonio Mu\u00c3\u00b1oz Salcido"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (41, '2nd ID', 'zalmanimrecords@gmail.com', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "2nd ID", "artist_brands": ["2nd ID"]}', false, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (51, 'Jellyfish Syndrome', 'original-artist-jellyfish-syndrome@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Jellyfish Syndrome", "artist_brands": ["Jellyfish Syndrome"]}', false, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (62, 'Rosenfears', 'original-artist-rosenfears@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Rosenfears", "artist_brands": ["Rosenfears"]}', false, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (68, 'Simon Rose', 'original-artist-simon-rose@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "2nd ID", "artist_brands": ["2nd ID", "Jellyfish Syndrome", "Rosenfears", "Simon Rose", "The Last Stand"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (70, 'The Last Stand', 'original-artist-the-last-stand@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "The Last Stand", "artist_brands": ["The Last Stand"]}', false, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (25, 'Luca Sirianni', 'lucasirio@yahoo.it', 'Full name: Luca Sirianni
soundcloud: https://on.soundcloud.com/pmN1J
instagram: https://instagram.com/lucasirio
spotify: https://open.spotify.com/artist/3CdllR0RH14iGp8OxCK4f1?si=0uW5KgVDRIWQp4Yc112xGQ', '2026-03-07 20:21:09.457814+00', '{"source_row": "11", "artist_brand": "Luca Sirianni", "full_name": "Luca Sirianni", "soundcloud": "https://on.soundcloud.com/pmN1J", "tiktok": "https://vm.tiktok.com/ZGJXrveeT/", "instagram": "https://instagram.com/lucasirio", "spotify": "https://open.spotify.com/artist/3CdllR0RH14iGp8OxCK4f1?si=0uW5KgVDRIWQp4Yc112xGQ"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (26, 'Lumy', 'lumygard8@gmail.com', 'Full name: Gard
soundcloud: https://soundcloud.com/user-731651500?utm_source=clipboard&utm_medium=text&utm_campaign=social_sharing
instagram: https://www.instagram.com/pacome_music/
spotify: https://open.spotify.com/intl-fr/artist/5Valz9O1sFGqmHNs4RW1BZ?si=TxNID3_PRAWSByuCAlHa5w
comments: I don''t have any TikTok or Facebook.
Thank you .

Lumy Gard
address: 23 RUE BLANCHARD 92320 ChÃ¢tillon', '2026-03-07 20:21:09.457814+00', '{"source_row": "27", "artist_brand": "Lumy", "full_name": "Gard", "soundcloud": "https://soundcloud.com/user-731651500?utm_source=clipboard&utm_medium=text&utm_campaign=social_sharing", "youtube": "http://www.youtube.com/@lumygard4498", "instagram": "https://www.instagram.com/pacome_music/", "spotify": "https://open.spotify.com/intl-fr/artist/5Valz9O1sFGqmHNs4RW1BZ?si=TxNID3_PRAWSByuCAlHa5w", "comments": "I don''t have any TikTok or Facebook.\r\nThank you .\r\n\r\nLumy Gard", "address": "23 RUE BLANCHARD 92320 Ch\u00c3\u00a2tillon"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (27, 'LutchamaK', 'lutchamak@gmail.com', 'Full name: Olivier LISE
website: https://lutchamak.bandcamp.com/music
soundcloud: https://soundcloud.com/user-lutchamak', '2026-03-07 20:21:09.457814+00', '{"source_row": "10", "artist_brand": "LutchamaK", "full_name": "Olivier LISE", "website": "https://lutchamak.bandcamp.com/music", "soundcloud": "https://soundcloud.com/user-lutchamak", "facebook": "https://www.facebook.com/profile.php?id=100063467315669", "youtube": "https://www.youtube.com/channel/UCebX3tIS3aI6aUEnKWQnylA"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (28, 'Meir aka loren', 'meirpro69@gmail.com', 'Full name: Loren shirel', '2026-03-07 20:21:09.457814+00', '{"source_row": "9", "artist_brand": "Meir aka loren", "full_name": "Loren shirel"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (29, 'MoonS', 'kfirmon@gmail.com', 'Full name: Kfir Monsonego
website: https://www.facebook.com/MoonSPsychedelicTranceMusicAndOtherTreasures
soundcloud: https://soundcloud.com/kfirmon', '2026-03-07 20:21:09.457814+00', '{"source_row": "13", "artist_brand": "MoonS", "full_name": "Kfir Monsonego", "website": "https://www.facebook.com/MoonSPsychedelicTranceMusicAndOtherTreasures", "soundcloud": "https://soundcloud.com/kfirmon", "facebook": "https://www.facebook.com/kfirmon/", "youtube": "https://www.youtube.com/@kfir6", "tiktok": "@kfirmonsonego"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (30, 'Nicolas Nucci', 'nicolasnucci@yahoo.fr', 'Full name: Nicolas Bochard
website: http://www.djnicolasnucci.com
soundcloud: http://www.soundcloud.com/nicolasnucci', '2026-03-07 20:21:09.457814+00', '{"source_row": "15", "artist_brand": "Nicolas Nucci", "full_name": "Nicolas Bochard", "website": "http://www.djnicolasnucci.com", "soundcloud": "http://www.soundcloud.com/nicolasnucci", "facebook": "http://www.facebook.com/djnicolasnucci", "youtube": "https://www.youtube.com/channel/UCTuUV5Sxau9AR3lPnNKGcMg/about", "other_1": "apple podcasts https://podcasts.apple.com/us/podcast/nicolas-nucci-house-2-techno/id1644387882", "other_2": "deezer https://deezer.page.link/TceaqXqFKgxUReu78", "other_3": "amazon https://music.amazon.fr/podcasts/540f01b4-8d78-4d61-8aee-71d0e48fc64d/nicolas-nucci---house-2-techno"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (31, 'Psychic Distance', 'psychicdistance@protonmail.com', 'Full name: Justin Beck
website: https://linktr.ee/psychicdistance
soundcloud: https://soundcloud.com/psychicdistance
instagram: https://www.instagram.com/psychic.distance/
spotify: https://open.spotify.com/artist/12XqH32VlseCHmdGMxaoqU
address: Wigandstr. 8
04229 Leipzig, Germany', '2026-03-07 20:21:09.457814+00', '{"source_row": "36", "artist_brand": "Psychic Distance", "full_name": "Justin Beck", "website": "https://linktr.ee/psychicdistance", "soundcloud": "https://soundcloud.com/psychicdistance", "facebook": "N/A", "twitter_1": "N/A", "youtube": "https://www.youtube.com/channel/UCZ0E5fPX6xAu_uU8YHdnccg/videos", "tiktok": "N/A", "instagram": "https://www.instagram.com/psychic.distance/", "spotify": "https://open.spotify.com/artist/12XqH32VlseCHmdGMxaoqU", "other_2": "https://www.beatport.com/artist/psychic-distance/928454", "apple_music": "https://music.apple.com/us/artist/psychic-distance/1535846078", "address": "Wigandstr. 8\r\n04229 Leipzig, Germany"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (32, 'Ralmoon', 'kybalioncapri@gmail.com', 'Full name: RubÃ©n Alvarez
website: https://ralmoon.bandcamp.com/
soundcloud: https://on.soundcloud.com/sQSXsDE8YfANtFMX8
spotify: https://open.spotify.com/user/313nidav6zb5vwewmf2iewm6vooa?si=iVWTGGruQ6OYzknGRGc-HQ
comments: Hello how are you? It is a great pleasure to greet you! I love their selections and a lot of the music they have! I want to collaborate with you if you like what I create with care and enthusiasm from...', '2026-03-07 20:21:09.457814+00', '{"source_row": "25", "artist_brand": "Ralmoon", "full_name": "Rub\u00c3\u00a9n Alvarez", "soundcloud": "https://on.soundcloud.com/vDyLKjWqP2YKipYw8", "youtube": "https://youtu.be/GoAv0oopSEc?si=3JKu2R5bAa5ezPb-", "other_1": "https://youtu.be/GW_Cmtn6-Co?si=0MGLvgBbTdhmRLIB", "comments": "Hello! I would love if you can release these singles that I sent you! I hope you like it a big greeting"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (34, 'Toi Toi', 'toitoi.mp3@gmail.com', 'Full name: Taio perez
website: https://www.soundcloud.com/brokentoytoy
soundcloud: https://www.soundcloud.com/brokentoytoy
instagram: https://www.instagram.com/toitoi.mp3
spotify: https://open.spotify.com/user/mw4hcqrvt3nbno0d06nrljk9r?si=iCtMhcxxTr-sjNsnhXokvQ', '2026-03-07 20:21:09.457814+00', '{"source_row": "17", "artist_brand": "Toi Toi", "full_name": "Taio perez", "website": "https://www.soundcloud.com/brokentoytoy", "soundcloud": "https://www.soundcloud.com/brokentoytoy", "facebook": "https://www.facebook.com/toitoi.ofc", "instagram": "https://www.instagram.com/toitoi.mp3", "spotify": "https://open.spotify.com/user/mw4hcqrvt3nbno0d06nrljk9r?si=iCtMhcxxTr-sjNsnhXokvQ"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (35, 'TomDan', 'tomerd78@gmail.com', 'Full name: Tomer Dana
website: https://linktr.ee/tomdan
soundcloud: https://on.soundcloud.com/KG27hzrGT1uGtkcXTD
instagram: https://www.instagram.com/tomerd?igsh=OXNwbTB4d29nN2E5
spotify: https://open.spotify.com/artist/4atu0GrLDf6uhWYRul50x3?si=kuz53pR8TJOkm3rxRfBcHw
address: Israel', '2026-03-07 20:21:09.457814+00', '{"source_row": "38", "artist_brand": "TomDan", "full_name": "Tomer Dana", "website": "https://linktr.ee/tomdan", "soundcloud": "https://on.soundcloud.com/KG27hzrGT1uGtkcXTD", "facebook": "https://www.facebook.com/share/1Gmz59S2QA/", "twitter_1": "https://x.com/Tomerd78?t=kRvpcSYsYaxBmhtFIacGeQ&s=09", "youtube": "https://youtube.com/@tomerd78?si=CXlpLvHOeI8F5xlJ", "instagram": "https://www.instagram.com/tomerd?igsh=OXNwbTB4d29nN2E5", "spotify": "https://open.spotify.com/artist/4atu0GrLDf6uhWYRul50x3?si=kuz53pR8TJOkm3rxRfBcHw", "apple_music": "https://music.apple.com/us/artist/tomdan/1623153774", "address": "Israel"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (36, 'Triex', 'alex@ruffbeatz.com', 'Full name: Alexander Zaroff
soundcloud: https://soundcloud.com/TriexMusic
instagram: https://instagram.com/TriexMusic', '2026-03-07 20:21:09.457814+00', '{"source_row": "31", "artist_brand": "Triex", "full_name": "Alexander Zaroff", "soundcloud": "https://soundcloud.com/TriexMusic", "facebook": "https://facebook.com/TriexMusic", "instagram": "https://instagram.com/TriexMusic", "other_1": "https://ruffbeatz.com"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (37, 'VELEVA', 'charlesquenot@live.fr', 'Full name: Charles Quenot
soundcloud: https://soundcloud.com/veleva', '2026-03-07 20:21:09.457814+00', '{"source_row": "8", "artist_brand": "VELEVA", "full_name": "Charles Quenot", "soundcloud": "https://soundcloud.com/veleva", "facebook": "https://www.facebook.com/profile.php?id=100063067038639"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (38, 'Vincent R', 'djvincentr@gmail.com', 'Full name: Vincent Roslewski
soundcloud: https://soundcloud.com/djvincentr
instagram: https://www.instagram.com/vincent__r/
spotify: https://open.spotify.com/artist/0IJ80vJKO8rD4YpyvzyRJl?si=owcABLjDQOGP6FvoM1Fkqg', '2026-03-07 20:21:09.457814+00', '{"source_row": "14", "artist_brand": "Vincent R", "full_name": "Vincent Roslewski", "soundcloud": "https://soundcloud.com/djvincentr", "facebook": "https://www.facebook.com/djvincentr", "twitter_1": "https://twitter.com/DJVincentR", "instagram": "https://www.instagram.com/vincent__r/", "spotify": "https://open.spotify.com/artist/0IJ80vJKO8rD4YpyvzyRJl?si=owcABLjDQOGP6FvoM1Fkqg", "other_1": "https://www.beatport.com/artist/vincent-r/631704", "other_2": "https://music.apple.com/us/artist/vincent-r/448633155"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (39, 'Yolisa', 'yolisa.art@gmail.com', 'Full name: Elisa HÃ¤rmÃ¤
website: https://www.yolisa.art/
soundcloud: https://on.soundcloud.com/PRVwU
instagram: https://instagram.com/yolisa.art?utm_source=qr&igshid=MzNlNGNkZWQ4Mg%3D%3D
spotify: https://open.spotify.com/artist/1Oyem8jnIyR3rsPxIa0wAN?si=HXJNAwGxSwSt0WQ5KRgwDQ', '2026-03-07 20:21:09.457814+00', '{"source_row": "16", "artist_brand": "Yolisa", "full_name": "Elisa H\u00c3\u00a4rm\u00c3\u00a4", "website": "https://www.yolisa.art/", "soundcloud": "https://on.soundcloud.com/PRVwU", "facebook": "https://www.facebook.com/yolisa.art", "youtube": "https://youtube.com/@yolisaharma", "instagram": "https://instagram.com/yolisa.art?utm_source=qr&igshid=MzNlNGNkZWQ4Mg%3D%3D", "spotify": "https://open.spotify.com/artist/1Oyem8jnIyR3rsPxIa0wAN?si=HXJNAwGxSwSt0WQ5KRgwDQ"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (40, 'Zaidman', 'tkyproductions@gmail.com', 'Full name: Yaniv  Zaidman
website: http://www.zaidman-music.com
soundcloud: http://soundcloud.com/zaidman', '2026-03-07 20:21:09.457814+00', '{"source_row": "7", "artist_brand": "Zaidman", "full_name": "Yaniv  Zaidman", "website": "http://www.zaidman-music.com", "soundcloud": "http://soundcloud.com/zaidman"}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (42, 'Carolina Reaper', 'original-artist-carolina-reaper@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Carolina Reaper", "artist_brands": ["Carolina Reaper"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (43, 'Clément Bequart', 'original-artist-clément-bequart@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Cl\u00e9ment Bequart", "artist_brands": ["Cl\u00e9ment Bequart"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (44, 'Dean More', 'original-artist-dean-more@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Dean More", "artist_brands": ["Dean More"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (45, 'Dubioza kolektiv', 'original-artist-dubioza-kolektiv@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Dubioza kolektiv", "artist_brands": ["Dubioza kolektiv"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (46, 'Erika Krall', 'original-artist-erika-krall@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Erika Krall", "artist_brands": ["Erika Krall"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (47, 'Froyke', 'original-artist-froyke@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Froyke", "artist_brands": ["Froyke"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (48, 'GuyR', 'original-artist-guyr@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "GuyR", "artist_brands": ["GuyR"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (49, 'Jad0', 'original-artist-jad0@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Jad0", "artist_brands": ["Jad0"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (50, 'Jason Xmoon', 'original-artist-jason-xmoon@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Jason Xmoon", "artist_brands": ["Jason Xmoon"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (52, 'Joseph Virum', 'original-artist-joseph-virum@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Joseph Virum", "artist_brands": ["Joseph Virum"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (53, 'KEAH', 'original-artist-keah@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "KEAH", "artist_brands": ["KEAH"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (54, 'Manjit Makhni', 'original-artist-manjit-makhni@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Manjit Makhni", "artist_brands": ["Manjit Makhni"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (56, 'Meir', 'original-artist-meir@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Meir", "artist_brands": ["Meir"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (57, 'Mellego', 'original-artist-mellego@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Mellego", "artist_brands": ["Mellego"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (58, 'Miguel Serrano', 'original-artist-miguel-serrano@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Miguel Serrano", "artist_brands": ["Miguel Serrano"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (59, 'Mime Time', 'original-artist-mime-time@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Mime Time", "artist_brands": ["Mime Time"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (60, 'Oren Levi', 'original-artist-oren-levi@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Oren Levi", "artist_brands": ["Oren Levi"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (61, 'PROUD WINNERS AGAIN', 'original-artist-proud-winners-again@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "PROUD WINNERS AGAIN", "artist_brands": ["PROUD WINNERS AGAIN"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (63, 'Royal VegA', 'original-artist-royal-vega@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Royal VegA", "artist_brands": ["Royal VegA"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (64, 'SPKTRR', 'original-artist-spktrr@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "SPKTRR", "artist_brands": ["SPKTRR"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (65, 'Salvador', 'original-artist-salvador@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Salvador", "artist_brands": ["Salvador"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (66, 'Shaul Eliyahu', 'original-artist-shaul-eliyahu@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Shaul Eliyahu", "artist_brands": ["Shaul Eliyahu"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (67, 'SiYu', 'original-artist-siyu@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "SiYu", "artist_brands": ["SiYu"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (69, 'Skazka-Agada', 'original-artist-skazka-agada@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Skazka-Agada", "artist_brands": ["Skazka-Agada"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (71, 'WSTND', 'original-artist-wstnd@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "WSTND", "artist_brands": ["WSTND"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (72, 'Zahid Noise', 'original-artist-zahid-noise@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Zahid Noise", "artist_brands": ["Zahid Noise"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (73, 'Zedkleinberg', 'original-artist-zedkleinberg@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Zedkleinberg", "artist_brands": ["Zedkleinberg"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (74, 'iDor', 'original-artist-idor@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "iDor", "artist_brands": ["iDor"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (55, 'Maor Azulay', 'original-artist-maor-azulay@label.local', '', '2026-03-07 21:52:30.032372+00', '{"artist_brand": "Maor Azulay", "artist_brands": ["Maor Azulay", "Maorazu86"]}', true, NULL);
INSERT INTO public.artists (id, name, email, notes, created_at, extra_json, is_active, password_hash) VALUES (75, 'Demo Artist', 'artist@label.local', 'Seed artist', '2026-03-12 19:40:31.682738+00', '{}', true, '$2b$12$UgeCdtaoJFAo3jA4pg3dAOHlFftKQQpcoO1R8w0rldFc/7/ufMGwS');


--
-- Name: artists_id_seq; Type: SEQUENCE SET; Schema: public; Owner: label
--

SELECT pg_catalog.setval('public.artists_id_seq', 75, true);


--
-- PostgreSQL database dump complete
--

\unrestrict j0z35Ngxhxg0f0zBF0gdbpPca9LvpFhIUntqTeYvNb2yCYJHPDktI80dTnj75pw

