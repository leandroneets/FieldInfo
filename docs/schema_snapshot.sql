--
-- PostgreSQL database dump
--

\restrict VKLFKq9iv99OyiSVhJ7MK3ALXAB32ulmW7gxRIyyrbFP8a8RMEPSiezaaHzN8eV

-- Dumped from database version 17.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: bump_revision(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bump_revision() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at := now();
  NEW.updated_by := auth.uid();
  NEW.revision := COALESCE(OLD.revision,0) + 1;
  RETURN NEW;
END $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: semeadura; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.semeadura (
    id_semeadura uuid DEFAULT gen_random_uuid() NOT NULL,
    id_plano uuid,
    data_inicio_femea date,
    data_fim_femea date,
    data_inicio_macho1 date,
    data_fim_macho1 date,
    data_inicio_macho2 date,
    data_fim_macho2 date,
    data_inicio_macho3 date,
    data_fim_macho3 date,
    espacamentomxm numeric,
    espacamentofxm numeric,
    espacamentofxf numeric,
    proporcaosemeadura numeric,
    tipoespacamento text,
    dataliberacaopivo date,
    status_semeadura text,
    observacoes text,
    criado_em timestamp without time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    revision bigint DEFAULT 0 NOT NULL,
    deleted_at timestamp with time zone
);


--
-- Name: semeadura_changes_since(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.semeadura_changes_since(p_since timestamp with time zone) RETURNS SETOF public.semeadura
    LANGUAGE sql SECURITY DEFINER
    AS $$
  SELECT * FROM public.semeadura
  WHERE updated_at > COALESCE(p_since, '1970-01-01'::timestamptz)
  ORDER BY updated_at ASC
  LIMIT 2000;
$$;


--
-- Name: material; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.material (
    id_material uuid DEFAULT gen_random_uuid() NOT NULL,
    hibrido text NOT NULL,
    macho text,
    femea text,
    cultura text,
    umidade_min numeric,
    umidade_max numeric
);


--
-- Name: plano_producao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plano_producao (
    id_plano uuid DEFAULT gen_random_uuid() NOT NULL,
    id_safra uuid NOT NULL,
    id_material uuid NOT NULL,
    num_campo integer NOT NULL,
    fazenda text,
    gleba text,
    hectare numeric,
    setor text,
    modo_colheita text,
    criado_em timestamp without time zone DEFAULT now()
);


--
-- Name: safra; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.safra (
    id_safra uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    data_inicio date,
    data_fim date,
    ativa boolean DEFAULT true
);


--
-- Name: usuario_plano; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_plano (
    id_usuario_plano uuid DEFAULT gen_random_uuid() NOT NULL,
    id_usuario uuid,
    id_plano uuid
);


--
-- Name: usuarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuarios (
    id_usuario uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    email text NOT NULL,
    senha text,
    tipo_usuario text NOT NULL,
    criado_em timestamp without time zone DEFAULT now(),
    CONSTRAINT usuarios_tipo_usuario_check CHECK ((tipo_usuario = ANY (ARRAY['Tecnico'::text, 'Supervisor'::text, 'Suporte'::text])))
);


--
-- Name: material material_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.material
    ADD CONSTRAINT material_pkey PRIMARY KEY (id_material);


--
-- Name: plano_producao plano_producao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plano_producao
    ADD CONSTRAINT plano_producao_pkey PRIMARY KEY (id_plano);


--
-- Name: safra safra_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.safra
    ADD CONSTRAINT safra_pkey PRIMARY KEY (id_safra);


--
-- Name: semeadura semeadura_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semeadura
    ADD CONSTRAINT semeadura_pkey PRIMARY KEY (id_semeadura);


--
-- Name: usuario_plano usuario_plano_id_usuario_id_plano_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_plano
    ADD CONSTRAINT usuario_plano_id_usuario_id_plano_key UNIQUE (id_usuario, id_plano);


--
-- Name: usuario_plano usuario_plano_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_plano
    ADD CONSTRAINT usuario_plano_pkey PRIMARY KEY (id_usuario_plano);


--
-- Name: usuarios usuarios_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_email_key UNIQUE (email);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id_usuario);


--
-- Name: semeadura trg_semeadura_bump; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_semeadura_bump BEFORE UPDATE ON public.semeadura FOR EACH ROW EXECUTE FUNCTION public.bump_revision();


--
-- Name: plano_producao plano_producao_id_material_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plano_producao
    ADD CONSTRAINT plano_producao_id_material_fkey FOREIGN KEY (id_material) REFERENCES public.material(id_material) ON DELETE CASCADE;


--
-- Name: plano_producao plano_producao_id_safra_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plano_producao
    ADD CONSTRAINT plano_producao_id_safra_fkey FOREIGN KEY (id_safra) REFERENCES public.safra(id_safra) ON DELETE CASCADE;


--
-- Name: semeadura semeadura_id_plano_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semeadura
    ADD CONSTRAINT semeadura_id_plano_fkey FOREIGN KEY (id_plano) REFERENCES public.plano_producao(id_plano) ON DELETE CASCADE;


--
-- Name: usuario_plano usuario_plano_id_plano_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_plano
    ADD CONSTRAINT usuario_plano_id_plano_fkey FOREIGN KEY (id_plano) REFERENCES public.plano_producao(id_plano) ON DELETE CASCADE;


--
-- Name: usuario_plano usuario_plano_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_plano
    ADD CONSTRAINT usuario_plano_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuarios(id_usuario) ON DELETE CASCADE;


--
-- Name: plano_producao Technicians see only assigned fields; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Technicians see only assigned fields" ON public.plano_producao FOR SELECT USING (((EXISTS ( SELECT 1
   FROM (public.usuario_plano up
     JOIN public.usuarios u ON ((u.id_usuario = up.id_usuario)))
  WHERE ((up.id_plano = plano_producao.id_plano) AND (u.email = auth.email())))) OR (EXISTS ( SELECT 1
   FROM public.usuarios u
  WHERE ((u.email = auth.email()) AND (u.tipo_usuario = ANY (ARRAY['Supervisor'::text, 'Suporte'::text])))))));


--
-- Name: plano_producao; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.plano_producao ENABLE ROW LEVEL SECURITY;

--
-- Name: semeadura; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.semeadura ENABLE ROW LEVEL SECURITY;

--
-- Name: semeadura semeadura_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY semeadura_rw ON public.semeadura USING ((EXISTS ( SELECT 1
   FROM public.usuario_plano up
  WHERE ((up.id_plano = semeadura.id_plano) AND (up.id_usuario = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.usuario_plano up
  WHERE ((up.id_plano = semeadura.id_plano) AND (up.id_usuario = auth.uid())))));


--
-- PostgreSQL database dump complete
--

\unrestrict VKLFKq9iv99OyiSVhJ7MK3ALXAB32ulmW7gxRIyyrbFP8a8RMEPSiezaaHzN8eV

