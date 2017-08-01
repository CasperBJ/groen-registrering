---
--- SET
---

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;


--
-- SCHEMAS
--

CREATE SCHEMA greg;

COMMENT ON SCHEMA greg IS 'Skema indeholdende grund- og rådatabeller.';


--
-- EXTENSIONS
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- FUNCTIONS
--

-- f_aendring_log(integer)

DROP FUNCTION IF EXISTS greg.f_aendring_log(integer);

CREATE FUNCTION greg.f_aendring_log(integer)
	RETURNS TABLE(
		versions_id uuid,
		objekt_id uuid,
		handling text,
		dato timestamp without time zone,
		bruger text,
		underelement text,
		arbejdssted text,
		objekt_type text,
		note text
	)
	LANGUAGE sql
	AS $$

WITH

tgp AS (
		SELECT -- Select all features that has been inserted, but not updated from the current dataset (Points)
			a.versions_id,
			a.objekt_id,
			'Tilføjet'::text AS handling,
			a.systid_fra::timestamp(0) AS dato,
			a.bruger_id_start AS bruger,
			a.underelement_kode || ' ' || b.underelement_tekst AS underelement,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted,
			'P'::text AS objekt_type,
			''::text AS note
		FROM greg.t_greg_punkter a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND systid_til IS NULL
	),

tghp AS (
		SELECT -- Select all features that represent update and delete operations from the history (Points)
			a.versions_id,
			a.objekt_id,
			CASE
				WHEN a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_punkter d WHERE a.objekt_id = d.objekt_id) AND a.objekt_id NOT IN(SELECT objekt_id FROM greg.t_greg_punkter WHERE systid_til IS NULL)
				THEN 'Slettet'::text
				ELSE 'Ændring'::text
			END AS handling,
			a.systid_til::timestamp(0) AS dato,
			a.bruger_id_slut AS bruger,
			a.underelement_kode || ' ' || b.underelement_tekst AS underelement,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted,
			'P'::text AS objekt_type,
			CASE
				WHEN EXTRACT (YEAR FROM a.oprettet) = $1
				THEN 'Tilføjet '::text || to_char(a.oprettet::date, 'dd-mm-yyyy')
				ELSE ''::text
			END AS note
		FROM greg.t_greg_punkter a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE EXTRACT (YEAR FROM a.systid_til) = $1
	),

tghpo AS (
		SELECT -- Select all features that represent insert opreations from the history (Points)
			a.versions_id,
			a.objekt_id,
			'Tilføjet'::text AS handling,
			a.systid_fra::timestamp(0) AS dato,
			a.bruger_id_start AS bruger,
			a.underelement_kode || ' ' || b.underelement_tekst AS underelement,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted,
			'P'::text AS objekt_type,
			''::text AS note
		FROM greg.t_greg_punkter a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND systid_til IS NOT NULL
	),

tgl AS (
		SELECT -- Select all features that has been inserted, but not updated from the current dataset (Lines)
			a.versions_id,
			a.objekt_id,
			'Tilføjet'::text AS handling,
			a.systid_fra::timestamp(0) AS dato,
			a.bruger_id_start AS bruger,
			a.underelement_kode || ' ' || b.underelement_tekst AS underelement,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted,
			'L'::text AS objekt_type,
			''::text AS note
		FROM greg.t_greg_linier a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND systid_til IS NULL
	),

tghl AS (
		SELECT -- Select all features that represent update and delete operations from the history (Lines)
			a.versions_id,
			a.objekt_id,
			CASE
				WHEN a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_linier d WHERE a.objekt_id = d.objekt_id) AND a.objekt_id NOT IN(SELECT objekt_id FROM greg.t_greg_linier WHERE systid_til IS NULL)
				THEN 'Slettet'::text
				ELSE 'Ændring'::text
			END AS handling,
			a.systid_til::timestamp(0) AS dato,
			a.bruger_id_slut AS bruger,
			a.underelement_kode || ' ' || b.underelement_tekst AS underelement,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted,
			'L'::text AS objekt_type,
			CASE
				WHEN EXTRACT (YEAR FROM a.oprettet) = $1
				THEN 'Tilføjet '::text || to_char(a.oprettet::date, 'dd-mm-yyyy')
				ELSE ''::text
			END AS note
		FROM greg.t_greg_linier a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE EXTRACT (YEAR FROM a.systid_til) = $1
	),

tghlo AS (
		SELECT -- Select all features that represent insert opreations from the history (Lines)
			a.versions_id,
			a.objekt_id,
			'Tilføjet'::text AS handling,
			a.systid_fra::timestamp(0) AS dato,
			a.bruger_id_start AS bruger,
			a.underelement_kode || ' ' || b.underelement_tekst AS underelement,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted,
			'L'::text AS objekt_type,
			''::text AS note
		FROM greg.t_greg_linier a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND systid_til IS NOT NULL
	),

tgf AS (
		SELECT -- Select all features that has been inserted, but not updated from the current dataset (Polygons)
			a.versions_id,
			a.objekt_id,
			'Tilføjet'::text AS handling,
			a.systid_fra::timestamp(0) AS dato,
			a.bruger_id_start AS bruger,
			a.underelement_kode || ' ' || b.underelement_tekst AS underelement,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted,
			'F'::text AS objekt_type,
			''::text AS note
		FROM greg.t_greg_flader a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND systid_til IS NULL
	),

tghf AS (
		SELECT -- Select all features that represent update and delete operations from the history (Polygons)
			a.versions_id,
			a.objekt_id,
			CASE
				WHEN a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_flader d WHERE a.objekt_id = d.objekt_id) AND a.objekt_id NOT IN(SELECT objekt_id FROM greg.t_greg_flader WHERE systid_til IS NULL)
				THEN 'Slettet'::text
				ELSE 'Ændring'::text
			END AS handling,
			a.systid_til::timestamp(0) AS dato,
			a.bruger_id_slut AS bruger,
			a.underelement_kode || ' ' || b.underelement_tekst AS underelement,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted,
			'F'::text AS objekt_type,
			CASE
				WHEN EXTRACT (YEAR FROM a.oprettet) = $1
				THEN 'Tilføjet '::text || to_char(a.oprettet::date, 'dd-mm-yyyy')
				ELSE ''::text
			END AS note
		FROM greg.t_greg_flader a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE EXTRACT (YEAR FROM a.systid_til) = $1
	),

tghfo AS (
		SELECT -- Select all features that represent insert opreations from the history (Polygons)
			a.versions_id,
			a.objekt_id,
			'Tilføjet'::text AS handling,
			a.systid_fra::timestamp(0) AS dato,
			a.bruger_id_start AS bruger,
			a.underelement_kode || ' ' || b.underelement_tekst AS underelement,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted,
			'F'::text AS objekt_type,
			''::text AS note
		FROM greg.t_greg_flader a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND systid_til IS NOT NULL
	)

SELECT * FROM tgp
UNION
SELECT * FROM tghp
UNION
SELECT * FROM tghpo
UNION
SELECT * FROM tgl
UNION
SELECT * FROM tghl
UNION
SELECT * FROM tghlo
UNION
SELECT * FROM tgf
UNION
SELECT * FROM tghf
UNION
SELECT * FROM tghfo

ORDER BY dato DESC;

$$;

COMMENT ON FUNCTION greg.f_aendring_log(integer) IS 'Ændringslog, som registrerer alle handlinger indenfor et givent år. Format: yyyy.';


-- f_dato_flader(integer, integer, integer);

DROP FUNCTION IF EXISTS greg.f_dato_flader(integer, integer, integer);

CREATE FUNCTION greg.f_dato_flader(integer, integer, integer)
	RETURNS TABLE(
		versions_id uuid,
		objekt_id uuid,
		oprettet timestamp with time zone,
		systid_fra timestamp with time zone,
		systid_til timestamp with time zone,
		bruger_id_start character varying,
		bruger_start character varying,
		bruger_id_slut character varying,
		bruger_slut character varying,

		geometri public.geometry('MultiPolygon', 25832),

		cvr_kode integer,
		cvr_navn character varying,
		oprindkode integer,
		oprindelse character varying,
		statuskode integer,
		status character varying,
		off_kode integer,
		offentlig character varying,

		note character varying,
		link character varying,
		vejkode integer,
		vejnavn character varying,
		tilstand_kode integer,
		tilstand character varying,
		anlaegsaar date,
		udfoerer_entrep_kode integer,
		udfoerer_entrep character varying,
		kommunal_kontakt_kode integer,
		kommunal_kontakt character varying,

		arbejdssted integer,
		pg_distrikt_tekst character varying,
		hovedelement_kode character varying,
		hovedelement_tekst character varying,
		element_kode character varying,
		element_tekst character varying,
		underelement_kode character varying,
		underelement_tekst character varying,

		hoejde numeric(10,1),
		klip_sider character varying,

		litra character varying,

		klip_flade numeric(10,1),
		areal numeric(10,1),
		omkreds numeric(10,1)
	)
	LANGUAGE sql
	AS $$

WITH

tgf AS (
		SELECT -- Select everything present at the end of the given day
			a.versions_id,
			a.objekt_id,
			a.oprettet,
			a.systid_fra,
			a.systid_til,
			a.bruger_id_start,
			c.navn AS bruger_start,
			a.bruger_id_slut,
			o.navn AS bruger_slut,

			a.geometri,

			a.cvr_kode,
			b.cvr_navn,
			a.oprindkode,
			d.oprindelse,
			a.statuskode,
			e.status,
			a.off_kode,
			f.offentlig,

			a.note,
			a.link,
			a.vejkode,
			g.vejnavn || ' (' || g.postnr || ')' AS vejnavn,
			a.tilstand_kode,
			h.tilstand,
			a.anlaegsaar,
			a.udfoerer_entrep_kode,
			i.udfoerer_entrep,
			a.kommunal_kontakt_kode,
			j.navn || ', tlf: ' || j.telefon || ', ' || j.email AS kommunal_kontakt,

			a.arbejdssted,
			a.arbejdssted || ' ' || k.pg_distrikt_tekst AS pg_distrikt_tekst,
			n.hovedelement_kode,
			n.hovedelement_kode || ' - ' || n.hovedelement_tekst AS hovedelement_tekst,
			m.element_kode,
			m.element_kode || ' ' || m.element_tekst AS element_tekst,
			a.underelement_kode,
			a.underelement_kode || ' ' || l.underelement_tekst AS underelement_tekst,

			a.hoejde,
			CASE
				WHEN a.klip_sider = 0
				THEN '0 (Kun toppen)'
				WHEN a.klip_sider = 1
				THEN '1 (Halvdelen af sidefladen, samt toppen)'
				WHEN a.klip_sider = 2
				THEN '2 (Hele sidefladen, samt toppen)'
			END AS klip_sider,

			a.litra,
	
			CASE
				WHEN LEFT(a.underelement_kode,2) LIKE 'HÆ'
				THEN (public.ST_Area(a.geometri) + a.klip_sider * a.hoejde * public.ST_Perimeter(a.geometri) /2)::numeric(10,1)
				ELSE NULL
			END AS klip_flade,
			public.ST_Area(a.geometri)::numeric(10,1) AS areal,
			public.ST_Perimeter(a.geometri)::numeric(10,1) AS omkreds
		FROM greg.t_greg_flader a
		LEFT JOIN greg.d_basis_ansvarlig_myndighed b ON a.cvr_kode = b.cvr_kode
		LEFT JOIN greg.d_basis_bruger_id c ON a.bruger_id_start = c.bruger_id
		LEFT JOIN greg.d_basis_oprindelse d ON a.oprindkode = d.oprindkode
		LEFT JOIN greg.d_basis_status e ON a.statuskode = e.statuskode
		LEFT JOIN greg.d_basis_offentlig f ON a.off_kode = f.off_kode

		LEFT JOIN greg.d_basis_vejnavn g ON a.vejkode = g.vejkode
		LEFT JOIN greg.d_basis_tilstand h ON a.tilstand_kode = h.tilstand_kode
		LEFT JOIN greg.d_basis_udfoerer_entrep i ON a.udfoerer_entrep_kode = i.udfoerer_entrep_kode
		LEFT JOIN greg.d_basis_kommunal_kontakt j ON a.kommunal_kontakt_kode = j.kommunal_kontakt_kode

		LEFT JOIN greg.t_greg_omraader k ON a.arbejdssted = k.pg_distrikt_nr
		LEFT JOIN greg.e_basis_underelementer l ON a.underelement_kode = l.underelement_kode
		LEFT JOIN greg.e_basis_elementer m ON l.element_kode = m.element_kode
		LEFT JOIN greg.e_basis_hovedelementer n ON m.hovedelement_kode = n.hovedelement_kode
		LEFT JOIN greg.d_basis_bruger_id o ON a.bruger_id_slut = o.bruger_id
		WHERE systid_fra::timestamp(0) <= ($3 || '-' || $2 || '-' || $1 || ' 23:59:00')::timestamp(0) AND (systid_til IS NULL OR systid_til::timestamp(0) >  ($3 || '-' || $2 || '-' || $1 || ' 23:59:00')::timestamp(0)) -- Date of creation is before (or on) the given date and the element is either still current or terminated after the current date
	)

SELECT * FROM tgf;

$$;

COMMENT ON FUNCTION greg.f_dato_flader(integer, integer, integer) IS 'Simulering af registreringen på en bestemt dato. Format: dd-MM-yyyy.';


-- f_dato_linier(integer, integer, integer);

DROP FUNCTION IF EXISTS greg.f_dato_linier(integer, integer, integer);

CREATE FUNCTION greg.f_dato_linier(integer, integer, integer)
	RETURNS TABLE(
		versions_id uuid,
		objekt_id uuid,
		oprettet timestamp with time zone,
		systid_fra timestamp with time zone,
		systid_til timestamp with time zone,
		bruger_id_start character varying,
		bruger_start character varying,
		bruger_id_slut character varying,
		bruger_slut character varying,

		geometri public.geometry('MultiLineString', 25832),

		cvr_kode integer,
		cvr_navn character varying,
		oprindkode integer,
		oprindelse character varying,
		statuskode integer,
		status character varying,
		off_kode integer,
		offentlig character varying,

		note character varying,
		link character varying,
		vejkode integer,
		vejnavn character varying,
		tilstand_kode integer,
		tilstand character varying,
		anlaegsaar date,
		udfoerer_entrep_kode integer,
		udfoerer_entrep character varying,
		kommunal_kontakt_kode integer,
		kommunal_kontakt character varying,

		arbejdssted integer,
		pg_distrikt_tekst character varying,
		hovedelement_kode character varying,
		hovedelement_tekst character varying,
		element_kode character varying,
		element_tekst character varying,
		underelement_kode character varying,
		underelement_tekst character varying,

		laengde numeric(10,1),
		bredde numeric(10,1),
		hoejde numeric(10,1),

		litra character varying,

		klip_flade numeric(10,1)
	)
	LANGUAGE sql
	AS $$

WITH

tgl AS (
		SELECT -- Select everything present at the end of the given day
			a.versions_id,
			a.objekt_id,
			a.oprettet,
			a.systid_fra,
			a.systid_til,
			a.bruger_id_start,
			c.navn AS bruger_start,
			a.bruger_id_slut,
			o.navn AS bruger_slut,

			a.geometri,

			a.cvr_kode,
			b.cvr_navn,
			a.oprindkode,
			d.oprindelse,
			a.statuskode,
			e.status,
			a.off_kode,
			f.offentlig,

			a.note,
			a.link,
			a.vejkode,
			g.vejnavn || ' (' || g.postnr || ')' AS vejnavn,
			a.tilstand_kode,
			h.tilstand,
			a.anlaegsaar,
			a.udfoerer_entrep_kode,
			i.udfoerer_entrep,
			a.kommunal_kontakt_kode,
			j.navn || ', tlf: ' || j.telefon || ', ' || j.email AS kommunal_kontakt,

			a.arbejdssted,
			a.arbejdssted || ' ' || k.pg_distrikt_tekst AS pg_distrikt_tekst,
			n.hovedelement_kode,
			n.hovedelement_kode || ' - ' || n.hovedelement_tekst AS hovedelement_tekst,
			m.element_kode,
			m.element_kode || ' ' || m.element_tekst AS element_tekst,
			a.underelement_kode,
			a.underelement_kode || ' ' || l.underelement_tekst AS underelement_tekst,

			public.ST_Length(a.geometri)::numeric(10,1) AS laengde,
			a.bredde,
			a.hoejde,
			
			a.litra,
						
			CASE
				WHEN a.underelement_kode = 'BL-05-02'
				THEN (public.ST_Length(a.geometri) * a.hoejde)::numeric(10,1)
				ELSE NULL
			END AS klip_flade
		FROM greg.t_greg_linier a
		LEFT JOIN greg.d_basis_ansvarlig_myndighed b ON a.cvr_kode = b.cvr_kode
		LEFT JOIN greg.d_basis_bruger_id c ON a.bruger_id_start = c.bruger_id
		LEFT JOIN greg.d_basis_oprindelse d ON a.oprindkode = d.oprindkode
		LEFT JOIN greg.d_basis_status e ON a.statuskode = e.statuskode
		LEFT JOIN greg.d_basis_offentlig f ON a.off_kode = f.off_kode

		LEFT JOIN greg.d_basis_vejnavn g ON a.vejkode = g.vejkode
		LEFT JOIN greg.d_basis_tilstand h ON a.tilstand_kode = h.tilstand_kode
		LEFT JOIN greg.d_basis_udfoerer_entrep i ON a.udfoerer_entrep_kode = i.udfoerer_entrep_kode
		LEFT JOIN greg.d_basis_kommunal_kontakt j ON a.kommunal_kontakt_kode = j.kommunal_kontakt_kode

		LEFT JOIN greg.t_greg_omraader k ON a.arbejdssted = k.pg_distrikt_nr
		LEFT JOIN greg.e_basis_underelementer l ON a.underelement_kode = l.underelement_kode
		LEFT JOIN greg.e_basis_elementer m ON l.element_kode = m.element_kode
		LEFT JOIN greg.e_basis_hovedelementer n ON m.hovedelement_kode = n.hovedelement_kode
		LEFT JOIN greg.d_basis_bruger_id o ON a.bruger_id_slut = o.bruger_id
		WHERE systid_fra::timestamp(0) <= ($3 || '-' || $2 || '-' || $1 || ' 23:59:00')::timestamp(0) AND (systid_til IS NULL OR systid_til::timestamp(0) >  ($3 || '-' || $2 || '-' || $1 || ' 23:59:00')::timestamp(0)) -- Date of creation is before (or on) the given date and the element is either still current or terminated after the current date
	)

SELECT * FROM tgl;

$$;

COMMENT ON FUNCTION greg.f_dato_linier(integer, integer, integer) IS 'Simulering af registreringen på en bestemt dato. Format: dd-MM-yyyy.';


-- f_dato_punkter(integer, integer, integer);

DROP FUNCTION IF EXISTS greg.f_dato_punkter(integer, integer, integer);

CREATE FUNCTION greg.f_dato_punkter(integer, integer, integer)
	RETURNS TABLE(
		versions_id uuid,
		objekt_id uuid,
		oprettet timestamp with time zone,
		systid_fra timestamp with time zone,
		systid_til timestamp with time zone,
		bruger_id_start character varying,
		bruger_start character varying,
		bruger_id_slut character varying,
		bruger_slut character varying,

		geometri public.geometry('MultiPoint', 25832),

		cvr_kode integer,
		cvr_navn character varying,
		oprindkode integer,
		oprindelse character varying,
		statuskode integer,
		status character varying,
		off_kode integer,
		offentlig character varying,

		note character varying,
		link character varying,
		vejkode integer,
		vejnavn character varying,
		tilstand_kode integer,
		tilstand character varying,
		anlaegsaar date,
		udfoerer_entrep_kode integer,
		udfoerer_entrep character varying,
		kommunal_kontakt_kode integer,
		kommunal_kontakt character varying,

		arbejdssted integer,
		pg_distrikt_tekst character varying,
		hovedelement_kode character varying,
		hovedelement_tekst character varying,
		element_kode character varying,
		element_tekst character varying,
		underelement_kode character varying,
		underelement_tekst character varying,

		laengde numeric(10,2),
		bredde numeric(10,2),
		diameter numeric(10,2),
		hoejde numeric(10,2),

		slaegt character varying,
		art character varying,

		litra character varying
	)
	LANGUAGE sql
	AS $$

WITH

tgp AS (
		SELECT -- Select everything present at the end of the given day
			a.versions_id,
			a.objekt_id,
			a.oprettet,
			a.systid_fra,
			a.systid_til,
			a.bruger_id_start,
			c.navn AS bruger_start,
			a.bruger_id_slut,
			o.navn AS bruger_slut,

			a.geometri,

			a.cvr_kode,
			b.cvr_navn,
			a.oprindkode,
			d.oprindelse,
			a.statuskode,
			e.status,
			a.off_kode,
			f.offentlig,

			a.note,
			a.link,
			a.vejkode,
			g.vejnavn || ' (' || g.postnr || ')' AS vejnavn,
			a.tilstand_kode,
			h.tilstand,
			a.anlaegsaar,
			a.udfoerer_entrep_kode,
			i.udfoerer_entrep,
			a.kommunal_kontakt_kode,
			j.navn || ', tlf: ' || j.telefon || ', ' || j.email AS kommunal_kontakt,

			a.arbejdssted,
			a.arbejdssted || ' ' || k.pg_distrikt_tekst AS pg_distrikt_tekst,
			n.hovedelement_kode,
			n.hovedelement_kode || ' - ' || n.hovedelement_tekst AS hovedelement_tekst,
			m.element_kode,
			m.element_kode || ' ' || m.element_tekst AS element_tekst,
			a.underelement_kode,
			a.underelement_kode || ' ' || l.underelement_tekst AS underelement_tekst,
	
			a.laengde,
			a.bredde,
			a.diameter,
			a.hoejde,

			a.slaegt,
			a.art,

			a.litra
		FROM greg.t_greg_punkter a
		LEFT JOIN greg.d_basis_ansvarlig_myndighed b ON a.cvr_kode = b.cvr_kode
		LEFT JOIN greg.d_basis_bruger_id c ON a.bruger_id_start = c.bruger_id
		LEFT JOIN greg.d_basis_oprindelse d ON a.oprindkode = d.oprindkode
		LEFT JOIN greg.d_basis_status e ON a.statuskode = e.statuskode
		LEFT JOIN greg.d_basis_offentlig f ON a.off_kode = f.off_kode

		LEFT JOIN greg.d_basis_vejnavn g ON a.vejkode = g.vejkode
		LEFT JOIN greg.d_basis_tilstand h ON a.tilstand_kode = h.tilstand_kode
		LEFT JOIN greg.d_basis_udfoerer_entrep i ON a.udfoerer_entrep_kode = i.udfoerer_entrep_kode
		LEFT JOIN greg.d_basis_kommunal_kontakt j ON a.kommunal_kontakt_kode = j.kommunal_kontakt_kode

		LEFT JOIN greg.t_greg_omraader k ON a.arbejdssted = k.pg_distrikt_nr
		LEFT JOIN greg.e_basis_underelementer l ON a.underelement_kode = l.underelement_kode
		LEFT JOIN greg.e_basis_elementer m ON l.element_kode = m.element_kode
		LEFT JOIN greg.e_basis_hovedelementer n ON m.hovedelement_kode = n.hovedelement_kode
		LEFT JOIN greg.d_basis_bruger_id o ON a.bruger_id_slut = o.bruger_id
		WHERE systid_fra::timestamp(0) <= ($3 || '-' || $2 || '-' || $1 || ' 23:59:00')::timestamp(0) AND (systid_til IS NULL OR systid_til::timestamp(0) >  ($3 || '-' || $2 || '-' || $1 || ' 23:59:00')::timestamp(0)) -- Date of creation is before (or on) the given date and the element is either still current or terminated after the current date
	)

SELECT * FROM tgp;

$$;

COMMENT ON FUNCTION greg.f_dato_punkter(integer, integer, integer) IS 'Simulering af registreringen på en bestemt dato. Format: dd-MM-yyyy.';


-- f_tot_flader(integer)

DROP FUNCTION IF EXISTS greg.f_tot_flader(integer);

CREATE FUNCTION greg.f_tot_flader(integer)
	RETURNS TABLE(
		objekt_id uuid,
		geometri public.geometry('MultiPolygon', 25832),
		handling text,
		dato date,
		element text,
		arbejdssted text
	)
	LANGUAGE sql
	AS $$

WITH

tgf AS (
		SELECT -- Select all inserts and updates in the main data within a specific number of days
			a.objekt_id,
			a.geometri,
			CASE
				WHEN a.systid_fra = a.oprettet
				THEN 'Tilføjet'
				WHEN a.oprettet <> a.systid_fra AND current_date - a.oprettet::date < $1
				THEN 'Tilføjet og ændret'
				ELSE 'Ændret'
			END AS handling,
			a.systid_fra::date AS dato,
			a.underelement_kode || ' ' || b.underelement_tekst AS element,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted
		FROM greg.t_greg_flader a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE current_date - a.systid_fra::date < $1 AND systid_til IS NULL
	),

tghf AS (
		SELECT DISTINCT ON(a.objekt_id) -- Select all delete operations from the history within a specific number of days
			a.objekt_id,
			a.geometri,
			CASE
				WHEN current_date - a.oprettet::date < $1
				THEN 'Tilføjet og slettet'::text
				ELSE 'Slettet'::text
			END AS handling,
			a.systid_til::date AS dato,
			a.underelement_kode || ' ' || b.underelement_tekst AS element,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted
		FROM greg.t_greg_flader a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE current_date - a.systid_til::date < $1 AND a.objekt_id NOT IN(SELECT objekt_id FROM tgf)

		ORDER BY a.objekt_id ASC, a.systid_til DESC
	)

SELECT * FROM tgf
UNION
SELECT * FROM tghf;

$$;

COMMENT ON FUNCTION greg.f_tot_flader(integer) IS 'Ændringsoversigt med tilhørende geometri. Defineres inden for x antal dage.';


-- f_tot_linier(integer)

DROP FUNCTION IF EXISTS greg.f_tot_linier(integer);

CREATE FUNCTION greg.f_tot_linier(integer)
	RETURNS TABLE(
		objekt_id uuid,
		geometri public.geometry('MultiLineString', 25832),
		handling text,
		dato date,
		element text,
		arbejdssted text
	)
	LANGUAGE sql
	AS $$

WITH

tgl AS (
		SELECT -- Select all inserts and updates in the main data within a specific number of days
			a.objekt_id,
			a.geometri,
			CASE
				WHEN a.systid_fra = a.oprettet
				THEN 'Tilføjet'
				WHEN a.oprettet <> a.systid_fra AND current_date - a.oprettet::date < $1
				THEN 'Tilføjet og ændret'
				ELSE 'Ændret'
			END AS handling,
			a.systid_fra::date AS dato,
			a.underelement_kode || ' ' || b.underelement_tekst AS element,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted
		FROM greg.t_greg_linier a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE current_date - a.systid_fra::date < $1 AND systid_til IS NULL
	),

tghl AS (
		SELECT DISTINCT ON(a.objekt_id) -- Select all delete operations from the history within a specific number of days
			a.objekt_id,
			a.geometri,
			CASE
				WHEN current_date - a.oprettet::date < $1
				THEN 'Tilføjet og slettet'::text
				ELSE 'Slettet'::text
			END AS handling,
			a.systid_til::date AS dato,
			a.underelement_kode || ' ' || b.underelement_tekst AS element,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted
		FROM greg.t_greg_linier a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE current_date - a.systid_til::date < $1 AND a.objekt_id NOT IN(SELECT objekt_id FROM tgl)

		ORDER BY a.objekt_id ASC, a.systid_til DESC
	)

SELECT * FROM tgl
UNION
SELECT * FROM tghl;

$$;

COMMENT ON FUNCTION greg.f_tot_linier(integer) IS 'Ændringsoversigt med tilhørende geometri. Defineres inden for x antal dage.';


-- f_tot_punkter(integer)

DROP FUNCTION IF EXISTS greg.f_tot_punkter(integer);

CREATE FUNCTION greg.f_tot_punkter(integer)
	RETURNS TABLE(
		objekt_id uuid,
		geometri public.geometry('MultiPoint', 25832),
		handling text,
		dato date,
		element text,
		arbejdssted text
	)
	LANGUAGE sql
	AS $$

WITH

tgp AS (
		SELECT -- Select all inserts and updates in the main data within a specific number of days
			a.objekt_id,
			a.geometri,
			CASE
				WHEN a.systid_fra = a.oprettet
				THEN 'Tilføjet'
				WHEN a.oprettet <> a.systid_fra AND current_date - a.oprettet::date < $1
				THEN 'Tilføjet og ændret'
				ELSE 'Ændret'
			END AS handling,
			a.systid_fra::date AS dato,
			a.underelement_kode || ' ' || b.underelement_tekst AS element,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted
		FROM greg.t_greg_punkter a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE current_date - a.systid_fra::date < $1 AND systid_til IS NULL
	),

tghp AS (
		SELECT DISTINCT ON(a.objekt_id) -- Select all delete operations from the history within a specific number of days
			a.objekt_id,
			a.geometri,
			CASE
				WHEN current_date - a.oprettet::date < $1
				THEN 'Tilføjet og slettet'::text
				ELSE 'Slettet'::text
			END AS handling,
			a.systid_til::date AS dato,
			a.underelement_kode || ' ' || b.underelement_tekst AS element,
			a.arbejdssted || ' ' || c.pg_distrikt_tekst AS arbejdssted
		FROM greg.t_greg_punkter a
		LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
		WHERE current_date - a.systid_til::date < $1 AND a.objekt_id NOT IN(SELECT objekt_id FROM tgp)

		ORDER BY a.objekt_id ASC, a.systid_til DESC
	)

SELECT * FROM tgp
UNION
SELECT * FROM tghp;

$$;

COMMENT ON FUNCTION greg.f_tot_punkter(integer) IS 'Ændringsoversigt med tilhørende geometri. Defineres inden for x antal dage.';


--
-- TRIGGER FUNCTIONS
--

-- basis_aktiv_trg()

CREATE FUNCTION greg.basis_aktiv_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		NEW.aktiv = COALESCE(NEW.aktiv, 't');

		RETURN NEW;

	END;

$$;

COMMENT ON FUNCTION greg.basis_aktiv_trg() IS 'Tilføjer aktiv = TRUE som DEFAULT.';


-- e_basis_underelementer_trg()

CREATE FUNCTION greg.e_basis_underelementer_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		-- Set DEFAULT table specific values (Updateable views)
		NEW.enhedspris_point = COALESCE(NEW.enhedspris_point, 0.00);
		NEW.enhedspris_line = COALESCE(NEW.enhedspris_line, 0.00);
		NEW.enhedspris_poly = COALESCE(NEW.enhedspris_poly, 0.00);
		NEW.enhedspris_speciel = COALESCE(NEW.enhedspris_speciel, 0.00);
		NEW.aktiv = COALESCE(NEW.aktiv, 't');

		RETURN NEW;

	END;

$$;

COMMENT ON FUNCTION greg.e_basis_underelementer_trg() IS 'Tilføjer DEAFULT VALUES, hvis ingen er angivet, da disse ikke angives automatisk via updateable views i QGIS.';


-- t_greg_generel_trg()

CREATE FUNCTION greg.t_greg_generel_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF ((TG_OP = 'DELETE') OR (TG_OP = 'UPDATE')) AND OLD.systid_til IS NOT NULL THEN -- If record is a part of history

			RETURN NULL;

		END IF;

		IF (TG_OP = 'DELETE') THEN

			RETURN OLD; -- Record is re-inserted with timestamp via AFTER-trigger to avoid conflicts with following trigger procedures on t_greg_flader

		ELSIF (TG_OP = 'UPDATE') THEN

			-- Updated feature
			NEW.versions_id = public.uuid_generate_v1();
			NEW.objekt_id = OLD.objekt_id; -- Overwrites potential changes from user
			NEW.oprettet = OLD.oprettet; -- Overwrites potential changes from user
			NEW.systid_fra = current_timestamp;
			NEW.systid_til = NULL; -- Overwrites potential changes from user
			NEW.bruger_id_start = current_user;
			NEW.bruger_id_slut = NULL; -- Overwrites potential changes from user
			NEW.geometri = public.ST_Multi(NEW.geometri); -- Force geometry into multigeometry

			-- Old record is inserted via an AFTER-trigger to avoid conflicts with PK

			RETURN NEW;

		ELSIF (TG_OP = 'INSERT') THEN

			IF NEW.systid_til = current_timestamp THEN -- Ignored if triggered via an UPDATE- / DELETE-action (via AFTER-trigger)

				RETURN NEW;

			END IF;

			-- Automated values and geometry
			NEW.versions_id = public.uuid_generate_v1();
			NEW.objekt_id = NEW.versions_id;
			NEW.oprettet = current_timestamp;
			NEW.systid_fra = NEW.oprettet;
			NEW.systid_til = NULL; -- Overwrites potential changes from user
			NEW.bruger_id_start = current_user;
			NEW.bruger_id_slut = NULL; -- Overwrites potential changes from user
			NEW.geometri = public.ST_Multi(NEW.geometri); -- Force geometry into multigeometry

			-- Universal DEFAULT values
			NEW.cvr_kode = COALESCE(NEW.cvr_kode, 29189129);
			NEW.oprindkode = COALESCE(NEW.oprindkode, 0);
			NEW.statuskode = COALESCE(NEW.statuskode, 0);
			NEW.off_kode = COALESCE(NEW.off_kode, 1);
			NEW.tilstand_kode = COALESCE(NEW.tilstand_kode,9);

			RETURN NEW;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.t_greg_generel_trg() IS 'Generelle informationer ved INSERT/UPDATE/DELETE for at opretholde historik, samt universelle DEFAULT values.';


-- t_greg_historik_trg_a_ud()

CREATE FUNCTION greg.t_greg_historik_trg_a_ud() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		OLD.systid_til = current_timestamp;
		OLD.bruger_id_slut = current_user;
		EXECUTE FORMAT('INSERT INTO %s SELECT $1.*', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME)
		USING OLD;

		RETURN NULL;

	END;

$$;

COMMENT ON FUNCTION greg.t_greg_historik_trg_a_ud() IS 'Indsætter den originale feature efter UPDATE / DELETE med påført systid_til.';


-- t_greg_flader_trg()

CREATE OR REPLACE FUNCTION greg.t_greg_flader_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF NEW.systid_til = current_timestamp THEN -- Ignored if triggered via an UPDATE- / DELETE-action (via AFTER-trigger)

			RETURN NEW;

		END IF;

		IF EXISTS (SELECT '1' FROM greg.t_greg_flader WHERE public.ST_Contains(geometri, NEW.geometri) IS TRUE AND systid_til IS NULL) THEN -- Geometry check #1: NEW.Geometry contained by an existing geometry

			RAISE EXCEPTION 'Geometrien befinder sig i en anden geometri';

		END IF;

		IF EXISTS (SELECT '1' FROM greg.t_greg_flader WHERE (public.ST_Overlaps(NEW.geometri, geometri) IS TRUE OR public.ST_Within(geometri, NEW.geometri) IS TRUE) AND systid_til IS NULL) THEN -- Geometry check #2: Overlaps and existing geometries contained by NEW.geometry

			NEW.geometri = public.ST_Multi(public.ST_CollectionExtract(public.ST_Difference(NEW.geometri, (SELECT public.ST_Union(geometri) FROM greg.t_greg_flader WHERE (public.ST_Overlaps(NEW.geometri, geometri) IS TRUE OR public.ST_Within(geometri, NEW.geometri) IS TRUE) AND systid_til IS NULL)), 3));

		END IF;

		-- Set DEFAULT table specific values (Updateable views)
		NEW.hoejde = COALESCE(NEW.hoejde, 0.0);
		NEW.klip_sider = COALESCE(NEW.klip_sider, 0);

		RETURN NEW;

	END;

$$;

COMMENT ON FUNCTION greg.t_greg_flader_trg() IS 'Geometritjeks:
1) Geometrier må ikke overlappe eksisterende geometrier - tilskæres automatisk,
2) Geometrier må ikke befinde sig inde i andre geometrier.

Tilføjer DEAFULT VALUES, hvis ingen er angivet, da disse ikke angives automatisk via updateable views i QGIS.';


-- t_greg_linier_trg()

CREATE FUNCTION greg.t_greg_linier_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF NEW.systid_til = current_timestamp THEN -- Ignored if triggered via an UPDATE- / DELETE-action (via AFTER-trigger)

			RETURN NEW;

		END IF;

		-- Set DEFAULT table specific values (Updateable views)
		NEW.bredde = COALESCE(NEW.bredde, 0.0);
		NEW.hoejde = COALESCE(NEW.hoejde, 0.0);

		RETURN NEW;

	END;

$$;

COMMENT ON FUNCTION greg.t_greg_linier_trg() IS 'Tilføjer DEAFULT VALUES, hvis ingen er angivet, da disse ikke angives automatisk via updateable views i QGIS.';


-- t_greg_punkter_trg()

CREATE FUNCTION greg.t_greg_punkter_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF NEW.systid_til = current_timestamp THEN -- Ignored if triggered via an UPDATE- / DELETE-action (via AFTER-trigger)

			RETURN NEW;

		END IF;

		-- Set DEFAULT table specific values (Updateable views)
		NEW.laengde = COALESCE(NEW.laengde, 0.0);
		NEW.bredde = COALESCE(NEW.bredde, 0.0);
		NEW.diameter = COALESCE(NEW.diameter, 0.0);
		NEW.hoejde = COALESCE(NEW.hoejde, 0.0);

		RETURN NEW;

	END;

$$;

COMMENT ON FUNCTION greg.t_greg_punkter_trg() IS 'Tilføjer DEAFULT VALUES, hvis ingen er angivet, da disse ikke angives automatisk via updateable views i QGIS.';


-- t_greg_omraader_trg()

CREATE OR REPLACE FUNCTION greg.t_greg_omraader_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	DECLARE
	
		distrikt_type text;

	BEGIN

		IF (TG_OP = 'UPDATE') THEN

			NEW.objekt_id = OLD.objekt_id; -- Overwrites potential changes from user
			NEW.geometri = public.ST_Multi(NEW.geometri);

			IF OLD.pg_distrikt_nr <> NEW.pg_distrikt_nr THEN
				INSERT INTO greg.d_basis_omraadenr -- Insertion into FK table (Indirect relation between areas and data). OLD record is deleted in AFTER-trigger. Only possible if no data in relation to area at all, history included
					VALUES (
						NEW.pg_distrikt_nr
					);
			END IF;

			RETURN NEW;

		ELSIF (TG_OP = 'INSERT') THEN

			SELECT pg_distrikt_type INTO distrikt_type FROM greg.d_basis_distrikt_type WHERE pg_distrikt_type_kode = NEW.pg_distrikt_type_kode;

			IF EXISTS (SELECT '1' FROM greg.t_greg_omraader WHERE public.ST_Contains(geometri, NEW.geometri) IS TRUE AND distrikt_type NOT IN('Vejarealer')) THEN -- Geometry check #1: NEW.Geometry contained by an existing geometry

				RAISE EXCEPTION 'Geometrien befinder sig i en anden geometri';

			END IF;

			IF EXISTS (SELECT '1' FROM greg.t_greg_omraader WHERE (public.ST_Overlaps(NEW.geometri, geometri) IS TRUE OR public.ST_Within(geometri, NEW.geometri) IS TRUE) AND distrikt_type NOT IN('Vejarealer')) THEN -- Geometry check #2: Overlaps and existing geometries contained by NEW.geometry

				NEW.geometri = public.ST_Multi(public.ST_CollectionExtract(public.ST_Difference(NEW.geometri, (SELECT public.ST_Union(geometri) FROM greg.t_greg_omraader WHERE (public.ST_Overlaps(NEW.geometri, geometri) IS TRUE OR public.ST_Within(geometri, NEW.geometri) IS TRUE) AND distrikt_type NOT IN('Vejarealer'))), 3));

			ELSE

				NEW.geometri = public.ST_Multi(NEW.geometri);

			END IF;

			INSERT INTO greg.d_basis_omraadenr -- Insertion into FK table (Indirect relation between areas and data)
				VALUES (
					NEW.pg_distrikt_nr
				);

			NEW.objekt_id = public.uuid_generate_v1();

			-- Set DEFAULT table specific values (Updateable views)
			NEW.aktiv = COALESCE(NEW.aktiv, 't');
			NEW.auto_opdat = COALESCE(NEW.auto_opdat, 't');

			RETURN NEW;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.t_greg_omraader_trg() IS 'Geometritjeks:
1) Geometrier må ikke overlappe eksisterende geometrier - tilskæres automatisk,
2) Geometrier må ikke befinde sig inde i andre geometrier.

Tilføjer DEAFULT VALUES, hvis ingen er angivet, da disse ikke angives automatisk via updateable views i QGIS.';

-- t_greg_omraader_trg_a_ud()

CREATE OR REPLACE FUNCTION greg.t_greg_omraader_trg_a_ud() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			DELETE FROM greg.t_greg_delomraader
				WHERE pg_distrikt_nr = OLD.pg_distrikt_nr;	

			DELETE FROM greg.d_basis_omraadenr
				WHERE pg_distrikt_nr = OLD.pg_distrikt_nr;		

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF OLD.pg_distrikt_nr = NEW.pg_distrikt_nr THEN

				RETURN NULL;

			END IF;

			UPDATE greg.t_greg_delomraader
				SET
					pg_distrikt_nr = NEW.pg_distrikt_nr
				WHERE pg_distrikt_nr = OLD.pg_distrikt_nr;

			DELETE FROM greg.d_basis_omraadenr
				WHERE pg_distrikt_nr = OLD.pg_distrikt_nr;

			RETURN NULL;

		END IF;	
	END

$$;

COMMENT ON FUNCTION greg.t_greg_omraader_trg_a_ud() IS 'Opdaterer rådata tabeller, samt delområder ved eventuelle ændringer af områdenumre.';

-- t_greg_omraader_upt_trg()

CREATE OR REPLACE FUNCTION greg.t_greg_omraader_upt_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	DECLARE

		geometri_n public.geometry;
		geometri_o public.geometry;
		opdatering_o boolean;
		opdatering_n boolean;
		fl_n public.geometry;
		fl_o public.geometry;

	BEGIN

		IF (TG_OP = 'DELETE') THEN

				-- Updateable area
				SELECT
					auto_opdat
				FROM greg.t_greg_omraader
				INTO opdatering_o WHERE pg_distrikt_nr = OLD.arbejdssted;

			IF opdatering_o IS TRUE THEN

				-- Polygons for differences and disjoints
				SELECT
					CASE
						WHEN public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 0.0001)) IS NULL
						THEN ST_GeomFromText('POLYGON EMPTY', 25832)
						ELSE public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 0.0001))
					END AS geometri
				FROM greg.t_greg_flader
				INTO fl_o WHERE arbejdssted = OLD.arbejdssted AND systid_til IS NULL;

				-- Geometry unions (OLD)
				SELECT
					public.ST_Multi(public.ST_Union(a.st_multi))
				FROM (	SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 0.0001))
						FROM greg.t_greg_flader
						WHERE arbejdssted = OLD.arbejdssted AND systid_til IS NULL
					UNION ALL
						SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 2))
						FROM greg.t_greg_linier
						WHERE arbejdssted = OLD.arbejdssted AND public.ST_Disjoint(geometri, fl_o) IS TRUE AND systid_til IS NULL
					UNION ALL
						SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Difference(public.ST_Union(geometri), fl_o), 2))
						FROM greg.t_greg_linier
						WHERE arbejdssted = OLD.arbejdssted AND systid_til IS NULL
					UNION ALL
						SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 2))
						FROM greg.t_greg_punkter
						WHERE arbejdssted = OLD.arbejdssted AND public.ST_Disjoint(geometri, fl_o) IS TRUE AND systid_til IS NULL) a
				INTO geometri_o;

				UPDATE greg.t_greg_omraader
					SET
						geometri = geometri_o
					WHERE pg_distrikt_nr = OLD.arbejdssted AND pg_distrikt_type_kode NOT IN(3);

			END IF;

			RETURN OLD;

		ELSIF (TG_OP = 'UPDATE') THEN

			-- Polygons for differences and disjoints
			SELECT
				CASE
					WHEN public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 0.0001)) IS NULL
					THEN ST_GeomFromText('POLYGON EMPTY', 25832)
					ELSE public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 0.0001))
				END AS geometri
			FROM greg.t_greg_flader
			INTO fl_n WHERE arbejdssted = NEW.arbejdssted AND systid_til IS NULL;

			SELECT
				CASE
					WHEN public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 0.0001)) IS NULL
					THEN ST_GeomFromText('POLYGON EMPTY', 25832)
					ELSE public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 0.0001))
				END AS geometri
			FROM greg.t_greg_flader
			INTO fl_o WHERE arbejdssted = OLD.arbejdssted AND systid_til IS NULL;

			-- Updateable area
			SELECT
				auto_opdat
			FROM greg.t_greg_omraader
			INTO opdatering_o WHERE pg_distrikt_nr = OLD.arbejdssted;

			SELECT
				auto_opdat
			FROM greg.t_greg_omraader
			INTO opdatering_n WHERE pg_distrikt_nr = NEW.arbejdssted;

			IF OLD.arbejdssted <> NEW.arbejdssted AND opdatering_o IS TRUE THEN

				-- Geometry unions (OLD)
				SELECT
					public.ST_Multi(public.ST_Union(a.st_multi))
				FROM (	SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 0.0001))
						FROM greg.t_greg_flader
						WHERE arbejdssted = OLD.arbejdssted AND systid_til IS NULL
					UNION ALL
						SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 2))
						FROM greg.t_greg_linier
						WHERE arbejdssted = OLD.arbejdssted AND public.ST_Disjoint(geometri, fl_o) IS TRUE AND systid_til IS NULL
					UNION ALL
						SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Difference(public.ST_Union(geometri), fl_o), 2))
						FROM greg.t_greg_linier
						WHERE arbejdssted = OLD.arbejdssted AND systid_til IS NULL
					UNION ALL
						SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 2))
						FROM greg.t_greg_punkter
						WHERE arbejdssted = OLD.arbejdssted AND public.ST_Disjoint(geometri, fl_o) IS TRUE AND systid_til IS NULL) a
				INTO geometri_o;

				UPDATE greg.t_greg_omraader
					SET
						geometri = geometri_o
					WHERE pg_distrikt_nr = OLD.arbejdssted AND pg_distrikt_type_kode NOT IN(3);

			END IF;

			IF (OLD.arbejdssted <> NEW.arbejdssted OR public.ST_Equals(OLD.geometri, NEW.geometri) IS FALSE) AND opdatering_n IS TRUE THEN

				-- Geometry unions (NEW)
				SELECT
					public.ST_Multi(public.ST_Union(a.st_multi))
				FROM (	SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 0.0001))
						FROM greg.t_greg_flader
						WHERE arbejdssted = NEW.arbejdssted AND systid_til IS NULL
					UNION ALL
						SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 2))
						FROM greg.t_greg_linier
						WHERE arbejdssted = NEW.arbejdssted AND public.ST_Disjoint(geometri, fl_n) IS TRUE AND systid_til IS NULL
					UNION ALL
						SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Difference(public.ST_Union(geometri), fl_n), 2))
						FROM greg.t_greg_linier
						WHERE arbejdssted = NEW.arbejdssted AND systid_til IS NULL
					UNION ALL
						SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 2))
						FROM greg.t_greg_punkter
						WHERE arbejdssted = NEW.arbejdssted AND public.ST_Disjoint(geometri, fl_n) IS TRUE AND systid_til IS NULL) a
				INTO geometri_n;

				UPDATE greg.t_greg_omraader
					SET
						geometri = geometri_n
					WHERE pg_distrikt_nr = NEW.arbejdssted AND pg_distrikt_type_kode NOT IN(3);

			END IF;

			RETURN NEW;

		ELSIF (TG_OP = 'INSERT') THEN

			-- Polygons for differences and disjoints
			SELECT
				CASE
					WHEN public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 0.0001)) IS NULL
					THEN ST_GeomFromText('POLYGON EMPTY', 25832)
					ELSE public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 0.0001))
				END AS geometri
			FROM greg.t_greg_flader
			INTO fl_n WHERE arbejdssted = NEW.arbejdssted AND systid_til IS NULL;

			-- Updateable area
			SELECT
				auto_opdat
			FROM greg.t_greg_omraader
			INTO opdatering_n WHERE pg_distrikt_nr = NEW.arbejdssted;

			IF opdatering_n IS TRUE THEN

				-- Geometry unions (NEW)
				SELECT
					public.ST_Multi(public.ST_Union(a.st_multi))
				FROM (	SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 0.0001))
						FROM greg.t_greg_flader
						WHERE arbejdssted = NEW.arbejdssted AND systid_til IS NULL
					UNION ALL
						SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 2))
						FROM greg.t_greg_linier
						WHERE arbejdssted = NEW.arbejdssted AND public.ST_Disjoint(geometri, fl_n) IS TRUE AND systid_til IS NULL
					UNION ALL
						SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Difference(public.ST_Union(geometri), fl_n), 2))
						FROM greg.t_greg_linier
						WHERE arbejdssted = NEW.arbejdssted AND systid_til IS NULL
					UNION ALL
						SELECT
							public.ST_Multi(public.ST_Buffer(public.ST_Union(geometri), 2))
						FROM greg.t_greg_punkter
						WHERE arbejdssted = NEW.arbejdssted AND public.ST_Disjoint(geometri, fl_n) IS TRUE AND systid_til IS NULL) a
				INTO geometri_n;

				UPDATE greg.t_greg_omraader
					SET
						geometri = geometri_n
					WHERE pg_distrikt_nr = NEW.arbejdssted AND pg_distrikt_type_kode NOT IN(3);

			END IF;

			RETURN NEW;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.t_greg_omraader_upt_trg() IS 'Opdaterer områdegrænsen, når der sker ændringer i registreringen';


-- t_greg_delomraader_trg()

CREATE OR REPLACE FUNCTION greg.t_greg_delomraader_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'UPDATE') THEN

			NEW.objekt_id = OLD.objekt_id; -- Overwrites potential changes from user
			NEW.geometri = public.ST_Multi(NEW.geometri);

			RETURN NEW;

		ELSIF (TG_OP = 'INSERT') THEN

			NEW.objekt_id = public.uuid_generate_v1();
			NEW.geometri = public.ST_Multi(NEW.geometri);

			RETURN NEW;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.t_greg_delomraader_trg() IS 'Indsætter UUID, retter geometri til ST_Multi og retter bruger_id, hvis ikke angivet.';


-- v_basis_bruger_id_trg()

CREATE OR REPLACE FUNCTION greg.v_basis_bruger_id_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.d_basis_bruger_id WHERE bruger_id = OLD.bruger_id) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.d_basis_bruger_id
				WHERE bruger_id = OLD.bruger_id;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.d_basis_bruger_id WHERE bruger_id = OLD.bruger_id) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.d_basis_bruger_id
				SET
					bruger_id = NEW.bruger_id,
					navn = NEW.navn,
					aktiv = NEW.aktiv
				WHERE bruger_id = OLD.bruger_id;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.d_basis_bruger_id
				VALUES (
					NEW.bruger_id,
					NEW.navn,
					NEW.aktiv
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_basis_bruger_id_trg() IS 'Muliggør opdatering gennem v_basis_bruger_id.';


-- v_basis_kommunal_kontakt_trg()

CREATE OR REPLACE FUNCTION greg.v_basis_kommunal_kontakt_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.d_basis_kommunal_kontakt WHERE kommunal_kontakt_kode = OLD.kommunal_kontakt_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.d_basis_kommunal_kontakt
				WHERE kommunal_kontakt_kode = OLD.kommunal_kontakt_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.d_basis_kommunal_kontakt WHERE kommunal_kontakt_kode = OLD.kommunal_kontakt_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.d_basis_kommunal_kontakt
				SET
					navn = NEW.navn,
					telefon = NEW.telefon,
					email = NEW.email,
					aktiv = NEW.aktiv
				WHERE kommunal_kontakt_kode = OLD.kommunal_kontakt_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.d_basis_kommunal_kontakt (navn, telefon, email, aktiv)
				VALUES (
					NEW.navn,
					NEW.telefon,
					NEW.email,
					NEW.aktiv
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_basis_kommunal_kontakt_trg() IS 'Muliggør opdatering gennem v_basis_kommunal_kontakt.';


-- v_basis_udfoerer_trg()

CREATE OR REPLACE FUNCTION greg.v_basis_udfoerer_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.d_basis_udfoerer WHERE udfoerer_kode = OLD.udfoerer_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.d_basis_udfoerer
				WHERE udfoerer_kode = OLD.udfoerer_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.d_basis_udfoerer WHERE udfoerer_kode = OLD.udfoerer_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.d_basis_udfoerer
				SET
					udfoerer = NEW.udfoerer,
					aktiv = NEW.aktiv
				WHERE udfoerer_kode = OLD.udfoerer_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.d_basis_udfoerer (udfoerer, aktiv)
				VALUES (
					NEW.udfoerer,
					NEW.aktiv
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_basis_udfoerer_trg() IS 'Muliggør opdatering gennem v_basis_udfoerer.';


-- v_basis_udfoerer_entrep_trg()

CREATE OR REPLACE FUNCTION greg.v_basis_udfoerer_entrep_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.d_basis_udfoerer_entrep WHERE udfoerer_entrep_kode = OLD.udfoerer_entrep_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.d_basis_udfoerer_entrep
				WHERE udfoerer_entrep_kode = OLD.udfoerer_entrep_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.d_basis_udfoerer_entrep WHERE udfoerer_entrep_kode = OLD.udfoerer_entrep_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.d_basis_udfoerer_entrep
				SET
					udfoerer_entrep = NEW.udfoerer_entrep,
					aktiv = NEW.aktiv
				WHERE udfoerer_entrep_kode = OLD.udfoerer_entrep_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.d_basis_udfoerer_entrep (udfoerer_entrep, aktiv)
				VALUES (
					NEW.udfoerer_entrep,
					NEW.aktiv
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_basis_udfoerer_entrep_trg() IS 'Muliggør opdatering gennem v_basis_udfoerer_entrep.';


-- v_basis_udfoerer_kontakt_trg()

CREATE OR REPLACE FUNCTION greg.v_basis_udfoerer_kontakt_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.d_basis_udfoerer_kontakt WHERE udfoerer_kontakt_kode = OLD.udfoerer_kontakt_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.d_basis_udfoerer_kontakt
				WHERE udfoerer_kontakt_kode = OLD.udfoerer_kontakt_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.d_basis_udfoerer_kontakt WHERE udfoerer_kontakt_kode = OLD.udfoerer_kontakt_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.d_basis_udfoerer_kontakt
				SET
					udfoerer_kode = NEW.udfoerer_kode,
					navn = NEW.navn,
					telefon = NEW.telefon,
					email = NEW.email,
					aktiv = NEW.aktiv
				WHERE udfoerer_kontakt_kode = OLD.udfoerer_kontakt_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.d_basis_udfoerer_kontakt (udfoerer_kode, navn, telefon, email, aktiv)
				VALUES (
					NEW.udfoerer_kode,
					NEW.navn,
					NEW.telefon,
					NEW.email,
					NEW.aktiv
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_basis_udfoerer_kontakt_trg() IS 'Muliggør opdatering gennem v_basis_udfoerer_kontakt.';


-- v_basis_distrikt_type_trg()

CREATE OR REPLACE FUNCTION greg.v_basis_distrikt_type_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.d_basis_distrikt_type WHERE pg_distrikt_type_kode = OLD.pg_distrikt_type_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.d_basis_distrikt_type
				WHERE pg_distrikt_type_kode = OLD.pg_distrikt_type_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.d_basis_distrikt_type WHERE pg_distrikt_type_kode = OLD.pg_distrikt_type_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.d_basis_distrikt_type
				SET
					pg_distrikt_type = NEW.pg_distrikt_type,
					aktiv = NEW.aktiv
				WHERE pg_distrikt_type_kode = OLD.pg_distrikt_type_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv)
				VALUES (
					NEW.pg_distrikt_type,
					NEW.aktiv
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_basis_distrikt_type_trg() IS 'Muliggør opdatering gennem v_basis_distrikt_type.';


-- v_basis_hovedelementer_trg()

CREATE OR REPLACE FUNCTION greg.v_basis_hovedelementer_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.e_basis_hovedelementer WHERE hovedelement_kode = OLD.hovedelement_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.e_basis_hovedelementer
				WHERE hovedelement_kode = OLD.hovedelement_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.e_basis_hovedelementer WHERE hovedelement_kode = OLD.hovedelement_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.e_basis_hovedelementer
				SET
					hovedelement_kode = NEW.hovedelement_kode,
					hovedelement_tekst = NEW.hovedelement_tekst,
					aktiv = NEW.aktiv
				WHERE hovedelement_kode = OLD.hovedelement_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.e_basis_hovedelementer
				VALUES (
					NEW.hovedelement_kode,
					NEW.hovedelement_tekst,
					NEW.aktiv
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_basis_hovedelementer_trg() IS 'Muliggør opdatering gennem v_basis_hovedelementer.';


-- v_basis_elementer_trg()

CREATE OR REPLACE FUNCTION greg.v_basis_elementer_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.e_basis_elementer WHERE element_kode = OLD.element_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.e_basis_elementer
				WHERE element_kode = OLD.element_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.e_basis_elementer WHERE element_kode = OLD.element_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.e_basis_elementer
				SET
					hovedelement_kode = NEW.hovedelement_kode,
					element_kode = NEW.element_kode,
					element_tekst = NEW.element_tekst,
					aktiv = NEW.aktiv
				WHERE element_kode = OLD.element_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.e_basis_elementer
				VALUES (
					NEW.hovedelement_kode,
					NEW.element_kode,
					NEW.element_tekst,
					NEW.aktiv
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_basis_elementer_trg() IS 'Muliggør opdatering gennem v_basis_elementer.';


-- v_basis_underelementer_trg()

CREATE OR REPLACE FUNCTION greg.v_basis_underelementer_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.e_basis_underelementer WHERE underelement_kode = OLD.underelement_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.e_basis_underelementer
				WHERE underelement_kode = OLD.underelement_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.e_basis_underelementer WHERE underelement_kode = OLD.underelement_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.e_basis_underelementer
				SET
					element_kode = NEW.element_kode,
					underelement_kode = NEW.underelement_kode,
					underelement_tekst = NEW.underelement_tekst,
					objekt_type = NEW.objekt_type,
					enhedspris_point = NEW.enhedspris_point,
					enhedspris_line = NEW.enhedspris_line,
					enhedspris_poly = NEW.enhedspris_poly,
					enhedspris_speciel = NEW.enhedspris_speciel,
					aktiv = NEW.aktiv
				WHERE underelement_kode = OLD.underelement_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.e_basis_underelementer
				VALUES (
				NEW.element_kode,
				NEW.underelement_kode,
				NEW.underelement_tekst,
				NEW.objekt_type,
				NEW.enhedspris_point,
				NEW.enhedspris_line,
				NEW.enhedspris_poly,
				NEW.enhedspris_speciel,	
				NEW.aktiv
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_basis_underelementer_trg() IS 'Muliggør opdatering gennem v_basis_underelementer.';


-- v_greg_flader_trg()

CREATE FUNCTION greg.v_greg_flader_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.t_greg_flader WHERE versions_id = OLD.versions_id AND systid_til IS NULL) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.t_greg_flader
				WHERE versions_id = OLD.versions_id;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.t_greg_flader WHERE versions_id = OLD.versions_id AND systid_til IS NULL) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.t_greg_flader
				SET
					geometri = NEW.geometri,

					cvr_kode = NEW.cvr_kode,
					oprindkode = NEW.oprindkode,
					statuskode = NEW.statuskode,
					off_kode = NEW.off_kode,

					note = NEW.note,
					link = NEW.link,
					tilstand_kode = NEW.tilstand_kode,
					vejkode = NEW.vejkode,
					anlaegsaar = NEW.anlaegsaar,
					udfoerer_entrep_kode = NEW.udfoerer_entrep_kode,
					kommunal_kontakt_kode = NEW.kommunal_kontakt_kode,

					arbejdssted = NEW.arbejdssted,
					underelement_kode = NEW.underelement_kode,

					hoejde = NEW.hoejde,
					klip_sider = NEW.klip_sider,

					litra = NEW.litra
				WHERE versions_id = OLD.versions_id;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.t_greg_flader
				VALUES (
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,

					NEW.geometri,

					NEW.cvr_kode,
					NEW.oprindkode,
					NEW.statuskode,
					NEW.off_kode,

					NEW.note,
					NEW.link,
					NEW.vejkode,
					NEW.tilstand_kode,
					NEW.anlaegsaar,
					NEW.udfoerer_entrep_kode,
					NEW.kommunal_kontakt_kode,

					NEW.arbejdssted,
					NEW.underelement_kode,

					NEW.hoejde,

					NEW.klip_sider,
					NEW.litra
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_greg_flader_trg() IS 'Muliggør opdatering gennem v_greg_flader.';


-- v_greg_linier_trg()

CREATE FUNCTION greg.v_greg_linier_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.t_greg_linier WHERE versions_id = OLD.versions_id AND systid_til IS NULL) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.t_greg_linier
				WHERE versions_id = OLD.versions_id;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.t_greg_linier WHERE versions_id = OLD.versions_id AND systid_til IS NULL) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.t_greg_linier
				SET
					geometri = NEW.geometri,

					cvr_kode = NEW.cvr_kode,
					oprindkode = NEW.oprindkode,
					statuskode = NEW.statuskode,
					off_kode = NEW.off_kode,

					note = NEW.note,
					link = NEW.link,
					vejkode = NEW.vejkode,
					tilstand_kode = NEW.tilstand_kode,
					anlaegsaar = NEW.anlaegsaar,
					udfoerer_entrep_kode = NEW.udfoerer_entrep_kode,
					kommunal_kontakt_kode = NEW.kommunal_kontakt_kode,

					arbejdssted = NEW.arbejdssted,
					underelement_kode = NEW.underelement_kode,

					bredde = NEW.bredde,
					hoejde = NEW.hoejde,

					litra = NEW.litra
				WHERE versions_id = OLD.versions_id;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.t_greg_linier
				VALUES (
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,

					NEW.geometri,

					NEW.cvr_kode,
					NEW.oprindkode,
					NEW.statuskode,
					NEW.off_kode,

					NEW.note,
					NEW.link,
					NEW.vejkode,
					NEW.tilstand_kode,
					NEW.anlaegsaar,
					NEW.udfoerer_entrep_kode,
					NEW.kommunal_kontakt_kode,

					NEW.arbejdssted,
					NEW.underelement_kode,

					NEW.bredde,
					NEW.hoejde,

					NEW.litra
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_greg_linier_trg() IS 'Muliggør opdatering gennem v_greg_linier.';


-- v_greg_punkter_trg()

CREATE OR REPLACE FUNCTION greg.v_greg_punkter_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.t_greg_punkter WHERE versions_id = OLD.versions_id AND systid_til IS NULL) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.t_greg_punkter
				WHERE versions_id = OLD.versions_id;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.t_greg_punkter WHERE versions_id = OLD.versions_id AND systid_til IS NULL) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.t_greg_punkter
				SET
					geometri = NEW.geometri,

					cvr_kode = NEW.cvr_kode,
					oprindkode = NEW.oprindkode,
					statuskode = NEW.statuskode,
					off_kode = NEW.off_kode,

					note = NEW.note,
					link = NEW.link,
					vejkode = NEW.vejkode,
					tilstand_kode = NEW.tilstand_kode,
					anlaegsaar = NEW.anlaegsaar,
					udfoerer_entrep_kode = NEW.udfoerer_entrep_kode,
					kommunal_kontakt_kode = NEW.kommunal_kontakt_kode,

					arbejdssted = NEW.arbejdssted,
					underelement_kode = NEW.underelement_kode,

					laengde = NEW.laengde,
					bredde = NEW.bredde,
					diameter = NEW.diameter,
					hoejde = NEW.hoejde,

					slaegt = NEW.slaegt,
					art = NEW.art,

					litra = NEW.litra
				WHERE versions_id = OLD.versions_id;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.t_greg_punkter
				VALUES (
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,

					NEW.geometri,

					NEW.cvr_kode,
					NEW.oprindkode,
					NEW.statuskode,
					NEW.off_kode,

					NEW.note,
					NEW.link,
					NEW.vejkode,
					NEW.tilstand_kode,
					NEW.anlaegsaar,
					NEW.udfoerer_entrep_kode,
					NEW.kommunal_kontakt_kode,

					NEW.arbejdssted,
					NEW.underelement_kode,

					NEW.laengde,
					NEW.bredde,
					NEW.diameter,
					NEW.hoejde,

					NEW.slaegt,
					NEW.art,

					NEW.litra
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_greg_punkter_trg() IS 'Muliggør opdatering gennem v_greg_punkter';


-- v_greg_omraader_trg()

CREATE FUNCTION greg.v_greg_omraader_trg() RETURNS trigger
	LANGUAGE plpgsql
	AS $$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.t_greg_omraader WHERE objekt_id = OLD.objekt_id) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.t_greg_omraader
				WHERE objekt_id = OLD.objekt_id;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.t_greg_omraader WHERE objekt_id = OLD.objekt_id) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.t_greg_omraader
				SET
					pg_distrikt_nr = NEW.pg_distrikt_nr,
					pg_distrikt_tekst = NEW.pg_distrikt_tekst,
					pg_distrikt_type_kode = NEW.pg_distrikt_type_kode,

					geometri = NEW.geometri,

					udfoerer_kontakt_kode1 = NEW.udfoerer_kontakt_kode1,
					udfoerer_kontakt_kode2 = NEW.udfoerer_kontakt_kode2,
					kommunal_kontakt_kode = NEW.kommunal_kontakt_kode,

					vejkode = NEW.vejkode,
					vejnr = NEW.vejnr,
					postnr = NEW.postnr,
					note = NEW.note,
					link = NEW.link,
					aktiv = NEW.aktiv,
					auto_opdat = NEW.auto_opdat
				WHERE objekt_id = OLD.objekt_id;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.t_greg_omraader
				VALUES (
					NULL,

					NEW.pg_distrikt_nr,
					NEW.pg_distrikt_tekst,
					NEW.pg_distrikt_type_kode,

					NEW.geometri,

					NEW.udfoerer_kontakt_kode1,
					NEW.udfoerer_kontakt_kode2,
					NEW.kommunal_kontakt_kode,

					NEW.vejkode,
					NEW.vejnr,
					NEW.postnr,
					NEW.note,
					NEW.link,
					NEW.aktiv,
					NEW.auto_opdat
				);

			RETURN NULL;

		END IF;
	END;

$$;

COMMENT ON FUNCTION greg.v_greg_omraader_trg() IS 'Muliggør opdatering gennem v_greg_omraader.';


--
-- TABLES
--

-- d_basis_ansvarlig_myndighed

CREATE TABLE greg.d_basis_ansvarlig_myndighed (
	cvr_kode integer NOT NULL,
	cvr_navn character varying(128) NOT NULL,
	kommunekode integer,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_ansvarlig_myndighed_pk PRIMARY KEY (cvr_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.d_basis_ansvarlig_myndighed IS 'Opslagstabel, ansvarlig myndighed for elementet (FKG).';


-- d_basis_bruger_id

CREATE TABLE greg.d_basis_bruger_id (
	bruger_id character varying(128) NOT NULL,
	navn character varying(128) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_bruger_id_pk PRIMARY KEY (bruger_id) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.d_basis_bruger_id IS 'Opslagstabel, bruger ID for elementet (FKG).';


-- d_basis_kommunal_kontakt

CREATE TABLE greg.d_basis_kommunal_kontakt (
	kommunal_kontakt_kode serial,
	navn character varying(100) NOT NULL,
	telefon character(8) NOT NULL,
	email character varying(50) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_kommunal_kontakt_pk PRIMARY KEY (kommunal_kontakt_kode) WITH (fillfactor='10'),
	CONSTRAINT d_basis_kommunal_kontakt_ck_telefon CHECK (telefon ~* '[0-9]{8}')
);

COMMENT ON TABLE greg.d_basis_kommunal_kontakt IS 'Opslagstabel, kommunal kontakt for element / område (FKG).';


-- d_basis_status

CREATE TABLE greg.d_basis_status (
	statuskode integer NOT NULL,
	status character varying(30) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_status_pk PRIMARY KEY (statuskode) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.d_basis_status IS 'Opslagstabel, gyldighedsstatus (FKG).';


-- d_basis_offentlig

CREATE TABLE greg.d_basis_offentlig (
	off_kode integer NOT NULL,
	offentlig character varying(60) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_offentlig_pk PRIMARY KEY (off_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.d_basis_offentlig IS 'Opslagstabel, offentlighedsstatus (FKG).';


-- d_basis_oprindelse

CREATE TABLE greg.d_basis_oprindelse (
	oprindkode integer NOT NULL,
	oprindelse character varying(35) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	begrebsdefinition character varying,
	CONSTRAINT d_basis_oprindelse_pk PRIMARY KEY (oprindkode) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.d_basis_oprindelse IS 'Opslagstabel, oprindelse (FKG).';


-- d_basis_tilstand

CREATE TABLE greg.d_basis_tilstand (
	tilstand_kode integer NOT NULL,
	tilstand character varying(25) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	begrebsdefinition character varying,
	CONSTRAINT d_basis_tilstand_pk PRIMARY KEY (tilstand_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.d_basis_tilstand IS 'Opslagstabel, tilstand (FKG).';


-- d_basis_udfoerer

CREATE TABLE greg.d_basis_udfoerer (
	udfoerer_kode serial,
	udfoerer character varying(50) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_udfoerer_pk PRIMARY KEY (udfoerer_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.d_basis_udfoerer IS 'Opslagstabel, ansvarlig udførende for entrepriseområde (FKG).';


-- d_basis_udfoerer_entrep

CREATE TABLE greg.d_basis_udfoerer_entrep (
	udfoerer_entrep_kode serial,
	udfoerer_entrep character varying(50) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_udfoerer_entrep_pk PRIMARY KEY (udfoerer_entrep_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.d_basis_udfoerer_entrep IS 'Opslagstabel, ansvarlig udførerende entreprenør for element (FKG).';


-- d_basis_udfoerer_kontakt

CREATE TABLE greg.d_basis_udfoerer_kontakt (
	udfoerer_kode integer NOT NULL,
	udfoerer_kontakt_kode serial,
	navn character varying(100) NOT NULL,
	telefon character(8) NOT NULL,
	email character varying(50) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_udfoerer_kontakt_pk PRIMARY KEY (udfoerer_kontakt_kode) WITH (fillfactor='10'),
	CONSTRAINT d_basis_udfoerer_kontakt_fk_d_basis_udfoerer FOREIGN KEY (udfoerer_kode) REFERENCES greg.d_basis_udfoerer(udfoerer_kode) MATCH FULL
		ON UPDATE CASCADE,
	CONSTRAINT d_basis_udfoerer_kontakt_ck_telefon CHECK (telefon ~* '[0-9]{8}')
);

COMMENT ON TABLE greg.d_basis_udfoerer_kontakt IS 'Opslagstabel, kontaktinformationer på ansvarlig udførende (FKG).';


-- d_basis_postnr

CREATE TABLE greg.d_basis_postnr (
	postnr integer NOT NULL,
	postnr_by character varying(128) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_postnr_pk PRIMARY KEY (postnr) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.d_basis_postnr IS 'Opslagstabel, postdistrikter (FKG).';


-- d_basis_vejnavn

CREATE TABLE greg.d_basis_vejnavn (
	vejkode integer NOT NULL,
	vejnavn character varying(40) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	cvf_vejkode character varying(7),
	postnr integer,
	kommunekode integer,
	CONSTRAINT d_basis_vejnavn_pk PRIMARY KEY (vejkode) WITH (fillfactor='10'),
	CONSTRAINT d_basis_vejnavn_fk_d_basis_postnr FOREIGN KEY (postnr) REFERENCES greg.d_basis_postnr(postnr) MATCH FULL
);

COMMENT ON TABLE greg.d_basis_vejnavn IS 'Opslagstabel, vejnavne (FKG).';


-- d_basis_distrikt_type

CREATE TABLE greg.d_basis_distrikt_type (
	pg_distrikt_type_kode serial,
	pg_distrikt_type character varying(30) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_distrikt_type_pk PRIMARY KEY (pg_distrikt_type_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.d_basis_distrikt_type IS 'Opslagstabel, områdetyper. Fx grønne områder, skoler mv.';


-- d_basis_omraadenr

CREATE TABLE greg.d_basis_omraadenr (
	pg_distrikt_nr integer NOT NULL,
	CONSTRAINT d_basis_omraadenr_pk PRIMARY KEY (pg_distrikt_nr) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.d_basis_omraadenr IS 'Indirekte relation mellem t_greg_omraader og hhv. (t_greg) flader, linier og punkter. Ellers er der problemer med merge i QGIS.';


-- e_basis_hovedelementer

CREATE TABLE greg.e_basis_hovedelementer (
	hovedelement_kode character varying(3) NOT NULL,
	hovedelement_tekst character varying(20) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT e_basis_hovedelementer_pk PRIMARY KEY (hovedelement_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.e_basis_hovedelementer IS 'Opslagstabel, den generelle elementtype. Fx græs, belægninger mv.';


-- e_basis_elementer

CREATE TABLE greg.e_basis_elementer (
	hovedelement_kode character varying(3) NOT NULL,
	element_kode character varying(6) NOT NULL,
	element_tekst character varying(30) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT e_basis_elementer_pk PRIMARY KEY (element_kode) WITH (fillfactor='10'),
	CONSTRAINT e_basis_elementer_fk_e_basis_hovedelementer FOREIGN KEY (hovedelement_kode) REFERENCES greg.e_basis_hovedelementer(hovedelement_kode) MATCH FULL,
	CONSTRAINT e_basis_elementer_ck_element_kode CHECK (element_kode ~* (hovedelement_kode || '-' || '[0-9]{2}'))
);

COMMENT ON TABLE greg.e_basis_elementer IS 'Opslagstabel, den mere specifikke elementtype. Fx Faste belægninger, løse belægninger mv.';


-- e_basis_underelementer

CREATE TABLE greg.e_basis_underelementer (
	element_kode character varying(6) NOT NULL,
	underelement_kode character varying(9) NOT NULL,
	underelement_tekst character varying(30) NOT NULL,
	objekt_type character varying(3) NOT NULL,
	enhedspris_point numeric(10,2) DEFAULT 0.00 NOT NULL,
	enhedspris_line numeric(10,2) DEFAULT 0.00 NOT NULL,
	enhedspris_poly numeric(10,2) DEFAULT 0.00 NOT NULL,
	enhedspris_speciel numeric(10,2) DEFAULT 0.00 NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT e_basis_underelementer_pk PRIMARY KEY (underelement_kode) WITH (fillfactor='10'),
	CONSTRAINT e_basis_underelementer_fk_e_basis_elementer FOREIGN KEY (element_kode) REFERENCES greg.e_basis_elementer(element_kode) MATCH FULL,
	CONSTRAINT e_basis_underelementer_ck_enhedspris CHECK (enhedspris_point >= 0.0 AND enhedspris_line >= 0.0 AND enhedspris_poly >= 0.0 AND enhedspris_speciel >= 0.0),
	CONSTRAINT e_basis_underelementer_ck_objekt_type CHECK (objekt_type ~* '(f|l|p)+'),
	CONSTRAINT e_basis_underelementer_ck_objekt_type_enhedspris_point CHECK (enhedspris_point = 0.00 OR objekt_type ILIKE '%P%'),
	CONSTRAINT e_basis_underelementer_ck_objekt_type_enhedspris_line CHECK (enhedspris_line = 0.00 OR objekt_type ILIKE '%L%'),
	CONSTRAINT e_basis_underelementer_ck_objekt_type_enhedspris_poly CHECK (enhedspris_poly = 0.00 OR objekt_type ILIKE '%F%' OR underelement_kode ILIKE 'REN%'),
	CONSTRAINT e_basis_underelementer_ck_underelement_kode CHECK (underelement_kode ~* (element_kode || '-' || '[0-9]{2}'))
);

COMMENT ON TABLE greg.e_basis_underelementer IS 'Opslagstabel, den helt specifikke elementtype. Fx beton, asfalt mv.';


-- t_greg_flader

CREATE TABLE greg.t_greg_flader (
    -- Automated values
	versions_id uuid NOT NULL,
	objekt_id uuid NOT NULL,
	oprettet timestamp with time zone NOT NULL,
	systid_fra timestamp with time zone NOT NULL,
	systid_til timestamp with time zone,
	bruger_id_start character varying(128) NOT NULL,
	bruger_id_slut character varying(128),

    -- Geometry
	geometri public.geometry(MultiPolygon,25832) NOT NULL,

    -- FKG #1
	cvr_kode integer NOT NULL, -- DEFAULT value is set in greg.t_greg_generel_trg()
	oprindkode integer DEFAULT 0 NOT NULL,
	statuskode integer DEFAULT 0 NOT NULL,
	off_kode integer DEFAULT 1 NOT NULL,

    -- FKG #2
	note character varying(254),
	link character varying(1024),
	vejkode integer,
	tilstand_kode integer DEFAULT 9 NOT NULL,
	anlaegsaar date,
	udfoerer_entrep_kode integer,
	kommunal_kontakt_kode integer,

    -- FKG #3
	arbejdssted integer NOT NULL,
	underelement_kode character varying(9) NOT NULL,

    -- Measurements
	hoejde numeric(10,1) DEFAULT 0.0 NOT NULL,

    -- Table specific
	klip_sider integer DEFAULT 0 NOT NULL,
	litra character varying(128),

	CONSTRAINT t_greg_flader_pk PRIMARY KEY (versions_id) WITH (fillfactor='10'),
	
	CONSTRAINT t_greg_flader_fk_d_basis_bruger_id_start FOREIGN KEY (bruger_id_start) REFERENCES greg.d_basis_bruger_id(bruger_id) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_bruger_id_slut FOREIGN KEY (bruger_id_slut) REFERENCES greg.d_basis_bruger_id(bruger_id) MATCH FULL,	
	
	CONSTRAINT t_greg_flader_fk_d_basis_ansvarlig_myndighed FOREIGN KEY (cvr_kode) REFERENCES greg.d_basis_ansvarlig_myndighed(cvr_kode) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_oprindelse FOREIGN KEY (oprindkode) REFERENCES greg.d_basis_oprindelse(oprindkode) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_status FOREIGN KEY (statuskode) REFERENCES greg.d_basis_status(statuskode) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_offentlig FOREIGN KEY (off_kode) REFERENCES greg.d_basis_offentlig(off_kode) MATCH FULL,
	
	CONSTRAINT t_greg_flader_fk_d_basis_vejnavn FOREIGN KEY (vejkode) REFERENCES greg.d_basis_vejnavn(vejkode) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_tilstand FOREIGN KEY (tilstand_kode) REFERENCES greg.d_basis_tilstand(tilstand_kode) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_udfoerer_entrep FOREIGN KEY (udfoerer_entrep_kode) REFERENCES greg.d_basis_udfoerer_entrep(udfoerer_entrep_kode) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_kommunal_kontakt FOREIGN KEY (kommunal_kontakt_kode) REFERENCES greg.d_basis_kommunal_kontakt(kommunal_kontakt_kode) MATCH FULL,
	
	CONSTRAINT t_greg_flader_fk_d_basis_omraadenr FOREIGN KEY (arbejdssted) REFERENCES greg.d_basis_omraadenr(pg_distrikt_nr) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_e_basis_underelementer FOREIGN KEY (underelement_kode) REFERENCES greg.e_basis_underelementer(underelement_kode) MATCH FULL,

	CONSTRAINT t_greg_flader_ck_geometri CHECK (public.ST_IsValid(geometri) IS TRUE),
	CONSTRAINT t_greg_flader_ck_hoejde CHECK (hoejde BETWEEN 0.00 AND 9.99),
	CONSTRAINT t_greg_flader_ck_klip_sider CHECK (klip_sider BETWEEN 0 AND 2)
);

COMMENT ON TABLE greg.t_greg_flader IS 'Rådatatabel for elementer defineret som flader. Indeholder både aktuel og historikdata.';


-- t_greg_linier

CREATE TABLE greg.t_greg_linier (
    -- Automated values
	versions_id uuid NOT NULL,
	objekt_id uuid NOT NULL,
	oprettet timestamp with time zone NOT NULL,
	systid_fra timestamp with time zone NOT NULL,
	systid_til timestamp with time zone,
	bruger_id_start character varying(128) NOT NULL,
	bruger_id_slut character varying(128),

    -- Geometry
	geometri public.geometry(MultiLineString,25832) NOT NULL,

    -- FKG #1
	cvr_kode integer NOT NULL,
	oprindkode integer DEFAULT 0 NOT NULL,
	statuskode integer DEFAULT 0 NOT NULL,
	off_kode integer DEFAULT 1 NOT NULL,

    -- FKG #2
	note character varying(254),
	link character varying(1024),
	vejkode integer,
	tilstand_kode integer DEFAULT 9 NOT NULL,
	anlaegsaar date,
	udfoerer_entrep_kode integer,
	kommunal_kontakt_kode integer,

    -- FKG #3
	arbejdssted integer NOT NULL,
	underelement_kode character varying(9) NOT NULL,

    -- Measurements
	bredde numeric(10,1) DEFAULT 0.0 NOT NULL,
	hoejde numeric(10,1) DEFAULT 0.0 NOT NULL,

    -- Table specific
	litra character varying(128),
	
	CONSTRAINT t_greg_linier_pk PRIMARY KEY (versions_id) WITH (fillfactor='10'),

	CONSTRAINT t_greg_linier_fk_d_basis_bruger_id_start FOREIGN KEY (bruger_id_start) REFERENCES greg.d_basis_bruger_id(bruger_id) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_bruger_id_slut FOREIGN KEY (bruger_id_slut) REFERENCES greg.d_basis_bruger_id(bruger_id) MATCH FULL,

	CONSTRAINT t_greg_linier_fk_d_basis_ansvarlig_myndighed FOREIGN KEY (cvr_kode) REFERENCES greg.d_basis_ansvarlig_myndighed(cvr_kode) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_oprindelse FOREIGN KEY (oprindkode) REFERENCES greg.d_basis_oprindelse(oprindkode) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_status FOREIGN KEY (statuskode) REFERENCES greg.d_basis_status(statuskode) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_offentlig FOREIGN KEY (off_kode) REFERENCES greg.d_basis_offentlig(off_kode) MATCH FULL,

	CONSTRAINT t_greg_linier_fk_d_basis_vejnavn FOREIGN KEY (vejkode) REFERENCES greg.d_basis_vejnavn(vejkode) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_tilstand FOREIGN KEY (tilstand_kode) REFERENCES greg.d_basis_tilstand(tilstand_kode) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_udfoerer_entrep FOREIGN KEY (udfoerer_entrep_kode) REFERENCES greg.d_basis_udfoerer_entrep(udfoerer_entrep_kode) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_kommunal_kontakt FOREIGN KEY (kommunal_kontakt_kode) REFERENCES greg.d_basis_kommunal_kontakt(kommunal_kontakt_kode) MATCH FULL,

	CONSTRAINT t_greg_linier_fk_d_basis_omraadenr FOREIGN KEY (arbejdssted) REFERENCES greg.d_basis_omraadenr(pg_distrikt_nr) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_e_basis_underelementer FOREIGN KEY (underelement_kode) REFERENCES greg.e_basis_underelementer(underelement_kode) MATCH FULL,

	CONSTRAINT t_greg_linier_ck_valid CHECK ((public.ST_IsValid(geometri) IS TRUE)),
	CONSTRAINT t_greg_linier_ck_maal CHECK ((bredde BETWEEN 0.00 AND 9.99 AND hoejde BETWEEN 0.00 AND 9.99))
);

COMMENT ON TABLE greg.t_greg_linier IS 'Rådatatabel for elementer defineret som linier. Indeholder både aktuel og historikdata.';


-- t_greg_punkter

CREATE TABLE greg.t_greg_punkter (
    -- Automated values
	versions_id uuid NOT NULL,
	objekt_id uuid NOT NULL,
	oprettet timestamp with time zone NOT NULL,
	systid_fra timestamp with time zone NOT NULL,
	systid_til timestamp with time zone,
	bruger_id_start character varying(128) NOT NULL,
	bruger_id_slut character varying(128),

    -- Geometry
	geometri public.geometry(MultiPoint,25832) NOT NULL,

    -- FKG #1
	cvr_kode integer NOT NULL,
	oprindkode integer DEFAULT 0 NOT NULL,
	statuskode integer DEFAULT 0 NOT NULL,
	off_kode integer DEFAULT 1 NOT NULL,

    -- FKG #2
	note character varying(254),
	link character varying(1024),
	vejkode integer,
	tilstand_kode integer DEFAULT 9 NOT NULL,
	anlaegsaar date,
	udfoerer_entrep_kode integer,
	kommunal_kontakt_kode integer,

    -- FKG #3
	arbejdssted integer NOT NULL,
	underelement_kode character varying(9) NOT NULL,

    -- Measurements
	laengde numeric(10,1) DEFAULT 0.0 NOT NULL,
	bredde numeric(10,1) DEFAULT 0.0 NOT NULL,
	diameter numeric(10,1) DEFAULT 0.0 NOT NULL,
	hoejde numeric(10,1) DEFAULT 0.0 NOT NULL,

    -- Table specific
	slaegt character varying(50),
	art character varying(50),
	litra character varying(128),

	CONSTRAINT t_greg_punkter_pk PRIMARY KEY (versions_id) WITH (fillfactor='10'),

	CONSTRAINT t_greg_punkter_fk_d_basis_bruger_id_start FOREIGN KEY (bruger_id_start) REFERENCES greg.d_basis_bruger_id(bruger_id) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_bruger_id_slut FOREIGN KEY (bruger_id_slut) REFERENCES greg.d_basis_bruger_id(bruger_id) MATCH FULL,

	CONSTRAINT t_greg_punkter_fk_d_basis_ansvarlig_myndighed FOREIGN KEY (cvr_kode) REFERENCES greg.d_basis_ansvarlig_myndighed(cvr_kode) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_oprindelse FOREIGN KEY (oprindkode) REFERENCES greg.d_basis_oprindelse(oprindkode) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_status FOREIGN KEY (statuskode) REFERENCES greg.d_basis_status(statuskode) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_offentlig FOREIGN KEY (off_kode) REFERENCES greg.d_basis_offentlig(off_kode) MATCH FULL,

	CONSTRAINT t_greg_punkter_fk_d_basis_vejnavn FOREIGN KEY (vejkode) REFERENCES greg.d_basis_vejnavn(vejkode) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_tilstand FOREIGN KEY (tilstand_kode) REFERENCES greg.d_basis_tilstand(tilstand_kode) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_udfoerer_entrep FOREIGN KEY (udfoerer_entrep_kode) REFERENCES greg.d_basis_udfoerer_entrep(udfoerer_entrep_kode) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_kommunal_kontakt FOREIGN KEY (kommunal_kontakt_kode) REFERENCES greg.d_basis_kommunal_kontakt(kommunal_kontakt_kode) MATCH FULL,

	CONSTRAINT t_greg_punkter_fk_d_basis_omraadenr FOREIGN KEY (arbejdssted) REFERENCES greg.d_basis_omraadenr(pg_distrikt_nr) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_e_basis_underelementer FOREIGN KEY (underelement_kode) REFERENCES greg.e_basis_underelementer(underelement_kode) MATCH FULL,

	CONSTRAINT t_greg_punkter_ck_maal CHECK (((laengde = 0.00 AND bredde = 0.00 AND diameter >= 0.00) OR (laengde >= 0.00 AND bredde >= 0.00 AND diameter = 0.00))),
	CONSTRAINT t_greg_punkter_ck_hoejde CHECK (hoejde >= 0.00)
);

COMMENT ON TABLE greg.t_greg_punkter IS 'Rådatatabel for elementer defineret som punkter. Indeholder både aktuel og historikdata.';


-- t_greg_omraader

CREATE TABLE greg.t_greg_omraader (
	objekt_id uuid NOT NULL,
	
	pg_distrikt_nr integer NOT NULL,
	pg_distrikt_tekst character varying(150) NOT NULL,
	pg_distrikt_type_kode integer NOT NULL,
	
	geometri public.geometry(MultiPolygon,25832),

	udfoerer_kontakt_kode1 integer,
	udfoerer_kontakt_kode2 integer,
	kommunal_kontakt_kode integer,
	
	vejkode integer,
	vejnr character varying(20),
	postnr integer NOT NULL,
	note character varying(254),
	link character varying(1024),
	aktiv boolean DEFAULT TRUE NOT NULL,
	auto_opdat boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT t_greg_omraader_pk PRIMARY KEY (objekt_id) WITH (fillfactor='10'),
	CONSTRAINT t_greg_omraader_unique_pg_distrikt_nr UNIQUE (pg_distrikt_nr),
	CONSTRAINT t_greg_omraader_fk_d_basis_distrikt_type FOREIGN KEY (pg_distrikt_type_kode) REFERENCES greg.d_basis_distrikt_type(pg_distrikt_type_kode) MATCH FULL,
	CONSTRAINT t_greg_omraader_fk_d_basis_kommunal_kontakt FOREIGN KEY (kommunal_kontakt_kode) REFERENCES greg.d_basis_kommunal_kontakt(kommunal_kontakt_kode) MATCH FULL,
	CONSTRAINT t_greg_omraader_fk_d_basis_omraadenr FOREIGN KEY (pg_distrikt_nr) REFERENCES greg.d_basis_omraadenr(pg_distrikt_nr) MATCH FULL,
	CONSTRAINT t_greg_omraader_fk_d_basis_postnr FOREIGN KEY (postnr) REFERENCES greg.d_basis_postnr(postnr) MATCH FULL,
	CONSTRAINT t_greg_omraader_fk_d_basis_udfoerer_kontakt1 FOREIGN KEY (udfoerer_kontakt_kode1) REFERENCES greg.d_basis_udfoerer_kontakt(udfoerer_kontakt_kode) MATCH FULL,
	CONSTRAINT t_greg_omraader_fk_d_basis_udfoerer_kontakt2 FOREIGN KEY (udfoerer_kontakt_kode2) REFERENCES greg.d_basis_udfoerer_kontakt(udfoerer_kontakt_kode) MATCH FULL,
	CONSTRAINT t_greg_omraader_fk_d_basis_vejnavn FOREIGN KEY (vejkode) REFERENCES greg.d_basis_vejnavn(vejkode) MATCH FULL
);

COMMENT ON TABLE greg.t_greg_omraader IS 'Områdetabel.';


-- t_greg_delomraader

CREATE TABLE greg.t_greg_delomraader (
	objekt_id uuid NOT NULL,
	geometri public.geometry(MultiPolygon,25832) NOT NULL,
	pg_distrikt_nr integer NOT NULL,
	delnavn character varying(150) NOT NULL,
	CONSTRAINT t_greg_delomraader_pk PRIMARY KEY (objekt_id) WITH (fillfactor='10'),
	CONSTRAINT t_greg_delomraader_fk_d_basis_omraadenr FOREIGN KEY (pg_distrikt_nr) REFERENCES greg.d_basis_omraadenr(pg_distrikt_nr) MATCH FULL
);

COMMENT ON TABLE greg.t_greg_delomraader IS 'Specifikke områdeopdelinger i tilfælde af for store områder mht. atlas i QGIS.';


--
-- VIEWS
--



-- v_basis_ansvarlig_myndighed

CREATE VIEW greg.v_basis_ansvarlig_myndighed AS

SELECT
	cvr_kode,
	cvr_navn,
	cvr_navn || ' (' || kommunekode || ')' AS kommune
FROM greg.d_basis_ansvarlig_myndighed
WHERE aktiv IS TRUE;

COMMENT ON VIEW greg.v_basis_ansvarlig_myndighed IS 'Look-up for d_basis_ansvarlig_myndighed.';


-- v_basis_bruger_id

CREATE VIEW greg.v_basis_bruger_id AS

SELECT
	bruger_id,
	navn,
	navn || ' (' || bruger_id || ')' AS bruger,
	aktiv
FROM greg.d_basis_bruger_id;

COMMENT ON VIEW greg.v_basis_bruger_id IS 'Look-up for d_basis_bruger_id.';


-- v_basis_kommunal_kontakt

CREATE VIEW greg.v_basis_kommunal_kontakt AS

SELECT

kommunal_kontakt_kode,
navn,
telefon,
email,
aktiv,
navn || ', tlf: ' || telefon || ', ' || email as kontakt

FROM greg.d_basis_kommunal_kontakt;

COMMENT ON VIEW greg.v_basis_kommunal_kontakt IS 'Look-up for d_basis_kommunal_kontakt.';


-- v_basis_status

CREATE VIEW greg.v_basis_status AS

SELECT
	statuskode,
	status
FROM greg.d_basis_status
WHERE aktiv IS TRUE;

COMMENT ON VIEW greg.v_basis_status IS 'Look-up for d_basis_status.';


-- v_basis_offentlig

CREATE VIEW greg.v_basis_offentlig AS

SELECT
	off_kode,
	offentlig
FROM greg.d_basis_offentlig
WHERE aktiv IS TRUE;

COMMENT ON VIEW greg.v_basis_offentlig IS 'Look-up for d_basis_offentlig.';


-- v_basis_oprindelse

CREATE VIEW greg.v_basis_oprindelse AS

SELECT
	oprindkode,
	oprindelse,
	begrebsdefinition
FROM greg.d_basis_oprindelse
WHERE aktiv IS TRUE;

COMMENT ON VIEW greg.v_basis_oprindelse IS 'Look-up for d_basis_oprindelse.';


-- v_basis_tilstand

CREATE VIEW greg.v_basis_tilstand AS

SELECT
	tilstand_kode,
	tilstand,
	begrebsdefinition
FROM greg.d_basis_tilstand
WHERE aktiv IS TRUE;

COMMENT ON VIEW greg.v_basis_tilstand IS 'Look-up for d_basis_tilstand.';


-- v_basis_udfoerer

CREATE VIEW greg.v_basis_udfoerer AS

SELECT
	udfoerer_kode,
	udfoerer,
	aktiv
FROM greg.d_basis_udfoerer;

COMMENT ON VIEW greg.v_basis_udfoerer IS 'Look-up for d_basis_udfoerer.';


-- v_basis_udfoerer_entrep

CREATE VIEW greg.v_basis_udfoerer_entrep AS

SELECT
	udfoerer_entrep_kode,
	udfoerer_entrep,
	aktiv
FROM greg.d_basis_udfoerer_entrep;

COMMENT ON VIEW greg.v_basis_udfoerer_entrep IS 'Look-up for d_basis_udfoerer_entrep.';


-- v_basis_udfoerer_kontakt

CREATE VIEW greg.v_basis_udfoerer_kontakt AS

SELECT
	b.udfoerer_kode,
	a.udfoerer_kontakt_kode,
	a.navn,
	a.telefon,
	a.email,
	a.aktiv,
	b.udfoerer || ' - ' || a.navn || ', tlf: ' || a.telefon || ', ' || a.email as kontakt
FROM greg.d_basis_udfoerer_kontakt a
LEFT JOIN greg.d_basis_udfoerer b ON a.udfoerer_kode = b.udfoerer_kode;

COMMENT ON VIEW greg.v_basis_udfoerer_kontakt IS 'Look-up for d_basis_udfoerer_kontakt.';


-- v_basis_vejnavn

CREATE VIEW greg.v_basis_vejnavn AS

SELECT
	postnr,
	vejkode,
	vejnavn,
	vejnavn || ' (' || postnr || ')' AS vej
FROM greg.d_basis_vejnavn
WHERE aktiv IS TRUE;

COMMENT ON VIEW greg.v_basis_vejnavn IS 'Look-up for d_basis_vejnavn.';


-- v_basis_distrikt_type

CREATE VIEW greg.v_basis_distrikt_type AS

SELECT
	pg_distrikt_type_kode,
	pg_distrikt_type,
	aktiv
FROM greg.d_basis_distrikt_type;

COMMENT ON VIEW greg.v_basis_distrikt_type IS 'Look-up for d_basis_distrikt_type.';


-- v_basis_postnr

CREATE VIEW greg.v_basis_postnr AS

SELECT

postnr,
postnr || ' ' || postnr_by as distrikt

FROM greg.d_basis_postnr
WHERE aktiv IS TRUE;

COMMENT ON VIEW greg.v_basis_postnr IS 'Look-up for d_basis_postnr.';


-- v_basis_hovedelementer

CREATE VIEW greg.v_basis_hovedelementer AS

SELECT
	a.hovedelement_kode,
	a.hovedelement_tekst,
	a.hovedelement_kode || ' - ' || a.hovedelement_tekst AS hovedelement,
	CASE 
		WHEN a.hovedelement_kode IN(SELECT 
										hovedelement_kode
									FROM greg.e_basis_underelementer a
									LEFT JOIN greg.e_basis_elementer b ON a.element_kode = b.element_kode
									WHERE objekt_type ILIKE '%F%')
		THEN 'F'
		ELSE ''
	END ||
	CASE 
		WHEN a.hovedelement_kode IN(SELECT
										hovedelement_kode
									FROM greg.e_basis_underelementer a
									LEFT JOIN greg.e_basis_elementer b ON a.element_kode = b.element_kode
									WHERE objekt_type ILIKE '%L%')
		THEN 'L'
		ELSE ''
	END ||
	CASE 
		WHEN a.hovedelement_kode IN(SELECT
										hovedelement_kode
									FROM greg.e_basis_underelementer a
									LEFT JOIN greg.e_basis_elementer b ON a.element_kode = b.element_kode
									WHERE objekt_type ILIKE '%P%')
		THEN 'P'
		ELSE ''
	END AS objekt_type,
	a.aktiv
FROM greg.e_basis_hovedelementer a
LEFT JOIN greg.e_basis_elementer b ON a.hovedelement_kode = b.hovedelement_kode
LEFT JOIN greg.e_basis_underelementer c ON b.element_kode = c.element_kode
GROUP BY a.hovedelement_kode, a.hovedelement_tekst

ORDER BY a.hovedelement_kode;

COMMENT ON VIEW greg.v_basis_hovedelementer IS 'Look-up for e_basis_hovedelementer.';

-- v_basis_elementer

CREATE VIEW greg.v_basis_elementer AS

SELECT
	a.hovedelement_kode,
	a.element_kode,
	a.element_tekst,
	a.element_kode || ' ' || a.element_tekst AS element,
	CASE 
		WHEN a.element_kode IN(SELECT
									element_kode
								FROM greg.e_basis_underelementer
								WHERE objekt_type ILIKE '%F%')
		THEN 'F'
		ELSE ''
	END ||
	CASE 
		WHEN a.element_kode IN(SELECT
									element_kode
								FROM greg.e_basis_underelementer
								WHERE objekt_type ILIKE '%L%')
		THEN 'L'
		ELSE ''
	END ||
	CASE 
		WHEN a.element_kode IN(SELECT
									element_kode
								FROM greg.e_basis_underelementer
								WHERE objekt_type ILIKE '%P%')
		THEN 'P'
		ELSE ''
	END AS objekt_type,
	a.aktiv
FROM greg.e_basis_elementer a
LEFT JOIN greg.e_basis_underelementer b ON a.element_kode = b.element_kode
LEFT JOIN greg.e_basis_hovedelementer c ON a.hovedelement_kode = c.hovedelement_kode
WHERE c.aktiv IS TRUE
GROUP BY a.element_kode, a.element_tekst

ORDER BY a.element_kode;

COMMENT ON VIEW greg.v_basis_elementer IS 'Look-up for e_basis_elementer.';


-- v_basis_underelementer

CREATE VIEW greg.v_basis_underelementer AS

SELECT
	a.element_kode,
	a.underelement_kode,
	a.underelement_tekst,
	a.underelement_kode || ' ' || a.underelement_tekst AS underelement,
	a.objekt_type,
	a.enhedspris_point,
	a.enhedspris_line,
	a.enhedspris_poly,
	a.enhedspris_speciel,
	a.aktiv
FROM greg.e_basis_underelementer a
LEFT JOIN greg.e_basis_elementer b ON a.element_kode = b.element_kode
LEFT JOIN greg.e_basis_hovedelementer c ON b.hovedelement_kode = c.hovedelement_kode
WHERE b.aktiv IS TRUE AND c.aktiv IS TRUE

ORDER BY a.underelement_kode;

COMMENT ON VIEW greg.v_basis_underelementer IS 'Look-up for e_basis_underelementer.';



-- v_greg_flader

CREATE VIEW greg.v_greg_flader AS

SELECT
	a.versions_id,
	a.objekt_id,
	a.oprettet,
	a.systid_fra,
	a.bruger_id_start AS bruger_id,
	c.navn AS bruger,
	
	a.geometri,
	
	a.cvr_kode,
	b.cvr_navn,
	a.oprindkode,
	d.oprindelse,
	a.statuskode,
	e.status,
	a.off_kode,
	f.offentlig,
	
	a.note,
	a.link,
	a.vejkode,
	g.vejnavn,
	a.tilstand_kode,
	h.tilstand,
	a.anlaegsaar,
	a.udfoerer_entrep_kode,
	i.udfoerer_entrep,
	a.kommunal_kontakt_kode,
	j.navn || ', tlf: ' || j.telefon || ', ' || j.email AS kommunal_kontakt,
	
	a.arbejdssted,
	k.pg_distrikt_tekst,
	n.hovedelement_kode,
	n.hovedelement_tekst,
	m.element_kode,
	m.element_tekst,
	a.underelement_kode,
	l.underelement_tekst,
	
	a.hoejde,
	a.klip_sider,

	a.litra,
	
	CASE
		WHEN LEFT(a.underelement_kode,2) LIKE 'HÆ'
		THEN (public.ST_Area(a.geometri) + a.klip_sider * a.hoejde * public.ST_Perimeter(a.geometri) /2)::numeric(10,1)
		ELSE NULL
	END AS klip_flade,
	public.ST_Area(a.geometri)::numeric(10,1) AS areal,
	public.ST_Perimeter(a.geometri)::numeric(10,1) AS omkreds,
	CASE
		WHEN LEFT(a.underelement_kode,2) LIKE 'HÆ'
		THEN (l.enhedspris_poly * public.ST_Area(a.geometri) + l.enhedspris_speciel * (public.ST_Area(a.geometri) + a.klip_sider * a.hoejde * public.ST_Perimeter(a.geometri) /2))::numeric(10,2)
		WHEN l.enhedspris_poly = 0
		THEN NULL
		ELSE (l.enhedspris_poly * public.ST_Area(a.geometri))::numeric(10,2)
	END AS element_pris,
	
	k.aktiv
FROM greg.t_greg_flader a
LEFT JOIN greg.d_basis_ansvarlig_myndighed b ON a.cvr_kode = b.cvr_kode
LEFT JOIN greg.d_basis_bruger_id c ON a.bruger_id_start = c.bruger_id
LEFT JOIN greg.d_basis_oprindelse d ON a.oprindkode = d.oprindkode
LEFT JOIN greg.d_basis_status e ON a.statuskode = e.statuskode
LEFT JOIN greg.d_basis_offentlig f ON a.off_kode = f.off_kode

LEFT JOIN greg.d_basis_vejnavn g ON a.vejkode = g.vejkode
LEFT JOIN greg.d_basis_tilstand h ON a.tilstand_kode = h.tilstand_kode
LEFT JOIN greg.d_basis_udfoerer_entrep i ON a.udfoerer_entrep_kode = i.udfoerer_entrep_kode
LEFT JOIN greg.d_basis_kommunal_kontakt j ON a.kommunal_kontakt_kode = j.kommunal_kontakt_kode

LEFT JOIN greg.t_greg_omraader k ON a.arbejdssted = k.pg_distrikt_nr
LEFT JOIN greg.e_basis_underelementer l ON a.underelement_kode = l.underelement_kode
LEFT JOIN greg.e_basis_elementer m ON l.element_kode = m.element_kode
LEFT JOIN greg.e_basis_hovedelementer n ON m.hovedelement_kode = n.hovedelement_kode
WHERE systid_til IS NULL;


COMMENT ON VIEW greg.v_greg_flader IS 'Opdatérbar view for greg.t_greg_flader.';


-- v_greg_linier

CREATE VIEW greg.v_greg_linier AS

SELECT
	a.versions_id,
	a.objekt_id,
	a.oprettet,
	a.systid_fra,
	a.bruger_id_start AS bruger_id,
	c.navn AS bruger,
	
	a.geometri,
	
	a.cvr_kode,
	b.cvr_navn,
	a.oprindkode,
	d.oprindelse,
	a.statuskode,
	e.status,
	a.off_kode,
	f.offentlig,
	
	a.note,
	a.link,
	a.vejkode,
	g.vejnavn,
	a.tilstand_kode,
	h.tilstand,
	a.anlaegsaar,
	a.udfoerer_entrep_kode,
	i.udfoerer_entrep,
	a.kommunal_kontakt_kode,
	j.navn || ', tlf: ' || j.telefon || ', ' || j.email AS kommunal_kontakt,

	a.arbejdssted,
	k.pg_distrikt_tekst,
	n.hovedelement_kode,
	n.hovedelement_tekst,
	m.element_kode,
	m.element_tekst,
	a.underelement_kode,
	l.underelement_tekst,
	
	public.ST_Length(a.geometri)::numeric(10,1) AS laengde,
	a.bredde,
	a.hoejde,
	
	a.litra,

	CASE
		WHEN a.underelement_kode = 'BL-05-02'
		THEN (public.ST_Length(a.geometri) * a.hoejde)::numeric(10,1)
		ELSE NULL
	END AS klip_flade,
	CASE
		WHEN a.underelement_kode = 'BL-05-02' AND l.enhedspris_speciel > 0
		THEN l.enhedspris_speciel * (public.ST_Length(a.geometri) * a.hoejde)::numeric(10,2)
		WHEN l.enhedspris_line = 0
		THEN NULL
		ELSE (l.enhedspris_line * public.ST_Length(a.geometri))::numeric(10,2)
	END AS element_pris,
	
	k.aktiv
FROM greg.t_greg_linier a
LEFT JOIN greg.d_basis_ansvarlig_myndighed b ON a.cvr_kode = b.cvr_kode
LEFT JOIN greg.d_basis_bruger_id c ON a.bruger_id_start = c.bruger_id
LEFT JOIN greg.d_basis_oprindelse d ON a.oprindkode = d.oprindkode
LEFT JOIN greg.d_basis_status e ON a.statuskode = e.statuskode
LEFT JOIN greg.d_basis_offentlig f ON a.off_kode = f.off_kode

LEFT JOIN greg.d_basis_vejnavn g ON a.vejkode = g.vejkode
LEFT JOIN greg.d_basis_tilstand h ON a.tilstand_kode = h.tilstand_kode
LEFT JOIN greg.d_basis_udfoerer_entrep i ON a.udfoerer_entrep_kode = i.udfoerer_entrep_kode
LEFT JOIN greg.d_basis_kommunal_kontakt j ON a.kommunal_kontakt_kode = j.kommunal_kontakt_kode

LEFT JOIN greg.t_greg_omraader k ON a.arbejdssted = k.pg_distrikt_nr
LEFT JOIN greg.e_basis_underelementer l ON a.underelement_kode = l.underelement_kode
LEFT JOIN greg.e_basis_elementer m ON l.element_kode = m.element_kode
LEFT JOIN greg.e_basis_hovedelementer n ON m.hovedelement_kode = n.hovedelement_kode
WHERE systid_til IS NULL;

COMMENT ON VIEW greg.v_greg_linier IS 'Opdatérbar view for greg.t_greg_linier.';


-- v_greg_punkter

CREATE VIEW greg.v_greg_punkter AS

SELECT
	a.versions_id,
	a.objekt_id,
	a.systid_fra,
	a.oprettet,
	a.bruger_id_start AS bruger_id,
	c.navn AS bruger,
	
	a.geometri,
	
	a.cvr_kode,
	b.cvr_navn,
	a.oprindkode,
	d.oprindelse,
	a.statuskode,
	e.status,
	a.off_kode,
	f.offentlig,
	
	a.note,
	a.link,
	a.vejkode,
	g.vejnavn,
	a.tilstand_kode,
	h.tilstand,
	a.anlaegsaar,
	a.udfoerer_entrep_kode,
	i.udfoerer_entrep,
	a.kommunal_kontakt_kode,
	j.navn || ', tlf: ' || j.telefon || ', ' || j.email AS kommunal_kontakt,

	a.arbejdssted,
	k.pg_distrikt_tekst,
	n.hovedelement_kode,
	n.hovedelement_tekst,
	m.element_kode,
	m.element_tekst,
	a.underelement_kode,
	l.underelement_tekst,
	
	a.laengde,
	a.bredde,
	a.diameter,
	a.hoejde,
	
	a.slaegt,
	a.art,
	
	a.litra,
	
	CASE
		WHEN n.hovedelement_kode = 'REN' AND l.enhedspris_speciel > 0
		THEN (l.enhedspris_speciel * o.areal)::numeric(10,2)
		WHEN l.enhedspris_point = 0
		THEN NULL
		ELSE ST_NumGeometries(a.geometri)*l.enhedspris_point
	END AS element_pris,
	
	k.aktiv
FROM greg.t_greg_punkter a
LEFT JOIN greg.d_basis_ansvarlig_myndighed b ON a.cvr_kode = b.cvr_kode
LEFT JOIN greg.d_basis_bruger_id c ON a.bruger_id_start = c.bruger_id
LEFT JOIN greg.d_basis_oprindelse d ON a.oprindkode = d.oprindkode
LEFT JOIN greg.d_basis_status e ON a.statuskode = e.statuskode
LEFT JOIN greg.d_basis_offentlig f ON a.off_kode = f.off_kode

LEFT JOIN greg.d_basis_vejnavn g ON a.vejkode = g.vejkode
LEFT JOIN greg.d_basis_tilstand h ON a.tilstand_kode = h.tilstand_kode
LEFT JOIN greg.d_basis_udfoerer_entrep i ON a.udfoerer_entrep_kode = i.udfoerer_entrep_kode
LEFT JOIN greg.d_basis_kommunal_kontakt j ON a.kommunal_kontakt_kode = j.kommunal_kontakt_kode

LEFT JOIN greg.t_greg_omraader k ON a.arbejdssted = k.pg_distrikt_nr
LEFT JOIN greg.e_basis_underelementer l ON a.underelement_kode = l.underelement_kode
LEFT JOIN greg.e_basis_elementer m ON l.element_kode = m.element_kode
LEFT JOIN greg.e_basis_hovedelementer n ON m.hovedelement_kode = n.hovedelement_kode

LEFT JOIN (SELECT	arbejdssted,
					SUM(public.ST_Area(geometri)) AS areal
				FROM greg.t_greg_flader
				WHERE LEFT(underelement_kode, 3) NOT IN('ANA', 'VA-')
				GROUP BY arbejdssted) o
		ON k.pg_distrikt_nr = o.arbejdssted
WHERE systid_til IS NULL;

COMMENT ON VIEW greg.v_greg_punkter IS 'Opdatérbar view for greg.t_greg_punkter.';


-- v_greg_omraader

CREATE VIEW greg.v_greg_omraader AS

SELECT
	a.objekt_id,
		
	a.pg_distrikt_nr,
	a.pg_distrikt_tekst,
	a.pg_distrikt_type_kode,
	b.pg_distrikt_type,

	CASE
		WHEN b.pg_distrikt_type IN('Vejarealer')
		THEN NULL::public.geometry(MultiPolygon,25832)
		ELSE a.geometri
	END AS geometri,

	a.udfoerer_kontakt_kode1,
	d.udfoerer || ', ' || c.navn || ', tlf: ' || c.telefon || ', ' || c.email AS udfoerer_kontakt1,
	a.udfoerer_kontakt_kode2,
	f.udfoerer || ', ' || e.navn || ', tlf: ' || e.telefon || ', ' || e.email AS udfoerer_kontakt2,
	a.kommunal_kontakt_kode,
	g.navn || ', tlf: ' || g.telefon || ', ' || g.email AS kommunal_kontakt,
	
	a.vejkode,
	h.vejnavn,
	a.vejnr,
	a.postnr,
	i.postnr_by AS distrikt,
	a.note,
	a.link,
	public.ST_Area(a.geometri)::numeric(10,1) AS areal,
	a.aktiv,
	a.auto_opdat
FROM greg.t_greg_omraader a
LEFT JOIN greg.d_basis_distrikt_type b ON a.pg_distrikt_type_kode = b.pg_distrikt_type_kode
LEFT JOIN greg.d_basis_udfoerer_kontakt c ON a.udfoerer_kontakt_kode1 = c.udfoerer_kontakt_kode
LEFT JOIN greg.d_basis_udfoerer d ON c.udfoerer_kode = d.udfoerer_kode
LEFT JOIN greg.d_basis_udfoerer_kontakt e ON a.udfoerer_kontakt_kode2 = e.udfoerer_kontakt_kode
LEFT JOIN greg.d_basis_udfoerer f ON e.udfoerer_kode = f.udfoerer_kode
LEFT JOIN greg.d_basis_kommunal_kontakt g ON a.kommunal_kontakt_kode = g.kommunal_kontakt_kode
LEFT JOIN greg.d_basis_vejnavn h ON a.vejkode = h.vejkode
LEFT JOIN greg.d_basis_postnr i ON a.postnr = i.postnr

ORDER BY a.pg_distrikt_nr;

COMMENT ON VIEW greg.v_greg_omraader IS 'Opdatérbar view for greg.t_greg_omraader.';




-- v_aendring_flader

DROP VIEW IF EXISTS greg.v_aendring_flader;

CREATE VIEW greg.v_aendring_flader AS

SELECT
	*
FROM greg.f_tot_flader(14)

ORDER BY dato desc;

COMMENT ON VIEW greg.v_aendring_flader IS 'Ændringsoversigt med tilhørende geometri. Defineret som 14 dage.';

-- v_aendring_linier

DROP VIEW IF EXISTS greg.v_aendring_linier;

CREATE VIEW greg.v_aendring_linier AS

SELECT
	*
FROM greg.f_tot_linier(14)

ORDER BY dato desc;

COMMENT ON VIEW greg.v_aendring_linier IS 'Ændringsoversigt med tilhørende geometri. Defineret som 14 dage.';

-- v_aendring_punkter

DROP VIEW IF EXISTS greg.v_aendring_punkter;

CREATE VIEW greg.v_aendring_punkter AS

SELECT
	*
FROM greg.f_tot_punkter(14)

ORDER BY dato desc;

COMMENT ON VIEW greg.v_aendring_punkter IS 'Ændringsoversigt med tilhørende geometri. Defineret som 14 dage.';



-- v_historik_flader
/*
DROP VIEW IF EXISTS greg.v_historik_flader;

CREATE VIEW greg.v_historik_flader AS

SELECT
	*
FROM greg.f_dato_flader(int,int,int);

COMMENT ON VIEW  IS 'Simulering af registreringen på en bestemt dato. Format: dd-MM-yyyy.';


-- v_historik_linier

DROP VIEW IF EXISTS greg.v_historik_linier;

CREATE VIEW greg.v_historik_linier AS

SELECT
	*
FROM greg.f_dato_linier(int,int,int);

COMMENT ON VIEW  IS 'Simulering af registreringen på en bestemt dato. Format: dd-MM-yyyy.';


-- v_historik_punkter

DROP VIEW IF EXISTS greg.v_historik_punkter;

CREATE VIEW greg.v_historik_punkter AS

SELECT
	*
FROM greg.f_dato_punkter(int,int,int);

COMMENT ON VIEW  IS 'Simulering af registreringen på en bestemt dato. Format: dd-MM-yyyy.';
*/



-- v_log_xxxx
/*
DROP VIEW IF EXISTS greg.v_log_xxxx;

CREATE VIEW greg.v_log_xxxx AS

SELECT 	
	*
FROM greg.f_aendring_log (xxxx);

COMMENT ON VIEW greg.v_log_xxxx IS 'Ændringslog, som registrerer alle handlinger indenfor et givent år (xxxx). Benyttes i Ændringslog.xlsx';
*/

-- v_log_2017

DROP VIEW IF EXISTS greg.v_log_2017;

CREATE VIEW greg.v_log_2017 AS

SELECT 	
	*
FROM greg.f_aendring_log (2017);

COMMENT ON VIEW greg.v_log_2017 IS 'Ændringslog, som registrerer alle handlinger indenfor et givent år (2017). Benyttes i Ændringslog.xlsx';



-- v_maengder_omraader_underelementer

DROP VIEW IF EXISTS greg.v_maengder_omraader_underelementer;

CREATE VIEW greg.v_maengder_omraader_underelementer AS

WITH

--
-- Element list
--

base_elements AS (	SELECT -- SELECT a complete (DISTINCT) list of all current elements within each area code from the current data set
					arbejdssted,
					underelement_kode
				FROM greg.t_greg_flader
				WHERE systid_til IS NULL -- Active
			
				UNION
			
				SELECT
					arbejdssted,
					underelement_kode
				FROM greg.t_greg_linier
				WHERE systid_til IS NULL -- Active
			
				UNION
			
				SELECT
					arbejdssted,
					underelement_kode
				FROM greg.t_greg_punkter
				WHERE systid_til IS NULL -- Active
		),

--
-- Basic calculations
--

base_poly AS (	SELECT -- SELECT the AREA and hedge surface for each element on each area code from the current data set
					arbejdssted,
					underelement_kode,
					SUM(ST_Area(geometri)) AS areal
				FROM greg.t_greg_flader
				WHERE systid_til IS NULL -- Active
				GROUP BY arbejdssted, underelement_kode
		),

base_line AS (	SELECT -- SELECT the LENGTH and trimming surface for each element on each area code from the current data set
					arbejdssted,
					underelement_kode,
					SUM(ST_Length(geometri)) AS laengde
				FROM greg.t_greg_linier
				WHERE systid_til IS NULL -- Active
				GROUP BY arbejdssted, underelement_kode
		),

base_point AS (	SELECT -- SELECT the points (MultiPoints are counted for each individual point) for each element on each area code from the current data set
					arbejdssted,
					underelement_kode,
					SUM(ST_NumGeometries(geometri)) AS antal
				FROM greg.t_greg_punkter
				WHERE systid_til IS NULL -- Active
				GROUP BY arbejdssted, underelement_kode
		),

--
-- Special calculations
--

spec_hae AS (	SELECT -- SELECT the hedge surface for each relevant element on each area code from the current data set
					arbejdssted,
					underelement_kode,
					SUM(ST_Area(geometri)) + SUM(klip_sider * hoejde * ST_Perimeter(geometri)) / 2 AS klippeflade -- Relevant for HÆ-..
				FROM greg.t_greg_flader
				WHERE LEFT(underelement_kode, 2) = 'HÆ' AND systid_til IS NULL -- Active
				GROUP BY arbejdssted, underelement_kode
		),

spec_bl AS (	SELECT -- SELECT the trimming surface for each relevant element on each area code from the current data set
					arbejdssted,
					underelement_kode,
					SUM(ST_Length(geometri) * hoejde) AS klippeflade -- Relevant for BL-05-02
				FROM greg.t_greg_linier
				WHERE underelement_kode = 'BL-05-02' AND systid_til IS NULL -- Active
				GROUP BY arbejdssted, underelement_kode
		),

spec_ren AS	(	SELECT -- SELECT the AREA for each area code excluding any element in the main element type of 'ANA', 'VA' and 'BE' from the current data set
					arbejdssted,
					SUM(ST_Area(geometri)) AS areal -- Relevant for REN-..
				FROM greg.t_greg_flader
				WHERE LEFT(underelement_kode, 3) NOT IN ('ANA', 'VA_', 'BE_') AND systid_til IS NULL -- Active
				GROUP BY arbejdssted
		),

--
-- Building the view
--

view_1 AS (	SELECT -- SELECT amounts of each feature type respectively for each element within each area code
				a.*,
				CASE
					WHEN LEFT(a.underelement_kode, 3) = 'REN' AND d.antal <= 1 -- If REN-.. appears more than once per area make notice
					THEN NULL
					ELSE d.antal
				END AS antal,
				CASE
					WHEN a.underelement_kode <> 'BL-05-02' -- LENGTH of BL-05-02 is not relevant, only trimming surface is
					THEN c.laengde
				END AS laengde,
				CASE
					WHEN a.underelement_kode ILIKE 'REN%' -- AREA for each area code excluding certain elements 
					THEN g.areal
					ELSE b.areal
				END AS areal,
				CASE
					WHEN LEFT(a.underelement_kode,2) = 'HÆ'
					THEN e.klippeflade
					WHEN a.underelement_kode = 'BL-05-02'
					THEN f.klippeflade
				END AS klippeflade
			FROM base_elements a
			LEFT JOIN base_poly		b ON a.arbejdssted = b.arbejdssted AND a.underelement_kode = b.underelement_kode
			LEFT JOIN base_line		c ON a.arbejdssted = c.arbejdssted AND a.underelement_kode = c.underelement_kode
			LEFT JOIN base_point	d ON a.arbejdssted = d.arbejdssted AND a.underelement_kode = d.underelement_kode
			LEFT JOIN spec_hae		e ON a.arbejdssted = e.arbejdssted AND a.underelement_kode = e.underelement_kode
			LEFT JOIN spec_bl		f ON a.arbejdssted = f.arbejdssted AND a.underelement_kode = f.underelement_kode
			LEFT JOIN spec_ren		g ON a.arbejdssted = g.arbejdssted
		),

view_2 AS (	SELECT -- SELECT full overview of all amounts including a total price for each element on each area code 
				a.arbejdssted,
				a.underelement_kode,
				a.antal,
				a.laengde,
				a.areal,
				a.klippeflade,
				CASE
					WHEN a.antal IS NOT NULL
					THEN (a.antal * b.enhedspris_point)::numeric(10,2)
					ELSE 0
				END +
				CASE
					WHEN a.laengde IS NOT NULL
					THEN (a.laengde * b.enhedspris_line)::numeric(10,2)
					ELSE 0
				END +
				CASE
					WHEN a.areal IS NOT NULL AND LEFT(a.underelement_kode, 3) = 'REN' -- Price of REN-.. should be in special category because it is defined as a point
					THEN (a. areal * b.enhedspris_speciel)::numeric(10,2)
					WHEN a.areal IS NOT NULL
					THEN (a.areal * b.enhedspris_poly)::numeric(10,2)
					ELSE 0
				END +
				CASE
					WHEN a.klippeflade IS NOT NULL
					THEN (a.klippeflade * b.enhedspris_speciel)::numeric(10,2)
					ELSE 0
				END AS pris
			FROM view_1 a
			LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
		),

view_3 AS (	SELECT -- SELECT full overview with JOINS to look-up TABLES. Price is set to NULL if 0 for Excel purposes
				c.pg_distrikt_type,
				b.pg_distrikt_nr,
				b.pg_distrikt_nr || ' ' || b.pg_distrikt_tekst AS omraade,
				f.hovedelement_kode,
				f.hovedelement_tekst AS hovedelement,
				e.element_kode,
				e.element_kode || ' ' || e.element_tekst AS element,
				d.underelement_kode,
				d.underelement_kode || ' ' || d.underelement_tekst AS underelement,
				a.antal,
				a.laengde::numeric(10,1),
				a.areal::numeric(10,1),
				a.klippeflade::numeric(10,1),
				CASE
					WHEN a.pris > 0
					THEN a.pris
				END AS pris
			FROM view_2 a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr
			LEFT JOIN greg.d_basis_distrikt_type c ON b.pg_distrikt_type_kode = c.pg_distrikt_type_kode
			LEFT JOIN greg.e_basis_underelementer d ON a.underelement_kode = d.underelement_kode
			LEFT JOIN greg.e_basis_elementer e ON d.element_kode = e.element_kode
			LEFT JOIN greg.e_basis_hovedelementer f ON e.hovedelement_kode = f.hovedelement_kode
			WHERE b.aktiv IS TRUE
		)


SELECT
	*
FROM view_3
ORDER BY pg_distrikt_nr, underelement_kode;

COMMENT ON VIEW greg.v_maengder_omraader_underelementer IS 'Mængdeoversigt over elementer grupperet pr. område';


-- v_maengder_omraader_underelementer_2

DROP VIEW IF EXISTS greg.v_maengder_omraader_underelementer_2;

CREATE VIEW greg.v_maengder_omraader_underelementer_2 AS

SELECT
	c.pg_distrikt_type,
	b.pg_distrikt_nr,
	b.pg_distrikt_nr || ' ' || b.pg_distrikt_tekst AS omraade,
	f.hovedelement_kode,
	f.hovedelement_tekst AS hovedelement,
	e.element_kode,
	e.element_tekst AS element,
	d.underelement_kode,
	d.underelement_tekst AS underelement,
	CASE
		WHEN d.objekt_type ILIKE '%P%' AND i.antal IS NOT NULL
		THEN i.antal
		ELSE 0
	END AS antal,
	CASE
		WHEN d.objekt_type ILIKE '%L%' AND h.laengde IS NOT NULL
		THEN h.laengde
		ELSE 0.0
	END AS laengde,
	CASE
		WHEN a.underelement_kode ILIKE 'REN%'
		THEN j.areal
		WHEN d.objekt_type ILIKE '%F%' AND g.areal IS NOT NULL
		THEN g.areal
		ELSE 0.0
	END AS areal,
	CASE
		WHEN LEFT(a.underelement_kode,2) = 'HÆ'
		THEN g.klippeflade
		WHEN a.underelement_kode = 'BL-05-02'
		THEN h.klippeflade
		ELSE 0.0
	END AS klippeflade
FROM (SELECT
		arbejdssted,
		underelement_kode
	FROM greg.t_greg_flader
	WHERE systid_til IS NULL

	UNION

	SELECT
		arbejdssted,
		underelement_kode
	FROM greg.t_greg_linier
	WHERE systid_til IS NULL

	UNION

	SELECT
		arbejdssted,
		underelement_kode
	FROM greg.t_greg_punkter
	WHERE systid_til IS NULL) a
LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr
LEFT JOIN greg.d_basis_distrikt_type c ON b.pg_distrikt_type_kode = c.pg_distrikt_type_kode
LEFT JOIN greg.e_basis_underelementer d ON a.underelement_kode = d.underelement_kode
LEFT JOIN greg.e_basis_elementer e ON d.element_kode = e.element_kode
LEFT JOIN greg.e_basis_hovedelementer f ON e.hovedelement_kode = f.hovedelement_kode
LEFT JOIN 	(SELECT
				arbejdssted,
				underelement_kode,
				SUM(ST_Area(geometri))::numeric(10,1) AS areal,
				CASE
					WHEN LEFT(underelement_kode,2) LIKE 'HÆ'
					THEN (SUM(ST_Area(geometri)) + SUM(klip_sider * hoejde * ST_Perimeter(geometri)) / 2)::numeric(10,1)
					ELSE 0.0
				END AS klippeflade
			FROM greg.t_greg_flader
			WHERE systid_til IS NULL
			GROUP BY arbejdssted, underelement_kode) g
	ON a.arbejdssted = g.arbejdssted AND a.underelement_kode = g.underelement_kode
LEFT JOIN 	(SELECT
				arbejdssted,
				underelement_kode,
				SUM(ST_Length(geometri))::numeric(10,1) AS laengde,
				CASE
					WHEN underelement_kode = 'BL-05-02'
					THEN (SUM(ST_Length(geometri) * hoejde))::numeric(10,1)
					ELSE 0.0
				END AS klippeflade
			FROM greg.t_greg_linier
			WHERE systid_til IS NULL
			GROUP BY arbejdssted, underelement_kode) h
	ON a.arbejdssted = h.arbejdssted AND a.underelement_kode = h.underelement_kode
LEFT JOIN 	(SELECT
				arbejdssted,
				underelement_kode,
				SUM(ST_NumGeometries(geometri)) AS antal
			FROM greg.t_greg_punkter
			WHERE systid_til IS NULL AND underelement_kode NOT ILIKE 'REN%'
			GROUP BY arbejdssted, underelement_kode) i
	ON a.arbejdssted = i.arbejdssted AND a.underelement_kode = i.underelement_kode
LEFT JOIN 	(SELECT
				arbejdssted,
				SUM(ST_Area(geometri))::numeric(10,1) AS areal
			FROM greg.t_greg_flader
			WHERE systid_til IS NULL AND LEFT(underelement_kode, 3) NOT IN ('ANA', 'VA-', 'BE-')
			GROUP BY arbejdssted) j
	ON a.arbejdssted = j.arbejdssted
WHERE b.aktiv IS TRUE

ORDER BY 2, 8;

COMMENT ON VIEW greg.v_maengder_omraader_underelementer_2 IS 'Mængdeoversigt over elementer grupperet pr. område. Benyttes i Mængdekort.xlsm';




-- v_oversigt_elementer

DROP VIEW IF EXISTS greg.v_oversigt_elementer;

CREATE VIEW greg.v_oversigt_elementer AS

SELECT 	
	c.hovedelement_kode AS h_element_kode,
	c.hovedelement_tekst,
	b.element_kode,
	b.element_tekst,
	a.underelement_kode AS u_element_kode,
	a.underelement_tekst AS underlement_tekst,
	a.objekt_type
FROM greg.e_basis_underelementer a
LEFT JOIN greg.e_basis_elementer b ON a.element_kode = b.element_kode
LEFT JOIN greg.e_basis_hovedelementer c ON b.hovedelement_kode = c.hovedelement_kode
WHERE a.aktiv IS TRUE AND b.aktiv IS TRUE AND c.aktiv IS TRUE

ORDER BY
	CASE 
		WHEN c.hovedelement_kode ILIKE 'GR' 
		THEN 10
		WHEN c.hovedelement_kode ILIKE 'BL' 
		THEN 20
		WHEN c.hovedelement_kode ILIKE 'BU' 
		THEN 30
		WHEN c.hovedelement_kode ILIKE 'HÆ' 
		THEN 40
		WHEN c.hovedelement_kode ILIKE 'TR' 
		THEN 50
		WHEN c.hovedelement_kode ILIKE 'VA' 
		THEN 60
		WHEN c.hovedelement_kode ILIKE 'BE' 
		THEN 70
		WHEN c.hovedelement_kode ILIKE 'UD' 
		THEN 80
		WHEN c.hovedelement_kode ILIKE 'ANA' 
		THEN 90
		WHEN c.hovedelement_kode ILIKE 'REN' 
		THEN 100
		ELSE 85 END, 
	b.element_kode, 
	a.underelement_kode;

COMMENT ON VIEW greg.v_oversigt_elementer IS 'Elementoversigt. Benyttes i Lister.xlsx';


-- v_oversigt_omraade

CREATE VIEW greg.v_oversigt_omraade AS

SELECT
	a.pg_distrikt_nr as omraadenr,
	a.pg_distrikt_nr || ' ' || a.pg_distrikt_tekst AS omraade,
	b.pg_distrikt_type AS arealtype,
	CASE
		WHEN a.vejnr IS NOT NULL
		THEN c.vejnavn || ' ' || a.vejnr || ' - ' || a.postnr || ' ' || postnr_by
		WHEN a.vejkode IS NOT NULL
		THEN c.vejnavn || ' - ' || a.postnr || ' ' || postnr_by
		ELSE a.postnr || ' ' || d.postnr_by
	END AS adresse,
	public.ST_Area(a.geometri) AS areal
FROM greg.t_greg_omraader a
LEFT JOIN greg.d_basis_distrikt_type b ON a.pg_distrikt_type_kode = b.pg_distrikt_type_kode
LEFT JOIN greg.d_basis_vejnavn c ON a.vejkode = c.vejkode
LEFT JOIN greg.d_basis_postnr d ON a.postnr = d.postnr
WHERE a.aktiv IS TRUE

ORDER BY a.pg_distrikt_nr;

COMMENT ON VIEW greg.v_oversigt_omraade IS 'Look-up for aktive områder (QGIS + Excel). Mængdekort.xlsm';


-- v_oversigt_omraade_2

DROP VIEW IF EXISTS greg.v_oversigt_omraade_2;

CREATE VIEW greg.v_oversigt_omraade_2 AS

SELECT 	
	a.pg_distrikt_nr || ' ' || a.pg_distrikt_tekst AS omraade,
	a.postnr || ' ' || c.postnr_by AS distrikt,
	CASE
		WHEN a.vejnr IS NOT NULL
		THEN b.vejnavn || ' ' || a.vejnr
		ELSE b.vejnavn
	END AS adresse,
	d.pg_distrikt_type AS arealtype
FROM greg.t_greg_omraader a
LEFT JOIN greg.d_basis_vejnavn b ON a.vejkode = b.vejkode
LEFT JOIN greg.d_basis_postnr c ON a.postnr = c.postnr
LEFT JOIN greg.d_basis_distrikt_type d ON a.pg_distrikt_type_kode = d.pg_distrikt_type_kode
WHERE a.aktiv IS TRUE

ORDER BY a.pg_distrikt_nr;

COMMENT ON VIEW greg.v_oversigt_omraade_2 IS 'Områdeoversigt. Benyttes i Lister.xlsx';

-- v_oversigt_litra

DROP VIEW IF EXISTS greg.v_oversigt_litra;

CREATE VIEW greg.v_oversigt_litra AS

SELECT
	c.pg_distrikt_nr || ' ' || c.pg_distrikt_tekst AS omraade,
	a.underelement_kode,
	b.underelement_tekst,
	a.litra,
	a.hoejde
FROM greg.t_greg_flader a
LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
WHERE c.aktiv IS TRUE AND a.litra IS NOT NULL
GROUP BY omraade, a.underelement_kode, b.underelement_tekst, a.litra, a.hoejde

UNION ALL

SELECT
	c.pg_distrikt_nr || ' ' || c.pg_distrikt_tekst AS omraade,
	a.underelement_kode,
	b.underelement_tekst,
	a.litra,
	a.hoejde
FROM greg.t_greg_linier a
LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
WHERE c.aktiv IS TRUE AND a.litra IS NOT NULL
GROUP BY omraade, a.underelement_kode, b.underelement_tekst, a.litra, a.hoejde

UNION ALL

SELECT
	c.pg_distrikt_nr || ' ' || c.pg_distrikt_tekst AS omraade,
	a.underelement_kode,
	b.underelement_tekst,
	a.litra,
	a.hoejde
FROM greg.t_greg_punkter a
LEFT JOIN greg.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr
WHERE c.aktiv IS TRUE AND a.litra IS NOT NULL
GROUP BY omraade, a.underelement_kode, b.underelement_tekst, a.litra, a.hoejde

ORDER BY omraade, underelement_kode, litra;

COMMENT ON VIEW greg.v_oversigt_litra IS 'Oversigt over litra og højder. Benyttes i Mængdekort.xlsm.';

-- v_atlas

CREATE VIEW greg.v_atlas AS

SELECT
	a.objekt_id,
	'Område' AS omraadetype,
	a.pg_distrikt_nr,
	a.pg_distrikt_tekst,
	NULL AS delnavn,
	b.pg_distrikt_type,
	NULL AS delomraade,
	NULL AS delomraade_total,
	c.vejnavn,
	a.vejnr,
	a.postnr,
	d.postnr_by,
	a.geometri
FROM greg.t_greg_omraader a
LEFT JOIN greg.d_basis_distrikt_type b ON a.pg_distrikt_type_kode = b.pg_distrikt_type_kode
LEFT JOIN greg.d_basis_vejnavn c ON a.vejkode = c.vejkode
LEFT JOIN greg.d_basis_postnr d ON a.postnr = d.postnr
WHERE a.aktiv IS TRUE AND a.pg_distrikt_nr NOT IN(SELECT pg_distrikt_nr FROM greg.t_greg_delomraader) AND b.pg_distrikt_type NOT IN('Vejarealer') AND a.geometri IS NOT NULL

UNION

SELECT
	a.objekt_id,
	'Delområde' AS omraadetype,
	a.pg_distrikt_nr,
	b.pg_distrikt_tekst,
	a.delnavn,
	c.pg_distrikt_type,
	ROW_NUMBER() OVER(PARTITION BY a.pg_distrikt_nr ORDER BY a.delnavn) AS delomraade,
	f.delomraade_total,
	d.vejnavn,
	b.vejnr,
	b.postnr,
	e.postnr_by,
	a.geometri
FROM greg.t_greg_delomraader a
LEFT JOIN greg.t_greg_omraader b ON a.pg_distrikt_nr = b.pg_distrikt_nr
LEFT JOIN greg.d_basis_distrikt_type c ON b.pg_distrikt_type_kode = c.pg_distrikt_type_kode
LEFT JOIN greg.d_basis_vejnavn d ON b.vejkode = d.vejkode
LEFT JOIN greg.d_basis_postnr e ON b.postnr = e.postnr
LEFT JOIN (SELECT
			pg_distrikt_nr,
				COUNT(pg_distrikt_nr) AS delomraade_total
			FROM greg.t_greg_delomraader
			GROUP BY pg_distrikt_nr) f
		ON a.pg_distrikt_nr = f.pg_distrikt_nr
WHERE b.aktiv IS TRUE

ORDER BY pg_distrikt_nr, delomraade;

COMMENT ON VIEW greg.v_atlas IS 'Samlet områdetabel på baggrund af områder og delområder';


--
-- INDEXES
--

CREATE INDEX t_greg_flader_gist ON greg.t_greg_flader USING gist (geometri);

CREATE INDEX t_greg_linier_gist ON greg.t_greg_linier USING gist (geometri);

CREATE INDEX t_greg_punkter_gist ON greg.t_greg_punkter USING gist (geometri);

CREATE INDEX t_greg_omraader_gist ON greg.t_greg_omraader USING gist (geometri);

CREATE INDEX t_greg_delomraader_gist ON greg.t_greg_delomraader USING gist (geometri);


--
-- INSERTS
--

-- d_basis_ansvarlig_myndighed

INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (66137112, 'Albertslund Kommune', 165, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (60183112, 'Allerød Kommune', 201, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189692, 'Assens Kommune', 420, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (58271713, 'Ballerup Kommune', 151, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189765, 'Billund Kommune', 530, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (26696348, 'Bornholms Regionskommune', 400, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (65113015, 'Brøndby Kommune', 153, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189501, 'Brønderslev Kommune', 810, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (25775635, 'Christiansø', 411, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (12881517, 'Dragør Kommune', 155, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188386, 'Egedal Kommune', 240, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189803, 'Esbjerg Kommune', 561, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (31210917, 'Fanø Kommune', 563, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189714, 'Favrskov Kommune', 710, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188475, 'Faxe Kommune', 320, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188335, 'Fredensborg Kommune', 210, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (69116418, 'Fredericia Kommune', 607, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (11259979, 'Frederiksberg Kommune', 147, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189498, 'Frederikshavn Kommune', 813, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189129, 'Frederikssund Kommune', 250, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188327, 'Furesø Kommune', 190, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188645, 'Faaborg-Midtfyn Kommune', 430, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (19438414, 'Gentofte Kommune', 157, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (62761113, 'Gladsaxe Kommune', 159, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (65120119, 'Glostrup Kommune', 161, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (44023911, 'Greve Kommune', 253, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188440, 'Gribskov Kommune', 270, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188599, 'Guldborgsund Kommune', 376, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189757, 'Haderslev Kommune', 510, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188416, 'Halsnæs Kommune', 260, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189587, 'Hedensted Kommune', 766, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (64502018, 'Helsingør Kommune', 217, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (63640719, 'Herlev Kommune', 163, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189919, 'Herning Kommune', 657, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189366, 'Hillerød Kommune', 219, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189382, 'Hjørring Kommune', 860, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189447, 'Holbæk Kommune', 316, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189927, 'Holstebro Kommune', 661, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189889, 'Horsens Kommune', 615, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (55606617, 'Hvidovre Kommune', 167, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (19501817, 'Høje-Taastrup Kommune', 169, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (70960516, 'Hørsholm Kommune', 223, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189617, 'Ikast-Brande Kommune', 756, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (11931316, 'Ishøj Kommune', 183, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189439, 'Jammerbugt Kommune', 849, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189595, 'Kalundborg Kommune', 326, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189706, 'Kerteminde Kommune', 440, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189897, 'Kolding Kommune', 621, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (64942212, 'Københavns Kommune', 101, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189374, 'Køge Kommune', 259, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188955, 'Langeland Kommune', 482, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188548, 'Lejre Kommune', 350, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189935, 'Lemvig Kommune', 665, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188572, 'Lolland Kommune', 360, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (11715311, 'Lyngby-Taarbæk Kommune', 173, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (45973328, 'Læsø Kommune', 825, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189455, 'Mariagerfjord Kommune', 846, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189684, 'Middelfart Kommune', 410, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (41333014, 'Morsø Kommune', 773, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189986, 'Norddjurs Kommune', 707, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188947, 'Nordfyns Kommune', 480, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189722, 'Nyborg Kommune', 450, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189625, 'Næstved Kommune', 370, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (32264328, 'Odder Kommune', 727, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (35209115, 'Odense Kommune', 461, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188459, 'Odsherred Kommune', 306, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189668, 'Randers Kommune', 730, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189463, 'Rebild Kommune', 840, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189609, 'Ringkøbing-Skjern Kommune', 760, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (18957981, 'Ringsted Kommune', 329, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189404, 'Roskilde Kommune', 265, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188378, 'Rudersdal Kommune', 230, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (65307316, 'Rødovre Kommune', 175, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (23795515, 'Samsø Kommune', 741, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189641, 'Silkeborg Kommune', 740, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189633, 'Skanderborg Kommune', 746, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189579, 'Skive Kommune', 779, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29188505, 'Slagelse Kommune', 330, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (68534917, 'Solrød Kommune', 269, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189994, 'Sorø Kommune', 340, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29208654, 'Stevns Kommune', 336, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189951, 'Struer Kommune', 671, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189730, 'Svendborg Kommune', 479, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189978, 'Syddjurs Kommune', 706, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189773, 'Sønderborg Kommune', 540, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189560, 'Thisted Kommune', 787, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189781, 'Tønder Kommune', 550, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (20310413, 'Tårnby Kommune', 185, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (19583910, 'Vallensbæk Kommune', 187, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189811, 'Varde Kommune', 573, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189838, 'Vejen Kommune', 575, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189900, 'Vejle Kommune', 630, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189471, 'Vesthimmerlands Kommune', 820, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189846, 'Viborg Kommune', 791, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189676, 'Vordingborg Kommune', 390, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (28856075, 'Ærø Kommune', 492, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189854, 'Aabenraa Kommune', 580, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (29189420, 'Aalborg Kommune', 851, 't');
INSERT INTO greg.d_basis_ansvarlig_myndighed VALUES (55133018, 'Aarhus Kommune', 751, 't');


-- d_basis_offentlig

INSERT INTO greg.d_basis_offentlig VALUES (1, 'Synlig for alle', 't');
INSERT INTO greg.d_basis_offentlig VALUES (2, 'Synlig for den ansvarlige myndighed', 't');
INSERT INTO greg.d_basis_offentlig VALUES (3, 'Synlig for alle myndigheder, men ikke offentligheden', 't');


-- d_basis_oprindelse

INSERT INTO greg.d_basis_oprindelse VALUES (0, 'Ikke udfyldt', 't', NULL);
INSERT INTO greg.d_basis_oprindelse VALUES (1, 'Ortofoto', 't', 'Der skelnes ikke mellem forskellige producenter og forskellige årgange');
INSERT INTO greg.d_basis_oprindelse VALUES (2, 'Matrikelkort', 't', 'Matrikelkort fra KMS (København og Frederiksberg). Det forudsættes, at der benyttes opdaterede matrikelkort for datoen for planens indberetning');
INSERT INTO greg.d_basis_oprindelse VALUES (3, 'Opmåling', 't', 'Kan være med GPS, andet instrument el. lign. Det er ikke et udtryk for præcisi-on, men at det er udført i marken');
INSERT INTO greg.d_basis_oprindelse VALUES (4, 'FOT / Tekniske kort', 't', 'FOT, DTK, Danmarks Topografisk kortværk eller andre raster kort samt kommunernes tekniske kort eller andre vektorkort. Indtil FOT er landsdækkende benyttes kort10 (jf. overgangsregler for FOT)');
INSERT INTO greg.d_basis_oprindelse VALUES (5, 'Modelberegning', 't', 'GIS analyser eller modellering');
INSERT INTO greg.d_basis_oprindelse VALUES (6, 'Tegning', 't', 'Digitaliseret på baggrund af PDF, billede eller andet tegningsmateriale');
INSERT INTO greg.d_basis_oprindelse VALUES (7, 'Felt-/markbesøg', 't', 'Registrering på baggrund af tilsyn i marken');
INSERT INTO greg.d_basis_oprindelse VALUES (8, 'Borgeranmeldelse', 't', 'Indberetning via diverse borgerløsninger – eks. "Giv et praj"');
INSERT INTO greg.d_basis_oprindelse VALUES (9, 'Luftfoto (historiske 1944-1993)', 't', 'Luftfoto er kendetegnet ved ikke at have samme nøjagtighed i georeferingen, men man kan se en del ting, der ikke er på de nuværende ortofoto.');
INSERT INTO greg.d_basis_oprindelse VALUES (10, 'Skråfoto', 't', 'Luftfoto tager fra de 4 verdenshjørner');
INSERT INTO greg.d_basis_oprindelse VALUES (11, 'Andre foto', 't', 'Foto taget i jordhøjde - "terræn foto" (street-view, sagsbehandlerfotos, borgerfotos m.v.). Her er det meget tydeligt at se de enkelte detaljer, men også her kan man normalt ikke direkte placere et punkt via fotoet, men må over at gøre det via noget andet.');
INSERT INTO greg.d_basis_oprindelse VALUES (12, '3D', 't', 'Laserscanning, Digital terrænmodel (DTM) afledninger, termografiske målinger (bestemmelse af temperaturforskelle) o.lign.');


-- d_basis_status

INSERT INTO greg.d_basis_status VALUES (0, 'Ukendt', 't');
INSERT INTO greg.d_basis_status VALUES (1, 'Kladde', 't');
INSERT INTO greg.d_basis_status VALUES (2, 'Forslag', 't');
INSERT INTO greg.d_basis_status VALUES (3, 'Gældende / Vedtaget', 't');
INSERT INTO greg.d_basis_status VALUES (4, 'Ikke gældende / Aflyst', 't');


-- d_basis_tilstand

INSERT INTO greg.d_basis_tilstand VALUES (1, 'Dårlig', 't', 'Udskiftning eller vedligeholdelse tiltrængt/påkrævet. Fungerer ikke efter hensigten eller i fare for det sker inden for kort tid.');
INSERT INTO greg.d_basis_tilstand VALUES (2, 'Middel', 't', 'Fungerer efter hensigten, men kunne trænge til vedligeholdelse for at forlænge levetiden/funktionen');
INSERT INTO greg.d_basis_tilstand VALUES (3, 'God', 't', 'Tæt på lige så god som et nyt.');
INSERT INTO greg.d_basis_tilstand VALUES (8, 'Andet', 't', 'Anden tilstand end Dårlig, Middel, God eller Ukendt.');
INSERT INTO greg.d_basis_tilstand VALUES (9, 'Ukendt', 't', 'Mangler viden til at kunne udfylde værdien med Dårlig, Middel eller God.');


-- d_basis_bruger_id

-- INSERT INTO greg.d_basis_bruger_id (bruger_id, navn, aktiv) VALUES ();

INSERT INTO greg.d_basis_bruger_id (bruger_id, navn, aktiv) VALUES ('postgres', 'Administrator', 't');


-- d_basis_kommunal_kontakt

-- INSERT INTO greg.d_basis_kommunal_kontakt (navn, telefon, email, aktiv) VALUES ();


-- d_basis_udfoerer

-- INSERT INTO greg.d_basis_udfoerer (udfoerer_kode, udfoerer, aktiv) VALUES ();


-- d_basis_udfoerer_entrep

-- INSERT INTO greg.d_basis_udfoerer_entrep (udfoerer_entrep, aktiv) VALUES ();


-- d_basis_udfoerer_kontakt

-- INSERT INTO greg.d_basis_udfoerer_kontakt (udfoerer_kode, navn, telefon, email, aktiv) VALUES ();


-- d_basis_postnr

INSERT INTO greg.d_basis_postnr VALUES (800, 'Høje Taastrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (900, 'København C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (917, 'Københavns Pakkecent', 'f');
INSERT INTO greg.d_basis_postnr VALUES (960, 'Udland', 'f');
INSERT INTO greg.d_basis_postnr VALUES (999, 'København C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1000, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1050, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1051, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1052, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1053, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1054, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1055, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1056, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1057, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1058, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1059, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1060, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1061, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1062, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1063, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1064, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1065, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1066, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1067, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1068, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1069, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1070, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1071, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1072, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1073, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1074, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1092, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1093, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1095, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1098, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1100, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1101, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1102, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1103, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1104, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1105, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1106, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1107, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1110, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1111, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1112, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1113, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1114, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1115, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1116, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1117, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1118, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1119, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1120, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1121, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1122, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1123, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1124, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1125, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1126, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1127, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1128, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1129, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1130, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1131, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1140, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1147, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1148, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1150, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1151, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1152, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1153, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1154, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1155, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1156, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1157, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1158, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1159, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1160, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1161, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1162, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1164, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1165, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1166, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1167, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1168, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1169, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1170, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1171, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1172, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1173, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1174, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1175, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1200, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1201, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1202, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1203, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1204, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1205, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1206, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1207, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1208, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1209, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1210, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1211, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1213, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1214, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1215, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1216, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1217, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1218, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1219, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1220, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1221, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1240, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1250, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1251, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1253, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1254, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1255, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1256, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1257, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1259, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1260, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1261, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1263, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1264, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1265, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1266, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1267, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1268, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1270, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1271, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1300, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1301, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1302, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1303, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1304, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1306, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1307, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1308, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1309, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1310, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1311, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1312, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1313, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1314, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1315, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1316, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1317, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1318, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1319, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1320, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1321, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1322, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1323, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1324, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1325, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1326, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1327, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1328, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1329, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1350, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1352, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1353, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1354, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1355, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1356, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1357, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1358, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1359, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1360, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1361, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1362, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1363, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1364, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1365, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1366, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1367, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1368, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1369, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1370, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1371, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1400, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1401, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1402, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1403, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1406, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1407, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1408, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1409, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1410, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1411, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1412, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1413, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1414, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1415, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1416, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1417, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1418, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1419, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1420, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1421, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1422, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1423, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1424, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1425, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1426, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1427, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1428, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1429, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1430, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1431, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1432, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1433, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1434, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1435, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1436, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1437, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1438, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1439, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1440, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1441, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1448, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1450, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1451, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1452, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1453, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1454, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1455, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1456, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1457, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1458, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1459, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1460, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1462, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1463, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1464, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1466, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1467, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1468, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1470, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1471, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1472, 'København K', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1500, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1513, 'Centraltastning', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1532, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1533, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1550, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1551, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1552, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1553, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1554, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1555, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1556, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1557, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1558, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1559, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1560, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1561, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1562, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1563, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1564, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1566, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1567, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1568, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1569, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1570, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1571, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1572, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1573, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1574, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1575, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1576, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1577, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1592, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1599, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1600, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1601, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1602, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1603, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1604, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1606, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1607, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1608, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1609, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1610, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1611, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1612, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1613, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1614, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1615, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1616, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1617, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1618, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1619, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1620, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1621, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1622, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1623, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1624, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1630, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1631, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1632, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1633, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1634, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1635, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1650, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1651, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1652, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1653, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1654, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1655, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1656, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1657, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1658, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1659, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1660, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1661, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1662, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1663, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1664, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1665, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1666, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1667, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1668, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1669, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1670, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1671, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1672, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1673, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1674, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1675, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1676, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1677, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1699, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1700, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1701, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1702, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1703, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1704, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1705, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1706, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1707, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1708, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1709, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1710, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1711, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1712, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1714, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1715, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1716, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1717, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1718, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1719, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1720, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1721, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1722, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1723, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1724, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1725, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1726, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1727, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1728, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1729, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1730, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1731, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1732, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1733, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1734, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1735, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1736, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1737, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1738, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1739, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1749, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1750, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1751, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1752, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1753, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1754, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1755, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1756, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1757, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1758, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1759, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1760, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1761, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1762, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1763, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1764, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1765, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1766, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1770, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1771, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1772, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1773, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1774, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1775, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1777, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1780, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1785, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1786, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1787, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1790, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1799, 'København V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1800, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1801, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1802, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1803, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1804, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1805, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1806, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1807, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1808, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1809, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1810, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1811, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1812, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1813, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1814, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1815, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1816, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1817, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1818, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1819, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1820, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1822, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1823, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1824, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1825, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1826, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1827, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1828, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1829, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1850, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1851, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1852, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1853, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1854, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1855, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1856, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1857, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1860, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1861, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1862, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1863, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1864, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1865, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1866, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1867, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1868, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1870, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1871, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1872, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1873, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1874, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1875, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1876, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1877, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1878, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1879, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1900, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1901, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1902, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1903, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1904, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1905, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1906, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1908, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1909, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1910, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1911, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1912, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1913, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1914, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1915, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1916, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1917, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1920, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1921, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1922, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1923, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1924, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1925, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1926, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1927, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1928, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1950, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1951, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1952, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1953, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1954, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1955, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1956, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1957, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1958, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1959, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1960, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1961, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1962, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1963, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1964, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1965, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1966, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1967, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1970, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1971, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1972, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1973, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (1974, 'Frederiksberg C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2000, 'Frederiksberg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2100, 'København Ø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2150, 'Nordhavn', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2200, 'København N', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2300, 'København S', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2400, 'København NV', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2450, 'København SV', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2500, 'Valby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2600, 'Glostrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2605, 'Brøndby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2610, 'Rødovre', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2620, 'Albertslund', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2625, 'Vallensbæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2630, 'Taastrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2635, 'Ishøj', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2640, 'Hedehusene', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2650, 'Hvidovre', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2660, 'Brøndby Strand', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2665, 'Vallensbæk Strand', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2670, 'Greve', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2680, 'Solrød Strand', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2690, 'Karlslunde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2700, 'Brønshøj', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2720, 'Vanløse', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2730, 'Herlev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2740, 'Skovlunde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2750, 'Ballerup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2760, 'Måløv', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2765, 'Smørum', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2770, 'Kastrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2791, 'Dragør', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2800, 'Kongens Lyngby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2820, 'Gentofte', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2830, 'Virum', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2840, 'Holte', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2850, 'Nærum', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2860, 'Søborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2870, 'Dyssegård', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2880, 'Bagsværd', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2900, 'Hellerup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2920, 'Charlottenlund', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2930, 'Klampenborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2942, 'Skodsborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2950, 'Vedbæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2960, 'Rungsted Kyst', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2970, 'Hørsholm', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2980, 'Kokkedal', 'f');
INSERT INTO greg.d_basis_postnr VALUES (2990, 'Nivå', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3000, 'Helsingør', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3050, 'Humlebæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3060, 'Espergærde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3070, 'Snekkersten', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3080, 'Tikøb', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3100, 'Hornbæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3120, 'Dronningmølle', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3140, 'Ålsgårde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3150, 'Hellebæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3200, 'Helsinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3210, 'Vejby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3220, 'Tisvildeleje', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3230, 'Græsted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3250, 'Gilleleje', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3300, 'Frederiksværk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3310, 'Ølsted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3320, 'Skævinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3330, 'Gørløse', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3360, 'Liseleje', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3370, 'Melby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3390, 'Hundested', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3400, 'Hillerød', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3450, 'Allerød', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3460, 'Birkerød', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3480, 'Fredensborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3490, 'Kvistgård', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3500, 'Værløse', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3520, 'Farum', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3540, 'Lynge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3550, 'Slangerup', 't');
INSERT INTO greg.d_basis_postnr VALUES (3600, 'Frederikssund', 't');
INSERT INTO greg.d_basis_postnr VALUES (3630, 'Jægerspris', 't');
INSERT INTO greg.d_basis_postnr VALUES (3650, 'Ølstykke', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3660, 'Stenløse', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3670, 'Veksø Sjælland', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3700, 'Rønne', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3720, 'Aakirkeby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3730, 'Nexø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3740, 'Svaneke', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3751, 'Østermarie', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3760, 'Gudhjem', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3770, 'Allinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3782, 'Klemensker', 'f');
INSERT INTO greg.d_basis_postnr VALUES (3790, 'Hasle', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4000, 'Roskilde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4030, 'Tune', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4040, 'Jyllinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4050, 'Skibby', 't');
INSERT INTO greg.d_basis_postnr VALUES (4060, 'Kirke Såby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4070, 'Kirke Hyllinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4100, 'Ringsted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4130, 'Viby Sjælland', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4140, 'Borup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4160, 'Herlufmagle', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4171, 'Glumsø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4173, 'Fjenneslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4174, 'Jystrup Midtsj', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4180, 'Sorø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4190, 'Munke Bjergby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4200, 'Slagelse', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4220, 'Korsør', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4230, 'Skælskør', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4241, 'Vemmelev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4242, 'Boeslunde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4243, 'Rude', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4250, 'Fuglebjerg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4261, 'Dalmose', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4262, 'Sandved', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4270, 'Høng', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4281, 'Gørlev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4291, 'Ruds Vedby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4293, 'Dianalund', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4295, 'Stenlille', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4296, 'Nyrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4300, 'Holbæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4320, 'Lejre', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4330, 'Hvalsø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4340, 'Tølløse', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4350, 'Ugerløse', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4360, 'Kirke Eskilstrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4370, 'Store Merløse', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4390, 'Vipperød', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4400, 'Kalundborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4420, 'Regstrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4440, 'Mørkøv', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4450, 'Jyderup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4460, 'Snertinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4470, 'Svebølle', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4480, 'Store Fuglede', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4490, 'Jerslev Sjælland', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4500, 'Nykøbing Sj', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4520, 'Svinninge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4532, 'Gislinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4534, 'Hørve', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4540, 'Fårevejle', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4550, 'Asnæs', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4560, 'Vig', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4571, 'Grevinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4572, 'Nørre Asmindrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4573, 'Højby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4581, 'Rørvig', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4583, 'Sjællands Odde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4591, 'Føllenslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4592, 'Sejerø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4593, 'Eskebjerg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4600, 'Køge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4621, 'Gadstrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4622, 'Havdrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4623, 'Lille Skensved', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4632, 'Bjæverskov', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4640, 'Faxe', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4652, 'Hårlev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4653, 'Karise', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4654, 'Faxe Ladeplads', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4660, 'Store Heddinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4671, 'Strøby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4672, 'Klippinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4673, 'Rødvig Stevns', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4681, 'Herfølge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4682, 'Tureby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4683, 'Rønnede', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4684, 'Holmegaard', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4690, 'Haslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4700, 'Næstved', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4720, 'Præstø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4733, 'Tappernøje', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4735, 'Mern', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4736, 'Karrebæksminde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4750, 'Lundby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4760, 'Vordingborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4771, 'Kalvehave', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4772, 'Langebæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4773, 'Stensved', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4780, 'Stege', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4791, 'Borre', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4792, 'Askeby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4793, 'Bogø By', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4800, 'Nykøbing F', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4840, 'Nørre Alslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4850, 'Stubbekøbing', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4862, 'Guldborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4863, 'Eskilstrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4871, 'Horbelev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4872, 'Idestrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4873, 'Væggerløse', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4874, 'Gedser', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4880, 'Nysted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4891, 'Toreby L', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4892, 'Kettinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4894, 'Øster Ulslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4895, 'Errindlev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4900, 'Nakskov', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4912, 'Harpelunde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4913, 'Horslunde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4920, 'Søllested', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4930, 'Maribo', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4941, 'Bandholm', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4943, 'Torrig L', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4944, 'Fejø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4951, 'Nørreballe', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4952, 'Stokkemarke', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4953, 'Vesterborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4960, 'Holeby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4970, 'Rødby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4983, 'Dannemare', 'f');
INSERT INTO greg.d_basis_postnr VALUES (4990, 'Sakskøbing', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5000, 'Odense C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5200, 'Odense V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5210, 'Odense NV', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5220, 'Odense SØ', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5230, 'Odense M', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5240, 'Odense NØ', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5250, 'Odense SV', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5260, 'Odense S', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5270, 'Odense N', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5290, 'Marslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5300, 'Kerteminde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5320, 'Agedrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5330, 'Munkebo', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5350, 'Rynkeby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5370, 'Mesinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5380, 'Dalby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5390, 'Martofte', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5400, 'Bogense', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5450, 'Otterup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5462, 'Morud', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5463, 'Harndrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5464, 'Brenderup Fyn', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5466, 'Asperup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5471, 'Søndersø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5474, 'Veflinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5485, 'Skamby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5491, 'Blommenslyst', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5492, 'Vissenbjerg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5500, 'Middelfart', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5540, 'Ullerslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5550, 'Langeskov', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5560, 'Aarup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5580, 'Nørre Aaby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5591, 'Gelsted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5592, 'Ejby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5600, 'Faaborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5610, 'Assens', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5620, 'Glamsbjerg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5631, 'Ebberup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5642, 'Millinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5672, 'Broby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5683, 'Haarby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5690, 'Tommerup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5700, 'Svendborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5750, 'Ringe', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5762, 'Vester Skerninge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5771, 'Stenstrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5772, 'Kværndrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5792, 'Årslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5800, 'Nyborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5853, 'Ørbæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5854, 'Gislev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5856, 'Ryslinge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5863, 'Ferritslev Fyn', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5871, 'Frørup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5874, 'Hesselager', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5881, 'Skårup Fyn', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5882, 'Vejstrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5883, 'Oure', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5884, 'Gudme', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5892, 'Gudbjerg Sydfyn', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5900, 'Rudkøbing', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5932, 'Humble', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5935, 'Bagenkop', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5953, 'Tranekær', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5960, 'Marstal', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5970, 'Ærøskøbing', 'f');
INSERT INTO greg.d_basis_postnr VALUES (5985, 'Søby Ærø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6000, 'Kolding', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6040, 'Egtved', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6051, 'Almind', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6052, 'Viuf', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6064, 'Jordrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6070, 'Christiansfeld', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6091, 'Bjert', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6092, 'Sønder Stenderup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6093, 'Sjølund', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6094, 'Hejls', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6100, 'Haderslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6200, 'Aabenraa', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6230, 'Rødekro', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6240, 'Løgumkloster', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6261, 'Bredebro', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6270, 'Tønder', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6280, 'Højer', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6300, 'Gråsten', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6310, 'Broager', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6320, 'Egernsund', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6330, 'Padborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6340, 'Kruså', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6360, 'Tinglev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6372, 'Bylderup-Bov', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6392, 'Bolderslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6400, 'Sønderborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6430, 'Nordborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6440, 'Augustenborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6470, 'Sydals', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6500, 'Vojens', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6510, 'Gram', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6520, 'Toftlund', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6534, 'Agerskov', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6535, 'Branderup J', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6541, 'Bevtoft', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6560, 'Sommersted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6580, 'Vamdrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6600, 'Vejen', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6621, 'Gesten', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6622, 'Bække', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6623, 'Vorbasse', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6630, 'Rødding', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6640, 'Lunderskov', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6650, 'Brørup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6660, 'Lintrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6670, 'Holsted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6682, 'Hovborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6683, 'Føvling', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6690, 'Gørding', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6700, 'Esbjerg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6705, 'Esbjerg Ø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6710, 'Esbjerg V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6715, 'Esbjerg N', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6720, 'Fanø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6731, 'Tjæreborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6740, 'Bramming', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6752, 'Glejbjerg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6753, 'Agerbæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6760, 'Ribe', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6771, 'Gredstedbro', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6780, 'Skærbæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6792, 'Rømø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6800, 'Varde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6818, 'Årre', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6823, 'Ansager', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6830, 'Nørre Nebel', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6840, 'Oksbøl', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6851, 'Janderup Vestj', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6852, 'Billum', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6853, 'Vejers Strand', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6854, 'Henne', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6855, 'Outrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6857, 'Blåvand', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6862, 'Tistrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6870, 'Ølgod', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6880, 'Tarm', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6893, 'Hemmet', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6900, 'Skjern', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6920, 'Videbæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6933, 'Kibæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6940, 'Lem St', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6950, 'Ringkøbing', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6960, 'Hvide Sande', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6971, 'Spjald', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6973, 'Ørnhøj', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6980, 'Tim', 'f');
INSERT INTO greg.d_basis_postnr VALUES (6990, 'Ulfborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7000, 'Fredericia', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7007, 'Fredericia', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7080, 'Børkop', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7100, 'Vejle', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7120, 'Vejle Øst', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7130, 'Juelsminde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7140, 'Stouby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7150, 'Barrit', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7160, 'Tørring', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7171, 'Uldum', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7173, 'Vonge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7182, 'Bredsten', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7183, 'Randbøl', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7184, 'Vandel', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7190, 'Billund', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7200, 'Grindsted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7250, 'Hejnsvig', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7260, 'Sønder Omme', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7270, 'Stakroge', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7280, 'Sønder Felding', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7300, 'Jelling', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7321, 'Gadbjerg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7323, 'Give', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7330, 'Brande', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7361, 'Ejstrupholm', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7362, 'Hampen', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7400, 'Herning', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7430, 'Ikast', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7441, 'Bording', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7442, 'Engesvang', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7451, 'Sunds', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7470, 'Karup J', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7480, 'Vildbjerg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7490, 'Aulum', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7500, 'Holstebro', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7540, 'Haderup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7550, 'Sørvad', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7560, 'Hjerm', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7570, 'Vemb', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7600, 'Struer', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7620, 'Lemvig', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7650, 'Bøvlingbjerg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7660, 'Bækmarksbro', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7673, 'Harboøre', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7680, 'Thyborøn', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7700, 'Thisted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7730, 'Hanstholm', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7741, 'Frøstrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7742, 'Vesløs', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7752, 'Snedsted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7755, 'Bedsted Thy', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7760, 'Hurup Thy', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7770, 'Vestervig', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7790, 'Thyholm', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7800, 'Skive', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7830, 'Vinderup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7840, 'Højslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7850, 'Stoholm Jyll', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7860, 'Spøttrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7870, 'Roslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7884, 'Fur', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7900, 'Nykøbing M', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7950, 'Erslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7960, 'Karby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7970, 'Redsted M', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7980, 'Vils', 'f');
INSERT INTO greg.d_basis_postnr VALUES (7990, 'Øster Assels', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8000, 'Aarhus C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8200, 'Aarhus N', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8210, 'Aarhus V', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8220, 'Brabrand', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8230, 'Åbyhøj', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8240, 'Risskov', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8245, 'Risskov Ø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8250, 'Egå', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8260, 'Viby J', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8270, 'Højbjerg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8300, 'Odder', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8305, 'Samsø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8310, 'Tranbjerg J', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8320, 'Mårslet', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8330, 'Beder', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8340, 'Malling', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8350, 'Hundslund', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8355, 'Solbjerg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8361, 'Hasselager', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8362, 'Hørning', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8370, 'Hadsten', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8380, 'Trige', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8381, 'Tilst', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8382, 'Hinnerup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8400, 'Ebeltoft', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8410, 'Rønde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8420, 'Knebel', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8444, 'Balle', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8450, 'Hammel', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8462, 'Harlev J', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8464, 'Galten', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8471, 'Sabro', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8472, 'Sporup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8500, 'Grenaa', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8520, 'Lystrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8530, 'Hjortshøj', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8541, 'Skødstrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8543, 'Hornslet', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8544, 'Mørke', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8550, 'Ryomgård', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8560, 'Kolind', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8570, 'Trustrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8581, 'Nimtofte', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8585, 'Glesborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8586, 'Ørum Djurs', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8592, 'Anholt', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8600, 'Silkeborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8620, 'Kjellerup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8632, 'Lemming', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8641, 'Sorring', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8643, 'Ans By', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8653, 'Them', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8654, 'Bryrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8660, 'Skanderborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8670, 'Låsby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8680, 'Ry', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8700, 'Horsens', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8721, 'Daugård', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8722, 'Hedensted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8723, 'Løsning', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8732, 'Hovedgård', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8740, 'Brædstrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8751, 'Gedved', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8752, 'Østbirk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8762, 'Flemming', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8763, 'Rask Mølle', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8765, 'Klovborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8766, 'Nørre Snede', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8781, 'Stenderup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8783, 'Hornsyld', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8800, 'Viborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8830, 'Tjele', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8831, 'Løgstrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8832, 'Skals', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8840, 'Rødkærsbro', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8850, 'Bjerringbro', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8860, 'Ulstrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8870, 'Langå', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8881, 'Thorsø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8882, 'Fårvang', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8883, 'Gjern', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8900, 'Randers C', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8920, 'Randers NV', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8930, 'Randers NØ', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8940, 'Randers SV', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8950, 'Ørsted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8960, 'Randers SØ', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8961, 'Allingåbro', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8963, 'Auning', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8970, 'Havndal', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8981, 'Spentrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8983, 'Gjerlev J', 'f');
INSERT INTO greg.d_basis_postnr VALUES (8990, 'Fårup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9000, 'Aalborg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9200, 'Aalborg SV', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9210, 'Aalborg SØ', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9220, 'Aalborg Øst', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9230, 'Svenstrup J', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9240, 'Nibe', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9260, 'Gistrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9270, 'Klarup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9280, 'Storvorde', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9293, 'Kongerslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9300, 'Sæby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9310, 'Vodskov', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9320, 'Hjallerup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9330, 'Dronninglund', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9340, 'Asaa', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9352, 'Dybvad', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9362, 'Gandrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9370, 'Hals', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9380, 'Vestbjerg', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9381, 'Sulsted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9382, 'Tylstrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9400, 'Nørresundby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9430, 'Vadum', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9440, 'Aabybro', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9460, 'Brovst', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9480, 'Løkken', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9490, 'Pandrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9492, 'Blokhus', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9493, 'Saltum', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9500, 'Hobro', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9510, 'Arden', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9520, 'Skørping', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9530, 'Støvring', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9541, 'Suldrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9550, 'Mariager', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9560, 'Hadsund', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9574, 'Bælum', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9575, 'Terndrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9600, 'Aars', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9610, 'Nørager', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9620, 'Aalestrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9631, 'Gedsted', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9632, 'Møldrup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9640, 'Farsø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9670, 'Løgstør', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9681, 'Ranum', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9690, 'Fjerritslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9700, 'Brønderslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9740, 'Jerslev J', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9750, 'Østervrå', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9760, 'Vrå', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9800, 'Hjørring', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9830, 'Tårs', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9850, 'Hirtshals', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9870, 'Sindal', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9881, 'Bindslev', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9900, 'Frederikshavn', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9940, 'Læsø', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9970, 'Strandby', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9981, 'Jerup', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9982, 'Ålbæk', 'f');
INSERT INTO greg.d_basis_postnr VALUES (9990, 'Skagen', 'f');


-- d_basis_vejnavn

-- INSERT INTO greg.d_basis_vejnavn (vejkode, vejnavn, aktiv, cvf_vejkode, postnr, kommunekode) VALUES ();

INSERT INTO greg.d_basis_vejnavn VALUES (1, 'A C Hansensvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (2, 'Aaskildevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (4, 'Abildgård', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (5, 'Adilsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (6, 'Agerhøjen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (7, 'Agervangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (8, 'Agervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (9, 'Agervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (10, 'Ahornkrogen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (11, 'Ahornvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (13, 'Ahornvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (14, 'Akacievej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (15, 'Alholm Ø', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (16, 'Alholmvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (17, 'Allingbjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (18, 'Amalievej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (19, 'Amledsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (20, 'Amsterdamhusene', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (21, 'Andekærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (22, 'Anders Jensens Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (23, 'Anders Jensensvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (24, 'Anemonevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (25, 'Anemonevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (26, 'Anemonevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (28, 'Anne Marievej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (29, 'Ansgarsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (30, 'Apholm', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (31, 'Arvedsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (32, 'Asgård', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (33, 'Askelundsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (34, 'Askevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (35, 'Askevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (37, 'Askøvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (38, 'Aslaugsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (39, 'Axelgaardsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (40, 'Bag Hegnet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (43, 'Bag Skovens Brugs', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (45, 'Bakager', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (46, 'Bakkebo', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (47, 'Bakkedraget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (48, 'Bakkegaardsmarken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (49, 'Bakkegade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (50, 'Bakkegården', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (51, 'Bakkegårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (52, 'Bakkehøjen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (53, 'Bakkekammen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (54, 'Bakkelundsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (55, 'Bakkestrædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (56, 'Bakkesvinget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (57, 'Bakkesvinget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (58, 'Bakkesvinget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (59, 'Bakkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (61, 'Bakkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (63, 'Bakkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (64, 'Bakkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (65, 'Bakkevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (66, 'Baldersvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (67, 'Ballermosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (68, 'Banegraven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (69, 'Baneledet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (70, 'Banevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (71, 'Barakvejen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (72, 'Baunehøjen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (73, 'Baunehøjgaardsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (75, 'Baunehøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (76, 'Baunevangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (77, 'Bautahøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (78, 'Bavnehøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (79, 'Bavnen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (82, 'Baygårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (83, 'Beckersvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (84, 'Bellisvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (85, 'Bellisvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (86, 'Bellisvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (88, 'Benediktevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (89, 'Betulavej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (90, 'Birkagervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (91, 'Birkealle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (92, 'Birkebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (93, 'Birkebækvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (94, 'Birkedal', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (95, 'Birkedalsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (96, 'Birkeengen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (97, 'Birkehaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (98, 'Birkehøjen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (99, 'Birkekæret', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (100, 'Birkelunden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (101, 'Birkemosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (102, 'Birkemosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (103, 'Birketoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (104, 'Birkevang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (106, 'Birkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (107, 'Birkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (108, 'Birkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (112, 'Birkevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (113, 'Birkevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (114, 'Birkholmvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (116, 'Bjarkesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (117, 'Bjarkesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (118, 'Bjergvejen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (120, 'Blakke Møllevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (121, 'Blommehaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (122, 'Blommevang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (123, 'Blommevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (124, 'Blødevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (125, 'Bogfinkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (126, 'Bogfinkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (127, 'Bogøvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (132, 'Bonderupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (133, 'Bonderupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (134, 'Bopladsen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (135, 'Borgervænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (136, 'Borgmarken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (137, 'Borgmestervænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (138, 'Brantegårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (139, 'Bredagervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (141, 'Bredviggårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (142, 'Bredvigvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (144, 'Bregnevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (145, 'Brobæksgade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (146, 'Broengen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (147, 'Bronzeager', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (148, 'Bruhnsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (149, 'Buen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (150, 'Buen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (152, 'Buresø', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (153, 'Busvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (154, 'Bybakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (155, 'Bygaden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (156, 'Bygaden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (157, 'Bygaden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (158, 'Bygaden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (160, 'Bygmarken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (161, 'Bygtoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (162, 'Bygvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (163, 'Byhøjen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (164, 'Bykærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (165, 'Bymidten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (166, 'Bystrædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (168, 'Bytoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (169, 'Byvangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (170, 'Byvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (171, 'Bækkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (172, 'Bøgealle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (173, 'Bøgebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (174, 'Bøgetoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (175, 'Bøgevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (176, 'Bøgevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (177, 'Bøgevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (179, 'Centervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (181, 'Chr Jørgensensvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (183, 'Christiansmindevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (186, 'Dalbovej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (190, 'Dalby Huse Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (192, 'Dalby Strandvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (193, 'Dalskrænten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (194, 'Dalsænkningen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (196, 'Dalvejen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (198, 'Damgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (199, 'Damgårdsvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (202, 'Dammen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (203, 'Damstræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (204, 'Damvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (207, 'Degnebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (210, 'Degnemosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (211, 'Degnersvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (212, 'Degnevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (213, 'Degnevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (214, 'Digevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (215, 'Digevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (217, 'Draaby Strandvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (218, 'Drosselvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (219, 'Drosselvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (220, 'Drosselvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (222, 'Drosselvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (223, 'Druedalsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (224, 'Druekrogen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (226, 'Dråbyvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (227, 'Duemosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (228, 'Duevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (229, 'Duevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (230, 'Duevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (231, 'Dunhammervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (232, 'Dunhammervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (233, 'Dyrlægegårds Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (234, 'Dyrnæsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (235, 'Dysagervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (236, 'Dyssebjerg', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (237, 'Dyssegaardsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (238, 'Dådyrvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (239, 'Egebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (240, 'Egebjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (241, 'Egehøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (243, 'Egelundsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (244, 'Egelyvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (245, 'Egeparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (246, 'Egeparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (247, 'Egernvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (249, 'Egernvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (250, 'Egestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (251, 'Egetoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (252, 'Egevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (254, 'Egevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (255, 'Egevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (257, 'Egilsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (258, 'Elbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (259, 'Ellehammervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (260, 'Ellekildehøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (261, 'Ellekær', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (262, 'Ellekær', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (263, 'Ellelunden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (264, 'Ellemosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (265, 'Ellens Vænge', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (266, 'Ellevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (268, 'Ellevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (270, 'Elmegårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (271, 'Elmegårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (272, 'Elmetoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (273, 'Elmevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (274, 'Elmevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (275, 'Elmevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (276, 'Elmevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (278, 'Elsenbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (279, 'Elverhøjen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (280, 'Enebærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (281, 'Engbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (282, 'Engblommevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (283, 'Engbovej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (284, 'Engdraget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (285, 'Engdraget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (286, 'Enghavegårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (287, 'Enghaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (288, 'Enghaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (289, 'Enghøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (290, 'Engledsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (291, 'Englodden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (292, 'Englodden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (293, 'Englodsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (294, 'Englystvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (295, 'Engparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (296, 'Engsvinget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (297, 'Engtoftevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (298, 'Engvang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (299, 'Engvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (300, 'Engvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (301, 'Engvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (303, 'Erantisvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (304, 'Erantisvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (305, 'Erik Arupsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (306, 'Erik Ejegodsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (307, 'Eskemosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (309, 'Eskilsø', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (310, 'Esrogårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (311, 'Esrohaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (312, 'Esromarken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (313, 'Fabriksvangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (314, 'Fagerholtvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (316, 'Fagerkærsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (317, 'Falkenborggården', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (318, 'Falkenborgvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (319, 'Falkevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (320, 'Falkevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (321, 'Fasangårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (322, 'Fasanvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (323, 'Fasanvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (324, 'Fasanvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (325, 'Fasanvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (327, 'Fasanvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (328, 'Fejøvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (329, 'Femhøj Stationsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (330, 'Femhøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (331, 'Femvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (332, 'Fengesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (334, 'Fiskerhusevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (335, 'Fiskervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (336, 'Fjeldhøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (337, 'Fjordbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (338, 'Fjordbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (339, 'Fjordglimtvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (340, 'Fjordgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (341, 'Fjordparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (342, 'Fjordskovvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (343, 'Fjordskrænten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (344, 'Fjordslugten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (345, 'Fjordstien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (346, 'Fjordtoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (348, 'Fjordvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (349, 'Fjordvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (350, 'Fjordvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (351, 'Flintehøjen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (352, 'Foderstofgården', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (353, 'Fogedgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (355, 'Forårsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (356, 'Fredbo Vænge', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (357, 'Fredensgade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (358, 'Fredensgade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (359, 'Frederiksborggade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (360, 'Frederiksborgvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (361, 'Frederiksborgvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (362, 'Hørup Skovvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (363, 'Frederikssundsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (364, 'Frederiksværkvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (365, 'Frejasvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (366, 'Frejasvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (367, 'Frihedsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (368, 'Frodesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (369, 'Frodesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (370, 'Fuglebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (371, 'Fyrrebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (372, 'Fyrrebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (373, 'Fyrrehaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (374, 'Fyrrehegnet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (375, 'Fyrrehøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (376, 'Fyrreknolden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (377, 'Fyrrekrogen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (378, 'Fyrreparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (379, 'Fyrresidevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (380, 'Fyrrevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (381, 'Fyrrevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (383, 'Fyrvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (384, 'Fælledvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (385, 'Fællesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (386, 'Færgelundsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (387, 'Færgeparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (388, 'Færgevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (389, 'Fæstermarken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (390, 'Gadehøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (392, 'Gadekærsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (393, 'Gammel Dalbyvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (394, 'Gammel Færgegårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (395, 'Gammel Kulhusvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (396, 'Gammel Marbækvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (397, 'Gammel Slangerupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (398, 'Gammel Stationsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (399, 'Gartnervænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (400, 'Gartnervænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (401, 'Kilde Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (402, 'Geddestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (403, 'Gedehøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (404, 'Gefionvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (406, 'Gerlev Strandvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (407, 'Gl Københavnsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (411, 'Glentevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (412, 'Goldbjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (413, 'Gormsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (414, 'Granbrinken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (415, 'Granhøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (416, 'Granplantagen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (417, 'Gransangervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (418, 'Grantoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (420, 'Granvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (421, 'Græse Bygade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (422, 'Græse Mølle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (423, 'Græse Skolevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (424, 'Græse Strandvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (425, 'Græsedalen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (426, 'Græsevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (427, 'Grønhøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (429, 'Grønnevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (430, 'Grønnevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (431, 'Grønshøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (432, 'Guldstjernevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (433, 'Gulspurvevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (434, 'Gyldenstens Vænge', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (435, 'Gyvelbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (436, 'Gyvelkrogen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (437, 'Gyvelvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (438, 'Gøgebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (439, 'Gøgevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (440, 'Gøgevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (441, 'H.C.Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (443, 'Hagerupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (444, 'Halfdansvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (445, 'Halvdansvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (446, 'Hammer Bakke', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (447, 'Hammertoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (448, 'Hammervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (450, 'Hanghøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (451, 'Hannelundsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (452, 'Hans Atkesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (453, 'Harald Blåtandsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (454, 'Harebakkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (456, 'Harevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (457, 'Harevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (458, 'Hartmannsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (459, 'Haspeholms Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (460, 'Hasselhøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (462, 'Hasselstrædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (463, 'Hasselvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (464, 'Hasselvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (465, 'Hasselvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (466, 'Hauge Møllevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (467, 'Havelse Mølle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (468, 'Havnegade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (469, 'Havnen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (470, 'Havnevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (471, 'Havremarken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (472, 'Havretoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (473, 'Havrevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (474, 'Heegårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (475, 'Heimdalsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (476, 'Hejre Sidevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (477, 'Hejrevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (478, 'Helgesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (479, 'Helgesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (480, 'Hellesø', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (482, 'Hestefolden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (483, 'Hestetorvet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (484, 'Hillerødvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (485, 'Hindbærvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (486, 'Hjaltesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (487, 'Hjortehaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (489, 'Hjortevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (490, 'Hjortevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (491, 'Hjorthøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (492, 'Hofvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (493, 'Holmegårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (494, 'Holmensvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (495, 'Horsehagevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (496, 'Hovdiget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (497, 'Hovedgaden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (500, 'Hovedgaden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (501, 'Hovleddet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (502, 'Hovmandsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (503, 'Hulekærsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (504, 'Hummervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (505, 'Hvedemarken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (506, 'Hvilehøj Sidevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (507, 'Hvilehøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (508, 'Hybenvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (509, 'Hybenvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (510, 'Hybenvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (511, 'Hyggevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (512, 'Hyldeager', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (513, 'Hyldebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (514, 'Hyldebærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (515, 'Hyldedal', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (516, 'Hyldegaardsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (517, 'Hyldeholm', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (518, 'Hyldevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (519, 'Hyllestedvejen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (520, 'Hyllingeriis', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (522, 'Hyrdevigen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (524, 'Hyttevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (525, 'Hækkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (526, 'Høgevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (527, 'Højager', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (528, 'Højagergaardsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (529, 'Højagervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (530, 'Højbovej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (531, 'Højdevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (532, 'Højdevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (534, 'Højgårds Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (535, 'Højskolevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (536, 'Højtoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (537, 'Højtoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (539, 'Højtoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (540, 'Højvang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (541, 'Højvangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (546, 'Hørupstien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (547, 'Hørupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (548, 'Hørupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (549, 'Høstvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (550, 'Håndværkervangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (551, 'Håndværkervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (553, 'Idrætsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (554, 'Idrætsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (555, 'Indelukket', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (556, 'Industrivej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (557, 'Industrivej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (559, 'Ingridvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (560, 'Irisvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (562, 'Irisvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (563, 'Irisvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (565, 'Isefjordvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (566, 'Islebjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (567, 'Ivar Lykkes Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (568, 'J. F. Willumsens Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (569, 'Jenriksvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (570, 'Jerichausvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (571, 'Jernager', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (572, 'Jernbanegade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (573, 'Jernbanevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (574, 'Jernhøjvænge', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (575, 'Jomsborgvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (576, 'Jordbærvang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (579, 'Jordhøj Bakke', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (580, 'Jordhøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (581, 'Julemosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (582, 'Jungedalsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (583, 'Jungehøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (584, 'Jupitervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (585, 'Juulsbjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (586, 'Jægeralle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (587, 'Jægerbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (588, 'Jægerstien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (591, 'Jættehøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (592, 'Jættehøjen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (594, 'Jørlunde Overdrev', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (595, 'Kalvøvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (596, 'Kannikestræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (597, 'Karl Frandsens Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (598, 'Karpevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (599, 'Kastaniealle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (600, 'Kastanievej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (601, 'Kignæsbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (602, 'Kignæshaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (603, 'Kignæskrogen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (604, 'Kignæsskrænten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (606, 'Kikkerbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (607, 'Kildebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (608, 'Kildeskåret', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (609, 'Kildestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (610, 'Kildevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (612, 'Kingovej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (613, 'Kirkealle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (614, 'Kirkebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (615, 'Kirkebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (616, 'Kirkegade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (618, 'Kirkegade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (619, 'Kirkestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (620, 'Kirkestræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (622, 'Kirkestræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (623, 'Kirkestræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (624, 'Kirketoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (625, 'Kirketorvet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (626, 'Kirkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (627, 'Kirkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (629, 'Kirkevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (630, 'Kirkeåsen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (631, 'Kirsebærvang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (632, 'Kirsebærvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (633, 'Klinten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (634, 'Klintevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (635, 'Klintevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (636, 'Klokkervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (637, 'Klostergården', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (638, 'Klosterstræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (639, 'Kløvertoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (640, 'Kløvervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (641, 'Kløvervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (642, 'Knoldager', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (643, 'Knud Den Storesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (644, 'Kobbelgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (645, 'Kobbelvangsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (646, 'Kocksvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (647, 'Koholmmosen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (648, 'Kong Dansvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (649, 'Kong Skjoldsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (650, 'Kongelysvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (651, 'Kongensgade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (653, 'Kongshøj Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (654, 'Kongshøjparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (655, 'Konkylievej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (656, 'Koralvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (657, 'Kornvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (658, 'Kornvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (659, 'Korshøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (660, 'Krabbevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (661, 'Kragevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (662, 'Krakasvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (663, 'Kratmøllestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (664, 'Kratvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (665, 'Kratvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (666, 'Kroghøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (668, 'Krogstrupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (669, 'Kronprins Fr''S Bro', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (671, 'Kulhusgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (672, 'Kulhustværvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (673, 'Kulhusvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (674, 'Kulmilevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (675, 'Kulsviervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (677, 'Kvinderupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (681, 'Kyndbyvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (683, 'Kystsvinget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (684, 'Kysttoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (685, 'Kystvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (686, 'Kæmpesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (687, 'Kærkrogen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (689, 'Kærsangervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (690, 'Kærstrædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (693, 'Kærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (694, 'Kærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (695, 'Københavnsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (696, 'Kølholm', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (697, 'Kølholmvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (698, 'Laksestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (700, 'Landerslevvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (701, 'Langager', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (702, 'Langesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (703, 'Lanternevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (704, 'Lars Hansensvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (705, 'Lebahnsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (706, 'Lejrvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (707, 'Lerager', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (709, 'Lergårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (710, 'Liljevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (711, 'Lille Bautahøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (712, 'Lille Blødevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (713, 'Lille Druedalsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (714, 'Lille Engvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (715, 'Lille Fjordvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (716, 'Lille Færgevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (717, 'Lille Hofvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (718, 'Lille Lyngerupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (719, 'Lille Marbækvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (720, 'Lille Rørbæk Enge', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (721, 'Lille Rørbækvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (723, 'Lille Skovvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (724, 'Lille Solbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (725, 'Lille Strandvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (727, 'Lillebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (728, 'Lilledal', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (729, 'Lillekær', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (730, 'Lilletoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (731, 'Lillevangsstien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (732, 'Lillevangsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (734, 'Lindealle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (735, 'Lindegaardsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (736, 'Lindegårds Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (737, 'Lindegårdsstien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (738, 'Lindegårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (739, 'Lindeparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (741, 'Linderupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (742, 'Lindevang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (743, 'Lindevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (745, 'Lindholm Stationsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (746, 'Lindholmvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (747, 'Lindormevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (748, 'Lineborg', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (750, 'Ll Troldmosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (751, 'Lodden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (753, 'Lodshaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (754, 'Lokesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (755, 'Louiseholmsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (756, 'Louisevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (757, 'Lundebjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (758, 'Lundeparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (759, 'Lundevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (760, 'Lupinvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (761, 'Lupinvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (762, 'Lupinvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (764, 'Lyngbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (765, 'Lyngbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (766, 'Lyngerupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (767, 'Lynghøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (768, 'Lyngkrogen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (769, 'Lysebjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (772, 'Lystrup Skov', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (773, 'Lystrupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (774, 'Lyøvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (775, 'Lærketoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (776, 'Lærkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (778, 'Lærkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (779, 'Lærkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (780, 'Lærkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (781, 'Lærkevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (782, 'Løgismose', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (783, 'Løjerthusvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (784, 'Løvekær', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (785, 'M P Jensens Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (786, 'Maglehøjparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (787, 'Maglehøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (789, 'Magnoliavej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (790, 'Magnoliavej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (794, 'Manderupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (795, 'Manderupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (796, 'Mannekildevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (797, 'Marbæk Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (798, 'Marbæk-Parken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (800, 'Marbækvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (801, 'Marbækvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (803, 'Margrethevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (804, 'Mariendalsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (805, 'Marienlystvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (806, 'Markleddet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (807, 'Markstien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (808, 'Marksvinget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (809, 'Markvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (810, 'Mathiesens Enghave', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (811, 'Mathildevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (812, 'Mejerigårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (814, 'Mejerivej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (815, 'Mejsevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (816, 'Mejsevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (817, 'Mejsevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (820, 'Mellemvang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (821, 'Midgård', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (822, 'Midtbanevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (823, 'Mimersvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (824, 'Mirabellestrædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (826, 'Mirabellevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (827, 'Morbærvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (828, 'Morelvang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (829, 'Morænevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (830, 'Mosebuen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (831, 'Mosehøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (832, 'Mosekærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (833, 'Mosestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (834, 'Mosesvinget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (835, 'Mosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (837, 'Mosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (838, 'Mosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (839, 'Mosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (840, 'Muldager', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (841, 'Murkærvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (842, 'Muslingevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (843, 'Mæremosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (844, 'Møllebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (845, 'Møllebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (846, 'Mølledammen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (847, 'Mølleengen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (848, 'Møllehaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (849, 'Møllehegnet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (850, 'Møllehøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (852, 'Møllehøjen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (853, 'Møllehøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (854, 'Mølleparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (855, 'Møllestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (856, 'Møllestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (857, 'Møllestræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (858, 'Møllevangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (859, 'Møllevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (860, 'Møllevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (862, 'Møllevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (863, 'Mønten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (864, 'Møntporten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (865, 'Møntstrædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (866, 'Mørkebjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (867, 'Mågevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (868, 'Mågevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (869, 'Mågevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (870, 'Mågevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (871, 'Månevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (872, 'Månevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (874, 'Nakkedamsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (875, 'Nattergalevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (877, 'Nialsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (878, 'Nikolajsensvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (879, 'Nordhøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (880, 'Nordkajen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (881, 'Nordmandshusene', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (882, 'Nordmandsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (884, 'Nordmandsvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (885, 'Nordre Pakhusvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (887, 'Nordskovhusvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (888, 'Nordskovvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (889, 'Nordsvinget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (890, 'Nordsøgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (891, 'Nordvangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (892, 'Nordvejen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (894, 'Nordvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (896, 'Ny Østergade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (897, 'Ny Øvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (898, 'Nybrovej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (899, 'Nybrovænge', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (900, 'Nygaardsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (901, 'Nygade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (902, 'Nygårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (903, 'Nytoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (904, 'Nyvang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (905, 'Nyvangshusene', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (906, 'Nyvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (908, 'Nyvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (909, 'Nøddekrogen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (910, 'Nøddevang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (912, 'Nøddevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (913, 'Nørhaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (914, 'Nørreparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (915, 'Nørresvinget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (916, 'Nørrevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (917, 'Odinsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (918, 'Oldvejen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (919, 'Ole Peters Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (924, 'Onsved Huse', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (926, 'Onsvedvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (927, 'Oppe-Sundbyvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (928, 'Ordrupdalsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (929, 'Ordrupholmsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (931, 'Orebjerg Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (932, 'Orebjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (936, 'Overdrevsstien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (937, 'Pagteroldvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (938, 'Palnatokesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (939, 'Parkalle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (940, 'Parkvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (941, 'Parkvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (942, 'Peberholm', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (943, 'Pedersholmparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (944, 'Pilealle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (945, 'Pilehaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (946, 'Pilehaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (947, 'Pilehegnet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (948, 'Pilevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (949, 'Pilevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (951, 'Planetvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (952, 'Plantagevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (954, 'Plantagevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (955, 'Plantagevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (956, 'Plantagevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (957, 'Platanvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (958, 'Poppelhegnet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (960, 'Poppelstrædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (961, 'Poppelvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (963, 'Poppelvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (964, 'Poppelvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (965, 'Primulavej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (966, 'Præstegaardsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (967, 'Præstemarken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (968, 'Præstemarken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (969, 'Præstevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (971, 'Påstrupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (972, 'Ranunkelvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (973, 'Rappendam Have', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (974, 'Rappendamsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (976, 'Ravnsbjergstien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (977, 'Ravnsbjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (978, 'Regnar Lodbrogsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (979, 'Rejestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (980, 'Rendebæk Strand', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (981, 'Rendebækvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (982, 'Resedavej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (983, 'Revelinen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (984, 'Ribisvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (985, 'Ringvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (986, 'Roarsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (987, 'Roarsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (988, 'Rolf Krakesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (989, 'Rolf Krakesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (990, 'Rollosvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (991, 'Rosenbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (992, 'Rosendalsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (993, 'Rosenfeldt', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (994, 'Rosenhaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (995, 'Rosenvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (996, 'Rosenvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (997, 'Rosenvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (999, 'Rosenvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1000, 'Roskildevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1002, 'Roskildevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1003, 'Rugmarken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1004, 'Rugskellet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1005, 'Rugtoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1006, 'Rugvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1007, 'Rugvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1008, 'Runegaards Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1009, 'Runestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1010, 'Rylevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1011, 'Rylevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1012, 'Rævevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1019, 'Røgerupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1020, 'Røglevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1021, 'Rønnebærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1022, 'Rønnebærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1023, 'Rønnevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1025, 'Rønnevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1026, 'Rørbæk Møllevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1027, 'Røriksvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1028, 'Rørsangervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1029, 'Rørsangervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1030, 'Rådhuspassagen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1031, 'Rådhusstræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1032, 'Rådhusstrædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1033, 'Rådhusvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1035, 'Rågevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1036, 'Sagavej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1037, 'Saltsøgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1038, 'Saltsøvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1040, 'Sandbergsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1041, 'Sandholmen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1042, 'Sandkærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1043, 'Sandsporet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1044, 'Sandvejen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1045, 'Saturnvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1047, 'Sct Bernardvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1048, 'Sct Jørgensvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1049, 'Sct Michaelsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1050, 'Sct Nilsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1051, 'Sejrøvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1054, 'Selsøvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1056, 'Servicegaden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1057, 'Sigerslevvestervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1058, 'Sigerslevøstervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1059, 'Sikavej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1060, 'Sivkærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1061, 'Sivsangervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1062, 'Skadevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1063, 'Skallekrogen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1064, 'Skansevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1065, 'Skarndalsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1066, 'Skehøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1067, 'Skelbæk', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1068, 'Skelvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1073, 'Skibby Old', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1074, 'Skibbyvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1075, 'Skiftestensvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1076, 'Skjoldagervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1077, 'Skjoldsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1079, 'Skolelodden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1080, 'Skoleparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1081, 'Skolestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1082, 'Skolestrædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1085, 'Skolevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1086, 'Skolevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1087, 'Skovbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1088, 'Skovbrynet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1089, 'Skovduevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1090, 'Skovengen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1091, 'Skovfogedvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1092, 'Skovgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1093, 'Skovkirkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1094, 'Skovmærkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1095, 'Skovnæsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1096, 'Skovsangervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1097, 'Skovskadevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1098, 'Skovsneppevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1099, 'Skovspurvevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1100, 'Skovvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1102, 'Skovvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1103, 'Skovvejen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1105, 'Skovvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1106, 'Skovvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1107, 'Skriverbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1108, 'Skrænten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1109, 'Skrænten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1112, 'Skuldelevvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1114, 'Skuldsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1115, 'Skyllebakke Havn', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1116, 'Skyllebakkegade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1117, 'Skyttevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1118, 'Slagslundevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1119, 'Slangerup Overdrev', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1120, 'Slangerup Ås', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1122, 'Slangerupgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1125, 'Slotsgården', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1126, 'Slåenbakkealle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1127, 'Slåenbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1128, 'Slåenbjerghuse', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1129, 'Smallevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1130, 'Smedebakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1131, 'Smedeengen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1132, 'Smedegyden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1133, 'Smedeparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1134, 'Smedetoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1135, 'Snerlevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1136, 'Snogekær', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1137, 'Snorresvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1138, 'Snostrupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1139, 'Solbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1140, 'Solbakkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1141, 'Solbærvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1142, 'Solhøjstræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1143, 'Solhøjvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1144, 'Solsikkevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1145, 'Solsortevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1146, 'Solsortevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1147, 'Solsortevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1148, 'Solvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1149, 'Solvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1151, 'Solvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1152, 'Solvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1153, 'Sportsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1154, 'Spurvevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1155, 'Spurvevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1156, 'Spurvevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1157, 'Stagetornsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1158, 'Stakhaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1159, 'Stationsparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1161, 'Stationsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1162, 'Stationsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1163, 'Stationsvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1164, 'Stenager', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1165, 'Stendyssen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1166, 'Stendyssevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1168, 'Stenledsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1169, 'Stenværksvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1174, 'Stjernevang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1175, 'Store Rørbækvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1176, 'Storgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1178, 'Storkevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1179, 'Stormgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1180, 'Strandager', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1181, 'Strandbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1182, 'Strandbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1183, 'Strandbovej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1184, 'Stranddyssen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1185, 'Strandengen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1186, 'Strandengen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1187, 'Strandgaardsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1188, 'Strandgangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1189, 'Strandgårds Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1190, 'Strandhaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1191, 'Strandhøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1192, 'Strandhøjen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1193, 'Strandhøjsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1194, 'Strandjægervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1195, 'Strandkanten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1196, 'Strandkrogen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1197, 'Strandkærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1198, 'Strandleddet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1199, 'Strandlinien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1200, 'Strandlunden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1201, 'Strandlystvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1202, 'Strandlystvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1203, 'Strandmarksvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1204, 'Strandstien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1205, 'Strandstræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1206, 'Strandsvinget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1207, 'Strandtoften', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1208, 'Strandvangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1209, 'Strandvangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1210, 'Strandvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1211, 'Strandvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1212, 'Strandvejen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1213, 'Strandvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1215, 'Strudhøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1216, 'Strædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1218, 'Strædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1219, 'Strædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1221, 'Stubbevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1222, 'Stybes Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1223, 'Stærevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1224, 'Stærevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1225, 'Stærevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1226, 'Stålager', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1229, 'Sundbylillevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1230, 'Sundbyvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1231, 'Sundparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1232, 'Svaldergade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1233, 'Svalevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1234, 'Svanemosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1235, 'Svanestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1236, 'Svanevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1237, 'Svanevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1239, 'Svanholm Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1241, 'Svend Tveskægsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1242, 'Svestrupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1243, 'Svineholm', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1244, 'Svinget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1248, 'Sydkajen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1250, 'Sydmarken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1251, 'Syrenbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1254, 'Syrenvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1255, 'Syrenvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1256, 'Syrenvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1257, 'Sævilsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1258, 'Søbovej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1260, 'Søgade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1261, 'Søgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1262, 'Søgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1263, 'Søhestevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1264, 'Søhøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1265, 'Søkærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1266, 'Sølvkærvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1267, 'Sømer Skovvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1268, 'Sønderby Bro', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1271, 'Sønderbyvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1272, 'Søndergade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1275, 'Sønderparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1277, 'Sønderstrædet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1278, 'Søndervangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1280, 'Søndervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1281, 'Søstjernevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1282, 'Søtungevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1283, 'Søvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1284, 'Søvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1285, 'Tagetesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1286, 'Teglværksvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1287, 'Ternevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1288, 'Thomsensvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1289, 'Thorfinsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1290, 'Thorsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1291, 'Thyrasvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1292, 'Thyrasvænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1293, 'Thyravej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1294, 'Timianstræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1295, 'Tingdyssevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1296, 'Tjørnevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1297, 'Tjørnevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1298, 'Tjørnevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1299, 'Tjørnevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1300, 'Toftegaardsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1301, 'Toftehøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1302, 'Toftekrogen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1303, 'Klosterbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1304, 'Toftevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1306, 'Toftevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1307, 'Toftevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1308, 'Toldmose', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1309, 'Tollerupparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1310, 'Tornebakke', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1311, 'Tornsangervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1312, 'Tornvig Olsens Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1316, 'Torpevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1317, 'Torvet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1318, 'Torøgelgårdsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1319, 'Traneagervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1320, 'Tranevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1322, 'Tranevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1323, 'Trekanten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1324, 'Troldhøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1325, 'Trymsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1326, 'Tuevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1327, 'Tulipanvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1328, 'Tulipanvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1329, 'Tunøvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1330, 'Tvebjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1331, 'Tværstræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1332, 'Tværvang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1333, 'Tværvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1335, 'Tværvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1336, 'Tørslevvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1337, 'Tørveagervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1338, 'Tøvkærsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1339, 'Tårnvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1341, 'Uffesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1342, 'Uffesvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1343, 'Uggeløse Skov', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1344, 'Uglevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1346, 'Ulf Jarlsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1347, 'Ullemosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1348, 'Ulriksvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1349, 'Urtebækvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1350, 'Urtehaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1353, 'Vagtelvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1354, 'Valmuevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1356, 'Valmuevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1357, 'Valmuevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1358, 'Valnøddevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1359, 'Vandtårnsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1360, 'Vandværksvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1361, 'Vandværksvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1362, 'Vangedevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1363, 'Vangevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1364, 'Varehusvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1365, 'Varmedalsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1366, 'Vasevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1367, 'Ved Diget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1368, 'Ved Gadekæret', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1369, 'Ved Gadekæret', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1370, 'Ved Grædehøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1371, 'Ved Kignæs', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1372, 'Ved Kilden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1373, 'Ved Kirken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1374, 'Ved Mosen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1375, 'Ved Nørreparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1376, 'Ved Skellet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1377, 'Ved Stranden', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1378, 'Ved Vigen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1379, 'Ved Åen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1428, 'Vellerupvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1429, 'Venslev Huse', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1433, 'Venslev Strand', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1434, 'Venslev Søpark', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1435, 'Venslevleddet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1437, 'Ventevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1438, 'Ventevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1439, 'Vermundsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1440, 'Vermundsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1441, 'Vestergaardsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1442, 'Vestergade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1444, 'Vestermoseparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1445, 'Vestervangsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1447, 'Vestervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1448, 'Vestervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1450, 'Vibevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1451, 'Vibevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1453, 'Vibevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1454, 'Vibevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1455, 'Vibevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1456, 'Vidarsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1457, 'Viermosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1458, 'Vifilsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1460, 'Vigvejen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1461, 'Vikingevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1462, 'Vildbjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1463, 'Vildrosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1464, 'Vinkelstien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1465, 'Vinkelvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1466, 'Vinkelvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1467, 'Vinkelvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1469, 'Vinkelvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1470, 'Violbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1472, 'Violvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1474, 'Violvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1475, 'Vænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1476, 'Vænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1477, 'Vængetvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1478, 'Vølundsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1480, 'Yderagervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1481, 'Ydermosevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1482, 'Ydunsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1483, 'Ymersvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1484, 'Æblehaven', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1485, 'Æblevang', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1486, 'Ægholm', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1487, 'Ægirsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1490, 'Ørnestens Vænge', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1491, 'Ørnevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1492, 'Ørnevænget', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1493, 'Ørnholmvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1497, 'Østbyvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1498, 'Østergaardsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1499, 'Østergade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1500, 'Østergade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1501, 'Østerled', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1502, 'Østersvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1503, 'Østersvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1505, 'Østervej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1506, 'Østkajen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1509, 'Øvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1510, 'Åbjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1511, 'Åbrinken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1512, 'Ådalsparken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1513, 'Ådalsvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1514, 'Ågade', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1515, 'Ågårdsstræde', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1516, 'Ålestien', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1518, 'Åskrænten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1519, 'Åvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1520, 'Åvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1521, 'Lundehusene', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1522, 'Meransletten', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1523, 'Stenøvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1524, 'Rønøvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1525, 'Hyldeholmvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1526, 'Eskilsøvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1527, 'Grevinde Danners Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1528, 'Carls Berlings Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1529, 'Frederik VII''s Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1530, 'Arveprins Frederiks Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1531, 'Prins Carls Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1532, 'Juliane Maries Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1533, 'Christian IV''s Vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1534, 'Josnekær', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1535, 'Gammel Draabyvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1536, 'Raasigvangen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1537, 'Snogedam', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1538, 'Pedershave Alle', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1539, 'Rørengen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1540, 'Siliciumvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1541, 'Stensbjergvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1542, 'Stensbjerghøj', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1543, 'Haldor Topsøe Park', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1544, 'Svanholm Møllevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1545, 'Svanholm Gods', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1546, 'Camarguevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1547, 'Obvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1548, 'Nilvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1549, 'Okavangovej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1550, 'Mekongvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1551, 'Deltavej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1552, 'Svanholm Skovhavevej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1553, 'Granbakken', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1554, 'Skovbrynet', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1555, 'Slap-a-vej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1556, 'Paradisvej', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1557, 'Grønningen', 't', '0', 3300, 250);
INSERT INTO greg.d_basis_vejnavn VALUES (1558, 'Slangeruphaver', 't', '0', 3300, 250);


-- d_basis_distrikt_type

-- INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ();

INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Ukendt', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Uden for drift', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Vejarealer', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Grønne områder', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Administrative ejendomme', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Boldbaner', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Idræt', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Kultur og fritid', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Skoler', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Institutioner', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Familieafdelingen', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Dag- og døgntilbud', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Ældreboliger', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Kommunale ejendomme', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Vej og park', 't');


-- e_basis_hovedelementer

-- INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovevdelement_tekst, aktiv) VALUES ();

INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovedelement_tekst, aktiv) VALUES ('GR', 'Græs', 't');
INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovedelement_tekst, aktiv) VALUES ('BL', 'Blomster', 't');
INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovedelement_tekst, aktiv) VALUES ('BU', 'Buske', 't');
INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovedelement_tekst, aktiv) VALUES ('HÆ', 'Hække og hegn', 't');
INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovedelement_tekst, aktiv) VALUES ('TR', 'Træer', 't');
INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovedelement_tekst, aktiv) VALUES ('VA', 'Vand', 't');
INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovedelement_tekst, aktiv) VALUES ('BE', 'Belægninger', 't');
INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovedelement_tekst, aktiv) VALUES ('UD', 'Terrænudstyr', 't');
INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovedelement_tekst, aktiv) VALUES ('ANA', 'Anden anvendelse', 't');
INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovedelement_tekst, aktiv) VALUES ('REN', 'Renhold', 't');


-- e_basis_elementer

-- INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst_ aktiv) VALUES ();

INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('GR', 'GR-00', 'Græs', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('GR', 'GR-01', 'Brugsplæner', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('GR', 'GR-02', 'Græsflader', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('GR', 'GR-03', 'Sportsplæner', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('GR', 'GR-04', 'Fælledgræs', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('GR', 'GR-05', 'Rabatgræs', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('GR', 'GR-06', 'Naturgræs', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('GR', 'GR-07', 'Græsning', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('GR', 'GR-08', 'Strande og klitter', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('GR', 'GR-09', '§3 Områder', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('GR', 'GR-10', 'Særlige græsområder', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BL', 'BL-00', 'Blomster', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BL', 'BL-01', 'Sommerblomster', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BL', 'BL-02', 'Ampler', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BL', 'BL-03', 'Plantekummer', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BL', 'BL-04', 'Roser og stauder', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BL', 'BL-05', 'Klatreplanter', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BL', 'BL-06', 'Urtehaver', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BU', 'BU-00', 'Buske', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BU', 'BU-01', 'Bunddækkende buske', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BU', 'BU-02', 'Busketter', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BU', 'BU-03', 'Krat og hegn', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BU', 'BU-04', 'Bunddækkende krat', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('HÆ', 'HÆ-00', 'Hække', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('HÆ', 'HÆ-01', 'Hække og pur', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('HÆ', 'HÆ-02', 'Hækkekrat', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('TR', 'TR-00', 'Træer', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('TR', 'TR-01', 'Fritstående træer', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('TR', 'TR-02', 'Vejtræer', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('TR', 'TR-03', 'Trægrupper', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('TR', 'TR-04', 'Trærækker', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('TR', 'TR-05', 'Formede træer', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('TR', 'TR-06', 'Frugttræer', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('TR', 'TR-07', 'Alléer', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('TR', 'TR-08', 'Skove og lunde', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('TR', 'TR-09', 'Fælledskove', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('VA', 'VA-00', 'Vand', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('VA', 'VA-01', 'Bassiner', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('VA', 'VA-02', 'Vandhuller', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('VA', 'VA-03', 'Søer og gadekær', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('VA', 'VA-04', 'Vandløb', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('VA', 'VA-05', 'Rørskove', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BE', 'BE-00', 'Belægninger', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BE', 'BE-01', 'Faste belægninger', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BE', 'BE-02', 'Grus', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BE', 'BE-03', 'Trimmet grus', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BE', 'BE-04', 'Andre løse belægninger', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BE', 'BE-05', 'Sportsbelægninger', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('BE', 'BE-06', 'Faldunderlag', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('UD', 'UD-00', 'Terrænudstyr', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('UD', 'UD-01', 'Andet terrænudstyr', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('UD', 'UD-02', 'Trapper', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('UD', 'UD-03', 'Terrænmure', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('UD', 'UD-04', 'Bænke', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('UD', 'UD-05', 'Faste hegn', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('UD', 'UD-06', 'Legeudstyr', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('UD', 'UD-07', 'Affald', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('UD', 'UD-08', 'Busstop', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('UD', 'UD-09', 'Fitness', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('ANA', 'ANA-01', 'Anden anvendelse', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('ANA', 'ANA-02', 'Udenfor drift og pleje', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('ANA', 'ANA-03', 'Private haver', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('ANA', 'ANA-04', 'Kantsten', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('REN', 'REN-01', 'Bypræg', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('REN', 'REN-02', 'Parkpræg', 't');
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) VALUES ('REN', 'REN-03', 'Naturpræg', 't');


-- e_basis_underelementer

-- INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ();

INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-00', 'GR-00-00', 'Græs', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-01', 'GR-01-01', 'Brugsplæne', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-01', 'GR-01-02', 'Brugsplæne - sport', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-02', 'GR-02-01', 'Græsflade', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-03', 'GR-03-01', 'Sportsplæne', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-04', 'GR-04-01', 'Fælledgræs', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-04', 'GR-04-02', 'Fælledgræs B', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-04', 'GR-04-03', 'Fælledgræs - Tørbassin', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-05', 'GR-05-01', 'Rabatgræs', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-06', 'GR-06-01', 'Naturgræs', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-06', 'GR-06-02', 'Naturgræs A', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-06', 'GR-06-03', 'Naturgræs B', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-06', 'GR-06-04', 'Naturgræs C', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-07', 'GR-07-01', 'Græsning', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-08', 'GR-08-01', 'Strand og klit', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-09', 'GR-09-01', '§3 Område', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('GR-10', 'GR-10-01', 'Særligt græsområde', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BL-00', 'BL-00-00', 'Blomster', 'FLP', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BL-01', 'BL-01-01', 'Sommerblomster', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BL-02', 'BL-02-01', 'Ampel', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BL-03', 'BL-03-01', 'Plantekumme', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BL-04', 'BL-04-01', 'Roser og stauder', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BL-05', 'BL-05-01', 'Solitær klatreplante', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BL-05', 'BL-05-02', 'Klatreplante', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BL-06', 'BL-06-01', 'Urtehave', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BU-00', 'BU-00-00', 'Buske', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BU-01', 'BU-01-01', 'Bunddækkende busk', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BU-02', 'BU-02-01', 'Busket', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BU-03', 'BU-03-01', 'Krat og hegn', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BU-04', 'BU-04-01', 'Bunddækkende krat', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('HÆ-00', 'HÆ-00-00', 'Hække', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('HÆ-01', 'HÆ-01-01', 'Hæk og pur', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('HÆ-01', 'HÆ-01-02', 'Hæk og pur - 2x klip', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('HÆ-02', 'HÆ-02-01', 'Hækkekrat', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('TR-00', 'TR-00-00', 'Træer', 'FP', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('TR-01', 'TR-01-01', 'Fritstående træ', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('TR-02', 'TR-02-01', 'Vejtræ', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('TR-03', 'TR-03-01', 'Trægruppe', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('TR-04', 'TR-04-01', 'Trærække', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('TR-05', 'TR-05-01', 'Formet træ', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('TR-06', 'TR-06-01', 'Frugttræ', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('TR-07', 'TR-07-01', 'Allé', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('TR-08', 'TR-08-01', 'Skov og lund', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('TR-09', 'TR-09-01', 'Fælledskov', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('VA-00', 'VA-00-00', 'Vand', 'FL', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('VA-01', 'VA-01-01', 'Bassin', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('VA-01', 'VA-01-02', 'Forbassin', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('VA-01', 'VA-01-03', 'Hovedbassin', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('VA-01', 'VA-01-04', 'Rørbassin', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('VA-02', 'VA-02-01', 'Vandhul', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('VA-03', 'VA-03-01', 'Sø og gadekær', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('VA-04', 'VA-04-01', 'Vandløb', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('VA-05', 'VA-05-01', 'Rørskov', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-00', 'BE-00-00', 'Belægninger', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-01', 'BE-01-01', 'Anden fast belægning', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-01', 'BE-01-02', 'Asfalt', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-01', 'BE-01-03', 'Beton', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-01', 'BE-01-04', 'Natursten', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-01', 'BE-01-05', 'Træ', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-02', 'BE-02-01', 'Grus', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-03', 'BE-03-01', 'Trimmet grus', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-04', 'BE-04-01', 'Anden løs belægning', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-04', 'BE-04-02', 'Sten', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-04', 'BE-04-03', 'Skærver', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-04', 'BE-04-04', 'Flis', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-04', 'BE-04-05', 'Jord', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-05', 'BE-05-01', 'SB - Anden sportsbelægning', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-05', 'BE-05-02', 'SB - Kunststof', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-05', 'BE-05-03', 'SB - Kunstgræs', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-05', 'BE-05-04', 'SB - Tennisgrus', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-05', 'BE-05-05', 'SB - Slagger', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-05', 'BE-05-06', 'SB - Stenmel', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-05', 'BE-05-07', 'SB - Asfalt', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-06', 'BE-06-01', 'Andet faldunderlag', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-06', 'BE-06-02', 'Faldgrus', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-06', 'BE-06-03', 'Faldsand', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-06', 'BE-06-04', 'Gummifliser', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('BE-06', 'BE-06-05', 'Støbt gummi', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-00', 'UD-00-00', 'Terrænudstyr', 'FLP', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-01', 'Andet terrænudstyr', 'FLP', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-02', 'Skilt', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-03', 'Trafikbom', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-04', 'Pullert', 'LP', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-05', 'Cykelstativ', 'LP', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-06', 'Parklys', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-07', 'Banelys', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-08', 'Tagrende', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-09', 'Lyskasse', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-10', 'Faskine', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-11', 'Affaldscontainer', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-12', 'Shelterhytte', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-13', 'Træbro', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-14', 'Kampesten', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-01', 'UD-01-15', 'Flagstang', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-02', 'UD-02-01', 'Trappe', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-02', 'UD-02-02', 'Betontrappe', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-02', 'UD-02-03', 'Naturstenstrappe', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-02', 'UD-02-04', 'Trappe - træ/jord', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-03', 'UD-03-01', 'Terrænmur', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-03', 'UD-03-02', 'Kampestensmur', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-03', 'UD-03-03', 'Betonmur', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-03', 'UD-03-04', 'Naturstensmur', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-03', 'UD-03-05', 'Træmur', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-04', 'UD-04-01', 'Bænk', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-04', 'UD-04-02', 'Bord- og bænkesæt', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-05', 'UD-05-01', 'Fast hegn', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-05', 'UD-05-02', 'Trådhegn', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-05', 'UD-05-03', 'Maskinflettet hegn', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-05', 'UD-05-04', 'Træhegn', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-05', 'UD-05-05', 'Fodhegn', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-06', 'UD-06-01', 'Legeudstyr', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-06', 'UD-06-02', 'Sandkasse', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-06', 'UD-06-03', 'Kant - faldunderlag', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-06', 'UD-06-04', 'Kant - sandkasse', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-07', 'UD-07-01', 'Affald', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-07', 'UD-07-02', 'Affaldsspand', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-07', 'UD-07-03', 'Askebæger', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-07', 'UD-07-04', 'Hundeposestativ', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-08', 'UD-08-01', 'Busstop', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-09', 'UD-09-01', 'Fitness', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('UD-09', 'UD-09-02', 'Fast sportsudstyr', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('ANA-01', 'ANA-01-01', 'Anden anvendelse', 'FLP', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('ANA-02', 'ANA-02-01', 'Udenfor drift og pleje', 'FLP', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('ANA-02', 'ANA-02-02', 'Urtehave', 'FLP', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('ANA-03', 'ANA-03-01', 'Privat have', 'F', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('ANA-04', 'ANA-04-01', 'Kantsten', 'L', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('REN-01', 'REN-01-01', 'Bypræg', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('REN-02', 'REN-02-01', 'Parkpræg', 'P', 0.00, 0.00, 0.00, 0.00, 't');
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) VALUES ('REN-03', 'REN-03-01', 'Naturpræg', 'P', 0.00, 0.00, 0.00, 0.00, 't');


--
-- TRIGGERS
--

-- d_basis_bruger_id

CREATE TRIGGER d_basis_bruger_id_trg_i BEFORE INSERT ON greg.d_basis_bruger_id FOR EACH ROW EXECUTE PROCEDURE greg.basis_aktiv_trg();

CREATE TRIGGER v_basis_bruger_id_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_basis_bruger_id FOR EACH ROW EXECUTE PROCEDURE greg.v_basis_bruger_id_trg();


-- d_basis_kommunal_kontakt

CREATE TRIGGER d_basis_kommunal_kontakt_trg_i BEFORE INSERT ON greg.d_basis_kommunal_kontakt FOR EACH ROW EXECUTE PROCEDURE greg.basis_aktiv_trg();

CREATE TRIGGER v_basis_kommunal_kontakt_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_basis_kommunal_kontakt FOR EACH ROW EXECUTE PROCEDURE greg.v_basis_kommunal_kontakt_trg();


-- d_basis_udfoerer

CREATE TRIGGER d_basis_udfoerer_trg_i BEFORE INSERT ON greg.d_basis_udfoerer FOR EACH ROW EXECUTE PROCEDURE greg.basis_aktiv_trg();

CREATE TRIGGER v_basis_udfoerer_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_basis_udfoerer FOR EACH ROW EXECUTE PROCEDURE greg.v_basis_udfoerer_trg();


-- d_basis_udfoerer_entrep

CREATE TRIGGER d_basis_udfoerer_entrep_trg_i BEFORE INSERT ON greg.d_basis_udfoerer_entrep FOR EACH ROW EXECUTE PROCEDURE greg.basis_aktiv_trg();

CREATE TRIGGER v_basis_udfoerer_entrep_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_basis_udfoerer_entrep FOR EACH ROW EXECUTE PROCEDURE greg.v_basis_udfoerer_entrep_trg();


-- d_basis_udfoerer_kontakt

CREATE TRIGGER d_basis_udfoerer_kontakt_trg_i BEFORE INSERT ON greg.d_basis_udfoerer_kontakt FOR EACH ROW EXECUTE PROCEDURE greg.basis_aktiv_trg();

CREATE TRIGGER v_basis_udfoerer_kontakt_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_basis_udfoerer_kontakt FOR EACH ROW EXECUTE PROCEDURE greg.v_basis_udfoerer_kontakt_trg();


-- d_basis_distrikt_type

CREATE TRIGGER d_basis_distrikt_type_trg_i BEFORE INSERT ON greg.d_basis_distrikt_type FOR EACH ROW EXECUTE PROCEDURE greg.basis_aktiv_trg();

CREATE TRIGGER v_basis_distrikt_type_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_basis_distrikt_type FOR EACH ROW EXECUTE PROCEDURE greg.v_basis_distrikt_type_trg();


-- e_basis_hovedelementer

CREATE TRIGGER v_basis_hovedelementer_trg_i BEFORE INSERT ON greg.e_basis_hovedelementer FOR EACH ROW EXECUTE PROCEDURE greg.basis_aktiv_trg();

CREATE TRIGGER v_basis_hovedelementer_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_basis_hovedelementer FOR EACH ROW EXECUTE PROCEDURE greg.v_basis_hovedelementer_trg();


-- e_basis_elementer

CREATE TRIGGER v_basis_elementer_trg_i BEFORE INSERT ON greg.e_basis_elementer FOR EACH ROW EXECUTE PROCEDURE greg.basis_aktiv_trg();

CREATE TRIGGER v_basis_elementer_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_basis_elementer FOR EACH ROW EXECUTE PROCEDURE greg.v_basis_elementer_trg();


-- e_basis_underelementer

CREATE TRIGGER e_basis_underelementer_trg_i BEFORE INSERT ON greg.e_basis_underelementer FOR EACH ROW EXECUTE PROCEDURE greg.e_basis_underelementer_trg();

CREATE TRIGGER v_basis_underelementer_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_basis_underelementer FOR EACH ROW EXECUTE PROCEDURE greg.v_basis_underelementer_trg();


-- t_greg_flader

CREATE TRIGGER a_t_greg_flader_generel_trg_iud BEFORE INSERT OR DELETE OR UPDATE ON greg.t_greg_flader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_generel_trg();

CREATE TRIGGER t_greg_flader_trg_i BEFORE INSERT ON greg.t_greg_flader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_flader_trg();

CREATE TRIGGER t_greg_flader_trg_a_ud AFTER UPDATE OR DELETE ON greg.t_greg_flader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_historik_trg_a_ud();

CREATE TRIGGER v_greg_flader_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_greg_flader FOR EACH ROW EXECUTE PROCEDURE greg.v_greg_flader_trg();

-- CREATE TRIGGER t_greg_omraader_flader_trg_a_iud AFTER INSERT OR DELETE OR UPDATE ON greg.t_greg_flader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_omraader_flader_trg();

CREATE TRIGGER t_greg_omraader_upt_trg_a_iud AFTER INSERT OR DELETE OR UPDATE ON greg.t_greg_flader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_omraader_upt_trg();


-- t_greg_linier

CREATE TRIGGER a_t_greg_linier_generel_trg_iud BEFORE INSERT OR DELETE OR UPDATE ON greg.t_greg_linier FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_generel_trg();

CREATE TRIGGER t_greg_linier_trg_i BEFORE INSERT ON greg.t_greg_linier FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_linier_trg();

CREATE TRIGGER t_greg_linier_trg_a_ud AFTER DELETE OR UPDATE ON greg.t_greg_linier FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_historik_trg_a_ud();

CREATE TRIGGER v_greg_linier_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_greg_linier FOR EACH ROW EXECUTE PROCEDURE greg.v_greg_linier_trg();

CREATE TRIGGER t_greg_omraader_upt_trg_a_iud AFTER INSERT OR DELETE OR UPDATE ON greg.t_greg_linier FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_omraader_upt_trg();


-- t_greg_punkter

CREATE TRIGGER a_t_greg_punkter_generel_trg_iud BEFORE INSERT OR DELETE OR UPDATE ON greg.t_greg_punkter FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_generel_trg();

CREATE TRIGGER t_greg_punkter_trg_i BEFORE INSERT ON greg.t_greg_punkter FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_punkter_trg();

CREATE TRIGGER t_greg_punkter_trg_a_ud AFTER DELETE OR UPDATE ON greg.t_greg_punkter FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_historik_trg_a_ud();

CREATE TRIGGER v_greg_punkter_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_greg_punkter FOR EACH ROW EXECUTE PROCEDURE greg.v_greg_punkter_trg();

CREATE TRIGGER t_greg_omraader_upt_trg_a_iud AFTER INSERT OR DELETE OR UPDATE ON greg.t_greg_punkter FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_omraader_upt_trg();


-- t_greg_omraader

CREATE TRIGGER t_greg_omraader_trg_iu BEFORE INSERT OR UPDATE ON greg.t_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_omraader_trg();

CREATE TRIGGER t_greg_omraader_trg_a_ud AFTER DELETE OR UPDATE ON greg.t_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_omraader_trg_a_ud();

CREATE TRIGGER v_greg_omraader_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.v_greg_omraader_trg();


-- t_greg_delomraader

CREATE TRIGGER t_greg_delomraader_trg_iu BEFORE INSERT OR UPDATE ON greg.t_greg_delomraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_delomraader_trg();


--
-- USERS
--


DO

$$

BEGIN

	IF NOT EXISTS (SELECT '1' FROM pg_catalog.pg_user WHERE usename = 'qgis_reader') THEN

		-- Opret bruger qgis_reader med password qgis_reader...
		CREATE ROLE qgis_reader LOGIN PASSWORD 'qgis_reader' NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION;

	END IF;

END;

$$;

GRANT CONNECT ON DATABASE groenreg TO qgis_reader;

-- Adgang til schema greg
GRANT USAGE ON SCHEMA greg TO qgis_reader;

-- Læserettigheder til qgis_reader på alle eksisterende tabeller...
GRANT SELECT ON ALL TABLES IN SCHEMA greg TO qgis_reader;

-- Læserettigheder til qgis_reader på alle fremtidige tabeller i schemaerne...
ALTER DEFAULT PRIVILEGES IN SCHEMA greg GRANT SELECT ON TABLES TO qgis_reader;


DROP USER IF EXISTS backadm;
CREATE USER backadm SUPERUSER password 'qgis';
ALTER USER backadm set default_transaction_read_only = on;


/*
New Columns:
- Table
- v_greg (if default value also t_greg) trigger functions
- View
- History functions


*/

