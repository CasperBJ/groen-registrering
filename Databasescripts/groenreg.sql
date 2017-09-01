--
-- DROP SCHEMAS AND MISC.
--

DROP SCHEMA IF EXISTS grunddata CASCADE;

DROP SCHEMA IF EXISTS basis CASCADE;

DROP SCHEMA IF EXISTS greg CASCADE;

DROP SCHEMA IF EXISTS styles CASCADE;

DROP VIEW IF EXISTS public.layer_styles;

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
-- REVOKE CONNECT
--

DO

$$

	DECLARE

		db text;

	BEGIN

		SELECT catalog_name FROM information_schema.information_schema_catalog_name INTO db; -- Name of database

		EXECUTE format('REVOKE CONNECT ON DATABASE %s FROM PUBLIC', db); -- Revoke ability to connect to the database from public

	END

$$;

--
-- CREATE SCHEMAS
--

CREATE SCHEMA grunddata;
COMMENT ON SCHEMA grunddata IS 'Skema indeholdende praktiske grunddata uden relation til de resterende data.';

CREATE SCHEMA basis;
COMMENT ON SCHEMA basis IS 'Skema indeholdende opsætningstabeller.';

CREATE SCHEMA greg;
COMMENT ON SCHEMA greg IS 'Skema indeholdende datatabeller.';

CREATE SCHEMA styles;
COMMENT ON SCHEMA styles IS 'Skema til håndtering af stilarter.';

--
-- CREATE EXTENSIONS
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;
COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language.';

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;
COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions.';

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
COMMENT ON EXTENSION "uuid-ossp" IS 'Generate universally unique identifiers (UUIDs).';

--
-- CREATE FUNCTIONS
--

-- Functions in schema basis --

-- multiply_aggregate(float, float)

DROP FUNCTION IF EXISTS basis.multiply_aggregate(float, float) CASCADE;

CREATE FUNCTION basis.multiply_aggregate(float, float)
	RETURNS float 
	LANGUAGE sql
	IMMUTABLE STRICT AS
$$

	SELECT $1 * $2;

$$;

COMMENT ON FUNCTION basis.multiply_aggregate(float, float) IS 'Funktion til at finde produktet af to værdier.';

-- Aggregate

CREATE AGGREGATE basis.multiply (basetype = float, sfunc = basis.multiply_aggregate, stype = float, initcond = 1);

-- f_prisregulering_produkt(dag integer, maaned integer, aar integer)

DROP FUNCTION IF EXISTS basis.f_prisregulering_produkt(dag integer, maaned integer, aar integer);

CREATE FUNCTION basis.f_prisregulering_produkt(dag integer, maaned integer, aar integer)
	RETURNS TABLE(
		multiply float
	)
	LANGUAGE sql AS
$$

	SELECT basis.multiply(prisregulering_faktor) FROM basis.v_basis_prisregulering WHERE dato <= ($3 || '-' || $2 || '-' || $1)::date;

$$;

COMMENT ON FUNCTION basis.f_prisregulering_produkt(dag integer, maaned integer, aar integer) IS 'Funktion til at lave et prisindeks frem til og med en bestemt dato. Format: dd-MM-yyyy.';

-- Functions in schema greg --

-- f_aendring_log(aar integer)

DROP FUNCTION IF EXISTS greg.f_aendring_log(aar integer);

CREATE FUNCTION greg.f_aendring_log(aar integer)
	RETURNS TABLE(
		objekt_type text,
		handling text,
		versions_id uuid,
		objekt_id uuid,
		dato timestamp without time zone,
		bruger text,
		arbejdssted text,
		underelement text,
		aendringer text
	)
	LANGUAGE sql AS
$$

	WITH

		query AS ( -- Make one table with all records
			SELECT
				*
			FROM greg.f_aendring_log_flader($1)

			UNION ALL

			SELECT
				*
			FROM greg.f_aendring_log_linier($1)

			UNION ALL

			SELECT
				*
			FROM greg.f_aendring_log_punkter($1)

			UNION ALL

			SELECT
				*
			FROM greg.f_aendring_log_omraader($1)
		)

	SELECT
		*
	FROM query
	ORDER BY dato DESC, CASE
							WHEN objekt_type = 'Område'
							THEN 2
							ELSE 1
						END;

$$;

COMMENT ON FUNCTION greg.f_aendring_log(aar integer) IS 'Funktion til at generere en samlet ændringslog for flader, linier, punkter og områder indenfor et givent år. Format: yyyy.';

-- f_aendring_log_flader(aar integer)

DROP FUNCTION IF EXISTS greg.f_aendring_log_flader(aar integer);

CREATE FUNCTION greg.f_aendring_log_flader(aar integer)
	RETURNS TABLE(
		objekt_type text,
		handling text,
		versions_id uuid,
		objekt_id uuid,
		dato timestamp without time zone,
		bruger text,
		arbejdssted text,
		underelement text,
		aendringer text
	)
	LANGUAGE sql AS
$$

	WITH

		column_names AS ( -- Select all column names as rows in a single column
			SELECT
				ordinal_position AS row,
				column_name
			FROM information_schema.columns
			WHERE table_schema = 'greg' AND table_name = 't_greg_flader'
		),

		raw AS ( -- Select rows where commas has been replaced with semi colon
			SELECT
				-- Automated values
				versions_id,
				objekt_id,
				oprettet,
				systid_fra,
				systid_til,
				bruger_id_start,
				bruger_id_slut,
				-- Geometry
				geometri,
				-- FKG #1
				cvr_kode,
				oprindkode,
				statuskode,
				off_kode,
				-- FKG #2
				regexp_replace(note, ',', ';', 'g'),
				regexp_replace(link, ',', ';', 'g'),
				vejkode,
				tilstand_kode,
				anlaegsaar,
				udfoerer_entrep_kode,
				kommunal_kontakt_kode,
				-- FKG #3
				arbejdssted,
				regexp_replace(underelement_kode, ',', ';', 'g'),
				-- Measurements
				hoejde,
				-- Table specific
				klip_sider,
				regexp_replace(litra, ',', ';', 'g')
			FROM greg.t_greg_flader
			WHERE EXTRACT (YEAR FROM systid_til) = $1 OR EXTRACT (YEAR FROM systid_fra) = $1 -- Where there has been some interaction during the year
		),

		compare AS ( -- Select a column with the old values and the new values for an object that has been changed
			SELECT
				ROW_NUMBER() OVER(PARTITION BY a.row) AS row, -- Each versions_id gets a row number for each of its record
				a.versions_id,
				a.old,
				a.new
			FROM (	SELECT
						ROW_NUMBER() OVER() AS row, -- Each versions_id gets one row number for all its records
						a.versions_id,
						regexp_split_to_table(regexp_replace(ROW(a.*)::text, '[(|)|"]', '', 'g'), ',') AS old, -- Split a record into individual records each representing the contents of one column in the original record
						regexp_split_to_table(regexp_replace(ROW(b.*)::text, '[(|)|"]', '', 'g'), ',') AS new -- Split a record into individual records each representing the contents of one column in the original record
					FROM raw a
					LEFT JOIN raw b ON a.objekt_id = b.objekt_id AND a.systid_til = b.systid_fra -- Join the old record with the one replacing it
					WHERE EXTRACT (YEAR FROM a.systid_til) = $1 AND CASE
																		WHEN a.objekt_id NOT IN (SELECT objekt_id FROM greg.t_greg_flader WHERE systid_til IS NULL) AND a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_flader d WHERE a.objekt_id = d.objekt_id)
																		THEN FALSE
																		ELSE TRUE
																	END -- If the object represent a deletion then FALSE
			) a
		),

		change AS ( -- Select columns that has been changed for a given version_id 
			SELECT
				a.versions_id,
				b.column_name
			FROM compare a
			LEFT JOIN column_names b ON a.row = b.row
			WHERE a.old != a.new AND b.column_name NOT IN ('versions_id', 'systid_fra', 'systid_til', 'bruger_id_start', 'bruger_id_slut') -- These columns are not relevant to have in the change log. Columns objekt_id and oprettet are not removed. If they show up in change log, something is wrong!!
		),

		change_2 AS ( -- Select all changed columns as aggregates to the version_id that has been changed
			SELECT
				a.versions_id,
				string_agg(a.column_name, ', ') AS aendringer
			FROM change a
			GROUP BY a.versions_id
		),

		tgf_insert AS ( -- Select all features that has been inserted, but not updated from the current data set
			SELECT
				'Flade'::text AS objekt_type,
				'Tilføjet'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_fra::timestamp(0) AS dato,
				a.bruger_id_start AS bruger,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || b.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode,
				''::text AS aendringer
			FROM greg.t_greg_flader a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr AND b.systid_fra <= a.systid_fra AND (a.systid_fra < b.systid_til OR b.systid_til IS NULL)
			WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND a.systid_til IS NULL
		),

		tgf_insert_his AS ( -- Select all features that represent insert opreations from the historic data set
			SELECT
				'Flade'::text AS objekt_type,
				'Tilføjet'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_fra::timestamp(0) AS dato,
				a.bruger_id_start AS bruger,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || b.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode,
				''::text AS aendringer
			FROM greg.t_greg_flader a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr AND b.systid_fra <= a.systid_fra AND (a.systid_fra < b.systid_til OR b.systid_til IS NULL)
			WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND a.systid_til IS NOT NULL
		),

		tgf_update AS ( -- Select all features that represent update operations from the historic data set
			SELECT
				'Flade'::text AS objekt_type,
				'Ændret'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_til::timestamp(0) AS dato,
				a.bruger_id_slut AS bruger,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || b.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode,
				c.aendringer
			FROM greg.t_greg_flader a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr AND b.systid_fra < a.systid_til AND (a.systid_til <= b.systid_til OR b.systid_til IS NULL)
			LEFT JOIN change_2 c ON a.versions_id = c.versions_id
			WHERE EXTRACT (YEAR FROM a.systid_til) = $1 AND 
					CASE
						WHEN a.objekt_id NOT IN (SELECT objekt_id FROM greg.t_greg_flader WHERE systid_til IS NULL) AND a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_flader d WHERE a.objekt_id = d.objekt_id)
						THEN FALSE
						ELSE TRUE
					END -- If the object represent a deletion then FALSE
		),

		tgf_delete AS( -- Select all features that represent delete operations from the historic data set
			SELECT
				'Flade'::text AS objekt_type,
				'Slettet'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_til::timestamp(0) AS dato,
				a.bruger_id_slut AS bruger,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || b.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode,
				''::text AS aendringer
			FROM greg.t_greg_flader a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr AND b.systid_fra < a.systid_til AND (a.systid_til <= b.systid_til OR b.systid_til IS NULL)
			WHERE EXTRACT (YEAR FROM a.systid_til) = $1 AND a.objekt_id NOT IN (SELECT objekt_id FROM greg.t_greg_flader WHERE systid_til IS NULL) AND a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_flader d WHERE a.objekt_id = d.objekt_id)
		),

		union_ AS( -- Make union of all tgf tables
			SELECT
				*
			FROM tgf_insert
			
			UNION ALL

			SELECT
				*
			FROM tgf_insert_his

			UNION ALL

			SELECT
				*
			FROM tgf_update

			UNION ALL

			SELECT
				*
			FROM tgf_delete
		)

	SELECT
		a.objekt_type,
		a.handling,
		a.versions_id,
		a.objekt_id,
		a.dato,
		a.bruger,
		a.arbejdssted,
		a.underelement_kode || ' ' || b.underelement_tekst AS underelement,
		a.aendringer
	FROM union_ a
	LEFT JOIN basis.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
	ORDER BY dato DESC;

$$;

COMMENT ON FUNCTION greg.f_aendring_log_flader(aar integer) IS 'Funktion til at generere en ændringslog for flader indenfor et givent år. Format: yyyy.';

-- f_aendring_log_linier(aar integer)

DROP FUNCTION IF EXISTS greg.f_aendring_log_linier(aar integer);

CREATE FUNCTION greg.f_aendring_log_linier(aar integer)
	RETURNS TABLE(
		objekt_type text,
		handling text,
		versions_id uuid,
		objekt_id uuid,
		dato timestamp without time zone,
		bruger text,
		arbejdssted text,
		underelement text,
		aendringer text
	)
	LANGUAGE sql AS
$$

	WITH

		column_names AS ( -- Select all column names as rows in a single column
			SELECT
				ordinal_position AS row,
				column_name
			FROM information_schema.columns
			WHERE table_schema = 'greg' AND table_name = 't_greg_linier'
		),

		raw AS ( -- Select rows where commas has been replaced with semi colon
			SELECT
				-- Automated values
				versions_id,
				objekt_id,
				oprettet,
				systid_fra,
				systid_til,
				bruger_id_start,
				bruger_id_slut,
				-- Geometry
				geometri,
				-- FKG #1
				cvr_kode,
				oprindkode,
				statuskode,
				off_kode,
				-- FKG #2
				regexp_replace(note, ',', ';', 'g'),
				regexp_replace(link, ',', ';', 'g'),
				vejkode,
				tilstand_kode,
				anlaegsaar,
				udfoerer_entrep_kode,
				kommunal_kontakt_kode,
				-- FKG #3
				arbejdssted,
				regexp_replace(underelement_kode, ',', ';', 'g'),
				-- Measurements
				bredde,
				hoejde,
				-- Table specific
				regexp_replace(litra, ',', ';', 'g')
			FROM greg.t_greg_linier
			WHERE EXTRACT (YEAR FROM systid_til) = $1 OR EXTRACT (YEAR FROM systid_fra) = $1 -- Where there has been some interaction during the year
		),

		compare AS ( -- Select a column with the old values and the new values for an object that has been changed
			SELECT
				ROW_NUMBER() OVER(PARTITION BY a.row) AS row, -- Each versions_id gets a row number for each of its record
				a.versions_id,
				a.old,
				a.new
			FROM (	SELECT
						ROW_NUMBER() OVER() AS row, -- Each versions_id gets one row number for all its records
						a.versions_id,
						regexp_split_to_table(regexp_replace(ROW(a.*)::text, '[(|)|"]', '', 'g'), ',') AS old, -- Split a record into individual records each representing the contents of one column in the original record
						regexp_split_to_table(regexp_replace(ROW(b.*)::text, '[(|)|"]', '', 'g'), ',') AS new -- Split a record into individual records each representing the contents of one column in the original record
					FROM raw a
					LEFT JOIN raw b ON a.objekt_id = b.objekt_id AND a.systid_til = b.systid_fra -- Join the old record with the one replacing it
					WHERE EXTRACT (YEAR FROM a.systid_til) = $1 AND CASE
																		WHEN a.objekt_id NOT IN (SELECT objekt_id FROM greg.t_greg_linier WHERE systid_til IS NULL) AND a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_linier d WHERE a.objekt_id = d.objekt_id)
																		THEN FALSE
																		ELSE TRUE
																	END -- If the object represent a deletion then FALSE
			) a
		),

		change AS ( -- Select columns that has been changed for a given version_id 
			SELECT
				a.versions_id,
				b.column_name
			FROM compare a
			LEFT JOIN column_names b ON a.row = b.row
			WHERE a.old != a.new AND b.column_name NOT IN ('versions_id', 'systid_fra', 'systid_til', 'bruger_id_start', 'bruger_id_slut') -- These columns are not relevant to have in the change log. Columns objekt_id and oprettet are not removed. If they show up in change log, something is wrong!!
		),

		change_2 AS ( -- Select all changed columns as aggregates to the version_id that has been changed
			SELECT
				a.versions_id,
				string_agg(a.column_name, ', ') AS aendringer
			FROM change a
			GROUP BY a.versions_id
		),

		tgl_insert AS ( -- Select all features that has been inserted, but not updated from the current data set
			SELECT
				'Linie'::text AS objekt_type,
				'Tilføjet'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_fra::timestamp(0) AS dato,
				a.bruger_id_start AS bruger,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || b.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode,
				''::text AS aendringer
			FROM greg.t_greg_linier a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr AND b.systid_fra <= a.systid_fra AND (a.systid_fra < b.systid_til OR b.systid_til IS NULL)
			WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND a.systid_til IS NULL
		),

		tgl_insert_his AS ( -- Select all features that represent insert opreations from the historic data set
			SELECT
				'Linie'::text AS objekt_type,
				'Tilføjet'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_fra::timestamp(0) AS dato,
				a.bruger_id_start AS bruger,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || b.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode,
				''::text AS aendringer
			FROM greg.t_greg_linier a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr AND b.systid_fra <= a.systid_fra AND (a.systid_fra < b.systid_til OR b.systid_til IS NULL)
			WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND a.systid_til IS NOT NULL
		),

		tgl_update AS ( -- Select all features that represent update operations from the historic data set
			SELECT
				'Linie'::text AS objekt_type,
				'Ændret'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_til::timestamp(0) AS dato,
				a.bruger_id_slut AS bruger,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || b.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode,
				c.aendringer
			FROM greg.t_greg_linier a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr AND b.systid_fra < a.systid_til AND (a.systid_til <= b.systid_til OR b.systid_til IS NULL)
			LEFT JOIN change_2 c ON a.versions_id = c.versions_id
			WHERE EXTRACT (YEAR FROM a.systid_til) = $1 AND 
					CASE
						WHEN a.objekt_id NOT IN (SELECT objekt_id FROM greg.t_greg_linier WHERE systid_til IS NULL) AND a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_linier d WHERE a.objekt_id = d.objekt_id)
						THEN FALSE
						ELSE TRUE
					END -- If the object represent a deletion then FALSE
		),

		tgl_delete AS( -- Select all features that represent delete operations from the historic data set
			SELECT
				'Linie'::text AS objekt_type,
				'Slettet'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_til::timestamp(0) AS dato,
				a.bruger_id_slut AS bruger,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || b.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode,
				''::text AS aendringer
			FROM greg.t_greg_linier a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr AND b.systid_fra < a.systid_til AND (a.systid_til <= b.systid_til OR b.systid_til IS NULL)
			WHERE EXTRACT (YEAR FROM a.systid_til) = $1 AND a.objekt_id NOT IN(SELECT objekt_id FROM greg.t_greg_linier WHERE systid_til IS NULL) AND a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_linier d WHERE a.objekt_id = d.objekt_id)
		),

		union_ AS( -- Make union of all tgp tables
			SELECT
				*
			FROM tgl_insert

			UNION ALL

			SELECT
				*
			FROM tgl_insert_his

			UNION ALL

			SELECT
				*
			FROM tgl_update

			UNION ALL

			SELECT
				*
			FROM tgl_delete
		)

	SELECT
		a.objekt_type,
		a.handling,
		a.versions_id,
		a.objekt_id,
		a.dato,
		a.bruger,
		a.arbejdssted,
		a.underelement_kode || ' ' || b.underelement_tekst AS underelement,
		a.aendringer
	FROM union_ a
	LEFT JOIN basis.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
	ORDER BY dato DESC;

$$;

COMMENT ON FUNCTION greg.f_aendring_log_linier(aar integer) IS 'Funktion til at generere en ændringslog for linier indenfor et givent år. Format: yyyy.';

-- f_aendring_log_punkter(aar integer)

DROP FUNCTION IF EXISTS greg.f_aendring_log_punkter(aar integer);

CREATE FUNCTION greg.f_aendring_log_punkter(aar integer)
	RETURNS TABLE(
		objekt_type text,
		handling text,
		versions_id uuid,
		objekt_id uuid,
		dato timestamp without time zone,
		bruger text,
		arbejdssted text,
		underelement text,
		aendringer text
	)
	LANGUAGE sql AS
$$

	WITH

		column_names AS ( -- Select all column names as rows in a single column
			SELECT
				ordinal_position AS row,
				column_name
			FROM information_schema.columns
			WHERE table_schema = 'greg' AND table_name = 't_greg_punkter'
		),

		raw AS ( -- Select rows where commas has been replaced with semi colon
			SELECT
				-- Automated values
				versions_id,
				objekt_id,
				oprettet,
				systid_fra,
				systid_til,
				bruger_id_start,
				bruger_id_slut,
				-- Geometry
				geometri,
				-- FKG #1
				cvr_kode,
				oprindkode,
				statuskode,
				off_kode,
				-- FKG #2
				regexp_replace(note, ',', ';', 'g'),
				regexp_replace(link, ',', ';', 'g'),
				vejkode,
				tilstand_kode,
				anlaegsaar,
				udfoerer_entrep_kode,
				kommunal_kontakt_kode,
				-- FKG #3
				arbejdssted,
				regexp_replace(underelement_kode, ',', ';', 'g'),
				-- Measurements
				laengde,
				bredde,
				diameter,
				hoejde,
				-- Table specific
				regexp_replace(slaegt, ',', ';', 'g'),
				regexp_replace(art, ',', ';', 'g'),
				regexp_replace(litra, ',', ';', 'g')
			FROM greg.t_greg_punkter
			WHERE EXTRACT (YEAR FROM systid_til) = $1 OR EXTRACT (YEAR FROM systid_fra) = $1 -- Where there has been some interaction during the year
		),

		compare AS ( -- Select a column with the old values and the new values for an object that has been changed
			SELECT
				ROW_NUMBER() OVER(PARTITION BY a.row) AS row, -- Each versions_id gets a row number for each of its record
				a.versions_id,
				a.old,
				a.new
			FROM (	SELECT
						ROW_NUMBER() OVER() AS row, -- Each versions_id gets one row number for all its records
						a.versions_id,
						regexp_split_to_table(regexp_replace(ROW(a.*)::text, '[(|)|"]', '', 'g'), ',') AS old,
						regexp_split_to_table(regexp_replace(ROW(b.*)::text, '[(|)|"]', '', 'g'), ',') AS new 
					FROM raw a
					LEFT JOIN raw b ON a.objekt_id = b.objekt_id AND a.systid_til = b.systid_fra -- Join the old record with the one replacing it
					WHERE EXTRACT (YEAR FROM a.systid_til) = $1 AND CASE
																		WHEN a.objekt_id NOT IN (SELECT objekt_id FROM greg.t_greg_punkter WHERE systid_til IS NULL) AND a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_punkter d WHERE a.objekt_id = d.objekt_id)
																		THEN FALSE
																		ELSE TRUE
																	END -- If the object represent a deletion then FALSE
			) a
		),

		change AS ( -- Select columns that has been changed for a given version_id 
			SELECT
				a.versions_id,
				b.column_name
			FROM compare a
			LEFT JOIN column_names b ON a.row = b.row
			WHERE a.old != a.new AND b.column_name NOT IN ('versions_id', 'systid_fra', 'systid_til', 'bruger_id_start', 'bruger_id_slut') -- These columns are not relevant to have in the change log. Columns objekt_id and oprettet are not removed. If they show up in change log, something is wrong!!
		),

		change_2 AS ( -- Select all changed columns as aggregates to the version_id that has been changed
			SELECT
				a.versions_id,
				string_agg(a.column_name, ', ') AS aendringer
			FROM change a
			GROUP BY a.versions_id
		),

		tgp_insert AS ( -- Select all features that has been inserted, but not updated from the current data set
			SELECT
				'Punkt'::text AS objekt_type,
				'Tilføjet'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_fra::timestamp(0) AS dato,
				a.bruger_id_start AS bruger,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || b.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode,
				''::text AS aendringer
			FROM greg.t_greg_punkter a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr AND b.systid_fra <= a.systid_fra AND (a.systid_fra < b.systid_til OR b.systid_til IS NULL)
			WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND a.systid_til IS NULL
		),

		tgp_insert_his AS ( -- Select all features that represent insert opreations from the historic data set
			SELECT
				'Punkt'::text AS objekt_type,
				'Tilføjet'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_fra::timestamp(0) AS dato,
				a.bruger_id_start AS bruger,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || b.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode,
				''::text AS aendringer
			FROM greg.t_greg_punkter a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr AND b.systid_fra <= a.systid_fra AND (a.systid_fra < b.systid_til OR b.systid_til IS NULL)
			WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND a.systid_til IS NOT NULL
		),

		tgp_update AS ( -- Select all features that represent update operations from the historic data set
			SELECT
				'Punkt'::text AS objekt_type,
				'Ændret'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_til::timestamp(0) AS dato,
				a.bruger_id_slut AS bruger,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || b.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode,
				c.aendringer
			FROM greg.t_greg_punkter a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr AND b.systid_fra < a.systid_til AND (a.systid_til <= b.systid_til OR b.systid_til IS NULL)
			LEFT JOIN change_2 c ON a.versions_id = c.versions_id
			WHERE EXTRACT (YEAR FROM a.systid_til) = $1 AND 
					CASE
						WHEN a.objekt_id NOT IN (SELECT objekt_id FROM greg.t_greg_punkter WHERE systid_til IS NULL) AND a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_punkter d WHERE a.objekt_id = d.objekt_id)
						THEN FALSE
						ELSE TRUE
					END -- If the object represent a deletion then FALSE
		),

		tgp_delete AS( -- Select all features that represent delete operations from the historic data set
			SELECT
				'Punkt'::text AS objekt_type,
				'Slettet'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_til::timestamp(0) AS dato,
				a.bruger_id_slut AS bruger,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || b.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode,
				''::text AS aendringer
			FROM greg.t_greg_punkter a
			LEFT JOIN greg.t_greg_omraader b ON a.arbejdssted = b.pg_distrikt_nr AND b.systid_fra < a.systid_til AND (a.systid_til <= b.systid_til OR b.systid_til IS NULL)
			WHERE EXTRACT (YEAR FROM a.systid_til) = $1 AND a.objekt_id NOT IN(SELECT objekt_id FROM greg.t_greg_punkter WHERE systid_til IS NULL) AND a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_punkter d WHERE a.objekt_id = d.objekt_id)
		),

		union_ AS( -- Make union of all tgp tables
			SELECT
				*
			FROM tgp_insert

			UNION ALL

			SELECT
				*
			FROM tgp_insert_his

			UNION ALL

			SELECT
				*
			FROM tgp_update

			UNION ALL

			SELECT
				*
			FROM tgp_delete
		)

	SELECT
		a.objekt_type,
		a.handling,
		a.versions_id,
		a.objekt_id,
		a.dato,
		a.bruger,
		a.arbejdssted,
		a.underelement_kode || ' ' || b.underelement_tekst AS underelement,
		a.aendringer
	FROM union_ a
	LEFT JOIN basis.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
	ORDER BY dato DESC;

$$;

COMMENT ON FUNCTION greg.f_aendring_log_punkter(aar integer) IS 'Funktion til at generere en ændringslog for punkter indenfor et givent år. Format: yyyy.';

-- f_aendring_log_omraader(aar integer)

DROP FUNCTION IF EXISTS greg.f_aendring_log_omraader(aar integer);

CREATE FUNCTION greg.f_aendring_log_omraader(aar integer)
	RETURNS TABLE(
		objekt_type text,
		handling text,
		versions_id uuid,
		objekt_id uuid,
		dato timestamp without time zone,
		bruger text,
		arbejdssted text,
		underelement text,
		aendringer text
	)
	LANGUAGE sql AS
$$

	WITH

		column_names AS ( -- Select all column names as rows in a single column
			SELECT
				ordinal_position AS row,
				column_name
			FROM information_schema.columns
			WHERE table_schema = 'greg' AND table_name = 't_greg_omraader'
		),

		raw AS ( -- Select rows where commas has been replaced with semi colon
			SELECT
				-- Automated values
				versions_id,
				objekt_id,
				oprettet,
				systid_fra,
				systid_til,
				bruger_id_start,
				bruger_id_slut,
				-- Geometry
				geometri,
				-- FKG #1
				pg_distrikt_nr,
				regexp_replace(pg_distrikt_tekst, ',', ';', 'g'),
				pg_distrikt_type_kode,
				-- FKG #2
				regexp_replace(note, ',', ';', 'g'),
				regexp_replace(link, ',', ';', 'g'),
				vejkode,
				regexp_replace(vejnr, ',', ';', 'g'),
				postnr,
				udfoerer_kode,
				udfoerer_kontakt_kode1,
				udfoerer_kontakt_kode2,
				kommunal_kontakt_kode,
				-- Table specific
				aktiv,
				synlig
			FROM greg.t_greg_omraader
			WHERE EXTRACT (YEAR FROM systid_til) = $1 OR EXTRACT (YEAR FROM systid_fra) = $1 -- Where there has been some interaction during the year
		),

		compare AS ( -- Select a column with the old values and the new values for a object that has been changed
			SELECT
				ROW_NUMBER() OVER(PARTITION BY a.row) AS row, -- Each versions_id gets a row number for each of its record
				a.versions_id,
				a.old,
				a.new
			FROM (	SELECT
						ROW_NUMBER() OVER() AS row, -- Each versions_id gets one row number for all its records
						a.versions_id,
						regexp_split_to_table(regexp_replace(ROW(a.*)::text, '[(|)|"]', '', 'g'), ',') AS old,
						regexp_split_to_table(regexp_replace(ROW(b.*)::text, '[(|)|"]', '', 'g'), ',') AS new 
					FROM raw a
					LEFT JOIN raw b ON a.objekt_id = b.objekt_id AND a.systid_til = b.systid_fra -- Join the old record with the one replacing it
					WHERE EXTRACT (YEAR FROM a.systid_til) = $1 AND CASE
																		WHEN a.objekt_id NOT IN (SELECT objekt_id FROM greg.t_greg_omraader WHERE systid_til IS NULL) AND a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_omraader d WHERE a.objekt_id = d.objekt_id)
																		THEN FALSE
																		ELSE TRUE
																	END -- If the object represent a deletion then FALSE
			) a
		),

		change AS ( -- Select columns that has been changed for a given version_id 
			SELECT
				a.versions_id,
				b.column_name
			FROM compare a
			LEFT JOIN column_names b ON a.row = b.row
			WHERE a.old != a.new AND b.column_name NOT IN ('versions_id', 'systid_fra', 'systid_til', 'bruger_id_start', 'bruger_id_slut') -- These columns are not relevant to have in the change log. Columns objekt_id and oprettet are not removed. If they show up in change log, something is wrong!!
		),

		change_2 AS ( -- Select all changed columns as aggregates to the version_id that has been changed
			SELECT
				a.versions_id,
				string_agg(a.column_name, ', ') AS aendringer
			FROM change a
			GROUP BY a.versions_id
		),

		tgo_insert AS ( -- Select all features that has been inserted, but not updated from the current data set
			SELECT
				'Område'::text AS objekt_type,
				'Tilføjet'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_fra::timestamp(0) AS dato,
				a.bruger_id_start AS bruger,
				a.pg_distrikt_nr || ' ' || a.pg_distrikt_tekst AS arbejdssted,
				NULL::text AS underelement,
				''::text AS aendringer
			FROM greg.t_greg_omraader a
			WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND a.systid_til IS NULL
		),

		tgo_insert_his AS ( -- Select all features that represent insert opreations from the historic data set
			SELECT
				'Område'::text AS objekt_type,
				'Tilføjet'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_fra::timestamp(0) AS dato,
				a.bruger_id_start AS bruger,
				a.pg_distrikt_nr || ' ' || a.pg_distrikt_tekst AS arbejdssted,
				NULL::text AS underelement,
				''::text AS aendringer
			FROM greg.t_greg_omraader a
			WHERE EXTRACT (YEAR FROM a.systid_fra) = $1 AND a.systid_fra = a.oprettet AND a.systid_til IS NOT NULL
		),

		tgo_update AS ( -- Select all features that represent update operations from the historic data set
			SELECT
				'Område'::text AS objekt_type,
				'Ændret'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_til::timestamp(0) AS dato,
				a.bruger_id_slut AS bruger,
				a.pg_distrikt_nr || ' ' || a.pg_distrikt_tekst AS arbejdssted,
				NULL::text AS underelement,
				c.aendringer
			FROM greg.t_greg_omraader a
			LEFT JOIN change_2 c ON a.versions_id = c.versions_id
			WHERE EXTRACT (YEAR FROM a.systid_til) = $1 AND 
					CASE
						WHEN a.objekt_id NOT IN(SELECT objekt_id FROM greg.t_greg_omraader WHERE systid_til IS NULL) AND a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_omraader d WHERE a.objekt_id = d.objekt_id)
						THEN FALSE
						ELSE TRUE
					END -- If the object represent a deletion then FALSE
		),

		tgo_delete AS( -- Select all features that represent delete operations from the historic data set
			SELECT
				'Område'::text AS objekt_type,
				'Slettet'::text AS handling,
				a.versions_id,
				a.objekt_id,
				a.systid_til::timestamp(0) AS dato,
				a.bruger_id_slut AS bruger,
				a.pg_distrikt_nr || ' ' || a.pg_distrikt_tekst AS arbejdssted,
				NULL::text AS underelement,
				''::text AS aendringer
			FROM greg.t_greg_omraader a
			WHERE EXTRACT (YEAR FROM a.systid_til) = $1 AND a.objekt_id NOT IN (SELECT objekt_id FROM greg.t_greg_omraader WHERE systid_til IS NULL) AND a.systid_til = (SELECT MAX(systid_til) FROM greg.t_greg_omraader d WHERE a.objekt_id = d.objekt_id)
		)

	-- Make union of all tgo tables
	SELECT
		*
	FROM tgo_insert
	
	UNION ALL

	SELECT
		*
	FROM tgo_insert_his

	UNION ALL

	SELECT
		*
	FROM tgo_update

	UNION ALL

	SELECT
		*
	FROM tgo_delete
	ORDER BY dato DESC;

$$;

COMMENT ON FUNCTION greg.f_aendring_log_omraader(aar integer) IS 'Funktion til at generere en ændringslog for områder indenfor et givent år. Format: yyyy.';

-- f_dato_flader(dag integer, maaned integer, aar integer)

DROP FUNCTION IF EXISTS greg.f_dato_flader(dag integer, maaned integer, aar integer);

CREATE FUNCTION greg.f_dato_flader(dag integer, maaned integer, aar integer)
	RETURNS TABLE(
		udtraeksdato text,
		-- Automated values
		versions_id uuid,
		objekt_id uuid,
		oprettet timestamp with time zone,
		systid_fra timestamp with time zone,
		systid_til timestamp with time zone,
		bruger_id_start character varying,
		bruger_start character varying,
		bruger_id_slut character varying,
		bruger_slut character varying,
		-- Geometry
		geometri public.geometry('MultiPolygon', 25832),
		-- FKG #1
		cvr_kode integer,
		cvr_navn character varying,
		oprindkode integer,
		oprindelse character varying,
		statuskode integer,
		status character varying,
		off_kode integer,
		offentlig character varying,
		-- FKG #2
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
		-- FKG #3
		arbejdssted integer,
		pg_distrikt_tekst character varying,
		hovedelement_kode character varying,
		hovedelement_tekst character varying,
		element_kode character varying,
		element_tekst character varying,
		underelement_kode character varying,
		underelement_tekst character varying,
		-- Measurements
		hoejde numeric(10,1),
		-- Table specific
		klip_sider integer,
		litra character varying,
		-- Special calculations and geometry derived values
		speciel_forklaring character varying,
		speciel numeric(10,1),
		areal numeric(10,1),
		omkreds numeric(10,1),
		element_pris numeric(10,2),
		-- Active
		aktiv boolean
	)
	LANGUAGE sql AS
$$

	WITH

		time_var AS ( -- 'Time of day'-variable
			SELECT ($3 || '-' || $2 || '-' || $1 || ' ' || (SELECT text_ FROM greg.variabel('his_time_var')))::timestamp with time zone AS column
		),
		
		pris_reg AS ( -- The factor for regulating prices on the given day
			SELECT * FROM basis.f_prisregulering_produkt($1, $2, $3)
		)

	SELECT -- Select everything present (at the end of) the given day
		RIGHT('0' || $1, 2) || '-' || RIGHT('0' || $2, 2) || '-' || $3 AS udtraeksdato,
		-- Automated values
		a.versions_id,
		a.objekt_id,
		a.oprettet,
		a.systid_fra,
		a.systid_til,
		a.bruger_id_start,
		b1.navn || ' (' || a.bruger_id_start || ')' AS bruger_start,
		a.bruger_id_slut,
		b2.navn || ' (' || a.bruger_id_slut || ')'  AS bruger_slut,
		-- Geometry
		a.geometri,
		-- FKG #1
		a.cvr_kode,
		CASE
			WHEN am.kommunekode IS NOT NULL
			THEN am.cvr_navn || ' (' || am.kommunekode || ')'
			ELSE am.cvr_navn
		END AS cvr_navn,
		a.oprindkode,
		o.oprindelse,
		a.statuskode,
		s.status,
		a.off_kode,
		of.offentlig,
		-- FKG #2
		a.note,
		a.link,
		a.vejkode,
		v.vejnavn || ' (' || v.postnr || ')' AS vejnavn,
		a.tilstand_kode,
		t.tilstand,
		a.anlaegsaar,
		a.udfoerer_entrep_kode,
		u.udfoerer_entrep,
		a.kommunal_kontakt_kode,
		kk.navn || ', tlf: ' || kk.telefon || ', ' || kk.email AS kommunal_kontakt,
		-- FKG #3
		a.arbejdssted,
		CASE 
			WHEN a.arbejdssted IS NOT NULL
			THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
			ELSE 'Udenfor område'
		END AS pg_distrikt_tekst,
		he.hovedelement_kode,
		he.hovedelement_kode || ' - ' || he.hovedelement_tekst AS hovedelement_tekst,
		e.element_kode,
		e.element_kode || ' ' || e.element_tekst AS element_tekst,
		a.underelement_kode,
		a.underelement_kode || ' ' || ue.underelement_tekst AS underelement_tekst,
		-- Measurements
		a.hoejde,
		-- Table specific
		a.klip_sider,
		a.litra,
		-- Special calculations and geometry derived values
		ue.speciel_forklaring || ':' AS speciel_forklaring,
		CASE
			WHEN ue.speciel_sql IS NOT NULL
			THEN (SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_flader', a.versions_id))
			ELSE NULL
		END AS speciel,
		public.ST_Area(a.geometri)::numeric(10,1) AS areal,
		public.ST_Perimeter(a.geometri)::numeric(10,1) AS omkreds,
		CASE
			WHEN ue.speciel_sql IS NOT NULL
			THEN ((SELECT speciel FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_flader', a.versions_id)) * ue.enhedspris_speciel * (SELECT * FROM pris_reg))::numeric(10,2)
			ELSE 0
		END +
		(public.ST_Area(a.geometri) * ue.enhedspris_poly * (SELECT * FROM pris_reg))::numeric(10,1) AS element_pris,
		-- Active
		CASE 
			WHEN a.arbejdssted IS NOT NULL	
			THEN om.aktiv
			ELSE TRUE
		END AS aktiv
	FROM greg.t_greg_flader a
	-- Automated values
	LEFT JOIN basis.d_basis_bruger_id b1 ON a.bruger_id_start = b1.bruger_id
	LEFT JOIN basis.d_basis_bruger_id b2 ON a.bruger_id_slut = b2.bruger_id
	-- FKG #1
	LEFT JOIN basis.d_basis_ansvarlig_myndighed am ON a.cvr_kode = am.cvr_kode
	LEFT JOIN basis.d_basis_oprindelse o ON a.oprindkode = o.oprindkode
	LEFT JOIN basis.d_basis_status s ON a.statuskode = s.statuskode
	LEFT JOIN basis.d_basis_offentlig of ON a.off_kode = of.off_kode
	-- FKG #2
	LEFT JOIN basis.d_basis_vejnavn v ON a.vejkode = v.vejkode
	LEFT JOIN basis.d_basis_tilstand t ON a.tilstand_kode = t.tilstand_kode
	LEFT JOIN basis.d_basis_udfoerer_entrep u ON a.udfoerer_entrep_kode = u.udfoerer_entrep_kode
	LEFT JOIN basis.d_basis_kommunal_kontakt kk ON a.kommunal_kontakt_kode = kk.kommunal_kontakt_kode
	-- FKG #3
	LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_fra <= (SELECT * FROM time_var) AND ((SELECT * FROM time_var) < om.systid_til OR om.systid_til IS NULL)
	LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
	LEFT JOIN basis.e_basis_elementer e ON ue.element_kode = e.element_kode
	LEFT JOIN basis.e_basis_hovedelementer he ON e.hovedelement_kode = he.hovedelement_kode
	WHERE a.systid_fra <= (SELECT * FROM time_var) AND ((SELECT * FROM time_var) < a.systid_til OR a.systid_til IS NULL); -- Date of creation is before (or on) the given date and the element is either still current or terminated after the current date

$$;

COMMENT ON FUNCTION greg.f_dato_flader(dag integer, maaned integer, aar integer) IS 'Funktion til simulering af registreringen på en bestemt dato. Format: dd-MM-yyyy.';

-- f_dato_linier(dag integer, maaned integer, aar integer)

DROP FUNCTION IF EXISTS greg.f_dato_linier(dag integer, maaned integer, aar integer);

CREATE FUNCTION greg.f_dato_linier(dag integer, maaned integer, aar integer)
	RETURNS TABLE(
		udtraeksdato text,
		-- Automated values
		versions_id uuid,
		objekt_id uuid,
		oprettet timestamp with time zone,
		systid_fra timestamp with time zone,
		systid_til timestamp with time zone,
		bruger_id_start character varying,
		bruger_start character varying,
		bruger_id_slut character varying,
		bruger_slut character varying,
		-- Geometry
		geometri public.geometry('MultiLineString', 25832),
		-- FKG #1
		cvr_kode integer,
		cvr_navn character varying,
		oprindkode integer,
		oprindelse character varying,
		statuskode integer,
		status character varying,
		off_kode integer,
		offentlig character varying,
		-- FKG #2
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
		-- FKG #3
		arbejdssted integer,
		pg_distrikt_tekst character varying,
		hovedelement_kode character varying,
		hovedelement_tekst character varying,
		element_kode character varying,
		element_tekst character varying,
		underelement_kode character varying,
		underelement_tekst character varying,
		-- Measurements
		bredde numeric(10,1),
		hoejde numeric(10,1),
		-- Table specific
		litra character varying,
		-- Special calculations and geometry derived values
		speciel_forklaring character varying,
		speciel numeric(10,1),
		laengde numeric(10,1),
		element_pris numeric(10,2),
		-- Active
		aktiv boolean
	)
	LANGUAGE sql AS
$$

	WITH

		time_var AS ( -- 'Time of day'-variable
			SELECT ($3 || '-' || $2 || '-' || $1 || ' ' || (SELECT text_ FROM greg.variabel('his_time_var')))::timestamp with time zone AS column
		),
		
		pris_reg AS ( -- The factor for regulating prices on the given day
			SELECT * FROM basis.f_prisregulering_produkt($1, $2, $3)
		)

	SELECT -- Select everything present (at the end of) the given day
		RIGHT('0' || $1, 2) || '-' || RIGHT('0' || $2, 2) || '-' || $3 AS udtraeksdato,
		-- Automated values
		a.versions_id,
		a.objekt_id,
		a.oprettet,
		a.systid_fra,
		a.systid_til,
		a.bruger_id_start,
		b1.navn || ' (' || a.bruger_id_start || ')' AS bruger_start,
		a.bruger_id_slut,
		b2.navn || ' (' || a.bruger_id_slut || ')'  AS bruger_slut,
		-- Geometry
		a.geometri,
		-- FKG #1
		a.cvr_kode,
		CASE
			WHEN am.kommunekode IS NOT NULL
			THEN am.cvr_navn || ' (' || am.kommunekode || ')'
			ELSE am.cvr_navn
		END AS cvr_navn,
		a.oprindkode,
		o.oprindelse,
		a.statuskode,
		s.status,
		a.off_kode,
		of.offentlig,
		-- FKG #2
		a.note,
		a.link,
		a.vejkode,
		v.vejnavn || ' (' || v.postnr || ')' AS vejnavn,
		a.tilstand_kode,
		t.tilstand,
		a.anlaegsaar,
		a.udfoerer_entrep_kode,
		u.udfoerer_entrep,
		a.kommunal_kontakt_kode,
		kk.navn || ', tlf: ' || kk.telefon || ', ' || kk.email AS kommunal_kontakt,
		-- FKG #3
		a.arbejdssted,
		CASE 
			WHEN a.arbejdssted IS NOT NULL
			THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
			ELSE 'Udenfor område'
		END AS pg_distrikt_tekst,
		he.hovedelement_kode,
		he.hovedelement_kode || ' - ' || he.hovedelement_tekst AS hovedelement_tekst,
		e.element_kode,
		e.element_kode || ' ' || e.element_tekst AS element_tekst,
		a.underelement_kode,
		a.underelement_kode || ' ' || ue.underelement_tekst AS underelement_tekst,
		-- Measurements
		a.bredde,
		a.hoejde,
		-- Table specific
		a.litra,
		-- Special calculations and geometry derived values
		ue.speciel_forklaring || ':' AS speciel_forklaring,
		CASE
			WHEN ue.speciel_sql IS NOT NULL
			THEN (SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_linier', a.versions_id))
			ELSE NULL
		END AS speciel,
		public.ST_Length(a.geometri)::numeric(10,1) AS laengde,
		CASE
			WHEN ue.speciel_sql IS NOT NULL
			THEN ((SELECT speciel FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_linier', a.versions_id)) * ue.enhedspris_speciel * (SELECT * FROM pris_reg))::numeric(10,2)
			ELSE 0
		END +
		(public.ST_Length(a.geometri) * ue.enhedspris_line * (SELECT * FROM pris_reg))::numeric(10,1) AS element_pris,
		-- Active
		CASE 
			WHEN a.arbejdssted IS NOT NULL	
			THEN om.aktiv
			ELSE TRUE
		END AS aktiv
	FROM greg.t_greg_linier a
	-- Automated values
	LEFT JOIN basis.d_basis_bruger_id b1 ON a.bruger_id_start = b1.bruger_id
	LEFT JOIN basis.d_basis_bruger_id b2 ON a.bruger_id_slut = b2.bruger_id
	-- FKG #1
	LEFT JOIN basis.d_basis_ansvarlig_myndighed am ON a.cvr_kode = am.cvr_kode
	LEFT JOIN basis.d_basis_oprindelse o ON a.oprindkode = o.oprindkode
	LEFT JOIN basis.d_basis_status s ON a.statuskode = s.statuskode
	LEFT JOIN basis.d_basis_offentlig of ON a.off_kode = of.off_kode
	-- FKG #2
	LEFT JOIN basis.d_basis_vejnavn v ON a.vejkode = v.vejkode
	LEFT JOIN basis.d_basis_tilstand t ON a.tilstand_kode = t.tilstand_kode
	LEFT JOIN basis.d_basis_udfoerer_entrep u ON a.udfoerer_entrep_kode = u.udfoerer_entrep_kode
	LEFT JOIN basis.d_basis_kommunal_kontakt kk ON a.kommunal_kontakt_kode = kk.kommunal_kontakt_kode
	-- FKG #3
	LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_fra <= (SELECT * FROM time_var) AND ((SELECT * FROM time_var) < om.systid_til OR om.systid_til IS NULL)
	LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
	LEFT JOIN basis.e_basis_elementer e ON ue.element_kode = e.element_kode
	LEFT JOIN basis.e_basis_hovedelementer he ON e.hovedelement_kode = he.hovedelement_kode
	WHERE a.systid_fra <= (SELECT * FROM time_var) AND ((SELECT * FROM time_var) < a.systid_til OR a.systid_til IS NULL); -- Date of creation is before (or on) the given date and the element is either still current or terminated after the current date

$$;

COMMENT ON FUNCTION greg.f_dato_linier(dag integer, maaned integer, aar integer) IS 'Funktion til simulering af registreringen på en bestemt dato. Format: dd-MM-yyyy.';

-- f_dato_punkter(dag integer, maaned integer, aar integer)

DROP FUNCTION IF EXISTS greg.f_dato_punkter(dag integer, maaned integer, aar integer);

CREATE FUNCTION greg.f_dato_punkter(dag integer, maaned integer, aar integer)
	RETURNS TABLE(
		udtraeksdato text,
		-- Automated values
		versions_id uuid,
		objekt_id uuid,
		oprettet timestamp with time zone,
		systid_fra timestamp with time zone,
		systid_til timestamp with time zone,
		bruger_id_start character varying,
		bruger_start character varying,
		bruger_id_slut character varying,
		bruger_slut character varying,
		-- Geometry
		geometri public.geometry('MultiPoint', 25832),
		-- FKG #1
		cvr_kode integer,
		cvr_navn character varying,
		oprindkode integer,
		oprindelse character varying,
		statuskode integer,
		status character varying,
		off_kode integer,
		offentlig character varying,
		-- FKG #2
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
		-- FKG #3
		arbejdssted integer,
		pg_distrikt_tekst character varying,
		hovedelement_kode character varying,
		hovedelement_tekst character varying,
		element_kode character varying,
		element_tekst character varying,
		underelement_kode character varying,
		underelement_tekst character varying,
		-- Measurements
		laengde numeric(10,1),
		bredde numeric(10,1),
		diameter numeric(10,1),
		hoejde numeric(10,1),
		-- Table specific
		slaegt character varying,
		art character varying,
		litra character varying,
		-- Special calculations and geometry derived values
		speciel_forklaring character varying,
		speciel numeric(10,1),
		antal integer,
		element_pris numeric(10,2),
		-- Active
		aktiv boolean
	)
	LANGUAGE sql AS
$$

	WITH

		time_var AS ( -- 'Time of day'-variable
			SELECT ($3 || '-' || $2 || '-' || $1 || ' ' || (SELECT text_ FROM greg.variabel('his_time_var')))::timestamp with time zone AS column
		),
		
		pris_reg AS ( -- The factor for regulating prices on the given day
			SELECT * FROM basis.f_prisregulering_produkt($1, $2, $3)
		)

	SELECT -- Select everything present (at the end of) the given day
		RIGHT('0' || $1, 2) || '-' || RIGHT('0' || $2, 2) || '-' || $3 AS udtraeksdato,
		-- Automated values
		a.versions_id,
		a.objekt_id,
		a.oprettet,
		a.systid_fra,
		a.systid_til,
		a.bruger_id_start,
		b1.navn || ' (' || a.bruger_id_start || ')' AS bruger_start,
		a.bruger_id_slut,
		b2.navn || ' (' || a.bruger_id_slut || ')'  AS bruger_slut,
		-- Geometry
		a.geometri,
		-- FKG #1
		a.cvr_kode,
		CASE
			WHEN am.kommunekode IS NOT NULL
			THEN am.cvr_navn || ' (' || am.kommunekode || ')'
			ELSE am.cvr_navn
		END AS cvr_navn,
		a.oprindkode,
		o.oprindelse,
		a.statuskode,
		s.status,
		a.off_kode,
		of.offentlig,
		-- FKG #2
		a.note,
		a.link,
		a.vejkode,
		v.vejnavn || ' (' || v.postnr || ')' AS vejnavn,
		a.tilstand_kode,
		t.tilstand,
		a.anlaegsaar,
		a.udfoerer_entrep_kode,
		u.udfoerer_entrep,
		a.kommunal_kontakt_kode,
		kk.navn || ', tlf: ' || kk.telefon || ', ' || kk.email AS kommunal_kontakt,
		-- FKG #3
		a.arbejdssted,
		CASE 
			WHEN a.arbejdssted IS NOT NULL
			THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
			ELSE 'Udenfor område'
		END AS pg_distrikt_tekst,
		he.hovedelement_kode,
		he.hovedelement_kode || ' - ' || he.hovedelement_tekst AS hovedelement_tekst,
		e.element_kode,
		e.element_kode || ' ' || e.element_tekst AS element_tekst,
		a.underelement_kode,
		a.underelement_kode || ' ' || ue.underelement_tekst AS underelement_tekst,
		-- Measurements
		a.laengde,
		a.bredde,
		a.diameter,
		a.hoejde,
		-- Table specific
		a.slaegt,
		a.art,
		a.litra,
		-- Special calculations and geometry derived values
		ue.speciel_forklaring || ':' AS speciel_forklaring,
		CASE
			WHEN ue.speciel_sql = 'REN'
			THEN s1.areal::numeric(10,1)
			WHEN ue.speciel_sql IS NOT NULL
			THEN (SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_punkter', a.versions_id))
			ELSE NULL
		END AS speciel,
		public.ST_NumGeometries(a.geometri) AS antal,
		CASE
			WHEN ue.speciel_sql = 'REN'
			THEN (s1.areal * ue.enhedspris_speciel * (SELECT * FROM pris_reg))::numeric(10,2)
			WHEN ue.speciel_sql IS NOT NULL
			THEN ((SELECT speciel FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_punkter', a.versions_id)) * ue.enhedspris_speciel * (SELECT * FROM pris_reg))::numeric(10,2)
			ELSE 0
		END +
		(public.ST_NumGeometries(a.geometri) * ue.enhedspris_point * (SELECT * FROM pris_reg))::numeric(10,1) AS element_pris,
		-- Active
		CASE 
			WHEN a.arbejdssted IS NOT NULL	
			THEN om.aktiv
			ELSE TRUE
		END AS aktiv
	FROM greg.t_greg_punkter a
	-- Automated values
	LEFT JOIN basis.d_basis_bruger_id b1 ON a.bruger_id_start = b1.bruger_id
	LEFT JOIN basis.d_basis_bruger_id b2 ON a.bruger_id_slut = b2.bruger_id
	-- FKG #1
	LEFT JOIN basis.d_basis_ansvarlig_myndighed am ON a.cvr_kode = am.cvr_kode
	LEFT JOIN basis.d_basis_oprindelse o ON a.oprindkode = o.oprindkode
	LEFT JOIN basis.d_basis_status s ON a.statuskode = s.statuskode
	LEFT JOIN basis.d_basis_offentlig of ON a.off_kode = of.off_kode
	-- FKG #2
	LEFT JOIN basis.d_basis_vejnavn v ON a.vejkode = v.vejkode
	LEFT JOIN basis.d_basis_tilstand t ON a.tilstand_kode = t.tilstand_kode
	LEFT JOIN basis.d_basis_udfoerer_entrep u ON a.udfoerer_entrep_kode = u.udfoerer_entrep_kode
	LEFT JOIN basis.d_basis_kommunal_kontakt kk ON a.kommunal_kontakt_kode = kk.kommunal_kontakt_kode
	-- FKG #3
	LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_fra <= (SELECT * FROM time_var) AND ((SELECT * FROM time_var) < om.systid_til OR om.systid_til IS NULL)
	LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
	LEFT JOIN basis.e_basis_elementer e ON ue.element_kode = e.element_kode
	LEFT JOIN basis.e_basis_hovedelementer he ON e.hovedelement_kode = he.hovedelement_kode
	-- For speciel_sql = 'REN'
	LEFT JOIN (SELECT	
					arbejdssted,
					SUM(public.ST_Area(a.geometri)) AS areal
				FROM greg.f_dato_flader($1, $2, $3) a
				LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
				WHERE ue.renhold IS TRUE
				GROUP BY arbejdssted) s1
		ON a.arbejdssted = s1.arbejdssted
	WHERE a.systid_fra <= (SELECT * FROM time_var) AND ((SELECT * FROM time_var) < a.systid_til OR a.systid_til IS NULL); -- Date of creation is before (or on) the given date and the element is either still current or terminated after the current date

$$;

COMMENT ON FUNCTION greg.f_dato_punkter(dag integer, maaned integer, aar integer) IS 'Funktion til simulering af registreringen på en bestemt dato. Format: dd-MM-yyyy.';

-- f_dato_omraader(dag integer, maaned integer, aar integer)

DROP FUNCTION IF EXISTS greg.f_dato_omraader(dag integer, maaned integer, aar integer);

CREATE FUNCTION greg.f_dato_omraader(dag integer, maaned integer, aar integer)
	RETURNS TABLE(
		udtraeksdato text,
		-- Automated values
		versions_id uuid,
		objekt_id uuid,
		oprettet timestamp with time zone,
		systid_fra timestamp with time zone,
		systid_til timestamp with time zone,
		bruger_id_start character varying,
		bruger_start character varying,
		bruger_id_slut character varying,
		bruger_slut character varying,
		-- Geometry
		geometri public.geometry('MultiPolygon', 25832),
		-- FKG #1
		pg_distrikt_nr integer,
		pg_distrikt_tekst character varying,
		pg_distrikt_type_kode integer,
		pg_distrikt_type character varying,
		-- FKG #2
		note character varying,
		link character varying,
		vejkode integer,
		vejnavn character varying,
		vejnr character varying,
		postnr integer,
		distrikt character varying,
		udfoerer_kode integer,
		udfoerer character varying,
		udfoerer_kontakt_kode1 integer,
		udfoerer_kontakt1 character varying,
		udfoerer_kontakt_kode2 integer,
		udfoerer_kontakt2 character varying,
		kommunal_kontakt_kode integer,
		kommunal_kontakt character varying,
		-- Table specific
		aktiv boolean,
		synlig boolean,
		-- Special calculations and geometry derived values
		areal numeric(10,1)
	)
	LANGUAGE sql AS
$$

	WITH

		time_var AS ( -- 'Time of day'-variable
			SELECT ($3 || '-' || $2 || '-' || $1 || ' ' || (SELECT text_ FROM greg.variabel('his_time_var')))::timestamp with time zone AS column
		)

	SELECT -- Select everything present (at the end of) the given day
		RIGHT('0' || $1, 2) || '-' || RIGHT('0' || $2, 2) || '-' || $3 AS udtraeksdato,
		-- Automated values
		a.versions_id,
		a.objekt_id,
		a.oprettet,
		a.systid_fra,
		a.systid_til,
		a.bruger_id_start,
		b1.navn || ' (' || a.bruger_id_start || ')' AS bruger_start,
		a.bruger_id_slut,
		b2.navn || ' (' || a.bruger_id_slut || ')'  AS bruger_slut,
		-- Geometry
		a.geometri,
		-- FKG #1
		a.pg_distrikt_nr,
		a.pg_distrikt_tekst,
		a.pg_distrikt_type_kode,
		dt.pg_distrikt_type,
		-- FKG #2
		a.note,
		a.link,
		a.vejkode,
		v.vejnavn,
		a.vejnr,
		a.postnr,
		a. postnr || ' ' || p.postnr_by AS distrikt,
		a.udfoerer_kode,
		u.udfoerer,
		a.udfoerer_kontakt_kode1,
		u1.udfoerer || ', ' || uk1.navn || ', tlf: ' || uk1.telefon || ', ' || uk1.email AS udfoerer_kontakt1,
		a.udfoerer_kontakt_kode2,
		u2.udfoerer || ', ' || uk2.navn || ', tlf: ' || uk2.telefon || ', ' || uk2.email AS udfoerer_kontakt2,
		a.kommunal_kontakt_kode,
		kk.navn || ', tlf: ' || kk.telefon || ', ' || kk.email AS kommunal_kontakt,
		-- Table specific
		a.aktiv,
		a.synlig,
		-- Special calculations and geometry derived values
		public.ST_Area(a.geometri)::numeric(10,1) AS areal
	FROM greg.t_greg_omraader a
	-- Automated values
	LEFT JOIN basis.d_basis_bruger_id b1 ON a.bruger_id_start = b1.bruger_id
	LEFT JOIN basis.d_basis_bruger_id b2 ON a.bruger_id_slut = b2.bruger_id
	-- FKG #1
	LEFT JOIN basis.d_basis_distrikt_type dt ON a.pg_distrikt_type_kode = dt.pg_distrikt_type_kode
	-- FKG #2
	LEFT JOIN basis.d_basis_vejnavn v ON a.vejkode = v.vejkode
	LEFT JOIN basis.d_basis_postnr p ON a.postnr = p.postnr
	LEFT JOIN basis.d_basis_udfoerer u ON a.udfoerer_kode = u.udfoerer_kode
	LEFT JOIN basis.d_basis_udfoerer_kontakt uk1 ON a.udfoerer_kontakt_kode1 = uk1.udfoerer_kontakt_kode
	LEFT JOIN basis.d_basis_udfoerer u1 ON uk1.udfoerer_kode = u1.udfoerer_kode
	LEFT JOIN basis.d_basis_udfoerer_kontakt uk2 ON a.udfoerer_kontakt_kode2 = uk2.udfoerer_kontakt_kode
	LEFT JOIN basis.d_basis_udfoerer u2 ON uk2.udfoerer_kode = u2.udfoerer_kode
	LEFT JOIN basis.d_basis_kommunal_kontakt kk ON a.kommunal_kontakt_kode = kk.kommunal_kontakt_kode
	WHERE a.systid_fra <= (SELECT * FROM time_var) AND ((SELECT * FROM time_var) < a.systid_til OR a.systid_til IS NULL) -- Date of creation is before (or on) the given date and the element is either still current or terminated after the current date
	ORDER BY a.pg_distrikt_nr;

$$;

COMMENT ON FUNCTION greg.f_dato_omraader(dag integer, maaned integer, aar integer) IS 'Funktion til simulering af registreringen på en bestemt dato. Format: dd-MM-yyyy.';

-- f_tot_flader(dage integer)

DROP FUNCTION IF EXISTS greg.f_tot_flader(dage integer);

CREATE FUNCTION greg.f_tot_flader(dage integer)
	RETURNS TABLE(
		objekt_id uuid,
		geometri public.geometry('MultiPolygon', 25832),
		handling text,
		dato date,
		arbejdssted text,
		underelement text
	)
	LANGUAGE sql AS
$$

	WITH

		tgf AS ( -- Select all inserts and updates in the current data set within a specific number of days
			SELECT
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
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode || ' ' || ue.underelement_tekst AS underelement
			FROM greg.t_greg_flader a
			LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_fra <= a.systid_fra
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
			WHERE current_date - a.systid_fra::date < $1 AND a.systid_til IS NULL
		),

		tghf AS ( -- Select all delete operations from the historic data set within a specific number of days
			SELECT DISTINCT ON(a.objekt_id)
				a.objekt_id,
				a.geometri,
				CASE
					WHEN current_date - a.oprettet::date < $1
					THEN 'Tilføjet og slettet'::text
					ELSE 'Slettet'::text
				END AS handling,
				a.systid_til::date AS dato,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode || ' ' || ue.underelement_tekst AS underelement
			FROM greg.t_greg_flader a
			LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_fra <= a.systid_til AND (a.systid_til < om.systid_til OR om.systid_til IS NULL)
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
			WHERE current_date - a.systid_til::date < $1 AND a.objekt_id NOT IN (SELECT objekt_id FROM tgf)
			ORDER BY a.objekt_id ASC, a.systid_til DESC
		)

	SELECT
		*
	FROM tgf

	UNION ALL

	SELECT
		*
	FROM tghf
	ORDER BY dato desc;

$$;

COMMENT ON FUNCTION greg.f_tot_flader(dage integer) IS 'Ændringsoversigt med tilhørende geometri. Defineres indenfor x antal dage.';

-- f_tot_linier(dage integer)

DROP FUNCTION IF EXISTS greg.f_tot_linier(dage integer);

CREATE FUNCTION greg.f_tot_linier(dage integer)
	RETURNS TABLE(
		objekt_id uuid,
		geometri public.geometry('MultiLineString', 25832),
		handling text,
		dato date,
		arbejdssted text,
		underelement text
	)
	LANGUAGE sql AS
$$

	WITH

		tgl AS ( -- Select all inserts and updates in the current data set within a specific number of days
			SELECT
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
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode || ' ' || ue.underelement_tekst AS underelement
			FROM greg.t_greg_linier a
			LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_fra <= a.systid_fra
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
			WHERE current_date - a.systid_fra::date < $1 AND a.systid_til IS NULL
		),

		tghl AS ( -- Select all delete operations from the historic data set within a specific number of days
			SELECT DISTINCT ON(a.objekt_id)
				a.objekt_id,
				a.geometri,
				CASE
					WHEN current_date - a.oprettet::date < $1
					THEN 'Tilføjet og slettet'::text
					ELSE 'Slettet'::text
				END AS handling,
				a.systid_til::date AS dato,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode || ' ' || ue.underelement_tekst AS underelement
			FROM greg.t_greg_linier a
			LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_fra <= a.systid_til AND (a.systid_til < om.systid_til OR om.systid_til IS NULL)
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
			WHERE current_date - a.systid_til::date < $1 AND a.objekt_id NOT IN (SELECT objekt_id FROM tgl)
			ORDER BY a.objekt_id ASC, a.systid_til DESC
		)

	SELECT
		*
	FROM tgl

	UNION ALL

	SELECT
		*
	FROM tghl
	ORDER BY dato desc;

$$;

COMMENT ON FUNCTION greg.f_tot_linier(dage integer) IS 'Ændringsoversigt med tilhørende geometri. Defineres indenfor x antal dage.';

-- f_tot_punkter(dage integer)

DROP FUNCTION IF EXISTS greg.f_tot_punkter(dage integer);

CREATE FUNCTION greg.f_tot_punkter(dage integer)
	RETURNS TABLE(
		objekt_id uuid,
		geometri public.geometry('MultiPoint', 25832),
		handling text,
		dato date,
		arbejdssted text,
		underelement text
	)
	LANGUAGE sql AS
$$

	WITH

		tgp AS ( -- Select all inserts and updates in the current data set within a specific number of days
			SELECT
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
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode || ' ' || ue.underelement_tekst AS underelement
			FROM greg.t_greg_punkter a
			LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_fra <= a.systid_fra
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
			WHERE current_date - a.systid_fra::date < $1 AND a.systid_til IS NULL
		),

		tghp AS ( -- Select all delete operations from the historic data set within a specific number of days
			SELECT DISTINCT ON(a.objekt_id)
				a.objekt_id,
				a.geometri,
				CASE
					WHEN current_date - a.oprettet::date < $1
					THEN 'Tilføjet og slettet'::text
					ELSE 'Slettet'::text
				END AS handling,
				a.systid_til::date AS dato,
				CASE 
					WHEN a.arbejdssted IS NOT NULL
					THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted,
				a.underelement_kode || ' ' || ue.underelement_tekst AS underelement
			FROM greg.t_greg_punkter a
			LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_fra <= a.systid_til AND (a.systid_til < om.systid_til OR om.systid_til IS NULL)
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
			WHERE current_date - a.systid_til::date < $1 AND a.objekt_id NOT IN (SELECT objekt_id FROM tgp)

			ORDER BY a.objekt_id ASC, a.systid_til DESC
		)

	SELECT
		*
	FROM tgp

	UNION ALL

	SELECT
		*
	FROM tghp
	ORDER BY dato desc;

$$;

COMMENT ON FUNCTION greg.f_tot_punkter(dage integer) IS 'Ændringsoversigt med tilhørende geometri. Defineres indenfor x antal dage.';

-- f_tot_omraader(dage integer)

DROP FUNCTION IF EXISTS greg.f_tot_omraader(dage integer);

CREATE FUNCTION greg.f_tot_omraader(dage integer)
	RETURNS TABLE(
		objekt_id uuid,
		geometri public.geometry('MultiPolygon', 25832),
		handling text,
		dato date,
		arbejdssted text
	)
	LANGUAGE sql AS
$$

	WITH

		tgo AS ( -- Select all inserts and updates in the current data set within a specific number of days
			SELECT
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
				CASE 
					WHEN a.pg_distrikt_nr IS NOT NULL
					THEN a.pg_distrikt_nr || ' ' || a.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted
			FROM greg.t_greg_omraader a
			WHERE current_date - a.systid_fra::date < $1 AND a.systid_til IS NULL
		),

		tgho AS ( -- Select all delete operations from the historic data set within a specific number of days
			SELECT DISTINCT ON(a.objekt_id)
				a.objekt_id,
				a.geometri,
				CASE
					WHEN current_date - a.oprettet::date < $1
					THEN 'Tilføjet og slettet'::text
					ELSE 'Slettet'::text
				END AS handling,
				a.systid_til::date AS dato,
				CASE 
					WHEN a.pg_distrikt_nr IS NOT NULL
					THEN a.pg_distrikt_nr || ' ' || a.pg_distrikt_tekst
					ELSE 'Udenfor område'
				END AS arbejdssted
			FROM greg.t_greg_omraader a
			WHERE current_date - a.systid_til::date < $1 AND a.objekt_id NOT IN (SELECT objekt_id FROM tgo)
			ORDER BY a.objekt_id ASC, a.systid_til DESC
		)

	SELECT
		*
	FROM tgo
	
	UNION ALL
	
	SELECT
		*
	FROM tgho
	ORDER BY dato desc;

$$;

COMMENT ON FUNCTION greg.f_tot_omraader(dage integer) IS 'Ændringsoversigt med tilhørende geometri. Defineres indenfor x antal dage.';

-- f_maengder(dag integer, maaned integer, aar integer)

DROP FUNCTION IF EXISTS greg.f_maengder(dag integer, maaned integer, aar integer);

CREATE FUNCTION greg.f_maengder(dag integer, maaned integer, aar integer)
	RETURNS TABLE(
		udtraeksdato text,
		pg_distrikt_type text,
		udfoerer text,
		arbejdssted integer,
		omraade text,
		hovedelement_kode text,
		hovedelement text,
		element_kode text,
		element text,
		underelement_kode text,
		underelement text,
		antal bigint,
		laengde numeric(10,1),
		areal numeric(10,1),
		speciel numeric(10,1),
		pris numeric(10,2)
	)
	LANGUAGE sql AS
$$

	WITH

		time_var AS (
			SELECT ($3 || '-' || $2 || '-' || $1 || ' ' || (SELECT text_ FROM greg.variabel('his_time_var')))::timestamp with time zone AS column -- 'Time of day'-variable
		),

		pris_reg AS (
			SELECT * FROM basis.f_prisregulering_produkt($1, $2, $3)
		),

		--
		-- Element list
		--

		base_elements AS ( -- Select a complete (DISTINCT) list of all current elements within each area code from the current data set
			SELECT
				a.arbejdssted,
				a.underelement_kode
			FROM greg.f_dato_flader($1, $2, $3) a
		
			UNION
		
			SELECT
				a.arbejdssted,
				a.underelement_kode
			FROM greg.f_dato_linier($1, $2, $3) a
		
			UNION
		
			SELECT
				a.arbejdssted,
				a.underelement_kode
			FROM greg.f_dato_punkter($1, $2, $3) a
		),

		--
		-- Basic calculations
		--

		base_poly AS ( -- Select the area for each element on each area code from the current data set
			SELECT
				a.arbejdssted,
				a.underelement_kode,
				SUM(ST_Area(a.geometri)) AS areal
			FROM greg.f_dato_flader($1, $2, $3) a
			GROUP BY a.arbejdssted, a.underelement_kode
		),

		base_line AS ( -- Select the length for each element on each area code from the current data set
			SELECT
				a.arbejdssted,
				a.underelement_kode,
				SUM(ST_Length(a.geometri)) AS laengde
			FROM greg.f_dato_linier($1, $2, $3) a
			GROUP BY a.arbejdssted, a.underelement_kode
		),

		base_point AS ( -- Select the points (MultiPoints are counted for each individual point) for each element on each area code from the current data set
			SELECT
				a.arbejdssted,
				a.underelement_kode,
				SUM(ST_NumGeometries(a.geometri)) AS antal
			FROM greg.f_dato_punkter($1, $2, $3) a
			GROUP BY a.arbejdssted, a.underelement_kode
		),

		--
		-- Special calculation
		--

		spec_ren AS	( -- Select the area for each area code excluding elements where renhold is set to false from the current data set
			SELECT
				a.arbejdssted,
				SUM(ST_Area(a.geometri)) AS areal -- Relevant for speciel_sql = 'REN'
			FROM greg.f_dato_flader($1, $2, $3) a
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
			WHERE ue.renhold IS TRUE
			GROUP BY arbejdssted
		),

		spec_poly AS ( -- Select all special calculations for each element on each area code from the current data set
			SELECT	
				a.arbejdssted,
				a.underelement_kode,
				(SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_flader', a.versions_id)) AS speciel
			FROM greg.f_dato_flader($1, $2, $3) a
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
			WHERE ue.speciel_sql IS NOT NULL
		),

		spec_line AS ( -- Select all special calculations for each element on each area code from the current data set
			SELECT	
				a.arbejdssted,
				a.underelement_kode,
				(SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_linier', a.versions_id)) AS speciel
			FROM greg.f_dato_linier($1, $2, $3) a
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
			WHERE ue.speciel_sql IS NOT NULL
		),

		spec_point AS ( -- Select all special calculations for each element on each area code from the current data set
			SELECT	
				a.arbejdssted,
				a.underelement_kode,
				CASE
					WHEN ue.speciel_sql = 'REN'
					THEN b.areal
					ELSE (SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_punkter', a.versions_id))
				END AS speciel
			FROM greg.f_dato_punkter($1, $2, $3) a
			LEFT JOIN spec_ren b ON a.arbejdssted = b.arbejdssted
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
			WHERE ue.speciel_sql IS NOT NULL
		),

		spec_one AS ( -- Select the sum of each special calculation grouped by each element and area code from the three queries above
			SELECT
				a.arbejdssted,
				a.underelement_kode,
				SUM(a.speciel) AS speciel
			FROM (
				SELECT * FROM spec_poly
				UNION ALL
				SELECT * FROM spec_line
				UNION ALL
				SELECT * FROM spec_point
			) a
			GROUP BY a.arbejdssted, a.underelement_kode
		),

		--
		-- Building the view
		--

		view_1 AS ( -- Select amounts of each feature type respectively for each element within each area code
			SELECT
				a.*,
				CASE
					WHEN ue.udregn_geometri IS TRUE
					THEN d.antal
					ELSE NULL
				END AS antal,
				CASE
					WHEN ue.udregn_geometri IS TRUE
					THEN c.laengde
					ELSE NULL
				END AS laengde,
				CASE
					WHEN ue.udregn_geometri IS TRUE
					THEN b.areal
					ELSE NULL
				END AS areal,
				e.speciel
			FROM base_elements a
			LEFT JOIN base_poly		b ON CASE
											WHEN a.arbejdssted IS NOT NULL
											THEN a.arbejdssted = b.arbejdssted AND a.underelement_kode = b.underelement_kode
											ELSE b.arbejdssted IS NULL AND a.underelement_kode = b.underelement_kode
										END
			LEFT JOIN base_line		c ON CASE
											WHEN a.arbejdssted IS NOT NULL
											THEN a.arbejdssted = c.arbejdssted AND a.underelement_kode = c.underelement_kode
											ELSE c.arbejdssted IS NULL AND a.underelement_kode = c.underelement_kode
										END
			LEFT JOIN base_point	d ON CASE
											WHEN a.arbejdssted IS NOT NULL
											THEN a.arbejdssted = d.arbejdssted AND a.underelement_kode = d.underelement_kode
											ELSE d.arbejdssted IS NULL AND a.underelement_kode = d.underelement_kode
										END
			LEFT JOIN spec_one		e ON CASE
											WHEN a.arbejdssted IS NOT NULL
											THEN a.arbejdssted = e.arbejdssted AND a.underelement_kode = e.underelement_kode
											ELSE e.arbejdssted IS NULL AND a.underelement_kode = e.underelement_kode
										END
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
		),

		view_2 AS ( -- Select full overview of all amounts including a total price for each element on each area code 
			SELECT
				a.arbejdssted,
				a.underelement_kode,
				a.antal,
				a.laengde,
				a.areal,
				a.speciel,
				CASE
					WHEN a.antal IS NOT NULL
					THEN (a.antal * ue.enhedspris_point * (SELECT * FROM pris_reg))::numeric(10,2)
					ELSE 0
				END +
				CASE
					WHEN a.laengde IS NOT NULL
					THEN (a.laengde * ue.enhedspris_line * (SELECT * FROM pris_reg))::numeric(10,2)
					ELSE 0
				END +
				CASE
					WHEN a.areal IS NOT NULL
					THEN (a.areal * ue.enhedspris_poly * (SELECT * FROM pris_reg))::numeric(10,2)
					ELSE 0
				END +
				CASE
					WHEN a.speciel IS NOT NULL
					THEN (a.speciel * ue.enhedspris_speciel * (SELECT * FROM pris_reg))::numeric(10,2)
					ELSE 0
				END AS pris
			FROM view_1 a
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
		)

	-- SELECT full overview with JOINS to look-up TABLES. Price is set to NULL if 0 for Excel purposes
	SELECT
		RIGHT('0' || $1, 2) || '-' || RIGHT('0' || $2, 2) || '-' || $3 AS udtraeksdato,
		dt.pg_distrikt_type,
		u.udfoerer,
		a.arbejdssted,
		CASE 
			WHEN a.arbejdssted IS NOT NULL
			THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
			ELSE 'Udenfor område'
		END AS omraade,
		he.hovedelement_kode,
		he.hovedelement_kode || ' - ' || he.hovedelement_tekst AS hovedelement,
		e.element_kode,
		e.element_kode || ' ' || e.element_tekst AS element,
		ue.underelement_kode,
		CASE
			WHEN ue.speciel_forklaring IS NOT NULL
			THEN ue.underelement_kode || ' ' || ue.underelement_tekst || ' (Speciel: ' || ue.speciel_forklaring || ')'
			ELSE ue.underelement_kode || ' ' || ue.underelement_tekst
			END AS underelement,
		a.antal,
		a.laengde::numeric(10,1),
		a.areal::numeric(10,1),
		a.speciel::numeric(10,1),
		CASE
			WHEN a.pris > 0
			THEN a.pris
		END AS pris
	FROM view_2 a
	LEFT JOIN (SELECT * FROM greg.f_dato_omraader($1, $2, $3)) om ON a.arbejdssted = om.pg_distrikt_nr
	LEFT JOIN basis.d_basis_distrikt_type dt ON om.pg_distrikt_type_kode = dt.pg_distrikt_type_kode
	LEFT JOIN basis.d_basis_udfoerer u ON om.udfoerer_kode = u.udfoerer_kode
	LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
	LEFT JOIN basis.e_basis_elementer e ON ue.element_kode = e.element_kode
	LEFT JOIN basis.e_basis_hovedelementer he ON e.hovedelement_kode = he.hovedelement_kode
	WHERE om.aktiv IS TRUE OR a.arbejdssted IS NULL
	ORDER BY pg_distrikt_nr, underelement_kode;

$$;

COMMENT ON FUNCTION greg.f_maengder(dag integer, maaned integer, aar integer) IS 'Funktion til simulering af mængdeoversigt på en bestemt dato. Format: dd-MM-yyyy.';

-- spec_calc(sql text, tabel text, versions_id uuid)

DROP FUNCTION IF EXISTS greg.spec_calc(sql text, tabel text, versions_id_ uuid);

CREATE FUNCTION greg.spec_calc(sql text, tabel text, version_id_ uuid)
	RETURNS TABLE (
		versions_id uuid,
		speciel numeric
	)
	LANGUAGE plpgsql AS
$$

	BEGIN

		RETURN QUERY EXECUTE format(
			'SELECT versions_id, (%s)::numeric AS speciel FROM %s WHERE versions_id = ''%s''', $1, $2, $3);

	END

$$;

COMMENT ON FUNCTION greg.spec_calc(sql text, tabel text, versions_id uuid) IS 'Funktion til udregning af dynamisk input i speciel kolonne fra e_basis_underelementer på rådata. Format: Input til udregning, tabel, versions_id';

-- variabel(var text)

DROP FUNCTION IF EXISTS greg.variabel(var text);

CREATE FUNCTION greg.variabel(var text)
	RETURNS TABLE (
		int_ integer,
		num_ numeric,
		text_ text
	)
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF $1 = 'omr_marg' THEN -- Margin for area boundaries. A margin of 0.90 means that 90% of the area / length of a geometry has to be inside the boundary

			RETURN QUERY 
				SELECT 
					NULL::integer,
					0.90,
					NULL::text;

		ELSIF $1 = 'his_time_var' THEN -- Time of day to query history functions

			RETURN QUERY 
				SELECT 
					NULL::integer,
					NULL::numeric,
					'23:59:59.999999'::text;

		ELSIF $1 = 'users' THEN -- Users without prefix in v_basis_bruger_id and not to be changed via v_basis_bruger_id

			RETURN QUERY 
				SELECT 
					NULL::integer,
					NULL::numeric,
					'postgres'::text; -- Comma seperated (No spaces)

		ELSIF $1 = 'num_days' THEN -- Number of days to register changes

			RETURN QUERY 
				SELECT 
					14,
					NULL::numeric,
					NULL::text;

		ELSIF $1 = 'picture' THEN -- Name (and path relative to project) of logo-file with extension included

			RETURN QUERY 
				SELECT 
					NULL::integer,
					NULL::numeric,
					'/Logos/logo.gif'::text;

		ELSIF $1 = 'composer' THEN -- Text for print composers

			RETURN QUERY 
				SELECT 
					NULL::integer,
					NULL::numeric,
					E'Frederikssund Kommune\nSmedetoften 4\n3600 Frederikssund'::text;

		ELSIF $1 = 'cvr' THEN -- Default value cvr_kode

			RETURN QUERY 
				SELECT 
					29189129::integer,
					NULL::numeric,
					NULL::text;

		ELSIF $1 = 'oprind' THEN -- Default value oprind_kode

			RETURN QUERY 
				SELECT 
					0::integer,
					NULL::numeric,
					NULL::text;

		ELSIF $1 = 'status' THEN -- Default value status_kode

			RETURN QUERY 
				SELECT 
					0::integer,
					NULL::numeric,
					NULL::text;

		ELSIF $1 = 'off_' THEN -- Default value off_kode

			RETURN QUERY 
				SELECT 
					1::integer,
					NULL::numeric,
					NULL::text;

		ELSIF $1 = 'tilstand' THEN -- Default value tilstand_kode

			RETURN QUERY 
				SELECT 
					9::integer,
					NULL::numeric,
					NULL::text;


/*		Insert above this line for other variables
		Copy until the line below
		ELSIF $1 = '' THEN -- #Comment

			RETURN QUERY 
				SELECT 
					NULL::integer,
					NULL::numeric,
					NULL::text;


		Copy from the line above for other variables*/

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.variabel(var text) IS 'Funktion til at fremkalde specifikke værdier, som slår igennem alle relevante steder i databasen og QGIS proejtk.';

-- Functions in schema styles --

-- hex_rgb(html text)

DROP FUNCTION IF EXISTS styles.hex_rgb(text);

CREATE FUNCTION styles.hex_rgb(text)
	RETURNS TABLE (
		rgb text
	)
	LANGUAGE plpgsql AS
$$

	DECLARE

		r_hex_1 text;
		r_hex_2 text;
		g_hex_1 text;
		g_hex_2 text;
		b_hex_1 text;
		b_hex_2 text;

		r_1 integer;
		r_2 integer;
		g_1 integer;
		g_2 integer;
		b_1 integer;
		b_2 integer;

	BEGIN

		SELECT substring($1 FROM 2 FOR 1) INTO r_hex_1;
		SELECT substring($1 FROM 3 FOR 1) INTO r_hex_2;
		SELECT substring($1 FROM 4 FOR 1) INTO g_hex_1;
		SELECT substring($1 FROM 5 FOR 1) INTO g_hex_2;
		SELECT substring($1 FROM 6 FOR 1) INTO b_hex_1;
		SELECT substring($1 FROM 7 FOR 1) INTO b_hex_2;

		SELECT a.rgb FROM styles.d_hex_rgb a WHERE hex = r_hex_1 INTO r_1;
		SELECT a.rgb FROM styles.d_hex_rgb a WHERE hex = r_hex_2 INTO r_2;
		SELECT a.rgb FROM styles.d_hex_rgb a WHERE hex = g_hex_1 INTO g_1;
		SELECT a.rgb FROM styles.d_hex_rgb a WHERE hex = g_hex_2 INTO g_2;
		SELECT a.rgb FROM styles.d_hex_rgb a WHERE hex = b_hex_1 INTO b_1;
		SELECT a.rgb FROM styles.d_hex_rgb a WHERE hex = b_hex_2 INTO b_2;

		RETURN QUERY
		SELECT
			(SELECT r_1 * 16 + r_2) || ',' ||
			(SELECT g_1 * 16 + g_2) || ',' ||
			(SELECT b_1 * 16 + b_2);

	END

$$;

COMMENT ON FUNCTION styles.hex_rgb(text) IS 'Funktion til konvertering fra hexadecimaler til RGB. Funktionen tager udgangspunkt i input fra QGIS, hvor koden har et nummertegn (#) foran koden.';

-- simple_style(niveau integer, kode text)

DROP FUNCTION IF EXISTS styles.simple_style(niveau integer, kode text);

CREATE FUNCTION styles.simple_style(niveau integer, kode text)
	RETURNS TABLE (
		point text,
		line text,
		poly text
	)
	LANGUAGE plpgsql AS
$$

	DECLARE

		_point_color text;
		_name text;
		_line_color text;
		_line_style text;
		_poly_color text;
		_style text;

		_point_rgb text;
		_line_rgb text;
		_poly_rgb text;

	BEGIN

		SELECT point_color	FROM styles.v_element_list a WHERE a.niveau = $1 AND a.kode = $2 INTO _point_color;
		SELECT name			FROM styles.v_element_list a WHERE a.niveau = $1 AND a.kode = $2 INTO _name;
		SELECT line_color	FROM styles.v_element_list a WHERE a.niveau = $1 AND a.kode = $2 INTO _line_color;
		SELECT line_style	FROM styles.v_element_list a WHERE a.niveau = $1 AND a.kode = $2 INTO _line_style;
		SELECT poly_color	FROM styles.v_element_list a WHERE a.niveau = $1 AND a.kode = $2 INTO _poly_color;
		SELECT style		FROM styles.v_element_list a WHERE a.niveau = $1 AND a.kode = $2 INTO _style;

		SELECT * FROM styles.hex_rgb(_point_color) INTO _point_rgb;
		SELECT * FROM styles.hex_rgb(_line_color) INTO _line_rgb;
		SELECT * FROM styles.hex_rgb(_poly_color) INTO _poly_rgb;

		RETURN QUERY
		SELECT
		E'      <symbol alpha="1" clip_to_extent="1" type="marker" name="0">\n'	||
		E'        <layer pass="0" class="SimpleMarker" locked="0">\n'			||
		E'          <prop k="angle" v="0"/>\n'									||
		 '          <prop k="color" v="'				|| (SELECT _point_rgb)	|| E',255"/>\n'	||
		E'          <prop k="horizontal_anchor_point" v="1"/>\n'				||
		E'          <prop k="joinstyle" v="bevel"/>\n'							||
		 '          <prop k="name" v="' 				|| (SELECT _name)		|| E'"/>\n'		||
		E'          <prop k="offset" v="0,0"/>\n'								||
		E'          <prop k="offset_map_unit_scale" v="0,0,0,0,0,0"/>\n'		||
		E'          <prop k="offset_unit" v="MM"/>\n'							||
		E'          <prop k="outline_color" v="0,0,0,255"/>\n'					||
		E'          <prop k="outline_style" v="solid"/>\n'						||
		E'          <prop k="outline_width" v="0"/>\n'							||
		E'          <prop k="outline_width_map_unit_scale" v="0,0,0,0,0,0"/>\n'	||
		E'          <prop k="outline_width_unit" v="MM"/>\n'					||
		E'          <prop k="scale_method" v="diameter"/>\n'					||
		E'          <prop k="size" v="2"/>\n'									||
		E'          <prop k="size_map_unit_scale" v="0,0,0,0,0,0"/>\n'			||
		E'          <prop k="size_unit" v="MM"/>\n'								||
		E'          <prop k="vertical_anchor_point" v="1"/>\n'					||
		E'        </layer>\n      </symbol>\n'
		AS point,		

		E'      <symbol alpha="1" clip_to_extent="1" type="line" name="0">\n'			||
		E'        <layer pass="0" class="SimpleLine" locked="0">\n'						||
		E'          <prop k="capstyle" v="square"/>\n'									||
		E'          <prop k="customdash" v="5;2"/>\n'									||
		E'          <prop k="customdash_map_unit_scale" v="0,0,0,0,0,0"/>\n'			||
		E'          <prop k="customdash_unit" v="MM"/>\n'								||
		E'          <prop k="draw_inside_polygon" v="0"/>\n'							||
		E'          <prop k="joinstyle" v="bevel"/>\n'									||
		 '          <prop k="line_color" v="'					|| (SELECT _line_rgb)	|| E',255"/>\n'	||
		 '          <prop k="line_style" v="'					|| (SELECT _line_style) || E'"/>\n'		||
		E'          <prop k="line_width" v="0.26"/>\n'									||
		E'          <prop k="line_width_unit" v="MM"/>\n'								||
		E'          <prop k="offset" v="0"/>\n'											||
		E'          <prop k="offset_map_unit_scale" v="0,0,0,0,0,0"/>\n'				||
		E'          <prop k="offset_unit" v="MM"/>\n'									||
		E'          <prop k="use_custom_dash" v="0"/>\n'								||
		E'          <prop k="width_map_unit_scale" v="0,0,0,0,0,0"/>\n'					||
		E'        </layer>\n      </symbol>\n'
		AS line,

		E'      <symbol alpha="1" clip_to_extent="1" type="fill" name="0">\n'		||
		E'        <layer pass="0" class="SimpleFill" locked="0">\n'						||
		E'          <prop k="border_width_map_unit_scale" v="0,0,0,0,0,0"/>\n'			||
		 '          <prop k="color" v="'						|| (SELECT _poly_rgb)	|| E',255"/>\n'	||
		E'          <prop k="joinstyle" v="bevel"/>\n'									||
		E'          <prop k="offset" v="0,0"/>\n'										||
		E'          <prop k="offset_map_unit_scale" v="0,0,0,0,0,0"/>\n'				||
		E'          <prop k="offset_unit" v="MM"/>\n'									||
		E'          <prop k="outline_color" v="0,0,0,255"/>\n'							||
		E'          <prop k="outline_style" v="solid"/>\n'								||
		E'          <prop k="outline_width" v="0.26"/>\n'								||
		E'          <prop k="outline_width_unit" v="MM"/>\n'							||
		 '          <prop k="style" v="'						|| (SELECT _style)		|| E'"/>\n'		||
		E'        </layer>\n      </symbol>\n'
		AS poly;

	END

$$;

COMMENT ON FUNCTION styles.simple_style(niveau integer, kode text) IS 'Funktion til at generere simple stilarter ud fra input fra e_basis-tabeller.';

--
-- CREATE TRIGGER FUNCTIONS
--

-- Trigger functions in schema greg --

-- basis_aktiv_trg()

CREATE FUNCTION basis.basis_aktiv_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		NEW.aktiv = COALESCE(NEW.aktiv, 't');

		RETURN NEW;

	END

$$;

COMMENT ON FUNCTION basis.basis_aktiv_trg() IS 'Tilføjer aktiv = TRUE som DEFAULT.';

-- d_basis_bruger_id_trg()

CREATE FUNCTION basis.d_basis_bruger_id_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	DECLARE

		db text;
		login text;

	BEGIN

		SELECT catalog_name FROM information_schema.information_schema_catalog_name INTO db;
		login := db || '_' || OLD.bruger_id;

		IF EXISTS (SELECT '1' FROM pg_catalog.pg_roles WHERE rolname = current_user AND rolsuper IS TRUE) OR EXISTS (SELECT '1' FROM basis.d_basis_bruger_id WHERE db || '_' || bruger_id = current_user AND rolle ='a') OR EXISTS (SELECT '1' FROM basis.d_basis_bruger_id WHERE login = current_user) THEN

			RETURN NEW;

		END IF;

		RAISE EXCEPTION 'Redigering af andre brugere er ikke tilladt';

	END

$$;

COMMENT ON FUNCTION basis.d_basis_bruger_id_trg() IS 'Tjekker tilladelse til at redigere i tabel';

-- e_basis_styles_trg()

CREATE FUNCTION basis.e_basis_styles_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		-- Style Manager
		-- Point
		NEW.point_color = COALESCE(NEW.point_color, '#000000');
		NEW.name = COALESCE(NEW.name, 'circle');		

		-- Line
		NEW.line_color = COALESCE(NEW.line_color, '#000000');
		NEW.line_style = COALESCE(NEW.line_style, 'solid');

		-- Polygon
		NEW.poly_color = COALESCE(NEW.poly_color, '#000000');
		NEW.style = COALESCE(NEW.style, 'solid');

		RETURN NEW;

	END

$$;

COMMENT ON FUNCTION basis.e_basis_styles_trg() IS 'Tilføjer DEAFULT stilarter for e_basis-tabeller.';

-- e_basis_hovedelementer_trg_a_iud()

CREATE FUNCTION basis.e_basis_hovedelementer_trg_a_iud()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			DELETE
				FROM styles.layer_styles
			WHERE stylename = OLD.hovedelement_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NEW.hovedelement_kode != OLD.hovedelement_kode THEN

				UPDATE styles.layer_styles
					SET
						stylename = NEW.hovedelement_kode,
						description = NEW.hovedelement_kode
				WHERE stylename = OLD.hovedelement_kode;

				RETURN NULL;

			END IF;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO styles.layer_styles (f_table_schema, f_table_name, f_geometry_column, stylename, description) VALUES ('greg', 'v_greg_flader', 'geometri', NEW.hovedelement_kode, NEW.hovedelement_kode);
			INSERT INTO styles.layer_styles (f_table_schema, f_table_name, f_geometry_column, stylename, description) VALUES ('greg', 'v_greg_linier', 'geometri', NEW.hovedelement_kode, NEW.hovedelement_kode);
			INSERT INTO styles.layer_styles (f_table_schema, f_table_name, f_geometry_column, stylename, description) VALUES ('greg', 'v_greg_punkter', 'geometri', NEW.hovedelement_kode, NEW.hovedelement_kode);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION basis.e_basis_hovedelementer_trg_a_iud() IS '';

-- e_basis_hovedelementer_trg_trunc()

CREATE FUNCTION basis.e_basis_hovedelementer_trg_trunc()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		DELETE
			FROM styles.layer_styles
		WHERE stylename IN (SELECT hovedelement_kode FROM basis.e_basis_hovedelementer);

		RETURN NULL;

	END

$$;

COMMENT ON FUNCTION basis.e_basis_hovedelementer_trg_trunc() IS '';

-- e_basis_underelementer_trg()

CREATE FUNCTION basis.e_basis_underelementer_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		-- Set DEFAULT table specific values (Updateable views)
		NEW.enhedspris_point = COALESCE(NEW.enhedspris_point, 0.00);
		NEW.enhedspris_line = COALESCE(NEW.enhedspris_line, 0.00);
		NEW.enhedspris_poly = COALESCE(NEW.enhedspris_poly, 0.00);
		NEW.enhedspris_speciel = COALESCE(NEW.enhedspris_speciel, 0.00);
		NEW.renhold = COALESCE(NEW.renhold, 'f');
		NEW.udregn_geometri = COALESCE(NEW.udregn_geometri, 't');
		NEW.aktiv = COALESCE(NEW.aktiv, 't');

		RETURN NEW;

	END

$$;

COMMENT ON FUNCTION basis.e_basis_underelementer_trg() IS 'Tilføjer DEAFULT VALUES, hvis ingen er angivet, da disse ikke angives automatisk via updateable views i QGIS.';

-- v_basis_bruger_id_trg()

CREATE FUNCTION basis.v_basis_bruger_id_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	DECLARE

		db text;
		role text;
		aktiv text;
		reader text;
		writer text;
		admin text;

	BEGIN

		SELECT catalog_name FROM information_schema.information_schema_catalog_name INTO db; -- Name of database

		IF (TG_OP = 'UPDATE') OR (TG_OP = 'INSERT') THEN

			NEW.bruger_id = lower(NEW.bruger_id);
			role := db || '_' || NEW.bruger_id;

			IF NEW.aktiv IS TRUE THEN -- If TRUE then user is able to login

				aktiv := 'LOGIN';

			ELSIF NEW.aktiv IS FALSE THEN -- If FALSE then user is not able to login

				aktiv := 'NOLOGIN';

			END IF;

		END IF;

		reader := db || '_reader';
		writer := db || '_writer';
		admin := db || '_admin';

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_bruger_id WHERE bruger_id = OLD.bruger_id) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM basis.d_basis_bruger_id
			WHERE bruger_id = OLD.bruger_id;

			role := db || '_' || OLD.bruger_id;

			EXECUTE format('DROP ROLE IF EXISTS %s', role); -- Drop role

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_bruger_id WHERE bruger_id = OLD.bruger_id) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			IF NEW.bruger_id != OLD.bruger_id THEN

				RAISE EXCEPTION 'Bruger ID kan ikke ændres. Hvis Bruger ID har været benyttet til registrering kan bruger gøres inaktiv ellers kan brugeren slettes og en ny oprettes';

			END IF;

			IF OLD.bruger_id = ANY(string_to_array((SELECT text_ FROM greg.variabel('users')), ',')) THEN

				RAISE EXCEPTION 'Brugeren "%" kan ikke ændres', OLD.bruger_id;

			END IF;

			IF EXISTS (SELECT '1' FROM pg_catalog.pg_roles WHERE rolname = current_user AND rolsuper IS TRUE) OR EXISTS (SELECT '1' FROM basis.v_basis_bruger_id WHERE login = current_user AND rolle ='a') THEN -- If user is superuser or DB Admin

				UPDATE basis.d_basis_bruger_id
					SET
						navn = NEW.navn,
						rolle = NEW.rolle,
						aktiv = NEW.aktiv
				WHERE bruger_id = OLD.bruger_id;			

				IF NEW.aktiv != OLD.aktiv THEN

					EXECUTE format('ALTER ROLE %s %s', role, aktiv); -- Change whether or not user can login based on boolean value in table

				END IF;

				IF NEW.password IS NOT NULL THEN

					EXECUTE format('ALTER ROLE %s WITH PASSWORD ''%s''', role, NEW.password); -- Change password if entered

				END IF;

				IF NEW.rolle != OLD.rolle THEN

					EXECUTE format('REVOKE %s FROM %s', reader, role); -- Clear role membership
					EXECUTE format('REVOKE %s FROM %s', writer, role); -- Clear role membership
					EXECUTE format('REVOKE %s FROM %s', admin, role); -- Clear role membership

					IF OLD.rolle = 'a' THEN -- If user was admin, but no longer is

						EXECUTE format('ALTER ROLE %s WITH NOCREATEROLE', role); -- Remove create role privileges

					ELSIF NEW.rolle = 'a' THEN -- If user has been made admin

						EXECUTE format('ALTER ROLE %s WITH CREATEROLE', role); -- Grant create role privileges
						EXECUTE format('GRANT %s to %s', admin, role); -- Grant role membership

					END IF;

					IF NEW.rolle = 'r' THEN -- If user has been made reader

						EXECUTE format('GRANT %s to %s', reader, role); -- Grant role membership

					ELSIF NEW.rolle = 'w' THEN -- If user has been made writer

						EXECUTE format('GRANT %s to %s', writer, role); -- Grant role membership

					END IF;

				END IF;

				RETURN NULL;

			END IF;

			IF OLD.login = current_user THEN -- Changeable settings for the actual non-admin user

				UPDATE basis.d_basis_bruger_id
					SET
						navn = NEW.navn
				WHERE bruger_id = OLD.bruger_id;

				IF NEW.password IS NOT NULL THEN

					EXECUTE format('ALTER ROLE %s WITH PASSWORD ''%s''', role, NEW.password); -- Change password if entered

				END IF;

			END IF;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			IF NEW.password IS NULL THEN

				RAISE EXCEPTION 'Password mangler';

			END IF;

			INSERT INTO basis.d_basis_bruger_id
				VALUES (
					NEW.bruger_id,
					NEW.navn,
					NEW.rolle,
					NEW.aktiv
			);

			IF NEW.rolle = 'r' THEN -- If user is reader

				EXECUTE format('CREATE ROLE %s %s PASSWORD ''%s'' NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION', role, aktiv, NEW.password); -- Create role
				EXECUTE format('GRANT %s to %s', reader, role); -- Grant role membership

			ELSIF NEW.rolle = 'w' THEN -- If user is writer

				EXECUTE format('CREATE ROLE %s %s PASSWORD ''%s'' NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION', role, aktiv, NEW.password); -- Create role
				EXECUTE format('GRANT %s to %s', writer, role); -- Grant role membership

			ELSIF NEW.rolle = 'a' THEN -- If user is admin

				EXECUTE format('CREATE ROLE %s %s PASSWORD ''%s'' NOSUPERUSER INHERIT NOCREATEDB CREATEROLE NOREPLICATION', role, aktiv, NEW.password); -- Create role with create role privileges
				EXECUTE format('GRANT %s to %s', admin, role); -- Grant role membership

			END IF;

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION basis.v_basis_bruger_id_trg() IS 'Muliggør opdatering gennem v_basis_bruger_id og opsætning af brugere i databasen.';

-- v_basis_kommunal_kontakt_trg()

CREATE FUNCTION basis.v_basis_kommunal_kontakt_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_kommunal_kontakt WHERE kommunal_kontakt_kode = OLD.kommunal_kontakt_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM basis.d_basis_kommunal_kontakt
			WHERE kommunal_kontakt_kode = OLD.kommunal_kontakt_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_kommunal_kontakt WHERE kommunal_kontakt_kode = OLD.kommunal_kontakt_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE basis.d_basis_kommunal_kontakt
				SET
					navn = NEW.navn,
					telefon = NEW.telefon,
					email = NEW.email,
					aktiv = NEW.aktiv
			WHERE kommunal_kontakt_kode = OLD.kommunal_kontakt_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO basis.d_basis_kommunal_kontakt (navn, telefon, email, aktiv)
				VALUES (
					NEW.navn,
					NEW.telefon,
					NEW.email,
					NEW.aktiv
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION basis.v_basis_kommunal_kontakt_trg() IS 'Muliggør opdatering gennem v_basis_kommunal_kontakt.';

-- v_basis_udfoerer_trg()

CREATE FUNCTION basis.v_basis_udfoerer_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_udfoerer WHERE udfoerer_kode = OLD.udfoerer_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM basis.d_basis_udfoerer
			WHERE udfoerer_kode = OLD.udfoerer_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_udfoerer WHERE udfoerer_kode = OLD.udfoerer_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE basis.d_basis_udfoerer
				SET
					udfoerer = NEW.udfoerer,
					aktiv = NEW.aktiv
			WHERE udfoerer_kode = OLD.udfoerer_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO basis.d_basis_udfoerer (udfoerer, aktiv)
				VALUES (
					NEW.udfoerer,
					NEW.aktiv
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION basis.v_basis_udfoerer_trg() IS 'Muliggør opdatering gennem v_basis_udfoerer.';

-- v_basis_udfoerer_entrep_trg()

CREATE FUNCTION basis.v_basis_udfoerer_entrep_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_udfoerer_entrep WHERE udfoerer_entrep_kode = OLD.udfoerer_entrep_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM basis.d_basis_udfoerer_entrep
			WHERE udfoerer_entrep_kode = OLD.udfoerer_entrep_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_udfoerer_entrep WHERE udfoerer_entrep_kode = OLD.udfoerer_entrep_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE basis.d_basis_udfoerer_entrep
				SET
					udfoerer_entrep = NEW.udfoerer_entrep,
					aktiv = NEW.aktiv
			WHERE udfoerer_entrep_kode = OLD.udfoerer_entrep_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO basis.d_basis_udfoerer_entrep (udfoerer_entrep, aktiv)
				VALUES (
					NEW.udfoerer_entrep,
					NEW.aktiv
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION basis.v_basis_udfoerer_entrep_trg() IS 'Muliggør opdatering gennem v_basis_udfoerer_entrep.';

-- v_basis_udfoerer_kontakt_trg()

CREATE FUNCTION basis.v_basis_udfoerer_kontakt_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_udfoerer_kontakt WHERE udfoerer_kontakt_kode = OLD.udfoerer_kontakt_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM basis.d_basis_udfoerer_kontakt
			WHERE udfoerer_kontakt_kode = OLD.udfoerer_kontakt_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_udfoerer_kontakt WHERE udfoerer_kontakt_kode = OLD.udfoerer_kontakt_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE basis.d_basis_udfoerer_kontakt
				SET
					udfoerer_kode = NEW.udfoerer_kode,
					navn = NEW.navn,
					telefon = NEW.telefon,
					email = NEW.email,
					aktiv = NEW.aktiv
			WHERE udfoerer_kontakt_kode = OLD.udfoerer_kontakt_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO basis.d_basis_udfoerer_kontakt (udfoerer_kode, navn, telefon, email, aktiv)
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

COMMENT ON FUNCTION basis.v_basis_udfoerer_kontakt_trg() IS 'Muliggør opdatering gennem v_basis_udfoerer_kontakt.';

-- v_basis_distrikt_type_trg()

CREATE FUNCTION basis.v_basis_distrikt_type_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_distrikt_type WHERE pg_distrikt_type_kode = OLD.pg_distrikt_type_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM basis.d_basis_distrikt_type
			WHERE pg_distrikt_type_kode = OLD.pg_distrikt_type_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_distrikt_type WHERE pg_distrikt_type_kode = OLD.pg_distrikt_type_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE basis.d_basis_distrikt_type
				SET
					pg_distrikt_type = NEW.pg_distrikt_type,
					aktiv = NEW.aktiv
			WHERE pg_distrikt_type_kode = OLD.pg_distrikt_type_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO basis.d_basis_distrikt_type (pg_distrikt_type, aktiv)
				VALUES (
					NEW.pg_distrikt_type,
					NEW.aktiv
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION basis.v_basis_distrikt_type_trg() IS 'Muliggør opdatering gennem v_basis_distrikt_type.';

-- v_basis_hovedelementer_trg()

CREATE FUNCTION basis.v_basis_hovedelementer_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.e_basis_hovedelementer WHERE hovedelement_kode = OLD.hovedelement_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM basis.e_basis_hovedelementer
			WHERE hovedelement_kode = OLD.hovedelement_kode;

			DELETE
				FROM styles.d_basis_element_lib
			WHERE niveau = 1 AND kode = OLD.hovedelement_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.e_basis_hovedelementer WHERE hovedelement_kode = OLD.hovedelement_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE basis.e_basis_hovedelementer
				SET
					hovedelement_kode = NEW.hovedelement_kode,
					hovedelement_tekst = NEW.hovedelement_tekst,
					aktiv = NEW.aktiv,
					-- Point	
					point_color = NEW.point_color,
					name = NEW.name,
					-- Line
					line_color = NEW.line_color,
					line_style = NEW.line_style,
					-- Polygon
					poly_color = NEW.poly_color,
					style = NEW.style
			WHERE hovedelement_kode = OLD.hovedelement_kode;

			IF OLD.hovedelement_kode != NEW.hovedelement_kode THEN -- If the code has changed

				UPDATE styles.d_basis_element_lib a
					SET kode = NEW.hovedelement_kode
				WHERE a.niveau = 1 AND a.kode = OLD.hovedelement_kode;

			END IF;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO basis.e_basis_hovedelementer
				VALUES (
					NEW.hovedelement_kode,
					NEW.hovedelement_tekst,
					NEW.aktiv,
					-- Point	
					NEW.point_color,
					NEW.name,
					-- Line
					NEW.line_color,
					NEW.line_style,
					-- Polygon
					NEW.poly_color,
					NEW.style
			);

			INSERT INTO styles.d_basis_element_lib
				VALUES (
					1,
					NEW.hovedelement_kode,
					NULL,
					NULL,
					NULL
			);

		END IF;

		IF NEW.p_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE styles.d_basis_element_lib a
				SET p_style = (SELECT
									b.p_style
								FROM styles.d_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.p_style_copy)
			WHERE a.niveau = 1 AND a.kode = NEW.hovedelement_kode;

		END IF;

		IF NEW.l_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE styles.d_basis_element_lib a
				SET l_style = (SELECT
									b.l_style
								FROM styles.d_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.l_style_copy)
			WHERE a.niveau = 1 AND a.kode = NEW.hovedelement_kode;

		END IF;

		IF NEW.f_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE styles.d_basis_element_lib a
				SET f_style = (SELECT
									b.f_style
								FROM styles.d_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.f_style_copy)
			WHERE a.niveau = 1 AND a.kode = NEW.hovedelement_kode;

		END IF;

		RETURN NULL;

	END

$$;

COMMENT ON FUNCTION basis.v_basis_hovedelementer_trg() IS 'Muliggør opdatering gennem v_basis_hovedelementer.';

-- v_basis_elementer_trg()

CREATE FUNCTION basis.v_basis_elementer_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.e_basis_elementer WHERE element_kode = OLD.element_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM basis.e_basis_elementer
			WHERE element_kode = OLD.element_kode;

			DELETE
				FROM styles.d_basis_element_lib
			WHERE niveau = 2 AND kode = OLD.element_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.e_basis_elementer WHERE element_kode = OLD.element_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE basis.e_basis_elementer
				SET
					hovedelement_kode = NEW.hovedelement_kode,
					element_kode = NEW.element_kode,
					element_tekst = NEW.element_tekst,
					aktiv = NEW.aktiv,
					-- Point	
					point_color = NEW.point_color,
					name = NEW.name,
					-- Line
					line_color = NEW.line_color,
					line_style = NEW.line_style,
					-- Polygon
					poly_color = NEW.poly_color,
					style = NEW.style
			WHERE element_kode = OLD.element_kode;

			IF OLD.element_kode != NEW.element_kode THEN -- If the code has changed

				UPDATE styles.d_basis_element_lib a
					SET kode = NEW.element_kode
				WHERE a.niveau = 2 AND a.kode = OLD.element_kode;

			END IF;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO basis.e_basis_elementer
				VALUES (
					NEW.hovedelement_kode,
					NEW.element_kode,
					NEW.element_tekst,
					NEW.aktiv,
					-- Point	
					NEW.point_color,
					NEW.name,
					-- Line
					NEW.line_color,
					NEW.line_style,
					-- Polygon
					NEW.poly_color,
					NEW.style
			);

			INSERT INTO styles.d_basis_element_lib
				VALUES (
					2,
					NEW.element_kode,
					NULL,
					NULL,
					NULL
			);

		END IF;

		IF NEW.p_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE styles.d_basis_element_lib a
				SET p_style = (SELECT
									b.p_style
								FROM styles.d_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.p_style_copy)
			WHERE a.niveau = 2 AND a.kode = NEW.element_kode;

		END IF;

		IF NEW.l_style_copy IS NOT NULL THEN -- Reuse already existing style
		
			UPDATE styles.d_basis_element_lib a
				SET l_style = (SELECT
									b.l_style
								FROM styles.d_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.l_style_copy)
			WHERE a.niveau = 2 AND a.kode = NEW.element_kode;

		END IF;

		IF NEW.f_style_copy IS NOT NULL THEN -- Reuse already existing style
		
			UPDATE styles.d_basis_element_lib a
				SET f_style = (SELECT
									b.f_style
								FROM styles.d_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.f_style_copy)
			WHERE a.niveau = 2 AND a.kode = NEW.element_kode;

		END IF;

		RETURN NULL;

	END

$$;

COMMENT ON FUNCTION basis.v_basis_elementer_trg() IS 'Muliggør opdatering gennem v_basis_elementer.';

-- v_basis_underelementer_trg()

CREATE FUNCTION basis.v_basis_underelementer_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.e_basis_underelementer WHERE underelement_kode = OLD.underelement_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM basis.e_basis_underelementer
			WHERE underelement_kode = OLD.underelement_kode;

			DELETE
				FROM styles.d_basis_element_lib
			WHERE niveau = 3 AND kode = OLD.underelement_kode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.e_basis_underelementer WHERE underelement_kode = OLD.underelement_kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE basis.e_basis_underelementer
				SET
					element_kode = NEW.element_kode,
					underelement_kode = NEW.underelement_kode,
					underelement_tekst = NEW.underelement_tekst,
					objekt_type = NEW.objekt_type,
					speciel_forklaring = NEW.speciel_forklaring,
					speciel_sql = NEW.speciel_sql,
					enhedspris_point = NEW.enhedspris_point,
					enhedspris_line = NEW.enhedspris_line,
					enhedspris_poly = NEW.enhedspris_poly,
					enhedspris_speciel = NEW.enhedspris_speciel,
					renhold = NEW.renhold,
					udregn_geometri = NEW.udregn_geometri,
					aktiv = NEW.aktiv,
					-- Point	
					point_color = NEW.point_color,
					name = NEW.name,
					-- Line
					line_color = NEW.line_color,
					line_style = NEW.line_style,
					-- Polygon
					poly_color = NEW.poly_color,
					style = NEW.style
			WHERE underelement_kode = OLD.underelement_kode;

			IF OLD.underelement_kode != NEW.underelement_kode THEN -- If the code has changed

				UPDATE styles.d_basis_element_lib a
					SET kode = NEW.underelement_kode
				WHERE a.niveau = 3 AND a.kode = OLD.underelement_kode;

			END IF;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO basis.e_basis_underelementer
				VALUES (
					NEW.element_kode,
					NEW.underelement_kode,
					NEW.underelement_tekst,
					NEW.objekt_type,
					NEW.speciel_forklaring,
					NEW.speciel_sql,
					NEW.enhedspris_point,
					NEW.enhedspris_line,
					NEW.enhedspris_poly,
					NEW.enhedspris_speciel,
					NEW.renhold,
					NEW.udregn_geometri,
					NEW.aktiv,
					-- Point	
					NEW.point_color,
					NEW.name,
					-- Line
					NEW.line_color,
					NEW.line_style,
					-- Polygon
					NEW.poly_color,
					NEW.style
			);

			INSERT INTO styles.d_basis_element_lib
				VALUES (
					3,
					NEW.underelement_kode,
					NULL,
					NULL,
					NULL
			);

		END IF;

		IF NEW.p_style_copy IS NOT NULL THEN -- Reuse already existing style
		
			UPDATE styles.d_basis_element_lib a
				SET p_style = (SELECT
									b.p_style
								FROM styles.d_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.p_style_copy)
			WHERE a.niveau = 3 AND a.kode = NEW.underelement_kode;

		END IF;

		IF NEW.l_style_copy IS NOT NULL THEN -- Reuse already existing style
		
			UPDATE styles.d_basis_element_lib a
				SET l_style = (SELECT
									b.l_style
								FROM styles.d_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.l_style_copy)
			WHERE a.niveau = 3 AND a.kode = NEW.underelement_kode;

		END IF;

		IF NEW.f_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE styles.d_basis_element_lib a
				SET f_style = (SELECT
									b.f_style
								FROM styles.d_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.f_style_copy)
			WHERE a.niveau = 3 AND a.kode = NEW.underelement_kode;

		END IF;

		RETURN NULL;

	END

$$;

COMMENT ON FUNCTION basis.v_basis_underelementer_trg() IS 'Muliggør opdatering gennem v_basis_underelementer.';

-- v_basis_prisregulering_trg()

CREATE FUNCTION basis.v_basis_prisregulering_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$
	
	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_prisregulering WHERE dato = OLD.dato) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM basis.d_basis_prisregulering
			WHERE dato = OLD.dato;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_prisregulering WHERE dato = OLD.dato) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE basis.d_basis_prisregulering
				SET
					dato = NEW.dato,
					aendring_pct = NEW.aendring_pct
			WHERE dato = OLD.dato;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO basis.d_basis_prisregulering
				VALUES (
					NEW.dato,
					NEW.aendring_pct
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION basis.v_basis_prisregulering_trg() IS 'Muliggør opdatering gennem v_basis_prisregulering.';

-- Trigger functions in schema greg --

-- t_greg_generel_trg()

CREATE FUNCTION greg.t_greg_generel_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF ((TG_OP = 'DELETE') OR (TG_OP = 'UPDATE')) AND OLD.systid_til IS NOT NULL THEN -- If record is a part of history

			RETURN NULL; -- Ignore action

		END IF;

		IF (TG_OP = 'DELETE') THEN

			RETURN OLD; -- Record is re-inserted with timestamp via AFTER-trigger

		ELSIF (TG_OP = 'UPDATE') THEN

			-- Updated feature
			NEW.versions_id = public.uuid_generate_v1(); -- UUID
			NEW.objekt_id = OLD.objekt_id; -- Overwrites potential changes from user
			NEW.oprettet = OLD.oprettet; -- Overwrites potential changes from user
			NEW.systid_fra = current_timestamp; -- Timestamp
			NEW.systid_til = NULL; -- Overwrites potential changes from user
			NEW.bruger_id_start = current_user; -- User responsible
			NEW.bruger_id_slut = NULL; -- Overwrites potential changes from user
			NEW.geometri = public.ST_Multi(NEW.geometri); -- Force geometry into multigeometry

			RETURN NEW; -- Original record is re-inserted with timestamp via AFTER-trigger

		ELSIF (TG_OP = 'INSERT') THEN

			IF NEW.systid_til = current_timestamp THEN -- Ignored if triggered via an UPDATE- / DELETE-action (AFTER-trigger)

				RETURN NEW;

			END IF;

			-- Automated values and geometry
			NEW.versions_id = public.uuid_generate_v1(); -- UUID
			NEW.objekt_id = NEW.versions_id; -- UUID as versions_id
			NEW.oprettet = current_timestamp; -- Timestamp
			NEW.systid_fra = NEW.oprettet; -- Timestamp as oprettet
			NEW.systid_til = NULL; -- Overwrites potential changes from user
			NEW.bruger_id_start = current_user; -- User responsible
			NEW.bruger_id_slut = NULL; -- Overwrites potential changes from user
			NEW.geometri = public.ST_Multi(NEW.geometri); -- Force geometry into multigeometry
			
			IF TG_TABLE_SCHEMA = 'greg' AND TG_TABLE_NAME IN('t_greg_flader', 't_greg_linier', 't_greg_punkter') THEN -- Table specific: t_greg_flader, t_greg_linier, t_greg_punkter

				-- Universal DEFAULT values
				NEW.cvr_kode = COALESCE(NEW.cvr_kode, 29189129);
				NEW.oprindkode = COALESCE(NEW.oprindkode, 0);
				NEW.statuskode = COALESCE(NEW.statuskode, 0);
				NEW.off_kode = COALESCE(NEW.off_kode, 1);
				NEW.tilstand_kode = COALESCE(NEW.tilstand_kode,9);

			END IF;

			RETURN NEW;

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.t_greg_generel_trg() IS 'Generelle informationer ved INSERT/UPDATE/DELETE for at opretholde historik, samt universelle DEFAULT values.';

-- t_greg_geometri_trg()

DROP FUNCTION IF EXISTS greg.t_greg_geometri_trg();

CREATE FUNCTION greg.t_greg_geometri_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	DECLARE

		boolean_var text;
		geom_var public.geometry('MultiPolygon',25832);

	BEGIN

		IF (TG_OP = 'UPDATE') THEN
		
			IF public.ST_EQUALS(NEW.geometri, OLD.geometri) IS FALSE THEN
			
				EXECUTE 'SELECT ''1'' FROM ' || TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME || ' WHERE public.ST_Contains(geometri, $1.geometri) IS TRUE AND systid_til IS NULL AND objekt_id != $1.objekt_id'
				USING NEW
				INTO boolean_var; -- Geometry check #1: NEW.geometry contained by an existing geometry

				IF boolean_var THEN -- If geometry check #1 is TRUE

					RAISE EXCEPTION 'Geometrien befinder sig i en anden geometri';

				END IF;

				EXECUTE 'SELECT ''1'' FROM ' || TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME || ' WHERE (public.ST_Overlaps($1.geometri, geometri) IS TRUE OR public.ST_Within(geometri, $1.geometri) IS TRUE) AND systid_til IS NULL AND objekt_id != $1.objekt_id'
				USING NEW
				INTO boolean_var; -- Geometry check #2: Overlaps and existing geometries contained by NEW.geometry'

				IF boolean_var THEN -- If geometry check #2 is TRUE

				EXECUTE 'SELECT public.ST_Multi(public.ST_CollectionExtract(public.ST_Difference($1.geometri, (SELECT public.ST_Union(geometri) FROM ' || TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME || ' WHERE (public.ST_Overlaps($1.geometri, geometri) IS TRUE OR public.ST_Within(geometri, $1.geometri) IS TRUE) AND systid_til IS NULL AND objekt_id != $1.objekt_id)), 3))'
				USING NEW
				INTO geom_var;
				
					IF public.ST_Area(geom_var)::numeric(20,6) != public.ST_Area(OLD.geometri)::numeric(20,6) THEN -- Due to QGIS reshape tool
		
						NEW.geometri = geom_var;
			
					END IF;
			
				END IF;
			
			END IF;
			
			RETURN NEW;
	
		ELSIF (TG_OP = 'INSERT') THEN
	
			IF NEW.systid_til = current_timestamp THEN -- Ignored if triggered via an UPDATE- / DELETE-action (via AFTER-trigger)

				RETURN NEW;

			END IF;

			EXECUTE 'SELECT ''1'' FROM ' || TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME || ' WHERE public.ST_Contains(geometri, $1.geometri) IS TRUE AND systid_til IS NULL'
			USING NEW
			INTO boolean_var; -- Geometry check #1: NEW.geometry contained by an existing geometry

			IF boolean_var THEN -- If geometry check #1 is TRUE

				RAISE EXCEPTION 'Geometrien befinder sig i en anden geometri';

			END IF;

			EXECUTE 'SELECT ''1'' FROM ' || TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME || ' WHERE (public.ST_Overlaps($1.geometri, geometri) IS TRUE OR public.ST_Within(geometri, $1.geometri) IS TRUE) AND systid_til IS NULL'
			USING NEW
			INTO boolean_var; -- Geometry check #2: Overlaps and existing geometries contained by NEW.geometry'

			IF boolean_var THEN -- If geometry check #2 is TRUE

				EXECUTE 'SELECT public.ST_Multi(public.ST_CollectionExtract(public.ST_Difference($1.geometri, (SELECT public.ST_Union(geometri) FROM ' || TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME || ' WHERE (public.ST_Overlaps($1.geometri, geometri) IS TRUE OR public.ST_Within(geometri, $1.geometri) IS TRUE) AND systid_til IS NULL)), 3))'
				USING NEW
				INTO NEW.geometri; -- Intersections with existing geometries are removed

			END IF;
			
			RETURN NEW;
		
		END IF;

	END;

$$;

COMMENT ON FUNCTION greg.t_greg_geometri_trg() IS 'Geometritjeks:
1) Geometrier må ikke befinde sig inde i andre geometrier.
2) Geometrier må ikke overlappe eksisterende geometrier - tilskæres automatisk.';

-- t_greg_flader_trg()

CREATE FUNCTION greg.t_greg_flader_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'UPDATE') THEN

			IF public.ST_EQUALS(NEW.geometri, OLD.geometri) IS FALSE THEN

				NEW.arbejdssted = 	(SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(NEW.geometri, b.geometri) IS TRUE
												THEN TRUE
												WHEN ST_Area(public.ST_Intersection(NEW.geometri, b.geometri)) / ST_Area(NEW.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
												THEN TRUE
											END
										AND b.systid_til IS NULL
									);

			END IF;

			RETURN NEW;

		ELSIF (TG_OP = 'INSERT') THEN

			IF NEW.systid_til = current_timestamp THEN -- Ignored if triggered via an UPDATE- / DELETE-action (via AFTER-trigger)

				RETURN NEW;

			END IF;

			-- Table specific DEFAULT values
			NEW.hoejde = COALESCE(NEW.hoejde, 0.0);
			NEW.klip_sider = COALESCE(NEW.klip_sider, 0);
			
			-- Automated evaluation of arbejdssted to be stored in the table itself
			NEW.arbejdssted = 	(SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(NEW.geometri, b.geometri) IS TRUE
												THEN TRUE
												WHEN ST_Area(public.ST_Intersection(NEW.geometri, b.geometri)) / ST_Area(NEW.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
												THEN TRUE
											END
										AND b.systid_til IS NULL
								);

			RETURN NEW;

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.t_greg_flader_trg() IS 'Tilføjer DEAFULT VALUES, hvis ingen er angivet, da disse ikke angives automatisk via updateable views i QGIS.';

-- t_greg_linier_trg()

CREATE FUNCTION greg.t_greg_linier_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'UPDATE') THEN

			IF public.ST_EQUALS(NEW.geometri, OLD.geometri) IS FALSE THEN

				NEW.arbejdssted = 	(SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(NEW.geometri, b.geometri) IS TRUE
												THEN TRUE
												WHEN ST_Length(public.ST_Intersection(NEW.geometri, b.geometri)) / ST_Length(NEW.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
												THEN TRUE
											END
										AND b.systid_til IS NULL
									);

			END IF;

			RETURN NEW;

		ELSIF (TG_OP = 'INSERT') THEN

			IF NEW.systid_til = current_timestamp THEN -- Ignored if triggered via an UPDATE- / DELETE-action (via AFTER-trigger)

				RETURN NEW;

			END IF;

			-- Table specific DEFAULT values
			NEW.bredde = COALESCE(NEW.bredde, 0.0);
			NEW.hoejde = COALESCE(NEW.hoejde, 0.0);
			
			-- Automated evaluation of arbejdssted to be stored in the table itself
			NEW.arbejdssted = 	(SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(NEW.geometri, b.geometri) IS TRUE
												THEN TRUE
												WHEN ST_Length(public.ST_Intersection(NEW.geometri, b.geometri)) / ST_Length(NEW.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
												THEN TRUE
											END
										AND b.systid_til IS NULL
								);

			RETURN NEW;

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.t_greg_linier_trg() IS 'Tilføjer DEAFULT VALUES, hvis ingen er angivet, da disse ikke angives automatisk via updateable views i QGIS.';

-- t_greg_punkter_trg()

CREATE FUNCTION greg.t_greg_punkter_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	DECLARE

		renhold text;
		renhold_old text;

	BEGIN

		SELECT speciel_sql INTO renhold FROM basis.e_basis_underelementer WHERE underelement_kode = NEW.underelement_kode;

		IF (TG_OP = 'UPDATE') THEN

			SELECT speciel_sql INTO renhold FROM basis.e_basis_underelementer WHERE underelement_kode = OLD.underelement_kode;

			IF public.ST_EQUALS(NEW.geometri, OLD.geometri) IS FALSE THEN

				NEW.arbejdssted = 	(SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(NEW.geometri, b.geometri) IS TRUE
												THEN TRUE
											END
										AND b.systid_til IS NULL
									);

			END IF;

			IF renhold != renhold_old AND renhold = 'REN' AND EXISTS (SELECT 
																		'1' 
																	FROM greg.t_greg_punkter a
																	LEFT JOIN basis.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
																	WHERE a.systid_til IS NULL AND b.speciel_sql = 'REN' AND a.arbejdssted = NEW.arbejdssted
																	) THEN -- If the area already contains an element defining 'REN'

				RAISE EXCEPTION 'Renhold er allerede defineret på det pågældende areal';

			END IF;

			RETURN NEW;

		ELSIF (TG_OP = 'INSERT') THEN

			IF NEW.systid_til = current_timestamp THEN -- Ignored if triggered via an UPDATE- / DELETE-action (via AFTER-trigger)

				RETURN NEW;

			END IF;

			-- Table specific DEFAULT values
			NEW.laengde = COALESCE(NEW.laengde, 0.0);
			NEW.bredde = COALESCE(NEW.bredde, 0.0);
			NEW.diameter = COALESCE(NEW.diameter, 0.0);
			NEW.hoejde = COALESCE(NEW.hoejde, 0.0);
			
			-- Automated evaluation of arbejdssted to be stored in the table itself
			NEW.arbejdssted = 	(SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(NEW.geometri, b.geometri) IS TRUE
												THEN TRUE
											END
										AND b.systid_til IS NULL
								);

			IF renhold = 'REN' AND EXISTS (SELECT 
												'1' 
											FROM greg.t_greg_punkter a
											LEFT JOIN basis.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
											WHERE a.systid_til IS NULL AND b.speciel_sql = 'REN' AND a.arbejdssted = NEW.arbejdssted
											) THEN -- If the area already contains an element defining 'REN'

				RAISE EXCEPTION 'Renhold er allerede defineret på det pågældende areal';

			END IF;

			RETURN NEW;

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.t_greg_punkter_trg() IS 'Tilføjer DEAFULT VALUES, hvis ingen er angivet, da disse ikke angives automatisk via updateable views i QGIS.';

-- t_greg_omraader_trg()

CREATE FUNCTION greg.t_greg_omraader_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'UPDATE') THEN

			IF OLD.pg_distrikt_nr != NEW.pg_distrikt_nr THEN

				INSERT INTO basis.d_basis_omraadenr -- Insertion into FK table (Indirect relation between areas and data). OLD record is deleted in AFTER-trigger.
					VALUES (
						NEW.pg_distrikt_nr
				);

			END IF;
			
			RETURN NEW;

		ELSIF (TG_OP = 'INSERT') THEN

			IF NEW.systid_til = current_timestamp THEN -- Ignored if triggered via an UPDATE- / DELETE-action (via AFTER-trigger)

				RETURN NEW;

			END IF;

			INSERT INTO basis.d_basis_omraadenr -- Insertion into FK table (Indirect relation between areas and data)
				VALUES (
					NEW.pg_distrikt_nr
			);

			-- Set DEFAULT table specific values (Updateable views)
			NEW.aktiv = COALESCE(NEW.aktiv, 't');
			NEW.synlig = COALESCE(NEW.synlig, 't');

			RETURN NEW;

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.t_greg_omraader_trg() IS 'Generelle informationer ved INSERT/UPDATE/DELETE for at opretholde historik, samt universelle DEFAULT values.';

-- t_greg_omraader_trg_a_iud()

CREATE FUNCTION greg.t_greg_omraader_trg_a_iud()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			UPDATE greg.t_greg_flader a -- Update t_greg_flader
				SET
					arbejdssted = (SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(a.geometri, b.geometri) IS TRUE
												THEN TRUE
												WHEN ST_Area(public.ST_Intersection(a.geometri, b.geometri)) / ST_Area(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
												THEN TRUE
											END
										AND b.systid_til IS NULL
									)
			WHERE	CASE 
						WHEN public.ST_Within(a.geometri, OLD.geometri) IS TRUE -- If the polygon was inside the boundary
						THEN TRUE
						WHEN ST_Area(public.ST_Intersection(a.geometri, OLD.geometri)) / ST_Area(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg')) -- If the polygon was up to x % inside the boundary
						THEN TRUE
					END
				AND a.systid_til IS NULL;

			UPDATE greg.t_greg_linier a -- Update t_greg_linier
				SET
					arbejdssted = (SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(a.geometri, b.geometri) IS TRUE
												THEN TRUE
												WHEN ST_Length(public.ST_Intersection(a.geometri, b.geometri)) / ST_Length(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
												THEN TRUE
											END
										AND b.systid_til IS NULL
									)
			WHERE	CASE 
						WHEN public.ST_Within(a.geometri, OLD.geometri) IS TRUE -- If the line was inside the boundary
						THEN TRUE
						WHEN ST_Length(public.ST_Intersection(a.geometri, OLD.geometri)) / ST_Length(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg')) -- If the line was up to x % inside the boundary
						THEN TRUE
					END
				AND a.systid_til IS NULL;

			UPDATE greg.t_greg_punkter a -- Update t_greg_punkter
				SET
					arbejdssted = (SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(a.geometri, b.geometri) IS TRUE
												THEN TRUE
											END
										AND b.systid_til IS NULL
									)
			WHERE	CASE 
						WHEN public.ST_Within(a.geometri, OLD.geometri) IS TRUE -- If the point was inside the new boundary
						THEN TRUE
					END
				AND a.systid_til IS NULL;
			
			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN
		
			IF public.ST_EQUALS(NEW.geometri, OLD.geometri) IS FALSE OR OLD.pg_distrikt_nr != NEW.pg_distrikt_nr THEN -- If geometry has been changed

				UPDATE greg.t_greg_flader a -- Update t_greg_flader
					SET
						arbejdssted = (SELECT
											b.pg_distrikt_nr
										FROM greg.t_greg_omraader b
										WHERE	CASE 
													WHEN public.ST_Within(a.geometri, b.geometri) IS TRUE
													THEN TRUE
													WHEN ST_Area(public.ST_Intersection(a.geometri, b.geometri)) / ST_Area(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
													THEN TRUE
												END
											AND b.systid_til IS NULL
										)
				WHERE	CASE 
							WHEN public.ST_Within(a.geometri, public.ST_Union(NEW.geometri, OLD.geometri)) IS TRUE -- If the polygon was inside the old boundary or is inside the new one
							THEN TRUE
							WHEN ST_Area(public.ST_Intersection(a.geometri, OLD.geometri)) / ST_Area(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg')) -- If the polygon was up to x % inside the old boundary
							THEN TRUE
							WHEN ST_Area(public.ST_Intersection(a.geometri, NEW.geometri)) / ST_Area(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg')) -- If the polygon is up to x % inside the new boundary
							THEN TRUE
						END
					AND a.systid_til IS NULL;

				UPDATE greg.t_greg_linier a -- Update t_greg_linier
					SET
						arbejdssted = (SELECT
											b.pg_distrikt_nr
										FROM greg.t_greg_omraader b
										WHERE	CASE 
													WHEN public.ST_Within(a.geometri, b.geometri) IS TRUE
													THEN TRUE
													WHEN ST_Length(public.ST_Intersection(a.geometri, b.geometri)) / ST_Length(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
													THEN TRUE
												END
										AND b.systid_til IS NULL
										)
				WHERE	CASE 
							WHEN public.ST_Within(a.geometri, public.ST_Union(NEW.geometri, OLD.geometri)) IS TRUE -- If the line was inside the old boundary or is inside the new one
							THEN TRUE
							WHEN ST_Length(public.ST_Intersection(a.geometri, OLD.geometri)) / ST_Length(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg')) -- If the line was up to x % inside the old boundary
							THEN TRUE
							WHEN ST_Length(public.ST_Intersection(a.geometri, NEW.geometri)) / ST_Length(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg')) -- If the line is up to x % inside the new boundary
							THEN TRUE
						END
					AND a.systid_til IS NULL;

				UPDATE greg.t_greg_punkter a -- Update t_greg_punkter
					SET
						arbejdssted = (SELECT
											b.pg_distrikt_nr
										FROM greg.t_greg_omraader b
										WHERE	CASE 
													WHEN public.ST_Within(a.geometri, b.geometri) IS TRUE
													THEN TRUE
												END
											AND b.systid_til IS NULL
										)
				WHERE	CASE 
							WHEN public.ST_Within(a.geometri, public.ST_Union(NEW.geometri, OLD.geometri)) IS TRUE -- If the point was inside the old boundary or is inside the new one
							THEN TRUE
						END
					AND a.systid_til IS NULL;

			END IF;
			
			RETURN NULL;
		
		ELSIF (TG_OP = 'INSERT') THEN
		
			IF NEW.systid_til = current_timestamp THEN -- Ignored if triggered via an UPDATE- / DELETE-action (via AFTER-trigger)

				RETURN NULL;

			END IF;
			
			UPDATE greg.t_greg_flader a -- Update t_greg_flader
				SET
					arbejdssted = (SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(a.geometri, b.geometri) IS TRUE
												THEN TRUE
												WHEN ST_Area(public.ST_Intersection(a.geometri, b.geometri)) / ST_Area(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
												THEN TRUE
											END
										AND b.systid_til IS NULL
									)
			WHERE	CASE 
						WHEN public.ST_Within(a.geometri, NEW.geometri) IS TRUE -- If the polygon is inside the boundary
						THEN TRUE
						WHEN ST_Area(public.ST_Intersection(a.geometri, NEW.geometri)) / ST_Area(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg')) -- If the polygon is up to x % inside the boundary
						THEN TRUE
					END
				AND a.systid_til IS NULL;

			UPDATE greg.t_greg_linier a -- Update t_greg_linier
				SET
					arbejdssted = (SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(a.geometri, b.geometri) IS TRUE
												THEN TRUE
												WHEN ST_Length(public.ST_Intersection(a.geometri, b.geometri)) / ST_Length(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
												THEN TRUE
											END
										AND b.systid_til IS NULL
									)
			WHERE	CASE 
						WHEN public.ST_Within(a.geometri, NEW.geometri) IS TRUE -- If the line is inside the boundary
						THEN TRUE
						WHEN ST_Length(public.ST_Intersection(a.geometri, NEW.geometri)) / ST_Length(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg')) -- If the line is up to x % inside the boundary
						THEN TRUE
					END
				AND a.systid_til IS NULL;

			UPDATE greg.t_greg_punkter a -- Update t_greg_punkter
				SET
					arbejdssted = (SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(a.geometri, b.geometri) IS TRUE
												THEN TRUE
											END
										AND b.systid_til IS NULL
									)
			WHERE	CASE 
						WHEN public.ST_Within(a.geometri, NEW.geometri) IS TRUE -- If the point is inside the new boundary
						THEN TRUE
					END
				AND a.systid_til IS NULL;
			
			RETURN NULL;
			
		END IF;

	END

$$;

COMMENT ON FUNCTION greg.t_greg_omraader_trg_a_iud() IS 'Opdaterer rådatatabeller.';

-- t_greg_omraader_trg_a_ud()

CREATE FUNCTION greg.t_greg_omraader_trg_a_ud()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			DELETE
				FROM greg.t_greg_delomraader
			WHERE pg_distrikt_nr = OLD.pg_distrikt_nr;	

			DELETE
				FROM basis.d_basis_omraadenr
			WHERE pg_distrikt_nr = OLD.pg_distrikt_nr;		

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF OLD.pg_distrikt_nr != NEW.pg_distrikt_nr THEN

				UPDATE greg.t_greg_delomraader
					SET
						pg_distrikt_nr = NEW.pg_distrikt_nr
				WHERE pg_distrikt_nr = OLD.pg_distrikt_nr;

				DELETE 
					FROM basis.d_basis_omraadenr
				WHERE pg_distrikt_nr = OLD.pg_distrikt_nr;

			END IF;

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.t_greg_omraader_trg_a_ud() IS 'Opdaterer rådata tabeller, samt delområder ved eventuelle ændringer af områdenumre.';

-- t_greg_historik_trg_a_ud()

CREATE FUNCTION greg.t_greg_historik_trg_a_ud()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		OLD.systid_til = current_timestamp;
		OLD.bruger_id_slut = current_user;
		EXECUTE format('INSERT INTO %s SELECT $1.*', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME)
		USING OLD;

		RETURN NULL;

	END

$$;

COMMENT ON FUNCTION greg.t_greg_historik_trg_a_ud() IS 'Indsætter den originale feature efter UPDATE / DELETE med påført systid_til.';

-- t_greg_delomraader_trg()

CREATE FUNCTION greg.t_greg_delomraader_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

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

	END

$$;

COMMENT ON FUNCTION greg.t_greg_delomraader_trg() IS 'Indsætter UUID, retter geometri til ST_Multi og retter bruger_id, hvis ikke angivet.';

-- v_greg_flader_trg()

CREATE FUNCTION greg.v_greg_flader_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

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
					-- Geometry
					geometri = NEW.geometri,
					-- FKG #1
					cvr_kode = NEW.cvr_kode,
					oprindkode = NEW.oprindkode,
					statuskode = NEW.statuskode,
					off_kode = NEW.off_kode,
					-- FKG #2
					note = NEW.note,
					link = NEW.link,
					vejkode = NEW.vejkode,
					tilstand_kode = NEW.tilstand_kode,
					anlaegsaar = NEW.anlaegsaar,
					udfoerer_entrep_kode = NEW.udfoerer_entrep_kode,
					kommunal_kontakt_kode = NEW.kommunal_kontakt_kode,
					-- FKG #3
					-- Arbejdssted is not updateable by user
					underelement_kode = NEW.underelement_kode,
					-- Measurements
					hoejde = NEW.hoejde,
					-- Table specific
					klip_sider = NEW.klip_sider,
					litra = NEW.litra
			WHERE versions_id = OLD.versions_id;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.t_greg_flader
				VALUES (
					-- Automated values
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					-- Geometry
					NEW.geometri,
					-- FKG #1
					NEW.cvr_kode,
					NEW.oprindkode,
					NEW.statuskode,
					NEW.off_kode,
					-- FKG #2
					NEW.note,
					NEW.link,
					NEW.vejkode,
					NEW.tilstand_kode,
					NEW.anlaegsaar,
					NEW.udfoerer_entrep_kode,
					NEW.kommunal_kontakt_kode,
					-- FKG #3
					NULL, -- Arbejdssted determined via trigger
					NEW.underelement_kode,
					-- Measurements
					NEW.hoejde,
					-- Table specific
					NEW.klip_sider,
					NEW.litra
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.v_greg_flader_trg() IS 'Muliggør opdatering gennem v_greg_flader.';

-- v_greg_linier_trg()

CREATE FUNCTION greg.v_greg_linier_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

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
					-- Geometry
					geometri = NEW.geometri,
					-- FKG #1
					cvr_kode = NEW.cvr_kode,
					oprindkode = NEW.oprindkode,
					statuskode = NEW.statuskode,
					off_kode = NEW.off_kode,
					-- FKG #2
					note = NEW.note,
					link = NEW.link,
					tilstand_kode = NEW.tilstand_kode,
					vejkode = NEW.vejkode,
					anlaegsaar = NEW.anlaegsaar,
					udfoerer_entrep_kode = NEW.udfoerer_entrep_kode,
					kommunal_kontakt_kode = NEW.kommunal_kontakt_kode,
					-- FKG #3
					-- Arbejdssted is not updateable by user
					underelement_kode = NEW.underelement_kode,
					-- Measurements
					bredde = NEW.bredde,
					hoejde = NEW.hoejde,
					-- Table specific
					litra = NEW.litra
			WHERE versions_id = OLD.versions_id;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.t_greg_linier
				VALUES (
					-- Automated values
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					-- Geometry
					NEW.geometri,
					-- FKG #1
					NEW.cvr_kode,
					NEW.oprindkode,
					NEW.statuskode,
					NEW.off_kode,
					-- FKG #2
					NEW.note,
					NEW.link,
					NEW.vejkode,
					NEW.tilstand_kode,
					NEW.anlaegsaar,
					NEW.udfoerer_entrep_kode,
					NEW.kommunal_kontakt_kode,
					-- FKG #3
					NULL, -- Arbejdssted determined via trigger
					NEW.underelement_kode,
					-- Measurements
					NEW.bredde,
					NEW.hoejde,
					-- Table specific
					NEW.litra
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.v_greg_linier_trg() IS 'Muliggør opdatering gennem v_greg_linier.';

-- v_greg_punkter_trg()

CREATE FUNCTION greg.v_greg_punkter_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

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
					-- Geometry
					geometri = NEW.geometri,
					-- FKG #1
					cvr_kode = NEW.cvr_kode,
					oprindkode = NEW.oprindkode,
					statuskode = NEW.statuskode,
					off_kode = NEW.off_kode,
					-- FKG #2
					note = NEW.note,
					link = NEW.link,
					vejkode = NEW.vejkode,
					tilstand_kode = NEW.tilstand_kode,
					anlaegsaar = NEW.anlaegsaar,
					udfoerer_entrep_kode = NEW.udfoerer_entrep_kode,
					kommunal_kontakt_kode = NEW.kommunal_kontakt_kode,
					-- FKG #3
					-- Arbejdssted is not updateable by user
					underelement_kode = NEW.underelement_kode,
					-- Measurements
					laengde = NEW.laengde,
					bredde = NEW.bredde,
					diameter = NEW.diameter,
					hoejde = NEW.hoejde,
					-- Table specific
					slaegt = NEW.slaegt,
					art = NEW.art,
					litra = NEW.litra
			WHERE versions_id = OLD.versions_id;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.t_greg_punkter
				VALUES (
					-- Automated values
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					-- Geometry
					NEW.geometri,
					-- FKG #1
					NEW.cvr_kode,
					NEW.oprindkode,
					NEW.statuskode,
					NEW.off_kode,
					-- FKG #2
					NEW.note,
					NEW.link,
					NEW.vejkode,
					NEW.tilstand_kode,
					NEW.anlaegsaar,
					NEW.udfoerer_entrep_kode,
					NEW.kommunal_kontakt_kode,
					-- FKG #3
					NULL, -- Arbejdssted determined via trigger
					NEW.underelement_kode,
					-- Measurements
					NEW.laengde,
					NEW.bredde,
					NEW.diameter,
					NEW.hoejde,
					-- Table specific
					NEW.slaegt,
					NEW.art,
					NEW.litra
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.v_greg_punkter_trg() IS 'Muliggør opdatering gennem v_greg_punkter';

-- v_greg_omraader_trg()

CREATE FUNCTION greg.v_greg_omraader_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.t_greg_omraader WHERE versions_id = OLD.versions_id) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM greg.t_greg_omraader
			WHERE versions_id = OLD.versions_id;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM greg.t_greg_omraader WHERE versions_id = OLD.versions_id) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE greg.t_greg_omraader
				SET
					-- Geometry
					geometri = NEW.geometri,
					-- FKG #1
					pg_distrikt_nr = NEW.pg_distrikt_nr,
					pg_distrikt_tekst = NEW.pg_distrikt_tekst,
					pg_distrikt_type_kode = NEW.pg_distrikt_type_kode,
					-- FKG #2
					note = NEW.note,
					link = NEW.link,
					vejkode = NEW.vejkode,
					vejnr = NEW.vejnr,
					postnr = NEW.postnr,
					udfoerer_kode = NEW.udfoerer_kode,
					udfoerer_kontakt_kode1 = NEW.udfoerer_kontakt_kode1,
					udfoerer_kontakt_kode2 = NEW.udfoerer_kontakt_kode2,
					kommunal_kontakt_kode = NEW.kommunal_kontakt_kode,
					-- Table specific
					aktiv = NEW.aktiv,
					synlig = NEW.synlig
			WHERE versions_id = OLD.versions_id;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO greg.t_greg_omraader
				VALUES (
					-- Automated values
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					-- Geometry
					NEW.geometri,
					-- FKG #1
					NEW.pg_distrikt_nr,
					NEW.pg_distrikt_tekst,
					NEW.pg_distrikt_type_kode,
					-- FKG #2
					NEW.note,
					NEW.link,
					NEW.vejkode,
					NEW.vejnr,
					NEW.postnr,
					NEW.udfoerer_kode,
					NEW.udfoerer_kontakt_kode1,
					NEW.udfoerer_kontakt_kode2,
					NEW.kommunal_kontakt_kode,
					-- Table specific
					NEW.aktiv,
					NEW.synlig
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.v_greg_omraader_trg() IS 'Muliggør opdatering gennem v_greg_omraader.';

-- Trigger functions in schema styles --

-- layer_styles_trg()

CREATE FUNCTION styles.layer_styles_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF NEW.stylename = 'DEFAULT' AND NEW.styleqml IS NOT NULL THEN -- DEFAULT will update all other styles, but HISTORIK

			UPDATE styles.layer_styles a
				SET
					styleqml = NEW.styleqml
			WHERE (a.stylename = 'HOVEDELEMENTER' OR ((a.stylename IN (SELECT hovedelement_kode FROM basis.e_basis_hovedelementer) OR a.stylename = 'ATLAS') AND a.styleqml IS NULL)) AND a.f_table_name = NEW.f_table_name;

			UPDATE styles.layer_styles a -- For all in e_basis_hovedelementer
				SET
					styleqml = (SELECT
									regexp_replace(regexp_replace(styleqml, '((.|\n)*)</edittypes>\n', substring(NEW.styleqml FROM '((.|\n)*) <renderer-v2')), ' <aliases>((.|\n)*)', substring(NEW.styleqml FROM '</annotationform>\n((.|\n)*)'))
								FROM styles.layer_styles b WHERE a.stylename = b.stylename AND b.f_table_name = NEW.f_table_name) -- Replace relevant parts of style file with new settings			
			WHERE a.stylename IN (SELECT hovedelement_kode FROM basis.e_basis_hovedelementer) AND a.f_table_name = NEW.f_table_name AND a.styleqml IS NOT NULL;

			UPDATE styles.layer_styles a -- For ATLAS
				SET
					styleqml = (SELECT
									regexp_replace(regexp_replace(styleqml, ' <edittypes>((.|\n)*)</edittypes>\n', ' <edittypes>' || substring(NEW.styleqml FROM ' <edittypes>((.|\n)*) <renderer-v2')), ' <aliases>((.|\n)*)', substring(NEW.styleqml FROM '</annotationform>\n((.|\n)*)'))
								FROM styles.layer_styles b WHERE a.stylename = b.stylename AND b.f_table_name = NEW.f_table_name) -- Replace relevant parts of style file with new settings			
			WHERE a.stylename = 'ATLAS' AND a.f_table_name = NEW.f_table_name AND a.styleqml IS NOT NULL;
			

		ELSIF NEW.stylename IN (SELECT hovedelement_kode FROM basis.e_basis_hovedelementer) THEN

			IF NEW.styleqml IS NULL THEN

				NEW.styleqml = (SELECT styleqml FROM public.layer_styles a WHERE a.f_table_name = NEW.f_table_name AND a.stylename = 'DEFAULT');

			END IF;

		END IF;

		IF NEW.stylename IN ('DEFAULT', 'HOVEDELEMENTER', 'ATLAS', 'HISTORIK') OR NEW.stylename IN (SELECT hovedelement_kode FROM basis.e_basis_hovedelementer) THEN
		
			NEW.description = NEW.stylename;
		
		END IF;
		
		IF NEW.stylename IN ('DEFAULT', 'HISTORIK') THEN
		
			NEW.useasdefault = TRUE;
		
		END IF;

		-- Set DEFAULT table specific values (Updateable views)
		NEW.f_table_catalog = (SELECT catalog_name FROM information_schema.information_schema_catalog_name);
		NEW.useasdefault = COALESCE(NEW.useasdefault, FALSE);
		NEW.stylesld = NULL;
		NEW.update_time = current_timestamp;

		RETURN NEW;

	END

$$;

COMMENT ON FUNCTION styles.layer_styles_trg() IS 'Administrerer layer_styles.';

-- v_layer_styles_trg()

CREATE FUNCTION styles.v_layer_styles_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM styles.layer_styles WHERE id = OLD.id) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM styles.layer_styles
			WHERE id = OLD.id AND (stylename NOT IN('DEFAULT', 'HOVEDELEMENTER', 'ATLAS', 'HISTORIK') OR stylename NOT IN(SELECT hovedelement_kode FROM basis.e_basis_hovedelementer));

			RETURN NULL;		

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM styles.layer_styles WHERE id = OLD.id) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE styles.layer_styles
				SET
					f_table_catalog = NEW.f_table_catalog,
					f_table_schema = NEW.f_table_schema,
					f_table_name = NEW.f_table_name,
					f_geometry_column = NEW.f_geometry_column,
					stylename = NEW.stylename,
					styleqml = NEW.styleqml,
					stylesld = NEW.stylesld,
					useasdefault = NEW.useasdefault,
					description = NEW.description,
					owner = NEW.owner,
					ui = NEW.ui,
					update_time = NEW.update_time
			WHERE id = OLD.id;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO styles.layer_styles (
				f_table_catalog,
				f_table_schema,
				f_table_name,
				f_geometry_column,
				stylename,
				styleqml,
				stylesld,
				useasdefault,
				description,
				owner,
				ui,
				update_time)
					VALUES (
						NEW.f_table_catalog,
						NEW.f_table_schema,
						NEW.f_table_name,
						NEW.f_geometry_column,
						NEW.stylename,
						NEW.styleqml,
						NEW.stylesld,
						NEW.useasdefault,
						NEW.description,
						NEW.owner,
						NEW.ui,
						NEW.update_time
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION styles.v_layer_styles_trg() IS 'Muligør opdatering af public.layer_styles.';

-- v_basis_element_lib_trg()

CREATE FUNCTION styles.v_basis_element_lib_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM styles.d_basis_element_lib WHERE niveau = OLD.niveau AND kode = OLD.kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM styles.d_basis_element_lib
			WHERE niveau = OLD.niveau AND kode = OLD.kode;

			RETURN NULL;		

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM styles.d_basis_element_lib WHERE niveau = OLD.niveau AND kode = OLD.kode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE styles.d_basis_element_lib
				SET
					niveau = NEW.niveau,
					kode = NEW.kode,
					p_style = NEW.p_style,
					l_style = NEW.l_style,
					f_style = NEW.f_style
			WHERE niveau = OLD.niveau AND kode = OLD.kode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO styles.d_basis_element_lib
				VALUES (
					NEW.niveau,
					NEW.kode,
					NEW.p_style,
					NEW.l_style,
					NEW.f_style
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION styles.v_basis_element_lib_trg() IS 'Muligør opdatering af v_basis_element_lib.';

--
-- CREATE TABLES
--

-- Tables in schema grunddata --

-- bygning

CREATE TABLE grunddata.bygning (
	id serial NOT NULL,
	geom public.geometry(MultiPolygon,25832),
	gml_id character varying(50),
	objektmeta character varying(100),
	arealkvali character varying(12),
	bbr_refere character varying(1),
	bbraktion character varying(18),
	bygning_id character varying(100),
	bygningsty character varying(12),
	fot_id character varying(12),
	fra_dato_f character varying(24),
	geometri_s character varying(9),
	kilde_id character varying(100),
	maalested_ character varying(12),
	metode_3d character varying(12),
	objekt_sta character varying(20),
	tank_silo_ character varying(13),
	til_dato_f character varying(24),
	under_mini character varying(1),
	under_mi_1 character varying(1),
	checksum character varying(16),
	checksum2 character varying(16),
	revdato character varying(24),
	mi_style character varying(254),
	mi_prinx bigint,
	CONSTRAINT bygning_pkey PRIMARY KEY (id) WITH (fillfactor='10')
);

-- bygraense

CREATE TABLE grunddata.bygraense (
	id serial NOT NULL,
	geom public.geometry(MultiPolygon,25832),
	webname character varying(50),
	navn character varying(50),
	mi_style character varying(254),
	mi_prinx bigint,
	CONSTRAINT bygraense_pkey PRIMARY KEY (id) WITH (fillfactor='10')
);

-- kommunale_veje

CREATE TABLE grunddata.kommunale_veje (
	id serial NOT NULL,
	geom public.geometry(MultiLineString,25832),
	vejnavn character varying(40),
	kommune_nr character varying(8),
	vejkode character varying(10),
	vejdel character varying(8),
	admvejnr character varying(10),
	cvf_vejkod character varying(10),
	vejkode_gl character varying(10),
	fra_stat_k bigint,
	til_stat_k bigint,
	frastation bigint,
	tilstation bigint,
	retning bigint,
	opr_initia character varying(8),
	oprind_dat date,
	mi_style character varying(254),
	mi_prinx bigint,
	CONSTRAINT kommunale_veje_pkey PRIMARY KEY (id) WITH (fillfactor='10')
);

-- kommunegraense

CREATE TABLE grunddata.kommunegraense (
	id serial NOT NULL,
	geom public.geometry(MultiPolygon,25832),
	qgs_fid bigint,
	ogr_fid bigint,
	komkode character varying(254),
	komnavn character varying(254),
	mi_style character varying(254),
	mi_prinx integer,
	CONSTRAINT kommunegraense_pkey PRIMARY KEY (id) WITH (fillfactor='10')
);

-- kyst

CREATE TABLE grunddata.kyst (
	id serial NOT NULL,
	geom public.geometry(MultiLineString,25832),
	ogr_fid bigint,
	objektmeta character varying(30),
	fot_id bigint,
	fra_dato_f character varying(24),
	geometri_s character varying(14),
	kilde_id character varying(5),
	objekt_sta character varying(25),
	under_mini bigint,
	checksum2 character varying(32),
	CONSTRAINT kyst_pkey PRIMARY KEY (id) WITH (fillfactor='10')
);

-- matrikelskel

CREATE TABLE grunddata.matrikelskel (
	id serial NOT NULL,
	geom public.geometry(MultiPolygon,25832),
	featureid bigint,
	landsejerl bigint,
	elavsnavn character varying(40),
	matrikelnu character varying(40),
	matrtal bigint,
	matrbogst character varying(10),
	faelleslod character varying(3),
	moderjords character varying(40),
	registrere numeric,
	vejareal numeric,
	arealtype character varying(15),
	kommunenr bigint,
	komnavn character varying(36),
	ejdnr character varying(10),
	oislink character varying(100),
	ejendomsnu bigint,
	kommunenum bigint,
	CONSTRAINT matrikelskel_pkey PRIMARY KEY (id) WITH (fillfactor='10')
);

-- privat_faellesveje

CREATE TABLE grunddata.privat_faellesveje (
	id serial NOT NULL,
	geom public.geometry(MultiLineString,25832),
	komnr character varying(8),
	vejkode_gl character varying(10),
	vejnavn character varying(40),
	vejdel character varying(8),
	frastat_ko bigint,
	tilstat_ko bigint,
	frastation bigint,
	tilstation bigint,
	notevd character varying(40),
	"længde_kor" bigint,
	"længde_vm" integer,
	stor_afv_p bigint,
	vejkode character varying(10),
	retning bigint,
	evt_cvf_ve character varying(10),
	dsfl_kode character varying(20),
	oprnr character varying(8),
	oprind_dat character varying(11),
	objekttype character varying(40),
	unikvejkod character varying(20),
	klasse bigint,
	admvejnr bigint,
	privatvej character varying(3),
	unikkode2 character varying(20),
	notegeogra character varying(100),
	fase character varying(2),
	placering_ character varying(25),
	mi_style character varying(254),
	mi_prinx bigint,
	CONSTRAINT privat_faellesveje_pkey PRIMARY KEY (id) WITH (fillfactor='10')
);

-- skov

CREATE TABLE grunddata.skov (
	id serial NOT NULL,
	geom public.geometry(MultiPolygon,25832),
	ogr_fid bigint,
	objektmeta character varying(30),
	anvendelse character varying(18),
	ejer_skov character varying(17),
	fot_id bigint,
	fra_dato_f character varying(24),
	geometri_s character varying(14),
	kilde_id character varying(5),
	objekt_sta character varying(25),
	under_mini bigint,
	checksum2 character varying(32),
	CONSTRAINT skov_pkey PRIMARY KEY (id) WITH (fillfactor='10')
);

-- soe

CREATE TABLE grunddata.soe (
	id serial NOT NULL,
	geom public.geometry(MultiPolygon,25832),
	ogr_fid bigint,
	objektmeta character varying(30),
	fot_id bigint,
	fra_dato_f character varying(24),
	geometri_s character varying(14),
	kilde_id character varying(5),
	objekt_sta character varying(25),
	oe_under_m bigint,
	salt_soe bigint,
	soe_under_ bigint,
	soetype character varying(17),
	temporaer bigint,
	checksum2 character varying(32),
	CONSTRAINT soe_pkey PRIMARY KEY (id) WITH (fillfactor='10')
);

-- vejkant

CREATE TABLE grunddata.vejkant (
	id serial NOT NULL,
	geom public.geometry(MultiLineString,25832),
	ogr_fid bigint,
	objektmeta character varying(30),
	fot_id bigint,
	fra_dato_f character varying(24),
	geometri_s character varying(14),
	kilde_id character varying(5),
	objekt_sta character varying(25),
	synlig_vej bigint,
	type character varying(23),
	checksum2 character varying(32),
	CONSTRAINT vejkant_pkey PRIMARY KEY (id) WITH (fillfactor='10')
);

-- Tables in schema basis --

-- d_basis_ansvarlig_myndighed

CREATE TABLE basis.d_basis_ansvarlig_myndighed (
	cvr_kode integer NOT NULL,
	cvr_navn character varying(128) NOT NULL,
	kommunekode integer,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_ansvarlig_myndighed_pk PRIMARY KEY (cvr_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_ansvarlig_myndighed IS 'Opslagstabel, ansvarlig myndighed for elementet (FKG).';

-- d_basis_bruger_id

CREATE TABLE basis.d_basis_bruger_id (
	bruger_id character varying(128) NOT NULL,
	navn character varying(128) NOT NULL,
	rolle character(1) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_bruger_id_pk PRIMARY KEY (bruger_id) WITH (fillfactor='10'),
	CONSTRAINT d_basis_rolle_ck CHECK (rolle IN('a', 'w', 'r'))
);

COMMENT ON TABLE basis.d_basis_bruger_id IS 'Opslagstabel, bruger ID for elementet (FKG).';

-- d_basis_kommunal_kontakt

CREATE TABLE basis.d_basis_kommunal_kontakt (
	kommunal_kontakt_kode serial NOT NULL,
	navn character varying(100) NOT NULL,
	telefon character(8) NOT NULL,
	email character varying(50) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_kommunal_kontakt_pk PRIMARY KEY (kommunal_kontakt_kode) WITH (fillfactor='10'),
	CONSTRAINT d_basis_kommunal_kontakt_ck_telefon CHECK (telefon ~* '[0-9]{8}')
);

COMMENT ON TABLE basis.d_basis_kommunal_kontakt IS 'Opslagstabel, kommunal kontakt for element / område (FKG).';

-- d_basis_status

CREATE TABLE basis.d_basis_status (
	statuskode integer NOT NULL,
	status character varying(30) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_status_pk PRIMARY KEY (statuskode) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_status IS 'Opslagstabel, gyldighedsstatus (FKG).';

-- d_basis_offentlig

CREATE TABLE basis.d_basis_offentlig (
	off_kode integer NOT NULL,
	offentlig character varying(60) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_offentlig_pk PRIMARY KEY (off_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_offentlig IS 'Opslagstabel, offentlighedsstatus (FKG).';

-- d_basis_oprindelse

CREATE TABLE basis.d_basis_oprindelse (
	oprindkode integer NOT NULL,
	oprindelse character varying(35) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	begrebsdefinition character varying,
	CONSTRAINT d_basis_oprindelse_pk PRIMARY KEY (oprindkode) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_oprindelse IS 'Opslagstabel, oprindelse (FKG).';

-- d_basis_tilstand

CREATE TABLE basis.d_basis_tilstand (
	tilstand_kode integer NOT NULL,
	tilstand character varying(25) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	begrebsdefinition character varying,
	CONSTRAINT d_basis_tilstand_pk PRIMARY KEY (tilstand_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_tilstand IS 'Opslagstabel, tilstand (FKG).';

-- d_basis_udfoerer

CREATE TABLE basis.d_basis_udfoerer (
	udfoerer_kode serial NOT NULL,
	udfoerer character varying(50) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_udfoerer_pk PRIMARY KEY (udfoerer_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_udfoerer IS 'Opslagstabel, ansvarlig udførende for entrepriseområde (FKG).';

-- d_basis_udfoerer_entrep

CREATE TABLE basis.d_basis_udfoerer_entrep (
	udfoerer_entrep_kode serial NOT NULL,
	udfoerer_entrep character varying(50) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_udfoerer_entrep_pk PRIMARY KEY (udfoerer_entrep_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_udfoerer_entrep IS 'Opslagstabel, ansvarlig udførerende entreprenør for element (FKG).';

-- d_basis_udfoerer_kontakt

CREATE TABLE basis.d_basis_udfoerer_kontakt (
	udfoerer_kode integer NOT NULL,
	udfoerer_kontakt_kode serial NOT NULL,
	navn character varying(100) NOT NULL,
	telefon character(8) NOT NULL,
	email character varying(50) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_udfoerer_kontakt_pk PRIMARY KEY (udfoerer_kontakt_kode) WITH (fillfactor='10'),
	CONSTRAINT d_basis_udfoerer_kontakt_fk_d_basis_udfoerer FOREIGN KEY (udfoerer_kode) REFERENCES basis.d_basis_udfoerer(udfoerer_kode) MATCH FULL
		ON UPDATE CASCADE,
	CONSTRAINT d_basis_udfoerer_kontakt_ck_telefon CHECK (telefon ~* '[0-9]{8}')
);

COMMENT ON TABLE basis.d_basis_udfoerer_kontakt IS 'Opslagstabel, kontaktinformationer på ansvarlig udførende (FKG).';

-- d_basis_postnr

CREATE TABLE basis.d_basis_postnr (
	postnr integer NOT NULL,
	postnr_by character varying(128) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_postnr_pk PRIMARY KEY (postnr) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_postnr IS 'Opslagstabel, postdistrikter (FKG).';

-- d_basis_vejnavn

CREATE TABLE basis.d_basis_vejnavn (
	vejkode integer NOT NULL,
	vejnavn character varying(40) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	cvf_vejkode character varying(7),
	postnr integer,
	kommunekode integer,
	CONSTRAINT d_basis_vejnavn_pk PRIMARY KEY (vejkode) WITH (fillfactor='10'),
	CONSTRAINT d_basis_vejnavn_fk_d_basis_postnr FOREIGN KEY (postnr) REFERENCES basis.d_basis_postnr(postnr) MATCH FULL
);

COMMENT ON TABLE basis.d_basis_vejnavn IS 'Opslagstabel, vejnavne (FKG).';

-- d_basis_distrikt_type

CREATE TABLE basis.d_basis_distrikt_type (
	pg_distrikt_type_kode serial NOT NULL,
	pg_distrikt_type character varying(30) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_distrikt_type_pk PRIMARY KEY (pg_distrikt_type_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_distrikt_type IS 'Opslagstabel, områdetyper. Fx grønne områder, skoler mv.';

-- d_basis_omraadenr

CREATE TABLE basis.d_basis_omraadenr (
	pg_distrikt_nr integer NOT NULL,
	CONSTRAINT d_basis_omraadenr_pk PRIMARY KEY (pg_distrikt_nr) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_omraadenr IS 'Indirekte relation mellem t_greg_omraader og hhv. (t_greg) flader, linier og punkter. Ellers er der problemer med merge i QGIS.';

-- e_basis_hovedelementer

CREATE TABLE basis.e_basis_hovedelementer (
	hovedelement_kode character varying(3) NOT NULL,
	hovedelement_tekst character varying(20) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	-- Style Manager
	-- Point
	point_color text DEFAULT '#000000',
	name text DEFAULT 'circle',
	-- Line
	line_color text DEFAULT '#000000',
	line_style text DEFAULT 'solid',
	-- Polygon
	poly_color text DEFAULT '#000000',
	style text DEFAULT 'solid',
	CONSTRAINT e_basis_hovedelementer_pk PRIMARY KEY (hovedelement_kode) WITH (fillfactor='10'),
	CONSTRAINT e_basis_hovedelementer_ck_name CHECK (name IN ('square', 'diamond', 'pentagon', 'hexagon', 'triangle', 'star', 'arrow', 'circle')),
	CONSTRAINT e_basis_hovedelementer_ck_line_style CHECK (line_style IN ('solid', 'dash', 'dot', 'dash dot', 'dash dot dot')),
	CONSTRAINT e_basis_hovedelementer_ck_style CHECK (style IN ('solid', 'horizontal', 'vertical', 'cross', 'b_diagonal', 'f_diagonal', 'diagonal_x', 'dense1', 'dense2', 'dense3', 'dense4', 'dense5', 'dense6', 'dense7'))
);

COMMENT ON TABLE basis.e_basis_hovedelementer IS 'Opslagstabel, den generelle elementtype. Fx græs, belægninger mv.';

-- e_basis_elementer

CREATE TABLE basis.e_basis_elementer (
	hovedelement_kode character varying(3) NOT NULL,
	element_kode character varying(6) NOT NULL,
	element_tekst character varying(30) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	-- Style Manager
	-- Point
	point_color text DEFAULT '#000000',
	name text DEFAULT 'circle',
	-- Line
	line_color text DEFAULT '#000000',
	line_style text DEFAULT 'solid',
	-- Polygon
	poly_color text DEFAULT '#000000',
	style text DEFAULT 'solid',
	CONSTRAINT e_basis_elementer_pk PRIMARY KEY (element_kode) WITH (fillfactor='10'),
	CONSTRAINT e_basis_elementer_fk_e_basis_hovedelementer FOREIGN KEY (hovedelement_kode) REFERENCES basis.e_basis_hovedelementer(hovedelement_kode) MATCH FULL,
	CONSTRAINT e_basis_elementer_ck_element_kode CHECK (element_kode ~* (hovedelement_kode || '-' || '[0-9]{2}')),
	CONSTRAINT e_basis_elementer_ck_name CHECK (name IN ('square', 'diamond', 'pentagon', 'hexagon', 'triangle', 'equilateral_triangle', 'star', 'arrow', 'circle')),
	CONSTRAINT e_basis_elementer_ck_line_style CHECK (line_style IN ('solid', 'dash', 'dot', 'dash dot', 'dash dot dot')),
	CONSTRAINT e_basis_elementer_ck_style CHECK (style IN ('solid', 'no', 'horizontal', 'vertical', 'cross', 'b_diagonal', 'f_diagonal', 'diagonal_x', 'dense1', 'dense2', 'dense3', 'dense4', 'dense5', 'dense6', 'dense7'))
);

COMMENT ON TABLE basis.e_basis_elementer IS 'Opslagstabel, den mere specifikke elementtype. Fx Faste belægninger, løse belægninger mv.';

-- e_basis_underelementer

CREATE TABLE basis.e_basis_underelementer (
	element_kode character varying(6) NOT NULL,
	underelement_kode character varying(9) NOT NULL,
	underelement_tekst character varying(30) NOT NULL,
	objekt_type character varying(3) NOT NULL,
	speciel_forklaring character varying(100),
	speciel_sql text,
	enhedspris_point numeric(10,2) DEFAULT 0.00 NOT NULL,
	enhedspris_line numeric(10,2) DEFAULT 0.00 NOT NULL,
	enhedspris_poly numeric(10,2) DEFAULT 0.00 NOT NULL,
	enhedspris_speciel numeric(10,2) DEFAULT 0.00 NOT NULL,
	renhold boolean DEFAULT FALSE NOT NULL,
	udregn_geometri boolean DEFAULT TRUE NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	-- Style Manager
	-- Point
	point_color text DEFAULT '#000000',
	name text DEFAULT 'circle',
	-- Line
	line_color text DEFAULT '#000000',
	line_style text DEFAULT 'solid',
	-- Polygon
	poly_color text DEFAULT '#000000',
	style text DEFAULT 'solid',
	-- Primary key
	CONSTRAINT e_basis_underelementer_pk PRIMARY KEY (underelement_kode) WITH (fillfactor='10'),
	-- Foreign keys
	CONSTRAINT e_basis_underelementer_fk_e_basis_elementer FOREIGN KEY (element_kode) REFERENCES basis.e_basis_elementer(element_kode) MATCH FULL,
	-- Check constraints
	-- enhedspris
	CONSTRAINT e_basis_underelementer_ck_enhedspris CHECK (enhedspris_point >= 0.0 AND enhedspris_line >= 0.0 AND enhedspris_poly >= 0.0 AND enhedspris_speciel >= 0.0), -- All prices positive or zero
	-- objekt_type
	CONSTRAINT e_basis_underelementer_ck_objekt_type CHECK (objekt_type ~* '(f|l|p)+'), -- Field should only contain the following letters: FLP
	CONSTRAINT e_basis_underelementer_ck_objekt_type_enhedspris_point CHECK (enhedspris_point = 0.00 OR objekt_type ILIKE '%P%'), -- Either the element is defined as a point or the point-price is zero
	CONSTRAINT e_basis_underelementer_ck_objekt_type_enhedspris_line CHECK (enhedspris_line = 0.00 OR objekt_type ILIKE '%L%'), -- Either the element is defined as a line or the line-price is zero
	CONSTRAINT e_basis_underelementer_ck_objekt_type_enhedspris_poly CHECK (enhedspris_poly = 0.00 OR objekt_type ILIKE '%F%'), -- Either the element is defined as a polygon or the polygon-price is zero
	-- underelement_kode
	CONSTRAINT e_basis_underelementer_ck_underelement_kode CHECK (underelement_kode ~* (element_kode || '-' || '[0-9]{2}')),
	-- speciel
	CONSTRAINT e_basis_underelementer_ck_speciel CHECK (speciel_sql IS NULL OR (speciel_sql IS NOT NULL AND speciel_forklaring IS NOT NULL)), -- If speciel_sql is defined then speciel_forklaring must have a value too
	CONSTRAINT e_basis_underelementer_ck_speciel_2 CHECK (objekt_type IN('F', 'L', 'P') OR speciel_sql IS NULL), -- Only speciel_sql if the element is defined as only point, line or polygon
	CONSTRAINT e_basis_underelementer_ck_speciel_3 CHECK (speciel_sql != 'REN' OR (objekt_type ILIKE 'P' AND speciel_forklaring ILIKE 'Renhold' AND enhedspris_point = 0.00)), -- If speciel_sql is 'REN' then objekt_type has to be point, speciel_forklaring has to be 'Renhold' and enhedspris_point has to be 0
	-- renhold
	CONSTRAINT e_basis_underelementer_ck_renhold CHECK (renhold IS FALSE OR objekt_type ILIKE '%F%'), -- Element must be defined as a polygon for renhold to be true
	-- Style Manager
	CONSTRAINT e_basis_underelementer_ck_name CHECK (name IN ('square', 'diamond', 'pentagon', 'hexagon', 'triangle', 'equilateral_triangle', 'star', 'arrow', 'circle')),
	CONSTRAINT e_basis_underelementer_ck_line_style CHECK (line_style IN ('solid', 'dash', 'dot', 'dash dot', 'dash dot dot')),
	CONSTRAINT e_basis_underelementer_ck_style CHECK (style IN ('solid', 'no', 'horizontal', 'vertical', 'cross', 'b_diagonal', 'f_diagonal', 'diagonal_x', 'dense1', 'dense2', 'dense3', 'dense4', 'dense5', 'dense6', 'dense7'))
);

COMMENT ON TABLE basis.e_basis_underelementer IS 'Opslagstabel, den helt specifikke elementtype. Fx beton, asfalt mv.';

-- d_basis_prisregulering

CREATE TABLE basis.d_basis_prisregulering (
	dato date NOT NULL,
	aendring_pct numeric(10,2),
	CONSTRAINT d_basis_prisregulering_pk PRIMARY KEY (dato) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_prisregulering IS 'Prisregulering af grundpriser i basis.e_basis_underelementer.';

-- Tables in schema greg --

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
	geometri public.geometry('MultiPolygon',25832) NOT NULL,
	-- FKG #1
	cvr_kode integer NOT NULL, -- DEFAULT value is set in greg.t_greg_default_trg()
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
	arbejdssted integer,
	underelement_kode character varying(9) NOT NULL,
	-- Measurements
	hoejde numeric(10,1) DEFAULT 0.0 NOT NULL,
	-- Table specific
	klip_sider integer DEFAULT 0 NOT NULL,
	litra character varying(128),
	-- Primary key
	CONSTRAINT t_greg_flader_pk PRIMARY KEY (versions_id) WITH (fillfactor='10'),
	-- Foreign keys
	-- Automated values
	CONSTRAINT t_greg_flader_fk_d_basis_bruger_id_start FOREIGN KEY (bruger_id_start) REFERENCES basis.d_basis_bruger_id(bruger_id) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_bruger_id_slut FOREIGN KEY (bruger_id_slut) REFERENCES basis.d_basis_bruger_id(bruger_id) MATCH FULL,	
	-- FKG #1
	CONSTRAINT t_greg_flader_fk_d_basis_ansvarlig_myndighed FOREIGN KEY (cvr_kode) REFERENCES basis.d_basis_ansvarlig_myndighed(cvr_kode) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_oprindelse FOREIGN KEY (oprindkode) REFERENCES basis.d_basis_oprindelse(oprindkode) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_status FOREIGN KEY (statuskode) REFERENCES basis.d_basis_status(statuskode) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_offentlig FOREIGN KEY (off_kode) REFERENCES basis.d_basis_offentlig(off_kode) MATCH FULL,
	-- FKG #2
	CONSTRAINT t_greg_flader_fk_d_basis_vejnavn FOREIGN KEY (vejkode) REFERENCES basis.d_basis_vejnavn(vejkode) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_tilstand FOREIGN KEY (tilstand_kode) REFERENCES basis.d_basis_tilstand(tilstand_kode) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_udfoerer_entrep FOREIGN KEY (udfoerer_entrep_kode) REFERENCES basis.d_basis_udfoerer_entrep(udfoerer_entrep_kode) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_d_basis_kommunal_kontakt FOREIGN KEY (kommunal_kontakt_kode) REFERENCES basis.d_basis_kommunal_kontakt(kommunal_kontakt_kode) MATCH FULL,
	-- FKG #3
	-- CONSTRAINT t_greg_flader_fk_d_basis_omraadenr FOREIGN KEY (arbejdssted) REFERENCES basis.d_basis_omraadenr(pg_distrikt_nr) MATCH FULL,
	CONSTRAINT t_greg_flader_fk_e_basis_underelementer FOREIGN KEY (underelement_kode) REFERENCES basis.e_basis_underelementer(underelement_kode) MATCH FULL,
	-- Check constraints
	CONSTRAINT t_greg_flader_ck_geometri CHECK (public.ST_IsValid(geometri) IS TRUE AND public.ST_IsEmpty(geometri) IS FALSE),
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
	geometri public.geometry('MultiLineString',25832) NOT NULL,
	-- FKG #1
	cvr_kode integer NOT NULL, -- DEFAULT value is set in greg.t_greg_default_trg()
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
	arbejdssted integer,
	underelement_kode character varying(9) NOT NULL,
	-- Measurements
	bredde numeric(10,1) DEFAULT 0.0 NOT NULL,
	hoejde numeric(10,1) DEFAULT 0.0 NOT NULL,
	-- Table specific
	litra character varying(128),
	-- Primary key
	CONSTRAINT t_greg_linier_pk PRIMARY KEY (versions_id) WITH (fillfactor='10'),
	-- Foreign keys
	-- Automated values
	CONSTRAINT t_greg_linier_fk_d_basis_bruger_id_start FOREIGN KEY (bruger_id_start) REFERENCES basis.d_basis_bruger_id(bruger_id) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_bruger_id_slut FOREIGN KEY (bruger_id_slut) REFERENCES basis.d_basis_bruger_id(bruger_id) MATCH FULL,
	-- FKG #1
	CONSTRAINT t_greg_linier_fk_d_basis_ansvarlig_myndighed FOREIGN KEY (cvr_kode) REFERENCES basis.d_basis_ansvarlig_myndighed(cvr_kode) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_oprindelse FOREIGN KEY (oprindkode) REFERENCES basis.d_basis_oprindelse(oprindkode) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_status FOREIGN KEY (statuskode) REFERENCES basis.d_basis_status(statuskode) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_offentlig FOREIGN KEY (off_kode) REFERENCES basis.d_basis_offentlig(off_kode) MATCH FULL,
	-- FKG #2
	CONSTRAINT t_greg_linier_fk_d_basis_vejnavn FOREIGN KEY (vejkode) REFERENCES basis.d_basis_vejnavn(vejkode) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_tilstand FOREIGN KEY (tilstand_kode) REFERENCES basis.d_basis_tilstand(tilstand_kode) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_udfoerer_entrep FOREIGN KEY (udfoerer_entrep_kode) REFERENCES basis.d_basis_udfoerer_entrep(udfoerer_entrep_kode) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_d_basis_kommunal_kontakt FOREIGN KEY (kommunal_kontakt_kode) REFERENCES basis.d_basis_kommunal_kontakt(kommunal_kontakt_kode) MATCH FULL,
	-- FKG #3
	-- CONSTRAINT t_greg_linier_fk_d_basis_omraadenr FOREIGN KEY (arbejdssted) REFERENCES basis.d_basis_omraadenr(pg_distrikt_nr) MATCH FULL,
	CONSTRAINT t_greg_linier_fk_e_basis_underelementer FOREIGN KEY (underelement_kode) REFERENCES basis.e_basis_underelementer(underelement_kode) MATCH FULL,
	-- Check constraints
	CONSTRAINT t_greg_linier_ck_valid CHECK (public.ST_IsValid(geometri) IS TRUE),
	CONSTRAINT t_greg_linier_ck_maal CHECK (bredde BETWEEN 0.00 AND 9.99 AND hoejde BETWEEN 0.00 AND 9.99)
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
	geometri public.geometry('MultiPoint',25832) NOT NULL,
	-- FKG #1
	cvr_kode integer NOT NULL, -- DEFAULT value is set in greg.t_greg_default_trg()
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
	arbejdssted integer,
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
	-- Primary key
	CONSTRAINT t_greg_punkter_pk PRIMARY KEY (versions_id) WITH (fillfactor='10'),
	-- Foreign keys
	-- Automated values
	CONSTRAINT t_greg_punkter_fk_d_basis_bruger_id_start FOREIGN KEY (bruger_id_start) REFERENCES basis.d_basis_bruger_id(bruger_id) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_bruger_id_slut FOREIGN KEY (bruger_id_slut) REFERENCES basis.d_basis_bruger_id(bruger_id) MATCH FULL,
	-- FKG #1
	CONSTRAINT t_greg_punkter_fk_d_basis_ansvarlig_myndighed FOREIGN KEY (cvr_kode) REFERENCES basis.d_basis_ansvarlig_myndighed(cvr_kode) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_oprindelse FOREIGN KEY (oprindkode) REFERENCES basis.d_basis_oprindelse(oprindkode) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_status FOREIGN KEY (statuskode) REFERENCES basis.d_basis_status(statuskode) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_offentlig FOREIGN KEY (off_kode) REFERENCES basis.d_basis_offentlig(off_kode) MATCH FULL,
	-- FKG #2
	CONSTRAINT t_greg_punkter_fk_d_basis_vejnavn FOREIGN KEY (vejkode) REFERENCES basis.d_basis_vejnavn(vejkode) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_tilstand FOREIGN KEY (tilstand_kode) REFERENCES basis.d_basis_tilstand(tilstand_kode) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_udfoerer_entrep FOREIGN KEY (udfoerer_entrep_kode) REFERENCES basis.d_basis_udfoerer_entrep(udfoerer_entrep_kode) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_d_basis_kommunal_kontakt FOREIGN KEY (kommunal_kontakt_kode) REFERENCES basis.d_basis_kommunal_kontakt(kommunal_kontakt_kode) MATCH FULL,
	-- FKG #3
	-- CONSTRAINT t_greg_punkter_fk_d_basis_omraadenr FOREIGN KEY (arbejdssted) REFERENCES basis.d_basis_omraadenr(pg_distrikt_nr) MATCH FULL,
	CONSTRAINT t_greg_punkter_fk_e_basis_underelementer FOREIGN KEY (underelement_kode) REFERENCES basis.e_basis_underelementer(underelement_kode) MATCH FULL,
	-- Check constraints
	CONSTRAINT t_greg_punkter_ck_maal CHECK ((laengde = 0.00 AND bredde = 0.00 AND diameter >= 0.00) OR (laengde >= 0.00 AND bredde >= 0.00 AND diameter = 0.00)),
	CONSTRAINT t_greg_punkter_ck_hoejde CHECK (hoejde >= 0.00)
);

COMMENT ON TABLE greg.t_greg_punkter IS 'Rådatatabel for elementer defineret som punkter. Indeholder både aktuel og historikdata.';

-- t_greg_omraader

CREATE TABLE greg.t_greg_omraader (
	-- Automated values
	versions_id uuid NOT NULL,
	objekt_id uuid NOT NULL,
	oprettet timestamp with time zone NOT NULL,
	systid_fra timestamp with time zone NOT NULL,
	systid_til timestamp with time zone,
	bruger_id_start character varying(128) NOT NULL,
	bruger_id_slut character varying(128),
	-- Geometry
	geometri public.geometry('MultiPolygon',25832),
	-- FKG #1
	pg_distrikt_nr integer NOT NULL,
	pg_distrikt_tekst character varying(150) NOT NULL,
	pg_distrikt_type_kode integer NOT NULL,
	-- FKG #2
	note character varying(254),
	link character varying(1024),
	vejkode integer,
	vejnr character varying(20),
	postnr integer NOT NULL,
	udfoerer_kode integer,
	udfoerer_kontakt_kode1 integer,
	udfoerer_kontakt_kode2 integer,
	kommunal_kontakt_kode integer,
	-- Table specific
	aktiv boolean DEFAULT TRUE NOT NULL,
	synlig boolean DEFAULT TRUE NOT NULL,
	-- Primary key
	CONSTRAINT t_greg_omraader_pk PRIMARY KEY (versions_id) WITH (fillfactor='10'),
	-- Foreign keys
	-- Automated values
	CONSTRAINT t_greg_omraader_fk_d_basis_bruger_id_start FOREIGN KEY (bruger_id_start) REFERENCES basis.d_basis_bruger_id(bruger_id) MATCH FULL,
	CONSTRAINT t_greg_omraader_fk_d_basis_bruger_id_slut FOREIGN KEY (bruger_id_slut) REFERENCES basis.d_basis_bruger_id(bruger_id) MATCH FULL,
	-- FKG #1
	CONSTRAINT t_greg_omraader_fk_d_basis_distrikt_type FOREIGN KEY (pg_distrikt_type_kode) REFERENCES basis.d_basis_distrikt_type(pg_distrikt_type_kode) MATCH FULL,
	-- FKG #2
	CONSTRAINT t_greg_omraader_fk_d_basis_vejnavn FOREIGN KEY (vejkode) REFERENCES basis.d_basis_vejnavn(vejkode) MATCH FULL,
	CONSTRAINT t_greg_omraader_fk_d_basis_postnr FOREIGN KEY (postnr) REFERENCES basis.d_basis_postnr(postnr) MATCH FULL,
	CONSTRAINT t_greg_omraader_fk_d_basis_udfoerer FOREIGN KEY (udfoerer_kode) REFERENCES basis.d_basis_udfoerer(udfoerer_kode) MATCH FULL,
	CONSTRAINT t_greg_omraader_fk_d_basis_udfoerer_kontakt1 FOREIGN KEY (udfoerer_kontakt_kode1) REFERENCES basis.d_basis_udfoerer_kontakt(udfoerer_kontakt_kode) MATCH FULL,
	CONSTRAINT t_greg_omraader_fk_d_basis_udfoerer_kontakt2 FOREIGN KEY (udfoerer_kontakt_kode2) REFERENCES basis.d_basis_udfoerer_kontakt(udfoerer_kontakt_kode) MATCH FULL,
	CONSTRAINT t_greg_omraader_fk_d_basis_kommunal_kontakt FOREIGN KEY (kommunal_kontakt_kode) REFERENCES basis.d_basis_kommunal_kontakt(kommunal_kontakt_kode) MATCH FULL,
	-- Check constraints
	CONSTRAINT t_greg_omraader_ck_geometri CHECK ((public.ST_IsValid(geometri) IS TRUE OR public.ST_IsValid(geometri) IS NULL) AND (public.ST_IsEmpty(geometri) IS FALSE OR public.ST_IsEmpty(geometri) IS NULL))
);

COMMENT ON TABLE greg.t_greg_omraader IS 'Områdetabel.';

-- t_greg_delomraader

CREATE TABLE greg.t_greg_delomraader (
	objekt_id uuid NOT NULL,
	geometri public.geometry('MultiPolygon',25832) NOT NULL,
	pg_distrikt_nr integer NOT NULL,
	delnavn character varying(150) NOT NULL,
	CONSTRAINT t_greg_delomraader_pk PRIMARY KEY (objekt_id) WITH (fillfactor='10')
);

COMMENT ON TABLE greg.t_greg_delomraader IS 'Specifikke områdeopdelinger i tilfælde af for store områder mht. atlas i QGIS.';

-- Tables in schema styles --

-- d_tables

CREATE TABLE styles.d_tables (
	f_table_name text NOT NULL,
	geometry_type text NOT NULL,
	CONSTRAINT d_tables_pk PRIMARY KEY (f_table_name) WITH (fillfactor='10')
);

COMMENT ON TABLE styles.d_tables IS 'Registreringstabellerne er deres geometritype for nem look-up.';

-- d_not_categorized

CREATE TABLE styles.d_not_categorized (
	f_table_name text NOT NULL,
	style text NOT NULL,
	CONSTRAINT d_not_categorized_pk PRIMARY KEY (f_table_name) WITH (fillfactor='10')
	
);

COMMENT ON TABLE styles.d_not_categorized IS 'Stilart for ''Ikke klassificeret''.';

-- d_basis_element_lib

CREATE TABLE styles.d_basis_element_lib (
	niveau integer NOT NULL	,
	kode text NOT NULL,
	p_style text,
	l_style text,
	f_style text,
	CONSTRAINT d_basis_element_lib_pk PRIMARY KEY (niveau, kode) WITH (fillfactor='10')
);

COMMENT ON TABLE styles.d_basis_element_lib IS 'Bibliotek over stilarter for elementer. Overskriver de simple stilarter i elementtabellerne.';

-- d_hex_rgb

CREATE TABLE styles.d_hex_rgb (
	hex character(1) NOT NULL,
	rgb integer NOT NULL,
	CONSTRAINT d_hex_rgb_pk PRIMARY KEY (hex) WITH (fillfactor='10')
);

COMMENT ON TABLE styles.d_hex_rgb IS 'Konvertering af hexadecimaler til værdier for udregning af RGB-kode.';

-- layer_styles

CREATE TABLE styles.layer_styles (
	id serial NOT NULL,
	f_table_catalog character varying,
	f_table_schema character varying,
	f_table_name character varying,
	f_geometry_column character varying,
	stylename character varying(30),
	styleqml text,
	stylesld text,
	useasdefault boolean,
	description text,
	owner character varying(30),
	ui text,
	update_time timestamp with time zone,
	CONSTRAINT layer_styles_pk PRIMARY KEY (id) WITH (fillfactor='10')
);

COMMENT ON TABLE styles.d_hex_rgb IS 'Stilarter til QGIS.';

--
-- CREATE VIEWS
--



-- v_basis_ansvarlig_myndighed

CREATE VIEW basis.v_basis_ansvarlig_myndighed AS

SELECT
	cvr_kode,
	cvr_navn,
	CASE
		WHEN kommunekode IS NOT NULL
		THEN cvr_navn || ' (' || kommunekode || ')'
		ELSE cvr_navn
	END AS myndighed
FROM basis.d_basis_ansvarlig_myndighed
WHERE aktiv IS TRUE;

COMMENT ON VIEW basis.v_basis_ansvarlig_myndighed IS 'Look-up for d_basis_ansvarlig_myndighed.';

-- v_basis_bruger_id

CREATE VIEW basis.v_basis_bruger_id AS

SELECT
	CASE
		WHEN CASE
				WHEN bruger_id != ALL(string_to_array((SELECT text_ FROM greg.variabel('users')), ','))
				THEN (SELECT catalog_name FROM information_schema.information_schema_catalog_name) || '_' || bruger_id
				ELSE bruger_id
			END = current_user
		THEN 'Du er logget ind som:'
		ELSE NULL
	END AS aktiv_bruger,
	CASE
		WHEN bruger_id != ALL(string_to_array((SELECT text_ FROM greg.variabel('users')), ','))
		THEN (SELECT catalog_name FROM information_schema.information_schema_catalog_name) || '_'
		ELSE NULL::text
	END AS prefix,
	bruger_id,
	CASE
		WHEN bruger_id != ALL(string_to_array((SELECT text_ FROM greg.variabel('users')), ','))
		THEN (SELECT catalog_name FROM information_schema.information_schema_catalog_name) || '_' || bruger_id
		ELSE bruger_id
	END AS login,
	navn,
	navn || ' (' || bruger_id || ')' AS bruger,
	rolle,
	aktiv,
	NULL::text AS password
FROM basis.d_basis_bruger_id;

COMMENT ON VIEW basis.v_basis_bruger_id IS 'Opdaterbar view. Look-up for d_basis_bruger_id.';

-- v_basis_kommunal_kontakt

CREATE VIEW basis.v_basis_kommunal_kontakt AS

SELECT
	kommunal_kontakt_kode,
	navn,
	telefon,
	email,
	aktiv,
	navn || ', tlf: ' || telefon || ', ' || email as kontakt
FROM basis.d_basis_kommunal_kontakt;

COMMENT ON VIEW basis.v_basis_kommunal_kontakt IS 'Opdaterbar view. Look-up for d_basis_kommunal_kontakt.';

-- v_basis_status

CREATE VIEW basis.v_basis_status AS

SELECT
	statuskode,
	status
FROM basis.d_basis_status
WHERE aktiv IS TRUE;

COMMENT ON VIEW basis.v_basis_status IS 'Look-up for d_basis_status.';

-- v_basis_offentlig

CREATE VIEW basis.v_basis_offentlig AS

SELECT
	off_kode,
	offentlig
FROM basis.d_basis_offentlig
WHERE aktiv IS TRUE;

COMMENT ON VIEW basis.v_basis_offentlig IS 'Look-up for d_basis_offentlig.';

-- v_basis_oprindelse

CREATE VIEW basis.v_basis_oprindelse AS

SELECT
	oprindkode,
	oprindelse,
	begrebsdefinition
FROM basis.d_basis_oprindelse
WHERE aktiv IS TRUE;

COMMENT ON VIEW basis.v_basis_oprindelse IS 'Look-up for d_basis_oprindelse.';

-- v_basis_tilstand

CREATE VIEW basis.v_basis_tilstand AS

SELECT
	tilstand_kode,
	tilstand,
	begrebsdefinition
FROM basis.d_basis_tilstand
WHERE aktiv IS TRUE;

COMMENT ON VIEW basis.v_basis_tilstand IS 'Look-up for d_basis_tilstand.';

-- v_basis_udfoerer

CREATE VIEW basis.v_basis_udfoerer AS

SELECT
	udfoerer_kode,
	udfoerer,
	aktiv
FROM basis.d_basis_udfoerer;

COMMENT ON VIEW basis.v_basis_udfoerer IS 'Opdaterbar view. Look-up for d_basis_udfoerer.';

-- v_basis_udfoerer_entrep

CREATE VIEW basis.v_basis_udfoerer_entrep AS

SELECT
	udfoerer_entrep_kode,
	udfoerer_entrep,
	aktiv
FROM basis.d_basis_udfoerer_entrep;

COMMENT ON VIEW basis.v_basis_udfoerer_entrep IS 'Opdaterbar view. Look-up for d_basis_udfoerer_entrep.';

-- v_basis_udfoerer_kontakt

CREATE VIEW basis.v_basis_udfoerer_kontakt AS

SELECT
	b.udfoerer_kode,
	a.udfoerer_kontakt_kode,
	a.navn,
	a.telefon,
	a.email,
	a.aktiv,
	b.udfoerer || ' - ' || a.navn || ', tlf: ' || a.telefon || ', ' || a.email as kontakt
FROM basis.d_basis_udfoerer_kontakt a
LEFT JOIN basis.d_basis_udfoerer b ON a.udfoerer_kode = b.udfoerer_kode;

COMMENT ON VIEW basis.v_basis_udfoerer_kontakt IS 'Opdaterbar view. Look-up for d_basis_udfoerer_kontakt.';

-- v_basis_vejnavn

CREATE VIEW basis.v_basis_vejnavn AS

SELECT
	postnr,
	vejkode,
	vejnavn,
	vejnavn || ' (' || postnr || ')' AS vej
FROM basis.d_basis_vejnavn
WHERE aktiv IS TRUE;

COMMENT ON VIEW basis.v_basis_vejnavn IS 'Look-up for d_basis_vejnavn.';

-- v_basis_distrikt_type

CREATE VIEW basis.v_basis_distrikt_type AS

SELECT
	pg_distrikt_type_kode,
	pg_distrikt_type,
	aktiv
FROM basis.d_basis_distrikt_type;

COMMENT ON VIEW basis.v_basis_distrikt_type IS 'Opdaterbar view. Look-up for d_basis_distrikt_type.';

-- v_basis_postnr

CREATE VIEW basis.v_basis_postnr AS

SELECT
	postnr,
	postnr || ' ' || postnr_by as distrikt
FROM basis.d_basis_postnr
WHERE aktiv IS TRUE;

COMMENT ON VIEW basis.v_basis_postnr IS 'Look-up for d_basis_postnr.';

-- v_basis_hovedelementer

CREATE VIEW basis.v_basis_hovedelementer AS

WITH 

	ebu AS(
		SELECT 
			b.hovedelement_kode,
			a.objekt_type
		FROM basis.e_basis_underelementer a
		LEFT JOIN basis.e_basis_elementer b ON a.element_kode = b.element_kode
	)

SELECT
	a.hovedelement_kode,
	a.hovedelement_tekst,
	a.hovedelement_kode || ' - ' || a.hovedelement_tekst AS hovedelement,
	CASE 
		WHEN a.hovedelement_kode IN(SELECT 
										hovedelement_kode
									FROM ebu
									WHERE objekt_type ILIKE '%F%')
		THEN 'F'
		ELSE ''
	END ||
	CASE 
		WHEN a.hovedelement_kode IN(SELECT 
										hovedelement_kode
									FROM ebu
									WHERE objekt_type ILIKE '%L%')
		THEN 'L'
		ELSE ''
	END ||
	CASE 
		WHEN a.hovedelement_kode IN(SELECT 
										hovedelement_kode
									FROM ebu
									WHERE objekt_type ILIKE '%P%')
		THEN 'P'
		ELSE ''
	END AS objekt_type,
	a.aktiv,
	-- Point	
	CASE 
		WHEN a.hovedelement_kode NOT IN(SELECT 
										hovedelement_kode
									FROM ebu
									WHERE objekt_type ILIKE '%P%')
		THEN NULL
		WHEN d.p_style IS NOT NULL
		THEN 'Stilart overskrevet'
		ELSE 'Stilart i brug'
	END AS p_style_ow,
	a.point_color,
	a.name,
	NULL::text AS p_style_copy,
	-- Line	
	CASE 
		WHEN a.hovedelement_kode NOT IN(SELECT 
										hovedelement_kode
									FROM ebu
									WHERE objekt_type ILIKE '%L%')
		THEN NULL
		WHEN d.l_style IS NOT NULL
		THEN 'Stilart overskrevet'
		ELSE 'Stilart i brug'
	END AS l_style_ow,
	a.line_color,
	a.line_style,
	NULL::text AS l_style_copy,
	-- Polygon	
	CASE 
		WHEN a.hovedelement_kode NOT IN(SELECT 
										hovedelement_kode
									FROM ebu
									WHERE objekt_type ILIKE '%F%')
		THEN NULL
		WHEN d.f_style IS NOT NULL
		THEN 'Stilart overskrevet'
		ELSE 'Stilart i brug'
	END AS f_style_ow,
	a.poly_color,
	a.style,
	NULL::text AS f_style_copy
FROM basis.e_basis_hovedelementer a
LEFT JOIN basis.e_basis_elementer b ON a.hovedelement_kode = b.hovedelement_kode
LEFT JOIN basis.e_basis_underelementer c ON b.element_kode = c.element_kode
LEFT JOIN styles.d_basis_element_lib d ON a.hovedelement_kode = d.kode AND d.niveau = 1
GROUP BY a.hovedelement_kode, a.hovedelement_tekst, p_style, a.point_color, a.name, d.l_style, a.line_color, a.line_style, d.f_style, a.poly_color, a.style
ORDER BY a.hovedelement_kode;

COMMENT ON VIEW basis.v_basis_hovedelementer IS 'Opdaterbar view. Look-up for e_basis_hovedelementer.';

-- v_basis_elementer

CREATE VIEW basis.v_basis_elementer AS

SELECT
	a.hovedelement_kode,
	a.element_kode,
	a.element_tekst,
	a.element_kode || ' ' || a.element_tekst AS element,
	CASE 
		WHEN a.element_kode IN(SELECT
									element_kode
								FROM basis.e_basis_underelementer
								WHERE objekt_type ILIKE '%F%')
		THEN 'F'
		ELSE ''
	END ||
	CASE 
		WHEN a.element_kode IN(SELECT
									element_kode
								FROM basis.e_basis_underelementer
								WHERE objekt_type ILIKE '%L%')
		THEN 'L'
		ELSE ''
	END ||
	CASE 
		WHEN a.element_kode IN(SELECT
									element_kode
								FROM basis.e_basis_underelementer
								WHERE objekt_type ILIKE '%P%')
		THEN 'P'
		ELSE ''
	END AS objekt_type,
	a.aktiv,
	-- Point	
	CASE
		WHEN a.element_kode NOT IN(SELECT
									element_kode
								FROM basis.e_basis_underelementer
								WHERE objekt_type ILIKE '%P%')
		THEN NULL
		WHEN p_style IS NOT NULL
		THEN 'Stilart overskrevet'
		ELSE 'Stilart i brug'
	END AS p_style_ow,
	a.point_color,
	a.name,
	NULL::text AS p_style_copy,
	-- Line	
	CASE
		WHEN a.element_kode NOT IN(SELECT
									element_kode
								FROM basis.e_basis_underelementer
								WHERE objekt_type ILIKE '%L%')
		THEN NULL
		WHEN l_style IS NOT NULL
		THEN 'Stilart overskrevet'
		ELSE 'Stilart i brug'
	END AS l_style_ow,
	a.line_color,
	a.line_style,
	NULL::text AS l_style_copy,
	-- Polygon	
	CASE
		WHEN a.element_kode NOT IN(SELECT
									element_kode
								FROM basis.e_basis_underelementer
								WHERE objekt_type ILIKE '%F%')
		THEN NULL
		WHEN f_style IS NOT NULL
		THEN 'Stilart overskrevet'
		ELSE 'Stilart i brug'
	END AS f_style_ow,
	a.poly_color,
	a.style,
	NULL::text AS f_style_copy
FROM basis.e_basis_elementer a
LEFT JOIN basis.e_basis_underelementer b ON a.element_kode = b.element_kode
LEFT JOIN basis.e_basis_hovedelementer c ON a.hovedelement_kode = c.hovedelement_kode
LEFT JOIN styles.d_basis_element_lib d ON a.element_kode = d.kode AND d.niveau = 2
WHERE c.aktiv IS TRUE
GROUP BY a.element_kode, a.element_tekst, p_style, a.point_color, a.name, d.l_style, a.line_color, a.line_style, d.f_style, a.poly_color, a.style
ORDER BY a.element_kode;

COMMENT ON VIEW basis.v_basis_elementer IS 'Opdaterbar view. Look-up for e_basis_elementer.';

-- v_basis_underelementer

CREATE VIEW basis.v_basis_underelementer AS

SELECT
	a.element_kode,
	a.underelement_kode,
	a.underelement_tekst,
	a.underelement_kode || ' ' || a.underelement_tekst AS underelement,
	a.objekt_type,
	a.speciel_forklaring,
	a.speciel_sql,
	a.enhedspris_point,
	a.enhedspris_line,
	a.enhedspris_poly,
	a.enhedspris_speciel,
	a.renhold,
	a.udregn_geometri,
	a.aktiv,
	-- Point	
	CASE
		WHEN a.objekt_type NOT ILIKE '%P%'
		THEN NULL
		WHEN d.p_style IS NOT NULL
		THEN 'Stilart overskrevet'
		ELSE 'Stilart i brug'
	END AS p_style_ow,
	a.point_color,
	a.name,
	NULL::text AS p_style_copy,
	-- Line	
	CASE
		WHEN a.objekt_type NOT ILIKE '%L%'
		THEN NULL
		WHEN d.l_style IS NOT NULL
		THEN 'Stilart overskrevet'
		ELSE 'Stilart i brug'
	END AS l_style_ow,
	a.line_color,
	a.line_style,
	NULL::text AS l_style_copy,
	-- Polygon	
	CASE
		WHEN a.objekt_type NOT ILIKE '%F%'
		THEN NULL
		WHEN d.f_style IS NOT NULL 
		THEN 'Stilart overskrevet'
		ELSE 'Stilart i brug'
	END AS f_style_ow,
	a.poly_color,
	a.style,
	NULL::text AS f_style_copy
FROM basis.e_basis_underelementer a
LEFT JOIN basis.e_basis_elementer b ON a.element_kode = b.element_kode
LEFT JOIN basis.e_basis_hovedelementer c ON b.hovedelement_kode = c.hovedelement_kode
LEFT JOIN styles.d_basis_element_lib d ON a.underelement_kode = d.kode AND d.niveau = 3
WHERE b.aktiv IS TRUE AND c.aktiv IS TRUE
ORDER BY a.underelement_kode;

COMMENT ON VIEW basis.v_basis_underelementer IS 'Opdaterbar view. Look-up for e_basis_underelementer.';

-- v_basis_prisregulering

CREATE VIEW basis.v_basis_prisregulering AS

SELECT
	dato,
	aendring_pct,
	1 + aendring_pct / 100 AS prisregulering_faktor
FROM basis.d_basis_prisregulering;

COMMENT ON VIEW basis.v_basis_prisregulering IS 'Opdaterbar view. Look-up for d_basis_prisregulering.';

-- v_default

DROP VIEW IF EXISTS basis.v_default;

CREATE VIEW basis.v_default AS

SELECT
	1 AS int,
	(SELECT text_ FROM greg.variabel('composer')) AS composer,
	(SELECT text_ FROM greg.variabel('picture')) AS picture,
	(SELECT int_ FROM greg.variabel('cvr')) AS cvr,
	(SELECT int_ FROM greg.variabel('oprind')) AS oprind,
	(SELECT int_ FROM greg.variabel('status')) AS status,
	(SELECT int_ FROM greg.variabel('off_')) AS off_,
	(SELECT int_ FROM greg.variabel('tilstand')) AS tilstand;

COMMENT ON VIEW basis.v_default IS 'Indeholder diverse indstillinger til QGIS.';



-- v_greg_flader

CREATE VIEW greg.v_greg_flader AS

WITH

	pris_reg AS (
		SELECT * FROM basis.f_prisregulering_produkt(EXTRACT (day FROM current_date)::integer, EXTRACT (month FROM current_date)::integer, EXTRACT (year FROM current_date)::integer)
	)

SELECT
	-- Automated values
	a.versions_id,
	a.objekt_id,
	a.oprettet,
	a.systid_fra,
	a.bruger_id_start AS bruger_id,
	b.navn || ' (' || b.bruger_id || ')' AS bruger,
	-- Geometry
	a.geometri,
	-- FKG #1
	a.cvr_kode,
	am.cvr_navn,
	a.oprindkode,
	o.oprindelse,
	a.statuskode,
	s.status,
	a.off_kode,
	of.offentlig,
	-- FKG #2
	a.note,
	a.link,
	a.vejkode,
	v.vejnavn,
	a.tilstand_kode,
	t.tilstand,
	a.anlaegsaar,
	a.udfoerer_entrep_kode,
	u.udfoerer_entrep,
	a.kommunal_kontakt_kode,
	kk.navn || ', tlf: ' || kk.telefon || ', ' || kk.email AS kommunal_kontakt,
	-- FKG #3
	a.arbejdssted,
	CASE 
		WHEN a.arbejdssted IS NOT NULL
		THEN om.pg_distrikt_tekst
		ELSE 'Udenfor område'
	END AS pg_distrikt_tekst,
	he.hovedelement_kode,
	he.hovedelement_tekst,
	e.element_kode,
	e.element_tekst,
	a.underelement_kode,
	ue.underelement_tekst,
	-- Measurements
	a.hoejde,
	-- Table specific
	a.klip_sider,
	a.litra,
	-- Special calculations and geometry derived values
	ue.speciel_forklaring || ':' AS speciel_forklaring,
	CASE
		WHEN ue.speciel_sql IS NOT NULL
		THEN (SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_flader', a.versions_id))
		ELSE NULL
	END AS speciel,
	public.ST_Area(a.geometri)::numeric(10,1) AS areal,
	public.ST_Perimeter(a.geometri)::numeric(10,1) AS omkreds,
	CASE
		WHEN ue.speciel_sql IS NOT NULL
		THEN ((SELECT speciel FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_flader', a.versions_id)) * ue.enhedspris_speciel * (SELECT * FROM pris_reg))::numeric(10,2)
		ELSE 0
	END +
	(public.ST_Area(a.geometri) * ue.enhedspris_poly * (SELECT * FROM pris_reg))::numeric(10,1) AS element_pris,
	-- Active
	CASE 
		WHEN a.arbejdssted IS NOT NULL	
		THEN om.aktiv
		ELSE TRUE
	END AS aktiv
FROM greg.t_greg_flader a
-- Automated values
LEFT JOIN basis.d_basis_bruger_id b ON a.bruger_id_start = b.bruger_id
-- FKG #1
LEFT JOIN basis.d_basis_ansvarlig_myndighed am ON a.cvr_kode = am.cvr_kode
LEFT JOIN basis.d_basis_oprindelse o ON a.oprindkode = o.oprindkode
LEFT JOIN basis.d_basis_status s ON a.statuskode = s.statuskode
LEFT JOIN basis.d_basis_offentlig of ON a.off_kode = of.off_kode
-- FKG #2
LEFT JOIN basis.d_basis_vejnavn v ON a.vejkode = v.vejkode
LEFT JOIN basis.d_basis_tilstand t ON a.tilstand_kode = t.tilstand_kode
LEFT JOIN basis.d_basis_udfoerer_entrep u ON a.udfoerer_entrep_kode = u.udfoerer_entrep_kode
LEFT JOIN basis.d_basis_kommunal_kontakt kk ON a.kommunal_kontakt_kode = kk.kommunal_kontakt_kode
-- FKG #3
LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_til IS NULL
LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
LEFT JOIN basis.e_basis_elementer e ON ue.element_kode = e.element_kode
LEFT JOIN basis.e_basis_hovedelementer he ON e.hovedelement_kode = he.hovedelement_kode
WHERE a.systid_til IS NULL;

COMMENT ON VIEW greg.v_greg_flader IS 'Opdatérbar view for greg.t_greg_flader.';

-- v_greg_linier

CREATE VIEW greg.v_greg_linier AS

WITH

	pris_reg AS (
		SELECT * FROM basis.f_prisregulering_produkt(EXTRACT (day FROM current_date)::integer, EXTRACT (month FROM current_date)::integer, EXTRACT (year FROM current_date)::integer)
	)

SELECT
	-- Automated values
	a.versions_id,
	a.objekt_id,
	a.oprettet,
	a.systid_fra,
	a.bruger_id_start AS bruger_id,
	b.navn || ' (' || b.bruger_id || ')' AS bruger,
	-- Geometry
	a.geometri,
	-- FKG #1
	a.cvr_kode,
	am.cvr_navn,
	a.oprindkode,
	o.oprindelse,
	a.statuskode,
	s.status,
	a.off_kode,
	of.offentlig,
	-- FKG #2
	a.note,
	a.link,
	a.vejkode,
	v.vejnavn,
	a.tilstand_kode,
	t.tilstand,
	a.anlaegsaar,
	a.udfoerer_entrep_kode,
	u.udfoerer_entrep,
	a.kommunal_kontakt_kode,
	kk.navn || ', tlf: ' || kk.telefon || ', ' || kk.email AS kommunal_kontakt,
	-- FKG #3
	a.arbejdssted,
	CASE 
		WHEN a.arbejdssted IS NOT NULL
		THEN om.pg_distrikt_tekst
		ELSE 'Udenfor område'
	END AS pg_distrikt_tekst,
	he.hovedelement_kode,
	he.hovedelement_tekst,
	e.element_kode,
	e.element_tekst,
	a.underelement_kode,
	ue.underelement_tekst,
	-- Measurements
	a.bredde,
	a.hoejde,
	-- Table specific
	a.litra,
	-- Special calculations and geometry derived values
	ue.speciel_forklaring || ':' AS speciel_forklaring,
	CASE
		WHEN ue.speciel_sql IS NOT NULL
		THEN (SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_linier', a.versions_id))
		ELSE NULL
	END AS speciel,
	public.ST_Length(a.geometri)::numeric(10,1) AS laengde,	
	CASE
		WHEN ue.speciel_sql IS NOT NULL
		THEN ((SELECT speciel FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_linier', a.versions_id)) * ue.enhedspris_speciel * (SELECT * FROM pris_reg))::numeric(10,2)
		ELSE 0
	END +
	(public.ST_Length(a.geometri) * ue.enhedspris_line * (SELECT * FROM pris_reg))::numeric(10,1) AS element_pris,
	-- Active
	CASE 
		WHEN a.arbejdssted IS NOT NULL	
		THEN om.aktiv
		ELSE TRUE
	END AS aktiv
FROM greg.t_greg_linier a
-- Automated values
LEFT JOIN basis.d_basis_bruger_id b ON a.bruger_id_start = b.bruger_id
-- FKG #1
LEFT JOIN basis.d_basis_ansvarlig_myndighed am ON a.cvr_kode = am.cvr_kode
LEFT JOIN basis.d_basis_oprindelse o ON a.oprindkode = o.oprindkode
LEFT JOIN basis.d_basis_status s ON a.statuskode = s.statuskode
LEFT JOIN basis.d_basis_offentlig of ON a.off_kode = of.off_kode
-- FKG #2
LEFT JOIN basis.d_basis_vejnavn v ON a.vejkode = v.vejkode
LEFT JOIN basis.d_basis_tilstand t ON a.tilstand_kode = t.tilstand_kode
LEFT JOIN basis.d_basis_udfoerer_entrep u ON a.udfoerer_entrep_kode = u.udfoerer_entrep_kode
LEFT JOIN basis.d_basis_kommunal_kontakt kk ON a.kommunal_kontakt_kode = kk.kommunal_kontakt_kode
-- FKG #3
LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_til IS NULL
LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
LEFT JOIN basis.e_basis_elementer e ON ue.element_kode = e.element_kode
LEFT JOIN basis.e_basis_hovedelementer he ON e.hovedelement_kode = he.hovedelement_kode
WHERE a.systid_til IS NULL;

COMMENT ON VIEW greg.v_greg_linier IS 'Opdatérbar view for greg.t_greg_linier.';

-- v_greg_punkter

CREATE VIEW greg.v_greg_punkter AS

WITH

	pris_reg AS (
		SELECT * FROM basis.f_prisregulering_produkt(EXTRACT (day FROM current_date)::integer, EXTRACT (month FROM current_date)::integer, EXTRACT (year FROM current_date)::integer)
	)

SELECT
	-- Automated values
	a.versions_id,
	a.objekt_id,
	a.oprettet,
	a.systid_fra,
	a.bruger_id_start AS bruger_id,
	b.navn || ' (' || b.bruger_id || ')' AS bruger,
	-- Geometry
	a.geometri,
	-- FKG #1
	a.cvr_kode,
	am.cvr_navn,
	a.oprindkode,
	o.oprindelse,
	a.statuskode,
	s.status,
	a.off_kode,
	of.offentlig,
	-- FKG #2
	a.note,
	a.link,
	a.vejkode,
	v.vejnavn,
	a.tilstand_kode,
	t.tilstand,
	a.anlaegsaar,
	a.udfoerer_entrep_kode,
	u.udfoerer_entrep,
	a.kommunal_kontakt_kode,
	kk.navn || ', tlf: ' || kk.telefon || ', ' || kk.email AS kommunal_kontakt,
	-- FKG #3
	a.arbejdssted,
	CASE 
		WHEN a.arbejdssted IS NOT NULL
		THEN om.pg_distrikt_tekst
		ELSE 'Udenfor område'
	END AS pg_distrikt_tekst,
	he.hovedelement_kode,
	he.hovedelement_tekst,
	e.element_kode,
	e.element_tekst,
	a.underelement_kode,
	ue.underelement_tekst,
	-- Measurements
	a.laengde,
	a.bredde,
	a.diameter,
	a.hoejde,
	-- Table specific
	a.slaegt,
	a.art,
	a.litra,
	-- Special calculations and geometry derived values
	ue.speciel_forklaring || ':' AS speciel_forklaring,
	CASE
		WHEN ue.speciel_sql = 'REN'
		THEN s1.areal::numeric(10,1)
		WHEN ue.speciel_sql IS NOT NULL
		THEN (SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_punkter', a.versions_id))
		ELSE NULL
	END AS speciel,
	public.ST_NumGeometries(a.geometri) AS antal,
	CASE
		WHEN ue.speciel_sql = 'REN'
		THEN (s1.areal * ue.enhedspris_speciel * (SELECT * FROM pris_reg))::numeric(10,2)
		WHEN ue.speciel_sql IS NOT NULL
		THEN ((SELECT speciel FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_punkter', a.versions_id)) * ue.enhedspris_speciel * (SELECT * FROM pris_reg))::numeric(10,2)
		ELSE 0
	END +
	(public.ST_NumGeometries(a.geometri) * ue.enhedspris_point * (SELECT * FROM pris_reg))::numeric(10,2) AS element_pris,
	-- Active
	CASE 
		WHEN a.arbejdssted IS NOT NULL	
		THEN om.aktiv
		ELSE TRUE
	END AS aktiv
FROM greg.t_greg_punkter a
-- Automated values
LEFT JOIN basis.d_basis_bruger_id b ON a.bruger_id_start = b.bruger_id
-- FKG #1
LEFT JOIN basis.d_basis_ansvarlig_myndighed am ON a.cvr_kode = am.cvr_kode
LEFT JOIN basis.d_basis_oprindelse o ON a.oprindkode = o.oprindkode
LEFT JOIN basis.d_basis_status s ON a.statuskode = s.statuskode
LEFT JOIN basis.d_basis_offentlig of ON a.off_kode = of.off_kode
-- FKG #2
LEFT JOIN basis.d_basis_vejnavn v ON a.vejkode = v.vejkode
LEFT JOIN basis.d_basis_tilstand t ON a.tilstand_kode = t.tilstand_kode
LEFT JOIN basis.d_basis_udfoerer_entrep u ON a.udfoerer_entrep_kode = u.udfoerer_entrep_kode
LEFT JOIN basis.d_basis_kommunal_kontakt kk ON a.kommunal_kontakt_kode = kk.kommunal_kontakt_kode
-- FKG #3
LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_til IS NULL
LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
LEFT JOIN basis.e_basis_elementer e ON ue.element_kode = e.element_kode
LEFT JOIN basis.e_basis_hovedelementer he ON e.hovedelement_kode = he.hovedelement_kode
-- For speciel_sql = 'REN'
LEFT JOIN (SELECT	arbejdssted,
					SUM(public.ST_Area(a.geometri)) AS areal
				FROM greg.t_greg_flader a
				LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
				WHERE ue.renhold IS TRUE AND systid_til IS NULL
				GROUP BY arbejdssted) s1
		ON a.arbejdssted = s1.arbejdssted
WHERE a.systid_til IS NULL;

COMMENT ON VIEW greg.v_greg_punkter IS 'Opdatérbar view for greg.t_greg_punkter.';

-- v_greg_omraader

CREATE VIEW greg.v_greg_omraader AS

SELECT
	-- Automated values
	a.versions_id,
	a.objekt_id,
	a.oprettet,
	a.systid_fra,
	a.bruger_id_start AS bruger_id,
	b.navn || ' (' || b.bruger_id || ')' AS bruger,
	-- Geometry
	a.geometri,
	-- FKG #1
	a.pg_distrikt_nr,
	a.pg_distrikt_tekst,
	a.pg_distrikt_type_kode,
	dt.pg_distrikt_type,
	-- FKG #2
	a.note,
	a.link,
	a.vejkode,
	v.vejnavn,
	a.vejnr,
	a.postnr,
	p.postnr_by AS distrikt,
	a.udfoerer_kode,
	u.udfoerer,
	a.udfoerer_kontakt_kode1,
	u1.udfoerer || ', ' || uk1.navn || ', tlf: ' || uk1.telefon || ', ' || uk1.email AS udfoerer_kontakt1,
	a.udfoerer_kontakt_kode2,
	u2.udfoerer || ', ' || uk2.navn || ', tlf: ' || uk2.telefon || ', ' || uk2.email AS udfoerer_kontakt2,
	a.kommunal_kontakt_kode,
	kk.navn || ', tlf: ' || kk.telefon || ', ' || kk.email AS kommunal_kontakt,
	-- Table specific
	a.aktiv,
	a.synlig,
	-- Special calculations and geometry derived values
	public.ST_Area(a.geometri)::numeric(10,1) AS areal
FROM greg.t_greg_omraader a
-- Automated values
LEFT JOIN basis.d_basis_bruger_id b ON a.bruger_id_start = b.bruger_id
-- FKG #1
LEFT JOIN basis.d_basis_distrikt_type dt ON a.pg_distrikt_type_kode = dt.pg_distrikt_type_kode
-- FKG #2
LEFT JOIN basis.d_basis_vejnavn v ON a.vejkode = v.vejkode
LEFT JOIN basis.d_basis_postnr p ON a.postnr = p.postnr
LEFT JOIN basis.d_basis_udfoerer u ON a.udfoerer_kode = u.udfoerer_kode
LEFT JOIN basis.d_basis_udfoerer_kontakt uk1 ON a.udfoerer_kontakt_kode1 = uk1.udfoerer_kontakt_kode
LEFT JOIN basis.d_basis_udfoerer u1 ON uk1.udfoerer_kode = u1.udfoerer_kode
LEFT JOIN basis.d_basis_udfoerer_kontakt uk2 ON a.udfoerer_kontakt_kode2 = uk2.udfoerer_kontakt_kode
LEFT JOIN basis.d_basis_udfoerer u2 ON uk2.udfoerer_kode = u2.udfoerer_kode
LEFT JOIN basis.d_basis_kommunal_kontakt kk ON a.kommunal_kontakt_kode = kk.kommunal_kontakt_kode
WHERE a.systid_til IS NULL
ORDER BY a.pg_distrikt_nr;

COMMENT ON VIEW greg.v_greg_omraader IS 'Opdatérbar view for greg.t_greg_omraader.';



-- v_aendring_flader

DROP VIEW IF EXISTS greg.v_aendring_flader;

CREATE VIEW greg.v_aendring_flader AS

SELECT
	objekt_id,
	geometri::public.geometry('MultiPolygon', 25832) AS geometri,
	handling,
	dato,
	arbejdssted,
	underelement
FROM greg.f_tot_flader((SELECT int_ FROM greg.variabel('num_days')));

COMMENT ON VIEW greg.v_aendring_flader IS 'Ændringsoversigt med tilhørende geometri.';

-- v_aendring_linier

DROP VIEW IF EXISTS greg.v_aendring_linier;

CREATE VIEW greg.v_aendring_linier AS

SELECT
	objekt_id,
	geometri::public.geometry('MultiLineString', 25832) AS geometri,
	handling,
	dato,
	arbejdssted,
	underelement
FROM greg.f_tot_linier((SELECT int_ FROM greg.variabel('num_days')));

COMMENT ON VIEW greg.v_aendring_linier IS 'Ændringsoversigt med tilhørende geometri.';

-- v_aendring_punkter

DROP VIEW IF EXISTS greg.v_aendring_punkter;

CREATE VIEW greg.v_aendring_punkter AS

SELECT
	objekt_id,
	geometri::public.geometry('MultiPoint', 25832) AS geometri,
	handling,
	dato,
	arbejdssted,
	underelement
FROM greg.f_tot_punkter((SELECT int_ FROM greg.variabel('num_days')));

COMMENT ON VIEW greg.v_aendring_punkter IS 'Ændringsoversigt med tilhørende geometri.';

-- v_aendring_omraader

DROP VIEW IF EXISTS greg.v_aendring_omraader;

CREATE VIEW greg.v_aendring_omraader AS

SELECT
	objekt_id,
	geometri::public.geometry('MultiPolygon', 25832) AS geometri,
	handling,
	dato,
	arbejdssted
FROM greg.f_tot_omraader((SELECT int_ FROM greg.variabel('num_days')));

COMMENT ON VIEW greg.v_aendring_omraader IS 'Ændringsoversigt med tilhørende geometri.';



-- v_log

DROP VIEW IF EXISTS greg.v_log;

CREATE VIEW greg.v_log AS

SELECT 	
	*
FROM greg.f_aendring_log (EXTRACT (YEAR FROM current_date)::integer);

COMMENT ON VIEW greg.v_log IS 'Ændringslog, som registrerer alle handlinger indenfor et gældende år. Benyttes i Ændringslog.xlsx';

-- v_log_historik

DROP VIEW IF EXISTS greg.v_log_historik;

CREATE VIEW greg.v_log_historik AS

SELECT 	
	*
FROM greg.f_aendring_log (2000);

COMMENT ON VIEW greg.v_log_historik IS 'Ændringslog, som registrerer alle handlinger indenfor et givent år. Benyttes i Historik_Ændringslog.xlsx';



-- v_greg_flader_historik

DROP VIEW IF EXISTS greg.v_greg_flader_historik;

CREATE VIEW greg.v_greg_flader_historik AS

SELECT
	*
FROM greg.f_dato_flader(01, 01, 2000);

COMMENT ON VIEW greg.v_greg_flader_historik IS 'Simulering af historik.';

-- v_greg_linier_historik

DROP VIEW IF EXISTS greg.v_greg_linier_historik;

CREATE VIEW greg.v_greg_linier_historik AS

SELECT
	*
FROM greg.f_dato_linier(01, 01, 2000);

COMMENT ON VIEW greg.v_greg_linier_historik IS 'Simulering af historik.';

-- v_greg_punkter_historik

DROP VIEW IF EXISTS greg.v_greg_punkter_historik;

CREATE VIEW greg.v_greg_punkter_historik AS

SELECT
	*
FROM greg.f_dato_punkter(01, 01, 2000);

COMMENT ON VIEW greg.v_greg_punkter_historik IS 'Simulering af historik.';

-- v_greg_omraader_historik

DROP VIEW IF EXISTS greg.v_greg_omraader_historik;

CREATE VIEW greg.v_greg_omraader_historik AS

SELECT
	*
FROM greg.f_dato_omraader(01, 01, 2000);

COMMENT ON VIEW greg.v_greg_omraader_historik IS 'Simulering af historik.';

-- v_maengder_historik

DROP VIEW IF EXISTS greg.v_maengder_historik;

CREATE VIEW greg.v_maengder_historik AS

SELECT
	*
FROM greg.f_maengder(01, 01, 2000);

COMMENT ON VIEW greg.v_maengder_historik IS 'Simulering af historik. Benyttes i Historik_Mængdeoversigt.xlsx';



-- v_maengder_omraader_underelementer

DROP VIEW IF EXISTS greg.v_maengder_omraader_underelementer;

CREATE VIEW greg.v_maengder_omraader_underelementer AS

WITH

	pris_reg AS (
		SELECT * FROM basis.f_prisregulering_produkt(EXTRACT (day FROM current_date)::integer, EXTRACT (month FROM current_date)::integer, EXTRACT (year FROM current_date)::integer)
	),

--
-- Element list
--

	base_elements AS ( -- Select a complete (DISTINCT) list of all current elements within each area code from the current data set
		SELECT
			a.arbejdssted,
			a.underelement_kode
		FROM greg.t_greg_flader a
		WHERE a.systid_til IS NULL
	
		UNION
	
		SELECT
			a.arbejdssted,
			a.underelement_kode
		FROM greg.t_greg_linier a
		WHERE a.systid_til IS NULL
	
		UNION
	
		SELECT
			a.arbejdssted,
			a.underelement_kode
		FROM greg.t_greg_punkter a
		WHERE a.systid_til IS NULL
	),

--
-- Basic calculations
--

	base_poly AS ( -- Select the area for each element on each area code from the current data set
		SELECT
			a.arbejdssted,
			a.underelement_kode,
			SUM(ST_Area(a.geometri)) AS areal
		FROM greg.t_greg_flader a
		WHERE a.systid_til IS NULL
		GROUP BY a.arbejdssted, a.underelement_kode
	),

	base_line AS ( -- Select the length for each element on each area code from the current data set
		SELECT
			a.arbejdssted,
			a.underelement_kode,
			SUM(ST_Length(a.geometri)) AS laengde
		FROM greg.t_greg_linier a
		WHERE a.systid_til IS NULL
		GROUP BY a.arbejdssted, a.underelement_kode
	),

	base_point AS ( -- Select the points (MultiPoints are counted for each individual point) for each element on each area code from the current data set
		SELECT
			a.arbejdssted,
			a.underelement_kode,
			SUM(ST_NumGeometries(a.geometri)) AS antal
		FROM greg.t_greg_punkter a
		WHERE a.systid_til IS NULL
		GROUP BY a.arbejdssted, a.underelement_kode
	),

--
-- Special calculation
--

	spec_ren AS	( -- Select the area for each area code excluding elements where renhold is set to false from the current data set
		SELECT
			a.arbejdssted,
			SUM(ST_Area(a.geometri)) AS areal -- Relevant for speciel_sql = 'REN'
		FROM greg.t_greg_flader a
		LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
		WHERE ue.renhold IS TRUE AND a.systid_til IS NULL
		GROUP BY arbejdssted
	),

	spec_poly AS ( -- Select all special calculations for each element on each area code from the current data set
		SELECT	
			a.arbejdssted,
			a.underelement_kode,
			(SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_flader', a.versions_id)) AS speciel
		FROM greg.t_greg_flader a
		LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
		WHERE systid_til IS NULL AND ue.speciel_sql IS NOT NULL
	),

	spec_line AS ( -- Select all special calculations for each element on each area code from the current data set
		SELECT	
			a.arbejdssted,
			a.underelement_kode,
			(SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_linier', a.versions_id)) AS speciel
		FROM greg.t_greg_linier a
		LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
		WHERE systid_til IS NULL AND ue.speciel_sql IS NOT NULL
	),

	spec_point AS ( -- Select all special calculations for each element on each area code from the current data set
		SELECT	
			a.arbejdssted,
			a.underelement_kode,
			CASE
				WHEN ue.speciel_sql = 'REN'
				THEN b.areal
				ELSE (SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_punkter', a.versions_id))
			END AS speciel
		FROM greg.t_greg_punkter a
		LEFT JOIN spec_ren b ON a.arbejdssted = b.arbejdssted
		LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
		WHERE systid_til IS NULL AND ue.speciel_sql IS NOT NULL
	),

	spec_one AS ( -- Select the sum of each special calculation grouped by each element and area code from the three queries above
		SELECT
			a.arbejdssted,
			a.underelement_kode,
			SUM(a.speciel) AS speciel
		FROM (
			SELECT * FROM spec_poly
			UNION ALL
			SELECT * FROM spec_line
			UNION ALL
			SELECT * FROM spec_point
		) a
		GROUP BY a.arbejdssted, a.underelement_kode
	),

--
-- Building the view
--

	view_1 AS ( -- Select amounts of each feature type respectively for each element within each area code
		SELECT
			a.*,
			CASE
				WHEN ue.udregn_geometri IS TRUE
				THEN d.antal
				ELSE NULL
			END AS antal,
			CASE
				WHEN ue.udregn_geometri IS TRUE
				THEN c.laengde
				ELSE NULL
			END AS laengde,
			CASE
				WHEN ue.udregn_geometri IS TRUE
				THEN b.areal
				ELSE NULL
			END AS areal,
			e.speciel
		FROM base_elements a
		LEFT JOIN base_poly		b ON CASE
										WHEN a.arbejdssted IS NOT NULL
										THEN a.arbejdssted = b.arbejdssted AND a.underelement_kode = b.underelement_kode
										ELSE b.arbejdssted IS NULL AND a.underelement_kode = b.underelement_kode
									END
		LEFT JOIN base_line		c ON CASE
										WHEN a.arbejdssted IS NOT NULL
										THEN a.arbejdssted = c.arbejdssted AND a.underelement_kode = c.underelement_kode
										ELSE c.arbejdssted IS NULL AND a.underelement_kode = c.underelement_kode
									END
		LEFT JOIN base_point	d ON CASE
										WHEN a.arbejdssted IS NOT NULL
										THEN a.arbejdssted = d.arbejdssted AND a.underelement_kode = d.underelement_kode
										ELSE d.arbejdssted IS NULL AND a.underelement_kode = d.underelement_kode
									END
		LEFT JOIN spec_one		e ON CASE
										WHEN a.arbejdssted IS NOT NULL
										THEN a.arbejdssted = e.arbejdssted AND a.underelement_kode = e.underelement_kode
										ELSE e.arbejdssted IS NULL AND a.underelement_kode = e.underelement_kode
									END
		LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
	),

	view_2 AS ( -- Select full overview of all amounts including a total price for each element on each area code 
		SELECT
			a.arbejdssted,
			a.underelement_kode,
			a.antal,
			a.laengde,
			a.areal,
			a.speciel,
			CASE
				WHEN a.antal IS NOT NULL
				THEN (a.antal * ue.enhedspris_point * (SELECT * FROM pris_reg))::numeric(10,2)
				ELSE 0
			END +
			CASE
				WHEN a.laengde IS NOT NULL
				THEN (a.laengde * ue.enhedspris_line * (SELECT * FROM pris_reg))::numeric(10,2)
				ELSE 0
			END +
			CASE
				WHEN a.areal IS NOT NULL
				THEN (a.areal * ue.enhedspris_poly * (SELECT * FROM pris_reg))::numeric(10,2)
				ELSE 0
			END +
			CASE
				WHEN a.speciel IS NOT NULL
				THEN (a.speciel * ue.enhedspris_speciel * (SELECT * FROM pris_reg))::numeric(10,2)
				ELSE 0
			END AS pris
		FROM view_1 a
		LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
	)

-- SELECT full overview with JOINS to look-up TABLES. Price is set to NULL if 0 for Excel purposes
SELECT
	dt.pg_distrikt_type,
	u.udfoerer,
	a.arbejdssted,
	CASE 
		WHEN a.arbejdssted IS NOT NULL
		THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
		ELSE 'Udenfor område'
	END AS omraade,
	he.hovedelement_kode,
	he.hovedelement_kode || ' - ' || he.hovedelement_tekst AS hovedelement,
	e.element_kode,
	e.element_kode || ' ' || e.element_tekst AS element,
	ue.underelement_kode,
	CASE
		WHEN ue.speciel_forklaring IS NOT NULL
		THEN ue.underelement_kode || ' ' || ue.underelement_tekst || ' (Speciel: ' || ue.speciel_forklaring || ')'
		ELSE ue.underelement_kode || ' ' || ue.underelement_tekst
		END AS underelement,
	a.antal,
	a.laengde::numeric(10,1),
	a.areal::numeric(10,1),
	a.speciel::numeric(10,1),
	CASE
		WHEN a.pris > 0
		THEN a.pris
	END AS pris
FROM view_2 a
LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_til IS NULL
LEFT JOIN basis.d_basis_distrikt_type dt ON om.pg_distrikt_type_kode = dt.pg_distrikt_type_kode
LEFT JOIN basis.d_basis_udfoerer u ON om.udfoerer_kode = u.udfoerer_kode
LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
LEFT JOIN basis.e_basis_elementer e ON ue.element_kode = e.element_kode
LEFT JOIN basis.e_basis_hovedelementer he ON e.hovedelement_kode = he.hovedelement_kode
WHERE om.aktiv IS TRUE OR a.arbejdssted IS NULL
ORDER BY pg_distrikt_nr, underelement_kode;

COMMENT ON VIEW greg.v_maengder_omraader_underelementer IS 'Mængdeoversigt over elementer grupperet pr. område.';

-- v_maengder_omraader_underelementer_2

DROP VIEW IF EXISTS greg.v_maengder_omraader_underelementer_2;

CREATE VIEW greg.v_maengder_omraader_underelementer_2 AS

WITH

--
-- Element list
--

	base_elements AS ( -- Select a complete (DISTINCT) list of all current elements within each area code from the current data set
		SELECT
			a.arbejdssted,
			a.underelement_kode
		FROM greg.t_greg_flader a
		WHERE a.systid_til IS NULL
	
		UNION
	
		SELECT
			a.arbejdssted,
			a.underelement_kode
		FROM greg.t_greg_linier a
		WHERE a.systid_til IS NULL
	
		UNION
	
		SELECT
			a.arbejdssted,
			a.underelement_kode
		FROM greg.t_greg_punkter a
		WHERE a.systid_til IS NULL
	),

--
-- Basic calculations
--

	base_poly AS ( -- Select the area for each element on each area code from the current data set
		SELECT
			a.arbejdssted,
			a.underelement_kode,
			SUM(ST_Area(a.geometri)) AS areal
		FROM greg.t_greg_flader a
		WHERE a.systid_til IS NULL
		GROUP BY a.arbejdssted, a.underelement_kode
	),

	base_line AS ( -- Select the length for each element on each area code from the current data set
		SELECT
			a.arbejdssted,
			a.underelement_kode,
			SUM(ST_Length(a.geometri)) AS laengde
		FROM greg.t_greg_linier a
		WHERE a.systid_til IS NULL
		GROUP BY a.arbejdssted, a.underelement_kode
	),

	base_point AS ( -- Select the points (MultiPoints are counted for each individual point) for each element on each area code from the current data set
		SELECT
			a.arbejdssted,
			a.underelement_kode,
			SUM(ST_NumGeometries(a.geometri)) AS antal
		FROM greg.t_greg_punkter a
		WHERE a.systid_til IS NULL
		GROUP BY a.arbejdssted, a.underelement_kode
	),

--
-- Special calculation
--

	spec_ren AS	( -- Select the area for each area code excluding elements where renhold is set to false from the current data set
		SELECT
			a.arbejdssted,
			SUM(ST_Area(a.geometri)) AS areal -- Relevant for speciel_sql = 'REN'
		FROM greg.t_greg_flader a
		LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
		WHERE ue.renhold IS TRUE AND a.systid_til IS NULL
		GROUP BY arbejdssted
	),

	spec_poly AS ( -- Select all special calculations for each element on each area code from the current data set
		SELECT	
			a.arbejdssted,
			a.underelement_kode,
			(SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_flader', a.versions_id)) AS speciel
		FROM greg.t_greg_flader a
		LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
		WHERE systid_til IS NULL AND ue.speciel_sql IS NOT NULL
	),

	spec_line AS ( -- Select all special calculations for each element on each area code from the current data set
		SELECT	
			a.arbejdssted,
			a.underelement_kode,
			(SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_linier', a.versions_id)) AS speciel
		FROM greg.t_greg_linier a
		LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
		WHERE systid_til IS NULL AND ue.speciel_sql IS NOT NULL
	),

	spec_point AS ( -- Select all special calculations for each element on each area code from the current data set
		SELECT	
			a.arbejdssted,
			a.underelement_kode,
			CASE
				WHEN ue.speciel_sql = 'REN'
				THEN b.areal
				ELSE (SELECT speciel::numeric(10,1) FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_punkter', a.versions_id))
			END AS speciel
		FROM greg.t_greg_punkter a
		LEFT JOIN spec_ren b ON a.arbejdssted = b.arbejdssted
		LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
		WHERE systid_til IS NULL AND ue.speciel_sql IS NOT NULL
	),

	spec_one AS ( -- Select the sum of each special calculation grouped by each element and area code from the three queries above
		SELECT
			a.arbejdssted,
			a.underelement_kode,
			SUM(a.speciel) AS speciel
		FROM (
			SELECT * FROM spec_poly
			UNION ALL
			SELECT * FROM spec_line
			UNION ALL
			SELECT * FROM spec_point
		) a
		GROUP BY a.arbejdssted, a.underelement_kode
	),

--
-- Building the view
--

	view_1 AS ( -- Select amounts of each feature type respectively for each element within each area code
		SELECT
			a.*,
			CASE
				WHEN ue.udregn_geometri IS TRUE
				THEN d.antal
				ELSE NULL
			END AS antal,
			CASE
				WHEN ue.udregn_geometri IS TRUE
				THEN c.laengde
				ELSE NULL
			END AS laengde,
			CASE
				WHEN ue.udregn_geometri IS TRUE
				THEN b.areal
				ELSE NULL
			END AS areal,
			e.speciel
		FROM base_elements a
		LEFT JOIN base_poly		b ON a.arbejdssted = b.arbejdssted AND a.underelement_kode = b.underelement_kode
		LEFT JOIN base_line		c ON a.arbejdssted = c.arbejdssted AND a.underelement_kode = c.underelement_kode
		LEFT JOIN base_point	d ON a.arbejdssted = d.arbejdssted AND a.underelement_kode = d.underelement_kode
		LEFT JOIN spec_one		e ON a.arbejdssted = e.arbejdssted AND a.underelement_kode = e.underelement_kode
		LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
	)

-- SELECT full overview with JOINS to look-up TABLES. Price is set to NULL if 0 for Excel purposes
SELECT
	dt.pg_distrikt_type,
	a.arbejdssted,
	CASE 
		WHEN a.arbejdssted IS NOT NULL
		THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
		ELSE 'Udenfor område'
	END AS omraade,
	he.hovedelement_kode,
	he.hovedelement_kode || ' - ' || he.hovedelement_tekst AS hovedelement,
	e.element_kode,
	e.element_kode || ' ' || e.element_tekst AS element,
	ue.underelement_kode,
	ue.underelement_kode || ' ' || ue.underelement_tekst AS underelement,
	a.antal,
	a.laengde::numeric(10,1),
	a.areal::numeric(10,1),
	ue.speciel_forklaring || ': ' || a.speciel::numeric(10,1) AS speciel
FROM view_1 a
LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_til IS NULL
LEFT JOIN basis.d_basis_distrikt_type dt ON om.pg_distrikt_type_kode = dt.pg_distrikt_type_kode
LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
LEFT JOIN basis.e_basis_elementer e ON ue.element_kode = e.element_kode
LEFT JOIN basis.e_basis_hovedelementer he ON e.hovedelement_kode = he.hovedelement_kode
WHERE om.aktiv IS TRUE
ORDER BY pg_distrikt_nr, underelement_kode;

COMMENT ON VIEW greg.v_maengder_omraader_underelementer_2 IS 'Mængdeoversigt over elementer grupperet pr. område. Benyttes i Mængdekort.xlsm.';



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
FROM basis.e_basis_underelementer a
LEFT JOIN basis.e_basis_elementer b ON a.element_kode = b.element_kode
LEFT JOIN basis.e_basis_hovedelementer c ON b.hovedelement_kode = c.hovedelement_kode
WHERE a.aktiv IS TRUE AND b.aktiv IS TRUE AND c.aktiv IS TRUE
ORDER BY c.hovedelement_kode, b.element_kode, a.underelement_kode;

COMMENT ON VIEW greg.v_oversigt_elementer IS 'Elementoversigt. Benyttes i Lister.xlsx.';

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
	public.ST_Area(a.geometri)::numeric(10,1) AS areal
FROM greg.t_greg_omraader a
LEFT JOIN basis.d_basis_distrikt_type b ON a.pg_distrikt_type_kode = b.pg_distrikt_type_kode
LEFT JOIN basis.d_basis_vejnavn c ON a.vejkode = c.vejkode
LEFT JOIN basis.d_basis_postnr d ON a.postnr = d.postnr
WHERE a.aktiv IS TRUE AND a.systid_til IS NULL
ORDER BY a.pg_distrikt_nr;

COMMENT ON VIEW greg.v_oversigt_omraade IS 'Look-up for aktive områder. Benyttes i Mængdekort.xlsm.';

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
LEFT JOIN basis.d_basis_vejnavn b ON a.vejkode = b.vejkode
LEFT JOIN basis.d_basis_postnr c ON a.postnr = c.postnr
LEFT JOIN basis.d_basis_distrikt_type d ON a.pg_distrikt_type_kode = d.pg_distrikt_type_kode
WHERE a.aktiv IS TRUE AND a.systid_til IS NULL
ORDER BY a.pg_distrikt_nr;

COMMENT ON VIEW greg.v_oversigt_omraade_2 IS 'Områdeoversigt. Benyttes i Lister.xlsx.';

-- v_oversigt_omraade_3

DROP VIEW IF EXISTS greg.v_oversigt_omraade_3;

CREATE VIEW greg.v_oversigt_omraade_3 AS

WITH

	tgo AS(
		SELECT 	
			ROW_NUMBER() OVER() AS id,
			a.pg_distrikt_nr as omraadenr,
			a.pg_distrikt_nr || ' ' || a.pg_distrikt_tekst AS omraade
		FROM greg.t_greg_omraader a
		WHERE a.systid_til IS NULL
	)

SELECT * FROM tgo

UNION

SELECT
	CASE
		WHEN (SELECT MAX(id)+1 FROM tgo) IS NOT NULL
		THEN (SELECT MAX(id)+1 FROM tgo)
		ELSE 1
	END AS id,
	NULL::integer AS omraadenr,
	'Udenfor område' AS omraade

ORDER BY 1;

COMMENT ON VIEW greg.v_oversigt_omraade_2 IS 'Områdeoversigt (QGIS).';

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
LEFT JOIN basis.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr AND c.systid_til IS NULL
WHERE c.aktiv IS TRUE AND a.litra IS NOT NULL AND a.systid_til IS NULL
GROUP BY omraade, a.underelement_kode, b.underelement_tekst, a.litra, a.hoejde

UNION ALL

SELECT
	c.pg_distrikt_nr || ' ' || c.pg_distrikt_tekst AS omraade,
	a.underelement_kode,
	b.underelement_tekst,
	a.litra,
	a.hoejde
FROM greg.t_greg_linier a
LEFT JOIN basis.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr AND c.systid_til IS NULL
WHERE c.aktiv IS TRUE AND a.litra IS NOT NULL AND a.systid_til IS NULL
GROUP BY omraade, a.underelement_kode, b.underelement_tekst, a.litra, a.hoejde

UNION ALL

SELECT
	c.pg_distrikt_nr || ' ' || c.pg_distrikt_tekst AS omraade,
	a.underelement_kode,
	b.underelement_tekst,
	a.litra,
	a.hoejde
FROM greg.t_greg_punkter a
LEFT JOIN basis.e_basis_underelementer b ON a.underelement_kode = b.underelement_kode
LEFT JOIN greg.t_greg_omraader c ON a.arbejdssted = c.pg_distrikt_nr AND c.systid_til IS NULL
WHERE c.aktiv IS TRUE AND a.litra IS NOT NULL AND a.systid_til IS NULL
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
LEFT JOIN basis.d_basis_distrikt_type b ON a.pg_distrikt_type_kode = b.pg_distrikt_type_kode
LEFT JOIN basis.d_basis_vejnavn c ON a.vejkode = c.vejkode
LEFT JOIN basis.d_basis_postnr d ON a.postnr = d.postnr
WHERE a.systid_til IS NULL AND a.aktiv IS TRUE AND a.pg_distrikt_nr NOT IN (SELECT pg_distrikt_nr FROM greg.t_greg_delomraader) AND a.synlig IS TRUE AND a.geometri IS NOT NULL

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
LEFT JOIN greg.t_greg_omraader b ON a.pg_distrikt_nr = b.pg_distrikt_nr AND systid_til IS NULL
LEFT JOIN basis.d_basis_distrikt_type c ON b.pg_distrikt_type_kode = c.pg_distrikt_type_kode
LEFT JOIN basis.d_basis_vejnavn d ON b.vejkode = d.vejkode
LEFT JOIN basis.d_basis_postnr e ON b.postnr = e.postnr
LEFT JOIN (SELECT
			pg_distrikt_nr,
				COUNT(pg_distrikt_nr) AS delomraade_total
			FROM greg.t_greg_delomraader
			GROUP BY pg_distrikt_nr) f
		ON a.pg_distrikt_nr = f.pg_distrikt_nr
WHERE b.aktiv IS TRUE
ORDER BY pg_distrikt_nr, delomraade;

COMMENT ON VIEW greg.v_atlas IS 'Samlet områdetabel på baggrund af områder og delområder';



-- v_basis_element_lib

DROP VIEW IF EXISTS styles.v_basis_element_lib;

CREATE VIEW styles.v_basis_element_lib AS

WITH
	un_ AS ( -- List all active elements in a single list
		SELECT
			1 AS niveau,
			hovedelement_kode AS kode,
			hovedelement_tekst AS tekst,
			objekt_type
		FROM basis.v_basis_hovedelementer

		UNION ALL

		SELECT
			2 AS niveau,
			element_kode AS kode,
			element_tekst AS tekst,
			objekt_type
		FROM basis.v_basis_elementer

		UNION ALL		

		SELECT
			3 AS niveau,
			underelement_kode AS kode,
			underelement_tekst AS tekst,
			objekt_type
		FROM basis.v_basis_underelementer
	)

SELECT
	a.niveau,
	a.kode,
	a.niveau || ' ' || a.kode AS niv_kode,
	a.kode || ' ' || b.tekst AS look_up,
	b.objekt_type,
	a.p_style,
	a.l_style,
	a.f_style
FROM styles.d_basis_element_lib a
LEFT JOIN un_ b ON a.niveau = b.niveau AND a.kode = b.kode

ORDER BY a.kode, a.niveau;

COMMENT ON VIEW styles.v_basis_element_lib IS 'Look-up til kopiering af eksistrerende stilarter.';

-- v_element_list

DROP VIEW IF EXISTS styles.v_element_list;

CREATE VIEW styles.v_element_list AS

SELECT DISTINCT
	1 AS niveau,
	c.hovedelement_kode AS kode,
	c.objekt_type,
	c.point_color,
	c.name,
	c.line_color,
	c.line_style,
	c.poly_color,
	c.style
FROM basis.v_basis_underelementer a
LEFT JOIN basis.v_basis_elementer b ON a.element_kode = b.element_kode
LEFT JOIN basis.v_basis_hovedelementer c ON b.hovedelement_kode = c.hovedelement_kode

UNION ALL

SELECT DISTINCT
	2 AS niveau,
	b.element_kode AS kode,
	b.objekt_type,
	b.point_color,
	b.name,
	b.line_color,
	b.line_style,
	b.poly_color,
	b.style
FROM basis.v_basis_underelementer a
LEFT JOIN basis.v_basis_elementer b ON a.element_kode = b.element_kode
LEFT JOIN basis.v_basis_hovedelementer c ON b.hovedelement_kode = c.hovedelement_kode

UNION ALL

SELECT
	3 AS niveau,
	a.underelement_kode AS kode,
	a.objekt_type,
	a.point_color,
	a.name,
	a.line_color,
	a.line_style,
	a.poly_color,
	a.style
FROM basis.v_basis_underelementer a
LEFT JOIN basis.v_basis_elementer b ON a.element_kode = b.element_kode
LEFT JOIN basis.v_basis_hovedelementer c ON b.hovedelement_kode = c.hovedelement_kode

ORDER BY kode, niveau;

COMMENT ON VIEW styles.v_element_list IS 'Elementliste over alle aktive elementer';

-- v_element_list_historik

DROP VIEW IF EXISTS styles.v_element_list_historik;

CREATE VIEW styles.v_element_list_historik AS

WITH 

	ebu AS(
		SELECT 
			b.hovedelement_kode,
			a.objekt_type
		FROM basis.e_basis_underelementer a
		LEFT JOIN basis.e_basis_elementer b ON a.element_kode = b.element_kode
	)

SELECT DISTINCT
	1 AS niveau,
	c.hovedelement_kode AS kode,
	CASE 
		WHEN c.hovedelement_kode IN(SELECT 
										hovedelement_kode
									FROM ebu
									WHERE objekt_type ILIKE '%F%')
		THEN 'F'
		ELSE ''
	END ||
	CASE 
		WHEN c.hovedelement_kode IN(SELECT 
										hovedelement_kode
									FROM ebu
									WHERE objekt_type ILIKE '%L%')
		THEN 'L'
		ELSE ''
	END ||
	CASE 
		WHEN c.hovedelement_kode IN(SELECT 
										hovedelement_kode
									FROM ebu
									WHERE objekt_type ILIKE '%P%')
		THEN 'P'
		ELSE ''
	END AS objekt_type,
	c.point_color,
	c.name,
	c.line_color,
	c.line_style,
	c.poly_color,
	c.style
FROM basis.e_basis_underelementer a
LEFT JOIN basis.e_basis_elementer b ON a.element_kode = b.element_kode
LEFT JOIN basis.e_basis_hovedelementer c ON b.hovedelement_kode = c.hovedelement_kode

UNION ALL

SELECT DISTINCT
	2 AS niveau,
	b.element_kode AS kode,
	CASE 
		WHEN b.element_kode IN(SELECT
									element_kode
								FROM basis.e_basis_underelementer
								WHERE objekt_type ILIKE '%F%')
		THEN 'F'
		ELSE ''
	END ||
	CASE 
		WHEN b.element_kode IN(SELECT
									element_kode
								FROM basis.e_basis_underelementer
								WHERE objekt_type ILIKE '%L%')
		THEN 'L'
		ELSE ''
	END ||
	CASE 
		WHEN b.element_kode IN(SELECT
									element_kode
								FROM basis.e_basis_underelementer
								WHERE objekt_type ILIKE '%P%')
		THEN 'P'
		ELSE ''
	END AS objekt_type,
	b.point_color,
	b.name,
	b.line_color,
	b.line_style,
	b.poly_color,
	b.style
FROM basis.e_basis_underelementer a
LEFT JOIN basis.e_basis_elementer b ON a.element_kode = b.element_kode
LEFT JOIN basis.e_basis_hovedelementer c ON b.hovedelement_kode = c.hovedelement_kode

UNION ALL

SELECT
	3 AS niveau,
	a.underelement_kode AS kode,
	a.objekt_type,
	a.point_color,
	a.name,
	a.line_color,
	a.line_style,
	a.poly_color,
	a.style
FROM basis.e_basis_underelementer a
LEFT JOIN basis.e_basis_elementer b ON a.element_kode = b.element_kode
LEFT JOIN basis.e_basis_hovedelementer c ON b.hovedelement_kode = c.hovedelement_kode

ORDER BY kode, niveau;

COMMENT ON VIEW styles.v_element_list_historik IS 'Elementliste over alle elementer';

-- v_elements_default

DROP VIEW IF EXISTS styles.v_elements_default;

CREATE VIEW styles.v_elements_default AS

WITH
	
	style_ AS ( -- Select full element list with styles for each table
		SELECT
			ROW_NUMBER() OVER(PARTITION BY a.f_table_name ORDER BY b.kode) - 1 AS row,
			a.f_table_name,
			b.kode,
			CASE
				WHEN a.geometry_type = 'F'
				THEN CASE
						WHEN c.f_style IS NOT NULL
						THEN c.f_style || E'\n'
						ELSE (SELECT poly FROM styles.simple_style(b.niveau, b.kode))
					END
				WHEN a.geometry_type = 'L'
				THEN CASE
						WHEN c.l_style IS NOT NULL
						THEN c.l_style || E'\n'
						ELSE (SELECT line FROM styles.simple_style(b.niveau, b.kode))
					END
				WHEN a.geometry_type = 'P'
				THEN CASE
						WHEN c.p_style IS NOT NULL
						THEN c.p_style || E'\n'
						ELSE (SELECT point FROM styles.simple_style(b.niveau, b.kode))
					END
				END AS body
		FROM styles.d_tables a
		LEFT JOIN styles.v_element_list b ON b.niveau = 2 AND EXISTS(SELECT regexp_matches(b.objekt_type, a.geometry_type))
		LEFT JOIN styles.d_basis_element_lib c ON b.niveau = c.niveau AND b.kode = c.kode
	),
	
	categories_ AS( -- Select list of categories for styles
		SELECT
			row,
			a.f_table_name,
			'      <category render="true" symbol="' || a.row
			|| '" value="' || a.kode
			|| '" label="' || a.kode || ' ' || b.element_tekst
			|| E'"/>\n' AS body
		FROM style_ a
		LEFT JOIN basis.e_basis_elementer b ON a.kode = b.element_kode
	),

	string_cat_ AS ( -- Concatenate categories
		SELECT
			a.f_table_name,
			E'<renderer-v2 attr="element_kode" forceraster="0" symbollevels="0" type="categorizedSymbol" enableorderby="0">\n    <categories>\n' || string_agg(a.body, '') || '      <category render="true" symbol="' || b.max_row || E'" value="" label="Ikke klassificeret"/>\n    </categories>\n' AS body
		FROM categories_ a
		LEFT JOIN (SELECT f_table_name, max(row)+1 AS max_row FROM categories_ GROUP BY f_table_name) b ON a.f_table_name = b.f_table_name
		GROUP BY a.f_table_name, b.max_row
	),

	elements_ AS ( -- Concatenate element styles + end
		SELECT
			a.f_table_name,
			E'    <symbols>\n' || string_agg(regexp_replace(regexp_replace(a.body, 'name="[0-9]*"', 'name="' || a.row || '"'), 'name="@[0-9]*@', 'name="@' || a.row || '@', 'g'), '')
			|| regexp_replace(regexp_replace(COALESCE(b.style, ''), 'name="[0-9]*"', 'name="' || c.max_row || '"'), 'name="@[0-9]*@', 'name="@' || c.max_row || '@', 'g') || E'\n    </symbols>' AS body
		FROM style_ a
		LEFT JOIN styles.d_not_categorized b ON a.f_table_name = b.f_table_name
		LEFT JOIN (SELECT f_table_name, max(row)+1 AS max_row FROM categories_ GROUP BY f_table_name) c ON a.f_table_name = c.f_table_name
		GROUP BY a.f_table_name, b.style, c.max_row
	)

SELECT
	a.f_table_name,
	b.body || c.body AS body
FROM styles.d_tables a
LEFT JOIN string_cat_ b ON a.f_table_name = b.f_table_name
LEFT JOIN elements_ c ON a.f_table_name = c.f_table_name;

COMMENT ON VIEW styles.v_elements_default IS 'Genererer stilarter til DEFAULT.';

-- v_elements_special

DROP VIEW IF EXISTS styles.v_elements_special;

CREATE VIEW styles.v_elements_special AS

WITH
	hoved_ AS (
		SELECT DISTINCT
			'hovedelement_kode'::text AS type,
			c.hovedelement_kode,
			1 AS niveau,
			d.hovedelement_kode AS kode,
			d.hovedelement_tekst AS tekst,
			d.hovedelement_kode || ' - ' || d.hovedelement_tekst AS label,
			c.objekt_type AS op_objekt_type,
			d.objekt_type,
			d.point_color,
			d.name,
			d.line_color,
			d.line_style,
			d.poly_color,
			d.style
		FROM basis.v_basis_underelementer a
		LEFT JOIN basis.v_basis_elementer b ON a.element_kode = b.element_kode
		LEFT JOIN basis.v_basis_hovedelementer c ON b.hovedelement_kode != c.hovedelement_kode
		LEFT JOIN basis.v_basis_hovedelementer d ON b.hovedelement_kode = d.hovedelement_kode
		WHERE c.aktiv IS TRUE
	),

	under_ AS (
		SELECT
			'underelement_kode'::text AS type,
			c.hovedelement_kode,
			3 AS niveau,
			a.underelement_kode AS kode,
			a.underelement_tekst AS tekst,
			a.underelement_kode || ' ' || a.underelement_tekst AS label,
			a.objekt_type AS op_objekt_type,
			a.objekt_type,
			a.point_color,
			a.name,
			a.line_color,
			a.line_style,
			a.poly_color,
			a.style
		FROM basis.v_basis_underelementer a
		LEFT JOIN basis.v_basis_elementer b ON a.element_kode = b.element_kode
		LEFT JOIN basis.V_basis_hovedelementer c ON b.hovedelement_kode = c.hovedelement_kode
		WHERE c.aktiv IS TRUE AND b.aktiv IS TRUE AND a.aktiv IS TRUE
	),

	union_ AS (
		SELECT
			*
		FROM hoved_
		
		UNION ALL
		
		SELECT
			*
		FROM under_
	),
	
	style_ AS (
		SELECT
			b.type,
			ROW_NUMBER() OVER(PARTITION BY a.f_table_name, b.hovedelement_kode ORDER BY a.f_table_name, b.hovedelement_kode, b.niveau DESC, b.kode) - 1 AS row,
			a.f_table_name,
			b.hovedelement_kode,
			b.kode,
			b.tekst,
			b.label,
				CASE
					WHEN a.geometry_type = 'F'
					THEN CASE
							WHEN c.f_style IS NOT NULL
							THEN c.f_style || E'\n'
							ELSE (SELECT poly FROM styles.simple_style(b.niveau, b.kode))
						END
					WHEN a.geometry_type = 'L'
					THEN CASE
							WHEN c.l_style IS NOT NULL
							THEN c.l_style || E'\n'
							ELSE (SELECT line FROM styles.simple_style(b.niveau, b.kode))
						END
					WHEN a.geometry_type = 'P'
					THEN CASE
							WHEN c.p_style IS NOT NULL
							THEN c.p_style || E'\n'
							ELSE (SELECT point FROM styles.simple_style(b.niveau, b.kode))
						END
					END AS body
		FROM styles.d_tables a
		LEFT JOIN union_ b ON EXISTS(SELECT regexp_matches(b.objekt_type, a.geometry_type)) AND EXISTS(SELECT regexp_matches(b.op_objekt_type, a.geometry_type))
		LEFT JOIN styles.d_basis_element_lib c ON b.niveau = c.niveau AND b.kode = c.kode
	),
	
	categories_ AS (
		SELECT
			a.row,
			a.hovedelement_kode,
			a.f_table_name,
			'      <rule filter="&quot;' || a.type || '&quot; = ''' || a.kode || '''" key="{' || (SELECT public.uuid_generate_v1()) || '}" symbol="' || a.row || '" label="' || a.label || E'"/>\n' AS body
		FROM style_ a
	),
	
	string_cat_ AS (
		SELECT
			f_table_name,
			hovedelement_kode,
			E'<renderer-v2 forceraster="0" symbollevels="0" type="RuleRenderer" enableorderby="0">\n    <rules key="{' || (SELECT public.uuid_generate_v1()) || E'}">\n' ||
			string_agg(body, '') || E'    </rules>\n' AS body
		FROM categories_
		GROUP BY f_table_name, hovedelement_kode
	),
	
	elements_ AS (
		SELECT
			a.f_table_name,
			a.hovedelement_kode,
			E'    <symbols>\n'  || string_agg(regexp_replace(regexp_replace(a.body, 'name="[0-9]*"', 'name="' || a.row || '"'), 'name="@[0-9]*@', 'name="@' || a.row || '@', 'g'), '') || '    </symbols>' AS body
		FROM style_ a
		GROUP BY a.f_table_name, a.hovedelement_kode
	)
	
SELECT DISTINCT ON (a.f_table_name, a.hovedelement_kode)
	a.f_table_name,
	a.hovedelement_kode,
	b.body ||c.body AS body
FROM style_ a
LEFT JOIN string_cat_ b ON a.f_table_name = b.f_table_name AND a.hovedelement_kode = b.hovedelement_kode
LEFT JOIN elements_ c ON a.f_table_name = c.f_table_name AND a.hovedelement_kode = c.hovedelement_kode;


COMMENT ON VIEW styles.v_elements_special IS 'Genererer stilarter for specielle kategoriseringer.';

-- v_elements_hovedelementer

DROP VIEW IF EXISTS styles.v_elements_hovedelementer;

CREATE VIEW styles.v_elements_hovedelementer AS

WITH
	
	style_ AS ( -- Select full element list with styles for each table
		SELECT
			ROW_NUMBER() OVER(PARTITION BY a.f_table_name ORDER BY b.kode) - 1 AS row,
			a.f_table_name,
			b.kode,
			CASE
				WHEN a.geometry_type = 'F'
				THEN CASE
						WHEN c.f_style IS NOT NULL
						THEN c.f_style || E'\n'
						ELSE (SELECT poly FROM styles.simple_style(b.niveau, b.kode))
					END
				WHEN a.geometry_type = 'L'
				THEN CASE
						WHEN c.l_style IS NOT NULL
						THEN c.l_style || E'\n'
						ELSE (SELECT line FROM styles.simple_style(b.niveau, b.kode))
					END
				WHEN a.geometry_type = 'P'
				THEN CASE
						WHEN c.p_style IS NOT NULL
						THEN c.p_style || E'\n'
						ELSE (SELECT point FROM styles.simple_style(b.niveau, b.kode))
					END
				END AS body
		FROM styles.d_tables a
		LEFT JOIN styles.v_element_list b ON b.niveau = 1 AND EXISTS(SELECT regexp_matches(b.objekt_type, a.geometry_type))
		LEFT JOIN styles.d_basis_element_lib c ON b.niveau = c.niveau AND b.kode = c.kode
	),
	
	categories_ AS( -- Select list of categories for styles
		SELECT
			row,
			a.f_table_name,
			'      <category render="true" symbol="' || a.row
			|| '" value="' || a.kode
			|| '" label="' || a.kode || ' ' || b.hovedelement_tekst
			|| E'"/>\n' AS body
		FROM style_ a
		LEFT JOIN basis.e_basis_hovedelementer b ON a.kode = b.hovedelement_kode
	),

	string_cat_ AS ( -- Concatenate categories
		SELECT
			a.f_table_name,
			E'<renderer-v2 attr="hovedelement_kode" forceraster="0" symbollevels="0" type="categorizedSymbol" enableorderby="0">\n    <categories>\n' || string_agg(a.body, '') || E'    </categories>\n' AS body
		FROM categories_ a
		GROUP BY a.f_table_name
	),

	elements_ AS ( -- Concatenate element styles + end
		SELECT
			a.f_table_name,
			E'    <symbols>\n' || string_agg(regexp_replace(regexp_replace(a.body, 'name="[0-9]*"', 'name="' || a.row || '"'), 'name="@[0-9]*@', 'name="@' || a.row || '@', 'g'), '') || E'    </symbols>' AS body
		FROM style_ a
		GROUP BY a.f_table_name
	)

SELECT
	a.f_table_name,
	b.body || c.body AS body
FROM styles.d_tables a
LEFT JOIN string_cat_ b ON a.f_table_name = b.f_table_name
LEFT JOIN elements_ c ON a.f_table_name = c.f_table_name;

COMMENT ON VIEW styles.v_elements_hovedelementer IS 'Genererer stilarter til hovedelementer.';

-- v_elements_atlas

DROP VIEW IF EXISTS styles.v_elements_atlas;

CREATE VIEW styles.v_elements_atlas AS

WITH
	style_ AS ( -- Select full element list with styles for each table
		SELECT
			ROW_NUMBER() OVER(PARTITION BY a.f_table_name ORDER BY b.kode) - 1 AS row,
			a.f_table_name,
			b.kode,
			CASE
				WHEN a.geometry_type = 'F'
				THEN CASE
						WHEN c.f_style IS NOT NULL
						THEN c.f_style || E'\n'
						ELSE (SELECT poly FROM styles.simple_style(b.niveau, b.kode))
					END
				WHEN a.geometry_type = 'L'
				THEN CASE
						WHEN c.l_style IS NOT NULL
						THEN c.l_style || E'\n'
						ELSE (SELECT line FROM styles.simple_style(b.niveau, b.kode))
					END
				WHEN a.geometry_type = 'P'
				THEN CASE
						WHEN c.p_style IS NOT NULL
						THEN c.p_style || E'\n'
						ELSE (SELECT point FROM styles.simple_style(b.niveau, b.kode))
					END
				END AS body
		FROM styles.d_tables a
		LEFT JOIN styles.v_element_list b ON b.niveau = 3 AND EXISTS(SELECT regexp_matches(b.objekt_type, a.geometry_type))
		LEFT JOIN styles.d_basis_element_lib c ON b.niveau = c.niveau AND b.kode = c.kode
	),
	
	categories_ AS (
		SELECT
			a.row,
			a.f_table_name,
			'        <rule filter="&quot;underelement_kode&quot; = ''' || a.kode || '''" key="{' || (SELECT public.uuid_generate_v1()) || '}" symbol="' || a.row || '" label="' || a.kode || ' ' || b.underelement_tekst || E'"/>\n' AS body
		FROM style_ a
		LEFT JOIN basis.e_basis_underelementer b ON a.kode = b.underelement_kode
	),
	
	string_cat_ AS (
		SELECT
			f_table_name,
			E'<renderer-v2 forceraster="0" symbollevels="0" type="RuleRenderer" enableorderby="0">\n    <rules key="{' || (SELECT public.uuid_generate_v1()) || E'}">\n' || E'      <rule filter="&quot;arbejdssted&quot; = attribute(@atlas_feature, ''pg_distrikt_nr'') and distance ( $geometry,@atlas_geometry ) = 0" key="{b87d9f69-63bf-4698-8582-e69453b3d450}">\n' ||
			string_agg(body, '') || E'   </rule>\n    </rules>\n' AS body
		FROM categories_
		GROUP BY f_table_name
	),
	
	elements_ AS (
		SELECT
			a.f_table_name,
			E'    <symbols>\n'  || string_agg(regexp_replace(regexp_replace(a.body, 'name="[0-9]*"', 'name="' || a.row || '"'), 'name="@[0-9]*@', 'name="@' || a.row || '@', 'g'), '') || '    </symbols>' AS body
		FROM style_ a
		GROUP BY a.f_table_name
	)
	
SELECT
	a.f_table_name,
	b.body ||c.body AS body
FROM styles.d_tables a
LEFT JOIN string_cat_ b ON a.f_table_name = b.f_table_name
LEFT JOIN elements_ c ON a.f_table_name = c.f_table_name;


COMMENT ON VIEW styles.v_elements_atlas IS 'Genererer stilarter for atlas.';

-- v_elements_historik

DROP VIEW IF EXISTS styles.v_elements_historik;

CREATE VIEW styles.v_elements_historik AS

WITH
	
	style_ AS ( -- Select full element list with styles for each table
		SELECT
			ROW_NUMBER() OVER(PARTITION BY a.f_table_name ORDER BY b.kode) - 1 AS row,
			a.f_table_name,
			b.kode,
			CASE
				WHEN a.geometry_type = 'F'
				THEN CASE
						WHEN c.f_style IS NOT NULL
						THEN c.f_style || E'\n'
						ELSE (SELECT poly FROM styles.simple_style(b.niveau, b.kode))
					END
				WHEN a.geometry_type = 'L'
				THEN CASE
						WHEN c.l_style IS NOT NULL
						THEN c.l_style || E'\n'
						ELSE (SELECT line FROM styles.simple_style(b.niveau, b.kode))
					END
				WHEN a.geometry_type = 'P'
				THEN CASE
						WHEN c.p_style IS NOT NULL
						THEN c.p_style || E'\n'
						ELSE (SELECT point FROM styles.simple_style(b.niveau, b.kode))
					END
				END AS body
		FROM styles.d_tables a
		LEFT JOIN styles.v_element_list_historik b ON b.niveau = 2 AND EXISTS(SELECT regexp_matches(b.objekt_type, a.geometry_type))
		LEFT JOIN styles.d_basis_element_lib c ON b.niveau = c.niveau AND b.kode = c.kode
	),
	
	categories_ AS( -- Select list of categories for styles
		SELECT
			row,
			a.f_table_name,
			'      <category render="true" symbol="' || a.row
			|| '" value="' || a.kode
			|| '" label="' || a.kode || ' ' || b.element_tekst
			|| E'"/>\n' AS body
		FROM style_ a
		LEFT JOIN basis.e_basis_elementer b ON a.kode = b.element_kode
	),

	string_cat_ AS ( -- Concatenate categories
		SELECT
			a.f_table_name,
			E'<renderer-v2 attr="element_kode" forceraster="0" symbollevels="0" type="categorizedSymbol" enableorderby="0">\n    <categories>\n' || string_agg(a.body, '') || '      <category render="true" symbol="' || b.max_row || E'" value="" label="Ikke klassificeret"/>\n    </categories>\n' AS body
		FROM categories_ a
		LEFT JOIN (SELECT f_table_name, max(row)+1 AS max_row FROM categories_ GROUP BY f_table_name) b ON a.f_table_name = b.f_table_name
		GROUP BY a.f_table_name, b.max_row
	),

	elements_ AS ( -- Concatenate element styles + end
		SELECT
			a.f_table_name,
			E'    <symbols>\n' || string_agg(regexp_replace(regexp_replace(a.body, 'name="[0-9]*"', 'name="' || a.row || '"'), 'name="@[0-9]*@', 'name="@' || a.row || '@', 'g'), '')
			|| regexp_replace(regexp_replace(b.style, 'name="[0-9]*"', 'name="' || c.max_row || '"'), 'name="@[0-9]*@', 'name="@' || c.max_row || '@', 'g') || E'\n    </symbols>' AS body
		FROM style_ a
		LEFT JOIN styles.d_not_categorized b ON a.f_table_name = b.f_table_name
		LEFT JOIN (SELECT f_table_name, max(row)+1 AS max_row FROM categories_ GROUP BY f_table_name) c ON a.f_table_name = c.f_table_name
		GROUP BY a.f_table_name, b.style, c.max_row
	)

SELECT
	a.f_table_name,
	b.body || c.body AS body
FROM styles.d_tables a
LEFT JOIN string_cat_ b ON a.f_table_name = b.f_table_name
LEFT JOIN elements_ c ON a.f_table_name = c.f_table_name;

COMMENT ON VIEW styles.v_elements_historik IS 'Genererer stilarter for historik.';



-- layer_styles

DROP VIEW IF EXISTS public.layer_styles;

CREATE VIEW public.layer_styles AS

-- All other styles that has been saved in the database
SELECT
	id,
	f_table_catalog,
	f_table_schema,
	f_table_name,
	f_geometry_column,
	stylename,
	styleqml,
	stylesld,
	useasdefault,
	description,
	owner,
	ui,
	update_time
FROM styles.layer_styles
WHERE stylename NOT IN('DEFAULT', 'HOVEDELEMENTER', 'ATLAS', 'HISTORIK') AND stylename NOT IN(SELECT hovedelement_kode FROM basis.e_basis_hovedelementer)

UNION ALL

-- All DEFAULT styles
SELECT
	a.id,
	a.f_table_catalog,
	a.f_table_schema,
	a.f_table_name,
	a.f_geometry_column,
	a.stylename,
	regexp_replace(a.styleqml, '<renderer-v2((.|\n)*)</symbols>', (SELECT body FROM styles.v_elements_default b WHERE b.f_table_name = a.f_table_name)) AS styleqml,
	NULL AS stylesld,
	a.useasdefault,
	a.description,
	a.owner,
	a.ui,
	a.update_time
FROM styles.layer_styles a
WHERE a.stylename = 'DEFAULT'

UNION ALL

-- All HOVEDELEMENTER styles
SELECT
	a.id,
	a.f_table_catalog,
	a.f_table_schema,
	a.f_table_name,
	a.f_geometry_column,
	a.stylename,
	regexp_replace(a.styleqml, '<renderer-v2((.|\n)*)</symbols>', (SELECT body FROM styles.v_elements_hovedelementer b WHERE b.f_table_name = a.f_table_name)) AS styleqml,
	NULL AS stylesld,
	a.useasdefault,
	a.description,
	a.owner,
	a.ui,
	a.update_time
FROM styles.layer_styles a
WHERE a.stylename = 'HOVEDELEMENTER'

UNION ALL

-- All ATLAS styles
SELECT
	a.id,
	a.f_table_catalog,
	a.f_table_schema,
	a.f_table_name,
	a.f_geometry_column,
	a.stylename,
	regexp_replace(a.styleqml, '<renderer-v2((.|\n)*)</symbols>', (SELECT body FROM styles.v_elements_atlas b WHERE b.f_table_name = a.f_table_name)) AS styleqml,
	NULL AS stylesld,
	a.useasdefault,
	a.description,
	a.owner,
	a.ui,
	a.update_time
FROM styles.layer_styles a
WHERE a.stylename = 'ATLAS'

UNION ALL

-- All styles in e_basis_hovedelementer (Polygons)
SELECT
	a.id,
	a.f_table_catalog,
	a.f_table_schema,
	a.f_table_name,
	a.f_geometry_column,
	a.stylename,
	regexp_replace(a.styleqml, '<renderer-v2((.|\n)*)</symbols>', (SELECT body FROM styles.v_elements_special b WHERE b.f_table_name = a.f_table_name AND b.hovedelement_kode = a.stylename)) AS styleqml,
	NULL AS stylesld,
	a.useasdefault,
	a.description,
	a.owner,
	a.ui,
	a.update_time
FROM styles.layer_styles a
WHERE a.f_table_name = 'v_greg_flader' AND a.stylename IN (SELECT
																b.hovedelement_kode
															FROM basis.e_basis_underelementer a
															LEFT JOIN basis.e_basis_elementer b ON a.element_kode = b.element_kode
															WHERE objekt_type ILIKE '%F%' AND b.aktiv IS TRUE)


UNION ALL

-- All styles in e_basis_hovedelementer (Lines)
SELECT
	a.id,
	a.f_table_catalog,
	a.f_table_schema,
	a.f_table_name,
	a.f_geometry_column,
	a.stylename,
	regexp_replace(a.styleqml, '<renderer-v2((.|\n)*)</symbols>', (SELECT body FROM styles.v_elements_special b WHERE b.f_table_name = a.f_table_name AND b.hovedelement_kode = a.stylename)) AS styleqml,
	NULL AS stylesld,
	a.useasdefault,
	a.description,
	a.owner,
	a.ui,
	a.update_time
FROM styles.layer_styles a
WHERE a.f_table_name = 'v_greg_linier' AND a.stylename IN (SELECT
																b.hovedelement_kode
															FROM basis.e_basis_underelementer a
															LEFT JOIN basis.e_basis_elementer b ON a.element_kode = b.element_kode
															WHERE objekt_type ILIKE '%L%' AND b.aktiv IS TRUE)

UNION ALL

-- All styles in e_basis_hovedelementer (Points)
SELECT
	a.id,
	a.f_table_catalog,
	a.f_table_schema,
	a.f_table_name,
	a.f_geometry_column,
	a.stylename,
	regexp_replace(a.styleqml, '<renderer-v2((.|\n)*)</symbols>', (SELECT body FROM styles.v_elements_special b WHERE b.f_table_name = a.f_table_name AND b.hovedelement_kode = a.stylename)) AS styleqml,
	NULL AS stylesld,
	a.useasdefault,
	a.description,
	a.owner,
	a.ui,
	a.update_time
FROM styles.layer_styles a
WHERE a.f_table_name = 'v_greg_punkter' AND a.stylename IN (SELECT
																b.hovedelement_kode
															FROM basis.e_basis_underelementer a
															LEFT JOIN basis.e_basis_elementer b ON a.element_kode = b.element_kode
															WHERE objekt_type ILIKE '%P%' AND b.aktiv IS TRUE)

UNION ALL

-- All HISTORIK styles
SELECT
	a.id,
	a.f_table_catalog,
	a.f_table_schema,
	a.f_table_name,
	a.f_geometry_column,
	a.stylename,
	regexp_replace(a.styleqml, '<renderer-v2((.|\n)*)</symbols>', (SELECT body FROM styles.v_elements_historik b WHERE b.f_table_name || '_historik' = a.f_table_name)) AS styleqml,
	NULL AS stylesld,
	a.useasdefault,
	a.description,
	a.owner,
	a.ui,
	a.update_time
FROM styles.layer_styles a
WHERE a.stylename = 'HISTORIK';

--
-- CREATE INDEXES
--

-- Indexes for tables in schema greg

CREATE INDEX t_greg_flader_gist ON greg.t_greg_flader USING gist (geometri);

CREATE INDEX t_greg_linier_gist ON greg.t_greg_linier USING gist (geometri);

CREATE INDEX t_greg_punkter_gist ON greg.t_greg_punkter USING gist (geometri);

CREATE INDEX t_greg_omraader_gist ON greg.t_greg_omraader USING gist (geometri);

CREATE INDEX t_greg_delomraader_gist ON greg.t_greg_delomraader USING gist (geometri);

-- Indexes for tables in schema grunddata

CREATE INDEX sidx_bygning_geom ON grunddata.bygning USING gist (geom);

CREATE INDEX sidx_bygraense_geom ON grunddata.bygraense USING gist (geom);

CREATE INDEX sidx_kommunale_veje_geom ON grunddata.kommunale_veje USING gist (geom);

CREATE INDEX sidx_kommunegraense_geom ON grunddata.kommunegraense USING gist (geom);

CREATE INDEX sidx_kyst_geom ON grunddata.kyst USING gist (geom);

CREATE INDEX sidx_matrikelskel_geom ON grunddata.matrikelskel USING gist (geom);

CREATE INDEX sidx_privat_faellesveje_geom ON grunddata.privat_faellesveje USING gist (geom);

CREATE INDEX sidx_skov_geom ON grunddata.skov USING gist (geom);

CREATE INDEX sidx_soe_geom ON grunddata.soe USING gist (geom);

CREATE INDEX sidx_vejkant_geom ON grunddata.vejkant USING gist (geom);

--
-- CREATE TRIGGERS
--

-- Triggers in schema public --

-- layer_styles

CREATE TRIGGER layer_styles_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON public.layer_styles FOR EACH ROW EXECUTE PROCEDURE styles.v_layer_styles_trg();

-- Triggers in schema basis --

-- d_basis_bruger_id

CREATE TRIGGER d_basis_bruger_id_trg_i BEFORE INSERT ON basis.d_basis_bruger_id FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER d_basis_bruger_id_trg_u BEFORE UPDATE ON basis.d_basis_bruger_id FOR EACH ROW EXECUTE PROCEDURE basis.d_basis_bruger_id_trg();

CREATE TRIGGER v_basis_bruger_id_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_bruger_id FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_bruger_id_trg();

-- d_basis_kommunal_kontakt

CREATE TRIGGER d_basis_kommunal_kontakt_trg_i BEFORE INSERT ON basis.d_basis_kommunal_kontakt FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER v_basis_kommunal_kontakt_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_kommunal_kontakt FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_kommunal_kontakt_trg();

-- d_basis_udfoerer

CREATE TRIGGER d_basis_udfoerer_trg_i BEFORE INSERT ON basis.d_basis_udfoerer FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER v_basis_udfoerer_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_udfoerer FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_udfoerer_trg();

-- d_basis_udfoerer_entrep

CREATE TRIGGER d_basis_udfoerer_entrep_trg_i BEFORE INSERT ON basis.d_basis_udfoerer_entrep FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER v_basis_udfoerer_entrep_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_udfoerer_entrep FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_udfoerer_entrep_trg();

-- d_basis_udfoerer_kontakt

CREATE TRIGGER d_basis_udfoerer_kontakt_trg_i BEFORE INSERT ON basis.d_basis_udfoerer_kontakt FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER v_basis_udfoerer_kontakt_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_udfoerer_kontakt FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_udfoerer_kontakt_trg();

-- d_basis_distrikt_type

CREATE TRIGGER d_basis_distrikt_type_trg_i BEFORE INSERT ON basis.d_basis_distrikt_type FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER v_basis_distrikt_type_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_distrikt_type FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_distrikt_type_trg();

-- e_basis_hovedelementer

CREATE TRIGGER e_basis_hovedelementer_trg_i BEFORE INSERT ON basis.e_basis_hovedelementer FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER e_basis_hovedelementer_trg_i_2 BEFORE INSERT ON basis.e_basis_hovedelementer FOR EACH ROW EXECUTE PROCEDURE basis.e_basis_styles_trg();

CREATE TRIGGER e_basis_hovedelementer_trg_trunc BEFORE TRUNCATE ON basis.e_basis_hovedelementer FOR EACH STATEMENT EXECUTE PROCEDURE basis.e_basis_hovedelementer_trg_trunc();

CREATE TRIGGER e_basis_hovedelementer_trg_a_iud AFTER INSERT OR DELETE OR UPDATE ON basis.e_basis_hovedelementer FOR EACH ROW EXECUTE PROCEDURE basis.e_basis_hovedelementer_trg_a_iud();

CREATE TRIGGER v_basis_hovedelementer_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_hovedelementer FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_hovedelementer_trg();

-- e_basis_elementer

CREATE TRIGGER e_basis_elementer_trg_i BEFORE INSERT ON basis.e_basis_elementer FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER e_basis_elementer_trg_i_2 BEFORE INSERT ON basis.e_basis_elementer FOR EACH ROW EXECUTE PROCEDURE basis.e_basis_styles_trg();

CREATE TRIGGER v_basis_elementer_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_elementer FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_elementer_trg();

-- e_basis_underelementer

CREATE TRIGGER e_basis_underelementer_trg_iu BEFORE INSERT ON basis.e_basis_underelementer FOR EACH ROW EXECUTE PROCEDURE basis.e_basis_underelementer_trg();

CREATE TRIGGER e_basis_underelementer_trg_i_2 BEFORE INSERT ON basis.e_basis_underelementer FOR EACH ROW EXECUTE PROCEDURE basis.e_basis_styles_trg();

CREATE TRIGGER v_basis_underelementer_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_underelementer FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_underelementer_trg();

-- d_basis_prisregulering

CREATE TRIGGER v_basis_prisregulering_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_prisregulering FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_prisregulering_trg();

-- Triggers in schema greg --

-- t_greg_flader

CREATE TRIGGER a_t_greg_flader_geometri_trg_iu BEFORE INSERT OR UPDATE ON greg.t_greg_flader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_geometri_trg();

CREATE TRIGGER b_t_greg_flader_generel_trg_iud BEFORE INSERT OR DELETE OR UPDATE ON greg.t_greg_flader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_generel_trg();

CREATE TRIGGER c_t_greg_flader_trg_iu BEFORE INSERT OR UPDATE ON greg.t_greg_flader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_flader_trg();

CREATE TRIGGER t_greg_flader_trg_a_ud AFTER DELETE OR UPDATE ON greg.t_greg_flader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_historik_trg_a_ud();

CREATE TRIGGER v_greg_flader_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_greg_flader FOR EACH ROW EXECUTE PROCEDURE greg.v_greg_flader_trg();

-- t_greg_linier

CREATE TRIGGER a_t_greg_linier_generel_trg_iud BEFORE INSERT OR DELETE OR UPDATE ON greg.t_greg_linier FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_generel_trg();

CREATE TRIGGER b_t_greg_linier_trg_iu BEFORE INSERT OR UPDATE ON greg.t_greg_linier FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_linier_trg();

CREATE TRIGGER t_greg_linier_trg_a_ud AFTER DELETE OR UPDATE ON greg.t_greg_linier FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_historik_trg_a_ud();

CREATE TRIGGER v_greg_linier_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_greg_linier FOR EACH ROW EXECUTE PROCEDURE greg.v_greg_linier_trg();

-- t_greg_punkter

CREATE TRIGGER a_t_greg_punkter_generel_trg_iud BEFORE INSERT OR DELETE OR UPDATE ON greg.t_greg_punkter FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_generel_trg();

CREATE TRIGGER b_t_greg_punkter_trg_iu BEFORE INSERT OR UPDATE ON greg.t_greg_punkter FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_punkter_trg();

CREATE TRIGGER t_greg_punkter_trg_a_ud AFTER DELETE OR UPDATE ON greg.t_greg_punkter FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_historik_trg_a_ud();

CREATE TRIGGER v_greg_punkter_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_greg_punkter FOR EACH ROW EXECUTE PROCEDURE greg.v_greg_punkter_trg();

-- t_greg_omraader

CREATE TRIGGER a_t_greg_omraader_geometri_trg_iu BEFORE INSERT OR UPDATE ON greg.t_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_geometri_trg();

CREATE TRIGGER b_t_greg_omraader_generel_trg_iud BEFORE INSERT OR DELETE OR UPDATE ON greg.t_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_generel_trg();

CREATE TRIGGER c_t_greg_omraader_trg_iu BEFORE INSERT OR UPDATE ON greg.t_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_omraader_trg();

CREATE TRIGGER a_t_greg_omraader_trg_a_ud AFTER DELETE OR UPDATE ON greg.t_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_historik_trg_a_ud();

CREATE TRIGGER b_t_greg_omraader_trg_a_iud AFTER INSERT OR DELETE OR UPDATE ON greg.t_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_omraader_trg_a_iud();

CREATE TRIGGER c_t_greg_omraader_trg_a_ud AFTER DELETE OR UPDATE ON greg.t_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_omraader_trg_a_ud();

CREATE TRIGGER v_greg_omraader_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.v_greg_omraader_trg();

-- t_greg_delomraader

CREATE TRIGGER t_greg_delomraader_trg_iu BEFORE INSERT OR UPDATE ON greg.t_greg_delomraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_delomraader_trg();

-- Triggers in schema styles --

-- layer_styles

CREATE TRIGGER layer_styles_trg BEFORE INSERT OR UPDATE ON styles.layer_styles FOR EACH ROW EXECUTE PROCEDURE styles.layer_styles_trg();

-- v_basis_element_lib

CREATE TRIGGER v_basis_element_lib_trg INSTEAD OF INSERT OR DELETE OR UPDATE ON styles.v_basis_element_lib FOR EACH ROW EXECUTE PROCEDURE styles.v_basis_element_lib_trg();

--
-- CREATE USERGROUPS
--

-- Reader group --

DO

$$

DECLARE

db text;
role text;

BEGIN

	SELECT catalog_name FROM information_schema.information_schema_catalog_name INTO db;
	role := db || '_reader';


	IF NOT EXISTS (SELECT '1' FROM pg_catalog.pg_roles WHERE rolname = role) THEN

		EXECUTE format('CREATE ROLE %s NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION', role);

	END IF;

	EXECUTE format('GRANT CONNECT ON DATABASE %s TO %s', db, role);

	EXECUTE format('GRANT USAGE ON SCHEMA basis TO %s', role);
	EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA basis TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA basis GRANT SELECT ON TABLES TO %s', role);
	EXECUTE format('GRANT UPDATE ON TABLE basis.v_basis_bruger_id TO %s', role);
	EXECUTE format('GRANT UPDATE (navn) ON TABLE basis.d_basis_bruger_id TO %s', role);

	EXECUTE format('GRANT USAGE ON SCHEMA greg TO %s', role);
	EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA greg TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA greg GRANT SELECT ON TABLES TO %s', role);

	EXECUTE format('GRANT USAGE ON SCHEMA grunddata TO %s', role);
	EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA grunddata TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA grunddata GRANT SELECT ON TABLES TO %s', role);
	
	EXECUTE format('GRANT USAGE ON SCHEMA styles TO %s', role);
	EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA styles TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA styles GRANT SELECT ON TABLES TO %s', role);


END;

$$;

-- Writer group --

DO

$$

DECLARE

db text;
role text;

BEGIN

	SELECT catalog_name FROM information_schema.information_schema_catalog_name INTO db;
	role := db || '_writer';


	IF NOT EXISTS (SELECT '1' FROM pg_catalog.pg_roles WHERE rolname = role) THEN

		EXECUTE format('CREATE ROLE %s NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION', role);

	END IF;

	EXECUTE format('GRANT CONNECT ON DATABASE %s TO %s', db, role);

	EXECUTE format('GRANT USAGE ON SCHEMA basis TO %s', role);
	EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA basis TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA basis GRANT SELECT ON TABLES TO %s', role);
	EXECUTE format('GRANT UPDATE ON TABLE basis.v_basis_bruger_id TO %s', role);
	EXECUTE format('GRANT UPDATE (navn) ON TABLE basis.d_basis_bruger_id TO %s', role);

	EXECUTE format('GRANT USAGE ON SCHEMA greg TO %s', role);
	EXECUTE format('GRANT ALL ON ALL TABLES IN SCHEMA greg TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA greg GRANT ALL ON TABLES TO %s', role);
	EXECUTE format('GRANT ALL ON ALL SEQUENCES IN SCHEMA greg TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA greg GRANT ALL ON SEQUENCES TO %s', role);
	EXECUTE format('GRANT ALL ON ALL FUNCTIONS IN SCHEMA greg TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA greg GRANT ALL ON FUNCTIONS TO %s', role);

	EXECUTE format('GRANT USAGE ON SCHEMA grunddata TO %s', role);
	EXECUTE format('GRANT ALL ON ALL TABLES IN SCHEMA grunddata TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA grunddata GRANT ALL ON TABLES TO %s', role);
	EXECUTE format('GRANT ALL ON ALL SEQUENCES IN SCHEMA grunddata TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA grunddata GRANT ALL ON SEQUENCES TO %s', role);
	EXECUTE format('GRANT ALL ON ALL FUNCTIONS IN SCHEMA grunddata TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA grunddata GRANT ALL ON FUNCTIONS TO %s', role);
	
	EXECUTE format('GRANT USAGE ON SCHEMA styles TO %s', role);
	EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA styles TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA styles GRANT SELECT ON TABLES TO %s', role);

END;

$$;

-- Admin group --

DO

$$

DECLARE

db text;
role text;

BEGIN

	SELECT catalog_name FROM information_schema.information_schema_catalog_name INTO db;
	role := db || '_admin';


	IF NOT EXISTS (SELECT '1' FROM pg_catalog.pg_roles WHERE rolname = role) THEN

		EXECUTE format('CREATE ROLE %s NOSUPERUSER INHERIT NOCREATEDB CREATEROLE REPLICATION', role);

	END IF;

	EXECUTE format('GRANT CONNECT ON DATABASE %s TO %s', db, role);

	EXECUTE format('GRANT USAGE ON SCHEMA basis TO %s', role);
	EXECUTE format('GRANT ALL ON ALL TABLES IN SCHEMA basis TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA basis GRANT ALL ON TABLES TO %s', role);
	EXECUTE format('GRANT ALL ON ALL SEQUENCES IN SCHEMA basis TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA basis GRANT ALL ON SEQUENCES TO %s', role);
	EXECUTE format('GRANT ALL ON ALL FUNCTIONS IN SCHEMA basis TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA basis GRANT ALL ON FUNCTIONS TO %s', role);

	EXECUTE format('GRANT USAGE ON SCHEMA greg TO %s', role);
	EXECUTE format('GRANT ALL ON ALL TABLES IN SCHEMA greg TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA greg GRANT ALL ON TABLES TO %s', role);
	EXECUTE format('GRANT ALL ON ALL SEQUENCES IN SCHEMA greg TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA greg GRANT ALL ON SEQUENCES TO %s', role);
	EXECUTE format('GRANT ALL ON ALL FUNCTIONS IN SCHEMA greg TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA greg GRANT ALL ON FUNCTIONS TO %s', role);

	EXECUTE format('GRANT USAGE ON SCHEMA grunddata TO %s', role);
	EXECUTE format('GRANT ALL ON ALL TABLES IN SCHEMA grunddata TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA grunddata GRANT ALL ON TABLES TO %s', role);
	EXECUTE format('GRANT ALL ON ALL SEQUENCES IN SCHEMA grunddata TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA grunddata GRANT ALL ON SEQUENCES TO %s', role);
	EXECUTE format('GRANT ALL ON ALL FUNCTIONS IN SCHEMA grunddata TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA grunddata GRANT ALL ON FUNCTIONS TO %s', role);
	
	EXECUTE format('GRANT USAGE ON SCHEMA styles TO %s', role);
	EXECUTE format('GRANT ALL ON ALL TABLES IN SCHEMA styles TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA styles GRANT ALL ON TABLES TO %s', role);
	EXECUTE format('GRANT ALL ON ALL SEQUENCES IN SCHEMA styles TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA styles GRANT ALL ON SEQUENCES TO %s', role);
	EXECUTE format('GRANT ALL ON ALL FUNCTIONS IN SCHEMA styles TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA styles GRANT ALL ON FUNCTIONS TO %s', role);

END;

$$;

