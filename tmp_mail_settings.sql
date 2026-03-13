--
-- PostgreSQL database dump
--

\restrict ocmdSVigjaRy217upinMWWFCmdfwDGgbUjL40O2kYKW8mUdV2KYbjSv9V0s0QCh

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
-- Data for Name: mail_settings; Type: TABLE DATA; Schema: public; Owner: label
--

INSERT INTO public.mail_settings (id, smtp_host, smtp_port, smtp_from_email, smtp_use_tls, smtp_use_ssl, smtp_user, smtp_password, emails_per_hour, updated_at) VALUES (1, 'smtp.hostinger.com', 465, 'simon@zalmanim.com', false, true, 'simon@zalmanim.com', 'Ssrr102030!', 5, '2026-03-12 18:43:19.763833+00');


--
-- PostgreSQL database dump complete
--

\unrestrict ocmdSVigjaRy217upinMWWFCmdfwDGgbUjL40O2kYKW8mUdV2KYbjSv9V0s0QCh

