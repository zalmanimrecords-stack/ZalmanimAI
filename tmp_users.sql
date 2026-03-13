--
-- PostgreSQL database dump
--

\restrict dSeTyevsFF5rIY1lANjIzGQLAppza0EQiwgk8ckkLeLXDRZRt9XNsAWANuTIcpG

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
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: label
--

INSERT INTO public.users (id, email, password_hash, role, artist_id, full_name, is_active, created_at, updated_at, last_login_at) VALUES (1, 'admin@label.local', '$2b$12$BktfxXKWtyRkwGlJsh9/8OH4uetM2aSrgU9hNRAW4/xDI9YmVhHee', 'admin', NULL, NULL, true, '2026-03-12 19:40:31.506588+00', '2026-03-12 19:40:31.506588+00', NULL);
INSERT INTO public.users (id, email, password_hash, role, artist_id, full_name, is_active, created_at, updated_at, last_login_at) VALUES (3, 'simon@zalmanim.com', '$2b$12$0dQpu5a8ZYDt0N7kdezRFeIbCqrUBglN8sob9r/qxkMN86hdKwCDW', 'admin', NULL, 'Simon Rose', true, '2026-03-13 07:40:43.350536+00', '2026-03-13 07:40:57.69263+00', NULL);
INSERT INTO public.users (id, email, password_hash, role, artist_id, full_name, is_active, created_at, updated_at, last_login_at) VALUES (2, 'artist@label.local', '$2b$12$YFFf64IdwG7bpHwROvI5HOlnNcHt49.5oi2s9EAxg8Eh6XHF7L2t.', 'artist', NULL, NULL, false, '2026-03-12 19:40:31.506588+00', '2026-03-13 07:42:54.080274+00', NULL);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: label
--

SELECT pg_catalog.setval('public.users_id_seq', 3, true);


--
-- PostgreSQL database dump complete
--

\unrestrict dSeTyevsFF5rIY1lANjIzGQLAppza0EQiwgk8ckkLeLXDRZRt9XNsAWANuTIcpG

