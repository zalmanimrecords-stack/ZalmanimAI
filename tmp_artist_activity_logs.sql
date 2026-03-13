--
-- PostgreSQL database dump
--

\restrict XcDbMovcaUC0jV6diJhHNSV6mB42bvP9vGvdXqDxYQYnroGqj58MOzG2TINTKEU

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
-- Data for Name: artist_activity_logs; Type: TABLE DATA; Schema: public; Owner: label
--

INSERT INTO public.artist_activity_logs (id, artist_id, activity_type, details, created_at) VALUES (1, 41, 'reminder_email', NULL, '2026-03-12 18:44:53.31093+00');


--
-- Name: artist_activity_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: label
--

SELECT pg_catalog.setval('public.artist_activity_logs_id_seq', 1, true);


--
-- PostgreSQL database dump complete
--

\unrestrict XcDbMovcaUC0jV6diJhHNSV6mB42bvP9vGvdXqDxYQYnroGqj58MOzG2TINTKEU

