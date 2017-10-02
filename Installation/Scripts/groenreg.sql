/*
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See
the GNU General Public License for more details. 
*/


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
-- DROP FUNCTION IF EXISTS basis.multiply_aggregate(float, float) CASCADE;

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
-- DROP FUNCTION IF EXISTS basis.f_prisregulering_produkt(dag integer, maaned integer, aar integer);

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
-- DROP FUNCTION IF EXISTS greg.f_aendring_log(aar integer);

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
-- DROP FUNCTION IF EXISTS greg.f_aendring_log_flader(aar integer);

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
				column_name,
				data_type
			FROM information_schema.columns
			WHERE table_schema = 'greg' AND table_name = 't_greg_flader'
		),

		column_string AS ( -- Select all column names as one string where commas will be replace from relevant columns
			SELECT
				string_agg(CASE
								WHEN data_type = ANY(string_to_array((SELECT text_ FROM greg.variabel('data_type')), ','))
								THEN 'regexp_replace(' || column_name || ', '','', '';'', ''g'')'
								ELSE column_name
							END, ',') AS columns
			FROM column_names
		),

		raw AS ( -- Select rows as record where commas has been replaced with semi colon
			SELECT
				*
			FROM greg.select_columns((SELECT columns FROM column_string), 'greg.t_greg_flader', $1)
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
						regexp_split_to_table(regexp_replace(a._row, '[(|)|"]', '', 'g'), ',') AS old, -- Split a record into individual records each representing the contents of one column in the original record
						regexp_split_to_table(regexp_replace(b._row, '[(|)|"]', '', 'g'), ',') AS new -- Split a record into individual records each representing the contents of one column in the original record
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
-- DROP FUNCTION IF EXISTS greg.f_aendring_log_linier(aar integer);

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
				column_name,
				data_type
			FROM information_schema.columns
			WHERE table_schema = 'greg' AND table_name = 't_greg_linier'
		),

		column_string AS ( -- Select all column names as one string where commas will be replace from relevant columns
			SELECT
				string_agg(CASE
								WHEN data_type = ANY(string_to_array((SELECT text_ FROM greg.variabel('data_type')), ','))
								THEN 'regexp_replace(' || column_name || ', '','', '';'', ''g'')'
								ELSE column_name
							END, ',') AS columns
			FROM column_names
		),

		raw AS ( -- Select rows as record where commas has been replaced with semi colon
			SELECT
				*
			FROM greg.select_columns((SELECT columns FROM column_string), 'greg.t_greg_linier', $1)
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
						regexp_split_to_table(regexp_replace(a._row, '[(|)|"]', '', 'g'), ',') AS old, -- Split a record into individual records each representing the contents of one column in the original record
						regexp_split_to_table(regexp_replace(b._row, '[(|)|"]', '', 'g'), ',') AS new -- Split a record into individual records each representing the contents of one column in the original record
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
-- DROP FUNCTION IF EXISTS greg.f_aendring_log_punkter(aar integer);

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
				column_name,
				data_type
			FROM information_schema.columns
			WHERE table_schema = 'greg' AND table_name = 't_greg_punkter'
		),

		column_string AS ( -- Select all column names as one string where commas will be replace from relevant columns
			SELECT
				string_agg(CASE
								WHEN data_type = ANY(string_to_array((SELECT text_ FROM greg.variabel('data_type')), ','))
								THEN 'regexp_replace(' || column_name || ', '','', '';'', ''g'')'
								ELSE column_name
							END, ',') AS columns
			FROM column_names
		),

		raw AS ( -- Select rows as record where commas has been replaced with semi colon
			SELECT
				*
			FROM greg.select_columns((SELECT columns FROM column_string), 'greg.t_greg_punkter', $1)
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
						regexp_split_to_table(regexp_replace(a._row, '[(|)|"]', '', 'g'), ',') AS old,
						regexp_split_to_table(regexp_replace(b._row, '[(|)|"]', '', 'g'), ',') AS new 
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
-- DROP FUNCTION IF EXISTS greg.f_aendring_log_omraader(aar integer);

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
				column_name,
				data_type
			FROM information_schema.columns
			WHERE table_schema = 'greg' AND table_name = 't_greg_omraader'
		),

		column_string AS ( -- Select all column names as one string where commas will be replace from relevant columns
			SELECT
				string_agg(CASE
								WHEN data_type = ANY(string_to_array((SELECT text_ FROM greg.variabel('data_type')), ','))
								THEN 'regexp_replace(' || column_name || ', '','', '';'', ''g'')'
								ELSE column_name
							END, ',') AS columns
			FROM column_names
		),

		raw AS ( -- Select rows as record where commas has been replaced with semi colon
			SELECT
				*
			FROM greg.select_columns((SELECT columns FROM column_string), 'greg.t_greg_omraader', $1)
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
						regexp_split_to_table(regexp_replace(a._row, '[(|)|"]', '', 'g'), ',') AS old,
						regexp_split_to_table(regexp_replace(b._row, '[(|)|"]', '', 'g'), ',') AS new 
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
-- DROP FUNCTION IF EXISTS greg.f_dato_flader(dag integer, maaned integer, aar integer);

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
-- DROP FUNCTION IF EXISTS greg.f_dato_linier(dag integer, maaned integer, aar integer);

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
-- DROP FUNCTION IF EXISTS greg.f_dato_punkter(dag integer, maaned integer, aar integer);

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
-- DROP FUNCTION IF EXISTS greg.f_dato_omraader(dag integer, maaned integer, aar integer);

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

-- f_maengder(dag integer, maaned integer, aar integer)
-- DROP FUNCTION IF EXISTS greg.f_maengder(dag integer, maaned integer, aar integer);

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
				(SELECT speciel FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_flader', a.versions_id)) AS speciel
			FROM greg.f_dato_flader($1, $2, $3) a
			LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
			WHERE ue.speciel_sql IS NOT NULL
		),

		spec_line AS ( -- Select all special calculations for each element on each area code from the current data set
			SELECT
				a.arbejdssted,
				a.underelement_kode,
				(SELECT speciel FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_linier', a.versions_id)) AS speciel
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
					ELSE (SELECT speciel FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_punkter', a.versions_id))
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

-- f_tot_flader(dage integer)
-- DROP FUNCTION IF EXISTS greg.f_tot_flader(dage integer);

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
			LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_fra <= a.systid_fra AND om.systid_til IS NULL
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
-- DROP FUNCTION IF EXISTS greg.f_tot_linier(dage integer);

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
			LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_fra <= a.systid_fra AND om.systid_til IS NULL
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
-- DROP FUNCTION IF EXISTS greg.f_tot_punkter(dage integer);

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
			LEFT JOIN greg.t_greg_omraader om ON a.arbejdssted = om.pg_distrikt_nr AND om.systid_fra <= a.systid_fra AND om.systid_til IS NULL
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
-- DROP FUNCTION IF EXISTS greg.f_tot_omraader(dage integer);

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

-- select_columns(kolonner text, tabel text)
-- DROP FUNCTION IF EXISTS greg.select_columns(kolonner text, tabel text, aar integer);

CREATE FUNCTION greg.select_columns(kolonner text, tabel text, aar integer)
	RETURNS TABLE (
		versions_id uuid,
		objekt_id uuid,
		systid_fra timestamp with time zone,
		systid_til timestamp with time zone,
		_row text
	)
	LANGUAGE plpgsql AS
$$

	BEGIN

		RETURN QUERY EXECUTE format(
			'SELECT versions_id, objekt_id, systid_fra, systid_til, ROW(%s)::text AS _row FROM %s WHERE EXTRACT (YEAR FROM systid_til) = %s OR EXTRACT (YEAR FROM systid_fra) = %3$s', $1, $2, $3);

	END

$$;

COMMENT ON FUNCTION greg.select_columns(kolonner text, tabel text, aar integer) IS 'Funktion, som samler alle kolonner til en record, dog med muligheden for at fjerne kommaer.';

-- spec_calc(sql text, tabel text, versions_id uuid)
-- DROP FUNCTION IF EXISTS greg.spec_calc(sql text, tabel text, versions_id_ uuid);

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
-- DROP FUNCTION IF EXISTS greg.variabel(var text);

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

		ELSIF $1 = 'data_type' THEN -- #Comment

			RETURN QUERY 
				SELECT 
					NULL::integer,
					NULL::numeric,
					'text,character,character varying'::text; -- Comma seperated (No spaces)


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
-- DROP FUNCTION IF EXISTS styles.hex_rgb(text);

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
-- DROP FUNCTION IF EXISTS styles.simple_style(niveau integer, kode text);

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
		login := db || '/' || OLD.bruger_id;

		IF EXISTS (SELECT '1' FROM pg_catalog.pg_roles WHERE rolname = current_user AND rolsuper IS TRUE) OR EXISTS (SELECT '1' FROM basis.d_basis_bruger_id WHERE db || '/' || bruger_id = current_user AND rolle ='a') OR EXISTS (SELECT '1' FROM basis.d_basis_bruger_id WHERE login = current_user) THEN

			RETURN NEW;

		END IF;

		RAISE EXCEPTION 'Redigering af andre brugere er ikke tilladt';

	END

$$;

COMMENT ON FUNCTION basis.d_basis_bruger_id_trg() IS 'Tjekker tilladelse til at redigere i tabel.';

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

			END IF;

			RETURN NULL;

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
			role := db || '/' || NEW.bruger_id;

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

			role := db || '/' || OLD.bruger_id;

			EXECUTE format('DROP ROLE IF EXISTS "%s"', role); -- Drop role

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_bruger_id WHERE bruger_id = OLD.bruger_id) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			IF OLD.bruger_id = ANY(string_to_array((SELECT text_ FROM greg.variabel('users')), ',')) AND OLD.bruger_id <> current_user THEN

				RAISE EXCEPTION 'Brugeren "%" kan ikke ændres', OLD.bruger_id;

			END IF;

			IF NEW.bruger_id != OLD.bruger_id THEN

				RAISE EXCEPTION 'Bruger ID kan ikke ændres. Hvis Bruger ID har været benyttet til registrering kan bruger gøres inaktiv ellers kan brugeren slettes og en ny oprettes';

			END IF;

			IF EXISTS (SELECT '1' FROM pg_catalog.pg_roles WHERE rolname = current_user AND rolsuper IS TRUE) OR EXISTS (SELECT '1' FROM basis.v_basis_bruger_id WHERE login = current_user AND rolle ='a') THEN -- If user is superuser or DB Admin

				UPDATE basis.d_basis_bruger_id
					SET
						navn = NEW.navn,
						rolle = NEW.rolle,
						aktiv = NEW.aktiv
				WHERE bruger_id = OLD.bruger_id;

				IF NEW.aktiv != OLD.aktiv THEN

					EXECUTE format('ALTER ROLE "%s" %s', role, aktiv); -- Change whether or not user can login based on boolean value in table

				END IF;

				IF NEW.password IS NOT NULL THEN

					EXECUTE format('ALTER ROLE "%s" WITH PASSWORD ''%s''', role, NEW.password); -- Change password if entered

				END IF;

				IF NEW.rolle != OLD.rolle THEN

					EXECUTE format('REVOKE %s FROM "%s"', reader, role); -- Clear role membership
					EXECUTE format('REVOKE %s FROM "%s"', writer, role); -- Clear role membership
					EXECUTE format('REVOKE %s FROM "%s"', admin, role); -- Clear role membership

					IF OLD.rolle = 'a' THEN -- If user was admin, but no longer is

						EXECUTE format('ALTER ROLE "%s" WITH NOCREATEROLE', role); -- Remove create role privileges

					ELSIF NEW.rolle = 'a' THEN -- If user has been made admin

						EXECUTE format('ALTER ROLE "%s" WITH CREATEROLE', role); -- Grant create role privileges
						EXECUTE format('GRANT %s to "%s"', admin, role); -- Grant role membership

					END IF;

					IF NEW.rolle = 'r' THEN -- If user has been made reader

						EXECUTE format('GRANT %s to "%s"', reader, role); -- Grant role membership

					ELSIF NEW.rolle = 'w' THEN -- If user has been made writer

						EXECUTE format('GRANT %s to "%s"', writer, role); -- Grant role membership

					END IF;

				END IF;

				RETURN NULL;

			ELSIF OLD.login = current_user THEN -- Changeable settings for the actual non-admin user

				UPDATE basis.d_basis_bruger_id
					SET
						navn = NEW.navn
				WHERE bruger_id = OLD.bruger_id;

				IF NEW.password IS NOT NULL THEN

					EXECUTE format('ALTER ROLE "%s" WITH PASSWORD ''%s''', role, NEW.password); -- Change password if entered

				END IF;

			ELSE

				RAISE EXCEPTION 'Du har ikke mulighed for at ændre på de pågældende indstillinger';

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

				EXECUTE format('CREATE ROLE "%s" %s PASSWORD ''%s'' NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION', role, aktiv, NEW.password); -- Create role
				EXECUTE format('GRANT %s to "%s"', reader, role); -- Grant role membership

			ELSIF NEW.rolle = 'w' THEN -- If user is writer

				EXECUTE format('CREATE ROLE "%s" %s PASSWORD ''%s'' NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION', role, aktiv, NEW.password); -- Create role
				EXECUTE format('GRANT %s to "%s"', writer, role); -- Grant role membership

			ELSIF NEW.rolle = 'a' THEN -- If user is admin

				EXECUTE format('CREATE ROLE "%s" %s PASSWORD ''%s'' NOSUPERUSER INHERIT NOCREATEDB CREATEROLE NOREPLICATION', role, aktiv, NEW.password); -- Create role with create role privileges
				EXECUTE format('GRANT %s to "%s"', admin, role); -- Grant role membership

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

-- v_basis_postnr_trg()

CREATE FUNCTION basis.v_basis_postnr_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_postnr WHERE postnr = OLD.postnr) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM basis.d_basis_postnr
			WHERE postnr = OLD.postnr;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_postnr WHERE postnr = OLD.postnr) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE basis.d_basis_postnr
				SET
					postnr = NEW.postnr,
					postnr_by = NEW.postnr_by,
					aktiv = NEW.aktiv
			WHERE postnr = OLD.postnr;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO basis.d_basis_postnr
				VALUES (
					NEW.postnr,
					NEW.postnr_by,
					NEW.aktiv
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION basis.v_basis_postnr_trg() IS 'Muliggør opdatering gennem v_basis_postnr.';

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

-- v_basis_vejnavn_trg()

CREATE FUNCTION basis.v_basis_vejnavn_trg()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	BEGIN

		IF (TG_OP = 'DELETE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_vejnavn WHERE vejkode = OLD.vejkode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			DELETE
				FROM basis.d_basis_vejnavn
			WHERE vejkode = OLD.vejkode;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF NOT EXISTS (SELECT '1' FROM basis.d_basis_vejnavn WHERE vejkode = OLD.vejkode) THEN -- Check if record still exists

				RETURN NULL;

			END IF;

			UPDATE basis.d_basis_vejnavn
				SET
					vejkode = NEW.vejkode,
					vejnavn = NEW.vejnavn,
					aktiv = NEW.aktiv,
					cvf_vejkode = NEW.cvf_vejkode,
					postnr = NEW.postnr,
					kommunekode = NEW.kommunekode
			WHERE vejkode = OLD.vejkode;

			RETURN NULL;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO basis.d_basis_vejnavn
				VALUES (
					NEW.vejkode,
					NEW.vejnavn,
					NEW.aktiv,
					NEW.cvf_vejkode,
					NEW.postnr,
					NEW.kommunekode
			);

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION basis.v_basis_vejnavn_trg() IS 'Muliggør opdatering gennem v_basis_vejnavn.';

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
					p_style = NEW.p_style,
					-- Line
					line_color = NEW.line_color,
					line_style = NEW.line_style,
					l_style = NEW.l_style,
					-- Polygon
					poly_color = NEW.poly_color,
					style = NEW.style,
					f_style = NEW.f_style
			WHERE hovedelement_kode = OLD.hovedelement_kode;

		ELSIF (TG_OP = 'INSERT') THEN

			INSERT INTO basis.e_basis_hovedelementer
				VALUES (
					NEW.hovedelement_kode,
					NEW.hovedelement_tekst,
					NEW.aktiv,
					-- Point
					NEW.point_color,
					NEW.name,
					NEW.p_style,
					-- Line
					NEW.line_color,
					NEW.line_style,
					NEW.l_style,
					-- Polygon
					NEW.poly_color,
					NEW.style,
					NEW.f_style
			);

		END IF;

		IF NEW.p_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE basis.e_basis_hovedelementer a
				SET p_style = (SELECT
									b.p_style
								FROM styles.v_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.p_style_copy)
			WHERE a.hovedelement_kode = NEW.hovedelement_kode;

		END IF;

		IF NEW.l_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE basis.e_basis_hovedelementer a
				SET l_style = (SELECT
									b.l_style
								FROM styles.v_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.l_style_copy)
			WHERE a.hovedelement_kode = NEW.hovedelement_kode;

		END IF;

		IF NEW.f_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE basis.e_basis_hovedelementer a
				SET f_style = (SELECT
									b.f_style
								FROM styles.v_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.f_style_copy)
			WHERE a.hovedelement_kode = NEW.hovedelement_kode;

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
					p_style = NEW.p_style,
					-- Line
					line_color = NEW.line_color,
					line_style = NEW.line_style,
					l_style = NEW.l_style,
					-- Polygon
					poly_color = NEW.poly_color,
					style = NEW.style,
					f_style = NEW.f_style
			WHERE element_kode = OLD.element_kode;

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
					NEW.p_style,
					-- Line
					NEW.line_color,
					NEW.line_style,
					NEW.l_style,
					-- Polygon
					NEW.poly_color,
					NEW.style,
					NEW.f_style
			);

		END IF;

		IF NEW.p_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE basis.e_basis_elementer a
				SET p_style = (SELECT
									b.p_style
								FROM styles.v_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.p_style_copy)
			WHERE a.element_kode = NEW.element_kode;

		END IF;

		IF NEW.l_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE basis.e_basis_elementer a
				SET l_style = (SELECT
									b.l_style
								FROM styles.v_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.l_style_copy)
			WHERE a.element_kode = NEW.element_kode;

		END IF;

		IF NEW.f_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE basis.e_basis_elementer a
				SET f_style = (SELECT
									b.f_style
								FROM styles.v_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.f_style_copy)
			WHERE a.element_kode = NEW.element_kode;

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
					p_style = NEW.p_style,
					-- Line
					line_color = NEW.line_color,
					line_style = NEW.line_style,
					l_style = NEW.l_style,
					-- Polygon
					poly_color = NEW.poly_color,
					style = NEW.style,
					f_style = NEW.f_style
			WHERE underelement_kode = OLD.underelement_kode;

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
					NEW.p_style,
					-- Line
					NEW.line_color,
					NEW.line_style,
					NEW.l_style,
					-- Polygon
					NEW.poly_color,
					NEW.style,
					NEW.f_style
			);

		END IF;

		IF NEW.p_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE basis.e_basis_underelementer a
				SET p_style = (SELECT
									b.p_style
								FROM styles.v_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.p_style_copy)
			WHERE a.underelement_kode = NEW.underelement_kode;

		END IF;

		IF NEW.l_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE basis.e_basis_underelementer a
				SET l_style = (SELECT
									b.l_style
								FROM styles.v_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.l_style_copy)
			WHERE a.underelement_kode = NEW.underelement_kode;

		END IF;

		IF NEW.f_style_copy IS NOT NULL THEN -- Reuse already existing style

			UPDATE basis.e_basis_underelementer a
				SET f_style = (SELECT
									b.f_style
								FROM styles.v_basis_element_lib b
								WHERE b.niveau || ' ' || b.kode = NEW.f_style_copy)
			WHERE a.underelement_kode = NEW.underelement_kode;

		END IF;

		RETURN NULL;

	END

$$;

COMMENT ON FUNCTION basis.v_basis_underelementer_trg() IS 'Muliggør opdatering gennem v_basis_underelementer.';

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
				NEW.cvr_kode = COALESCE(NEW.cvr_kode, (SELECT int_ FROM greg.variabel('cvr')));
				NEW.oprindkode = COALESCE(NEW.oprindkode, (SELECT int_ FROM greg.variabel('oprind')));
				NEW.statuskode = COALESCE(NEW.statuskode, (SELECT int_ FROM greg.variabel('status')));
				NEW.off_kode = COALESCE(NEW.off_kode, (SELECT int_ FROM greg.variabel('off_')));
				NEW.tilstand_kode = COALESCE(NEW.tilstand_kode, (SELECT int_ FROM greg.variabel('tilstand')));

			ELSIF TG_TABLE_SCHEMA = 'greg' AND TG_TABLE_NAME = 't_greg_omraader' THEN -- Table specific: t_greg_omraader

				-- DEFAULT values
				NEW.aktiv = COALESCE(NEW.aktiv, 't');
				NEW.synlig = COALESCE(NEW.synlig, 't');

			END IF;

			RETURN NEW;

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.t_greg_generel_trg() IS 'Generelle informationer ved INSERT/UPDATE/DELETE for at opretholde historik, samt universelle DEFAULT values.';

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
												WHEN public.ST_Area(public.ST_Intersection(NEW.geometri, b.geometri)) / public.ST_Area(NEW.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
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
												WHEN public.ST_Area(public.ST_Intersection(NEW.geometri, b.geometri)) / public.ST_Area(NEW.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
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
												WHEN public.ST_Length(public.ST_Intersection(NEW.geometri, b.geometri)) / public.ST_Length(NEW.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
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
												WHEN public.ST_Length(public.ST_Intersection(NEW.geometri, b.geometri)) / public.ST_Length(NEW.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
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

-- t_greg_omraader_trg_a_iud()

CREATE FUNCTION greg.t_greg_omraader_trg_a_iud()
	RETURNS trigger
	LANGUAGE plpgsql AS
$$

	DECLARE
	
		geom_var public.geometry('MultiPolygon',25832);

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
												WHEN public.ST_Area(public.ST_Intersection(a.geometri, b.geometri)) / public.ST_Area(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
												THEN TRUE
											END
										AND b.systid_til IS NULL
									)
			WHERE a.arbejdssted = OLD.pg_distrikt_nr AND a.systid_til IS NULL;

			UPDATE greg.t_greg_linier a -- Update t_greg_linier
				SET
					arbejdssted = (SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(a.geometri, b.geometri) IS TRUE
												THEN TRUE
												WHEN public.ST_Length(public.ST_Intersection(a.geometri, b.geometri)) / public.ST_Length(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
												THEN TRUE
											END
										AND b.systid_til IS NULL
									)
			WHERE a.arbejdssted = OLD.pg_distrikt_nr AND a.systid_til IS NULL;

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
			WHERE a.arbejdssted = OLD.pg_distrikt_nr AND a.systid_til IS NULL;

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF public.ST_EQUALS(NEW.geometri, OLD.geometri) IS FALSE OR OLD.pg_distrikt_nr != NEW.pg_distrikt_nr THEN -- If geometry has been changed

				IF public.ST_EQUALS(NEW.geometri, OLD.geometri) IS FALSE THEN

					SELECT public.ST_Multi(public.ST_SymDifference(NEW.geometri, OLD.geometri)) INTO geom_var;

				END IF;

				UPDATE greg.t_greg_flader a -- Update t_greg_flader
					SET
						arbejdssted = (SELECT
											b.pg_distrikt_nr
										FROM greg.t_greg_omraader b
										WHERE	CASE 
													WHEN public.ST_Within(a.geometri, b.geometri) IS TRUE
													THEN TRUE
													WHEN public.ST_Area(public.ST_Intersection(a.geometri, b.geometri)) / public.ST_Area(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
													THEN TRUE
												END
											AND b.systid_til IS NULL
										)
				WHERE 	CASE
							WHEN OLD.pg_distrikt_nr != NEW.pg_distrikt_nr IS TRUE
							THEN a.arbejdssted = OLD.pg_distrikt_nr
							ELSE (a.arbejdssted = NEW.pg_distrikt_nr OR a.arbejdssted IS NULL) AND public.ST_Intersects(a.geometri, geom_var) IS TRUE
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
													WHEN public.ST_Length(public.ST_Intersection(a.geometri, b.geometri)) / public.ST_Length(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
													THEN TRUE
												END
										AND b.systid_til IS NULL
										)
				WHERE 	CASE
							WHEN OLD.pg_distrikt_nr != NEW.pg_distrikt_nr IS TRUE
							THEN a.arbejdssted = OLD.pg_distrikt_nr
							ELSE (a.arbejdssted = NEW.pg_distrikt_nr OR a.arbejdssted IS NULL) AND public.ST_Intersects(a.geometri, geom_var) IS TRUE
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
				WHERE 	CASE
							WHEN OLD.pg_distrikt_nr != NEW.pg_distrikt_nr IS TRUE
							THEN a.arbejdssted = OLD.pg_distrikt_nr
							ELSE (a.arbejdssted = NEW.pg_distrikt_nr OR a.arbejdssted IS NULL) AND public.ST_Intersects(a.geometri, geom_var) IS TRUE
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
												WHEN public.ST_Area(public.ST_Intersection(a.geometri, b.geometri)) / public.ST_Area(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
												THEN TRUE
											END
										AND b.systid_til IS NULL
									)
			WHERE a.arbejdssted IS NULL AND public.ST_Intersects(a.geometri, NEW.geometri) IS TRUE AND a.systid_til IS NULL;

			UPDATE greg.t_greg_linier a -- Update t_greg_linier
				SET
					arbejdssted = (SELECT
										b.pg_distrikt_nr
									FROM greg.t_greg_omraader b
									WHERE	CASE 
												WHEN public.ST_Within(a.geometri, b.geometri) IS TRUE
												THEN TRUE
												WHEN public.ST_Length(public.ST_Intersection(a.geometri, b.geometri)) / public.ST_Length(a.geometri) >= (SELECT num_ FROM greg.variabel('omr_marg'))
												THEN TRUE
											END
										AND b.systid_til IS NULL
									)
			WHERE a.arbejdssted IS NULL AND public.ST_Intersects(a.geometri, NEW.geometri) IS TRUE AND a.systid_til IS NULL;

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
			WHERE a.arbejdssted IS NULL AND public.ST_Intersects(a.geometri, NEW.geometri) IS TRUE AND a.systid_til IS NULL;

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

			RETURN NULL;

		ELSIF (TG_OP = 'UPDATE') THEN

			IF OLD.pg_distrikt_nr != NEW.pg_distrikt_nr THEN

				UPDATE greg.t_greg_delomraader
					SET
						pg_distrikt_nr = NEW.pg_distrikt_nr
				WHERE pg_distrikt_nr = OLD.pg_distrikt_nr;

			END IF;

			RETURN NULL;

		END IF;

	END

$$;

COMMENT ON FUNCTION greg.t_greg_omraader_trg_a_ud() IS 'Opdaterer delområder ved eventuelle ændringer af områdenumre.';

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

COMMENT ON FUNCTION greg.t_greg_delomraader_trg() IS 'Indsætter UUID, retter geometri til multi-geometri.';

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
	CONSTRAINT d_basis_bruger_id_ck_rolle CHECK (rolle IN('a', 'w', 'r'))
);

COMMENT ON TABLE basis.d_basis_bruger_id IS 'Opslagstabel, bruger ID for elementet (FKG).';

-- d_basis_distrikt_type

CREATE TABLE basis.d_basis_distrikt_type (
	pg_distrikt_type_kode serial NOT NULL,
	pg_distrikt_type character varying(30) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_distrikt_type_pk PRIMARY KEY (pg_distrikt_type_kode) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_distrikt_type IS 'Opslagstabel, områdetyper. Fx grønne områder, skoler mv. (FKG).';

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

-- d_basis_postnr

CREATE TABLE basis.d_basis_postnr (
	postnr integer NOT NULL,
	postnr_by character varying(128) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_postnr_pk PRIMARY KEY (postnr) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_postnr IS 'Opslagstabel, postdistrikter (FKG).';

-- d_basis_prisregulering

CREATE TABLE basis.d_basis_prisregulering (
	dato date NOT NULL,
	aendring_pct numeric(10,2),
	CONSTRAINT d_basis_prisregulering_pk PRIMARY KEY (dato) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_prisregulering IS 'Prisregulering af grundpriser i basis.e_basis_underelementer.';

-- d_basis_status

CREATE TABLE basis.d_basis_status (
	statuskode integer NOT NULL,
	status character varying(30) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	CONSTRAINT d_basis_status_pk PRIMARY KEY (statuskode) WITH (fillfactor='10')
);

COMMENT ON TABLE basis.d_basis_status IS 'Opslagstabel, gyldighedsstatus (FKG).';

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

-- e_basis_hovedelementer

CREATE TABLE basis.e_basis_hovedelementer (
	hovedelement_kode character varying(3) NOT NULL,
	hovedelement_tekst character varying(20) NOT NULL,
	aktiv boolean DEFAULT TRUE NOT NULL,
	-- Style Manager
	-- Point
	point_color text DEFAULT '#000000',
	name text DEFAULT 'circle',
	p_style text,
	-- Line
	line_color text DEFAULT '#000000',
	line_style text DEFAULT 'solid',
	l_style text,
	-- Polygon
	poly_color text DEFAULT '#000000',
	style text DEFAULT 'solid',
	f_style text,
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
	p_style text,
	-- Line
	line_color text DEFAULT '#000000',
	line_style text DEFAULT 'solid',
	l_style text,
	-- Polygon
	poly_color text DEFAULT '#000000',
	style text DEFAULT 'solid',
	f_style text,
	CONSTRAINT e_basis_elementer_pk PRIMARY KEY (element_kode) WITH (fillfactor='10'),
	CONSTRAINT e_basis_elementer_fk_e_basis_hovedelementer FOREIGN KEY (hovedelement_kode) REFERENCES basis.e_basis_hovedelementer(hovedelement_kode) MATCH FULL,
	CONSTRAINT e_basis_elementer_ck_element_kode CHECK (element_kode ~* (hovedelement_kode || '-' || '[0-9]{2}')),
	CONSTRAINT e_basis_elementer_ck_name CHECK (name IN ('square', 'diamond', 'pentagon', 'hexagon', 'triangle', 'star', 'arrow', 'circle')),
	CONSTRAINT e_basis_elementer_ck_line_style CHECK (line_style IN ('solid', 'dash', 'dot', 'dash dot', 'dash dot dot')),
	CONSTRAINT e_basis_elementer_ck_style CHECK (style IN ('solid', 'horizontal', 'vertical', 'cross', 'b_diagonal', 'f_diagonal', 'diagonal_x', 'dense1', 'dense2', 'dense3', 'dense4', 'dense5', 'dense6', 'dense7'))
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
	p_style text,
	-- Line
	line_color text DEFAULT '#000000',
	line_style text DEFAULT 'solid',
	l_style text,
	-- Polygon
	poly_color text DEFAULT '#000000',
	style text DEFAULT 'solid',
	f_style text,
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
	CONSTRAINT e_basis_underelementer_ck_name CHECK (name IN ('square', 'diamond', 'pentagon', 'hexagon', 'triangle', 'star', 'arrow', 'circle')),
	CONSTRAINT e_basis_underelementer_ck_line_style CHECK (line_style IN ('solid', 'dash', 'dot', 'dash dot', 'dash dot dot')),
	CONSTRAINT e_basis_underelementer_ck_style CHECK (style IN ('solid', 'horizontal', 'vertical', 'cross', 'b_diagonal', 'f_diagonal', 'diagonal_x', 'dense1', 'dense2', 'dense3', 'dense4', 'dense5', 'dense6', 'dense7'))
);

COMMENT ON TABLE basis.e_basis_underelementer IS 'Opslagstabel, den helt specifikke elementtype. Fx beton, asfalt mv.';

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
	cvr_kode integer NOT NULL,
	oprindkode integer NOT NULL,
	statuskode integer NOT NULL,
	off_kode integer NOT NULL,
	-- FKG #2
	note character varying(254),
	link character varying(1024),
	vejkode integer,
	tilstand_kode integer NOT NULL,
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
	CONSTRAINT t_greg_flader_fk_e_basis_underelementer FOREIGN KEY (underelement_kode) REFERENCES basis.e_basis_underelementer(underelement_kode) MATCH FULL,
	-- Check constraints
	CONSTRAINT t_greg_flader_ck_geometri CHECK (public.ST_IsValid(geometri) IS TRUE AND public.ST_IsEmpty(geometri) IS FALSE),
	CONSTRAINT t_greg_flader_ck_hoejde CHECK (hoejde BETWEEN 0.0 AND 9.9),
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
	cvr_kode integer NOT NULL,
	oprindkode integer NOT NULL,
	statuskode integer NOT NULL,
	off_kode integer NOT NULL,
	-- FKG #2
	note character varying(254),
	link character varying(1024),
	vejkode integer,
	tilstand_kode integer NOT NULL,
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
	CONSTRAINT t_greg_linier_fk_e_basis_underelementer FOREIGN KEY (underelement_kode) REFERENCES basis.e_basis_underelementer(underelement_kode) MATCH FULL,
	-- Check constraints
	CONSTRAINT t_greg_linier_ck_geometri CHECK (public.ST_IsValid(geometri) IS TRUE AND public.ST_IsEmpty(geometri) IS FALSE),
	CONSTRAINT t_greg_linier_ck_maal CHECK (bredde BETWEEN 0.0 AND 9.9 AND hoejde BETWEEN 0.00 AND 9.9)
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
	cvr_kode integer NOT NULL,
	oprindkode integer NOT NULL,
	statuskode integer NOT NULL,
	off_kode integer NOT NULL,
	-- FKG #2
	note character varying(254),
	link character varying(1024),
	vejkode integer,
	tilstand_kode integer NOT NULL,
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
	CONSTRAINT t_greg_punkter_fk_e_basis_underelementer FOREIGN KEY (underelement_kode) REFERENCES basis.e_basis_underelementer(underelement_kode) MATCH FULL,
	-- Check constraints
	CONSTRAINT t_greg_punkter_ck_geometri CHECK (public.ST_IsEmpty(geometri) IS FALSE),
	CONSTRAINT t_greg_punkter_ck_maal CHECK (hoejde >= 0.0 AND ((laengde = 0.0 AND bredde = 0.0 AND diameter >= 0.0) OR (laengde >= 0.0 AND bredde >= 0.0 AND diameter = 0.0)))
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

-- d_hex_rgb

CREATE TABLE styles.d_hex_rgb (
	hex character(1) NOT NULL,
	rgb integer NOT NULL,
	CONSTRAINT d_hex_rgb_pk PRIMARY KEY (hex) WITH (fillfactor='10')
);

COMMENT ON TABLE styles.d_hex_rgb IS 'Konvertering af hexadecimaler til værdier for udregning af RGB-kode.';

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
	CONSTRAINT d_not_categorized_pk PRIMARY KEY (f_table_name) WITH (fillfactor='10'),
	CONSTRAINT d_not_categorized_fk_d_tables FOREIGN KEY (f_table_name) REFERENCES styles.d_tables(f_table_name) MATCH FULL
);

COMMENT ON TABLE styles.d_not_categorized IS 'Stilart for ''Ikke klassificeret''.';

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

-- Views in schema basis --

-- v_basis_bruger_id

CREATE VIEW basis.v_basis_bruger_id AS

SELECT
	CASE
		WHEN CASE
				WHEN bruger_id = ANY(string_to_array((SELECT text_ FROM greg.variabel('users')), ','))
				THEN bruger_id
				ELSE (SELECT catalog_name FROM information_schema.information_schema_catalog_name) || '/' || bruger_id
			END = current_user
		THEN 'Du er logget ind som:'
		ELSE NULL
	END AS aktiv_bruger,
	CASE
		WHEN bruger_id != ALL(string_to_array((SELECT text_ FROM greg.variabel('users')), ','))
		THEN (SELECT catalog_name FROM information_schema.information_schema_catalog_name) || '/'
		ELSE NULL::text
	END AS prefix,
	bruger_id,
	CASE
		WHEN bruger_id = ANY(string_to_array((SELECT text_ FROM greg.variabel('users')), ','))
		THEN CASE
				WHEN bruger_id IN (SELECT rolname FROM pg_catalog.pg_roles)
				THEN bruger_id
				ELSE NULL::text
			END
		ELSE CASE
				WHEN (SELECT catalog_name FROM information_schema.information_schema_catalog_name) || '/' || bruger_id IN (SELECT rolname FROM pg_catalog.pg_roles)
				THEN (SELECT catalog_name FROM information_schema.information_schema_catalog_name) || '/' || bruger_id
				ELSE NULL::text
			END
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

-- v_basis_postnr

CREATE VIEW basis.v_basis_postnr AS

SELECT
	postnr,
	postnr_by,
	postnr || ' ' || postnr_by AS distrikt,
	aktiv
FROM basis.d_basis_postnr;

COMMENT ON VIEW basis.v_basis_postnr IS 'Look-up for d_basis_postnr.';

-- v_basis_prisregulering

CREATE VIEW basis.v_basis_prisregulering AS

SELECT
	dato,
	aendring_pct,
	1 + aendring_pct / 100 AS prisregulering_faktor
FROM basis.d_basis_prisregulering;

COMMENT ON VIEW basis.v_basis_prisregulering IS 'Opdaterbar view. Look-up for d_basis_prisregulering.';

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
	vejkode,
	vejnavn,
	vejnavn || ' (' || postnr || ')' AS vej,
	aktiv,
	cvf_vejkode,
	postnr,
	kommunekode
FROM basis.d_basis_vejnavn;

COMMENT ON VIEW basis.v_basis_vejnavn IS 'Look-up for d_basis_vejnavn.';

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
	a.point_color,
	a.name,
	a.p_style,
	NULL::text AS p_style_copy,
	-- Line
	a.line_color,
	a.line_style,
	a.l_style,
	NULL::text AS l_style_copy,
	-- Polygon
	a.poly_color,
	a.style,
	a.f_style,
	NULL::text AS f_style_copy,
	a.aktiv::text AS aktiv_text
FROM basis.e_basis_hovedelementer a
-- GROUP BY a.hovedelement_kode, a.hovedelement_tekst, p_style, a.point_color, a.name, d.l_style, a.line_color, a.line_style, d.f_style, a.poly_color, a.style
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
	a.point_color,
	a.name,
	a.p_style,
	NULL::text AS p_style_copy,
	-- Line
	a.line_color,
	a.line_style,
	a.l_style,
	NULL::text AS l_style_copy,
	-- Polygon
	a.poly_color,
	a.style,
	a.f_style,
	NULL::text AS f_style_copy,
	a.aktiv::text AS aktiv_text
FROM basis.e_basis_elementer a
LEFT JOIN basis.e_basis_hovedelementer c ON a.hovedelement_kode = c.hovedelement_kode
WHERE c.aktiv IS TRUE
--GROUP BY a.element_kode, a.element_tekst, p_style, a.point_color, a.name, d.l_style, a.line_color, a.line_style, d.f_style, a.poly_color, a.style
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
	a.point_color,
	a.name,
	a.p_style,
	NULL::text AS p_style_copy,
	-- Line
	a.line_color,
	a.line_style,
	a.l_style,
	NULL::text AS l_style_copy,
	-- Polygon
	a.poly_color,
	a.style,
	a.f_style,
	NULL::text AS f_style_copy,
	a.aktiv::text AS aktiv_text
FROM basis.e_basis_underelementer a
LEFT JOIN basis.e_basis_elementer b ON a.element_kode = b.element_kode
LEFT JOIN basis.e_basis_hovedelementer c ON b.hovedelement_kode = c.hovedelement_kode
WHERE b.aktiv IS TRUE AND c.aktiv IS TRUE
ORDER BY a.underelement_kode;

COMMENT ON VIEW basis.v_basis_underelementer IS 'Opdaterbar view. Look-up for e_basis_underelementer.';

-- Views in schema greg --

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
		THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
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
		THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
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
		THEN a.arbejdssted || ' ' || om.pg_distrikt_tekst
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
			(SELECT speciel FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_flader', a.versions_id)) AS speciel
		FROM greg.t_greg_flader a
		LEFT JOIN basis.e_basis_underelementer ue ON a.underelement_kode = ue.underelement_kode
		WHERE systid_til IS NULL AND ue.speciel_sql IS NOT NULL
	),

	spec_line AS ( -- Select all special calculations for each element on each area code from the current data set
		SELECT
			a.arbejdssted,
			a.underelement_kode,
			(SELECT speciel FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_linier', a.versions_id)) AS speciel
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
				ELSE (SELECT speciel FROM greg.spec_calc(ue.speciel_sql, 'greg.t_greg_punkter', a.versions_id))
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

-- Views in schema styles --

-- v_basis_element_lib

DROP VIEW IF EXISTS styles.v_basis_element_lib;

CREATE VIEW styles.v_basis_element_lib AS

WITH 

	ebu AS(
		SELECT 
			b.hovedelement_kode,
			a.objekt_type
		FROM basis.e_basis_underelementer a
		LEFT JOIN basis.e_basis_elementer b ON a.element_kode = b.element_kode
	)

SELECT
	1 AS niveau,
	a.hovedelement_kode AS kode,
	1 || ' ' || a.hovedelement_kode AS niv_kode,
	a.hovedelement_kode || ' ' || a.hovedelement_tekst AS look_up,
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
	a.p_style,
	a.l_style,
	a.f_style
FROM basis.e_basis_hovedelementer a

UNION ALL

SELECT
	2 AS niveau,
	a.element_kode AS kode,
	2 || ' ' || a.element_kode AS niv_kode,
	a.element_kode || ' ' || a.element_tekst AS look_up,
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
	a.p_style,
	a.l_style,
	a.f_style
FROM basis.e_basis_elementer a

UNION ALL

SELECT
	3 AS niveau,
	a.underelement_kode AS kode,
	3 || ' ' || a.underelement_kode AS niv_kode,
	a.underelement_kode || ' ' || a.underelement_tekst AS look_up,
	a.objekt_type,
	a.p_style,
	a.l_style,
	a.f_style
FROM basis.e_basis_underelementer a

ORDER BY kode, niveau;

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
		LEFT JOIN styles.v_basis_element_lib c ON b.niveau = c.niveau AND b.kode = c.kode
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
		LEFT JOIN styles.v_basis_element_lib c ON b.niveau = c.niveau AND b.kode = c.kode
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
		LEFT JOIN styles.v_basis_element_lib c ON b.niveau = c.niveau AND b.kode = c.kode
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
		LEFT JOIN styles.v_basis_element_lib c ON b.niveau = c.niveau AND b.kode = c.kode
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
			string_agg(body, '') || E'      </rule>\n    </rules>\n' AS body
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
	b.body || c.body AS body
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
		LEFT JOIN styles.v_basis_element_lib c ON b.niveau = c.niveau AND b.kode = c.kode
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

-- Views in schema public --

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

-- Indexes for tables in schema greg

CREATE INDEX t_greg_flader_gist ON greg.t_greg_flader USING gist (geometri);

CREATE INDEX t_greg_linier_gist ON greg.t_greg_linier USING gist (geometri);

CREATE INDEX t_greg_punkter_gist ON greg.t_greg_punkter USING gist (geometri);

CREATE INDEX t_greg_omraader_gist ON greg.t_greg_omraader USING gist (geometri);

CREATE INDEX t_greg_delomraader_gist ON greg.t_greg_delomraader USING gist (geometri);

--
-- CREATE TRIGGERS
--

-- Triggers in schema basis --

-- d_basis_bruger_id

CREATE TRIGGER d_basis_bruger_id_trg_i BEFORE INSERT ON basis.d_basis_bruger_id FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER d_basis_bruger_id_trg_u BEFORE UPDATE ON basis.d_basis_bruger_id FOR EACH ROW EXECUTE PROCEDURE basis.d_basis_bruger_id_trg();

CREATE TRIGGER v_basis_bruger_id_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_bruger_id FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_bruger_id_trg();

-- d_basis_kommunal_kontakt

CREATE TRIGGER d_basis_kommunal_kontakt_trg_i BEFORE INSERT ON basis.d_basis_kommunal_kontakt FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER v_basis_kommunal_kontakt_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_kommunal_kontakt FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_kommunal_kontakt_trg();

-- d_basis_postnr

CREATE TRIGGER d_basis_postnr_trg_i BEFORE INSERT ON basis.d_basis_postnr FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER v_basis_postnr_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_postnr FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_postnr_trg();

-- d_basis_prisregulering

CREATE TRIGGER v_basis_prisregulering_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_prisregulering FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_prisregulering_trg();

-- d_basis_udfoerer_kontakt

CREATE TRIGGER d_basis_udfoerer_kontakt_trg_i BEFORE INSERT ON basis.d_basis_udfoerer_kontakt FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER v_basis_udfoerer_kontakt_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_udfoerer_kontakt FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_udfoerer_kontakt_trg();

-- d_basis_vejnavn

CREATE TRIGGER d_basis_vejnavn_trg_i BEFORE INSERT ON basis.d_basis_vejnavn FOR EACH ROW EXECUTE PROCEDURE basis.basis_aktiv_trg();

CREATE TRIGGER v_basis_vejnavn_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON basis.v_basis_vejnavn FOR EACH ROW EXECUTE PROCEDURE basis.v_basis_vejnavn_trg();

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

CREATE TRIGGER a_t_greg_omraader_trg_a_ud AFTER DELETE OR UPDATE ON greg.t_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_historik_trg_a_ud();

CREATE TRIGGER b_t_greg_omraader_trg_a_iud AFTER INSERT OR DELETE OR UPDATE ON greg.t_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_omraader_trg_a_iud();

CREATE TRIGGER c_t_greg_omraader_trg_a_ud AFTER DELETE OR UPDATE ON greg.t_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_omraader_trg_a_ud();

CREATE TRIGGER v_greg_omraader_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON greg.v_greg_omraader FOR EACH ROW EXECUTE PROCEDURE greg.v_greg_omraader_trg();

-- t_greg_delomraader

CREATE TRIGGER t_greg_delomraader_trg_iu BEFORE INSERT OR UPDATE ON greg.t_greg_delomraader FOR EACH ROW EXECUTE PROCEDURE greg.t_greg_delomraader_trg();

-- Triggers in schema styles --

-- layer_styles

CREATE TRIGGER layer_styles_trg BEFORE INSERT OR UPDATE ON styles.layer_styles FOR EACH ROW EXECUTE PROCEDURE styles.layer_styles_trg();

-- Triggers in schema public --

-- layer_styles

CREATE TRIGGER layer_styles_trg_iud INSTEAD OF INSERT OR DELETE OR UPDATE ON public.layer_styles FOR EACH ROW EXECUTE PROCEDURE styles.v_layer_styles_trg();

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


	EXECUTE format('GRANT USAGE ON SCHEMA public TO %s', role);
	EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA public TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO %s', role);

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


	EXECUTE format('GRANT USAGE ON SCHEMA public TO %s', role);
	EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA public TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO %s', role);

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


	EXECUTE format('GRANT USAGE ON SCHEMA public TO %s', role);
	EXECUTE format('GRANT ALL ON ALL TABLES IN SCHEMA public TO %s', role);
	EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO %s', role);

END;

$$;

--
-- INSERTS
--

-- Inserts in schema basis --

-- d_basis_ansvarlig_myndighed

INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (66137112, 'Albertslund Kommune', 165, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (60183112, 'Allerød Kommune', 201, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189692, 'Assens Kommune', 420, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (58271713, 'Ballerup Kommune', 151, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189765, 'Billund Kommune', 530, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (26696348, 'Bornholms Regionskommune', 400, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (65113015, 'Brøndby Kommune', 153, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189501, 'Brønderslev Kommune', 810, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (25775635, 'Christiansø', 411, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (12881517, 'Dragør Kommune', 155, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188386, 'Egedal Kommune', 240, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189803, 'Esbjerg Kommune', 561, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (31210917, 'Fanø Kommune', 563, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189714, 'Favrskov Kommune', 710, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188475, 'Faxe Kommune', 320, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188335, 'Fredensborg Kommune', 210, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (69116418, 'Fredericia Kommune', 607, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (11259979, 'Frederiksberg Kommune', 147, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189498, 'Frederikshavn Kommune', 813, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189129, 'Frederikssund Kommune', 250, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188327, 'Furesø Kommune', 190, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188645, 'Faaborg-Midtfyn Kommune', 430, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (19438414, 'Gentofte Kommune', 157, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (62761113, 'Gladsaxe Kommune', 159, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (65120119, 'Glostrup Kommune', 161, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (44023911, 'Greve Kommune', 253, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188440, 'Gribskov Kommune', 270, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188599, 'Guldborgsund Kommune', 376, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189757, 'Haderslev Kommune', 510, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188416, 'Halsnæs Kommune', 260, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189587, 'Hedensted Kommune', 766, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (64502018, 'Helsingør Kommune', 217, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (63640719, 'Herlev Kommune', 163, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189919, 'Herning Kommune', 657, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189366, 'Hillerød Kommune', 219, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189382, 'Hjørring Kommune', 860, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189447, 'Holbæk Kommune', 316, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189927, 'Holstebro Kommune', 661, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189889, 'Horsens Kommune', 615, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (55606617, 'Hvidovre Kommune', 167, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (19501817, 'Høje-Taastrup Kommune', 169, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (70960516, 'Hørsholm Kommune', 223, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189617, 'Ikast-Brande Kommune', 756, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (11931316, 'Ishøj Kommune', 183, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189439, 'Jammerbugt Kommune', 849, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189595, 'Kalundborg Kommune', 326, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189706, 'Kerteminde Kommune', 440, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189897, 'Kolding Kommune', 621, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (64942212, 'Københavns Kommune', 101, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189374, 'Køge Kommune', 259, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188955, 'Langeland Kommune', 482, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188548, 'Lejre Kommune', 350, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189935, 'Lemvig Kommune', 665, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188572, 'Lolland Kommune', 360, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (11715311, 'Lyngby-Taarbæk Kommune', 173, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (45973328, 'Læsø Kommune', 825, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189455, 'Mariagerfjord Kommune', 846, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189684, 'Middelfart Kommune', 410, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (41333014, 'Morsø Kommune', 773, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189986, 'Norddjurs Kommune', 707, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188947, 'Nordfyns Kommune', 480, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189722, 'Nyborg Kommune', 450, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189625, 'Næstved Kommune', 370, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (32264328, 'Odder Kommune', 727, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (35209115, 'Odense Kommune', 461, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188459, 'Odsherred Kommune', 306, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189668, 'Randers Kommune', 730, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189463, 'Rebild Kommune', 840, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189609, 'Ringkøbing-Skjern Kommune', 760, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (18957981, 'Ringsted Kommune', 329, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189404, 'Roskilde Kommune', 265, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188378, 'Rudersdal Kommune', 230, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (65307316, 'Rødovre Kommune', 175, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (23795515, 'Samsø Kommune', 741, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189641, 'Silkeborg Kommune', 740, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189633, 'Skanderborg Kommune', 746, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189579, 'Skive Kommune', 779, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29188505, 'Slagelse Kommune', 330, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (68534917, 'Solrød Kommune', 269, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189994, 'Sorø Kommune', 340, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29208654, 'Stevns Kommune', 336, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189951, 'Struer Kommune', 671, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189730, 'Svendborg Kommune', 479, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189978, 'Syddjurs Kommune', 706, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189773, 'Sønderborg Kommune', 540, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189560, 'Thisted Kommune', 787, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189781, 'Tønder Kommune', 550, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (20310413, 'Tårnby Kommune', 185, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (19583910, 'Vallensbæk Kommune', 187, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189811, 'Varde Kommune', 573, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189838, 'Vejen Kommune', 575, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189900, 'Vejle Kommune', 630, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189471, 'Vesthimmerlands Kommune', 820, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189846, 'Viborg Kommune', 791, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189676, 'Vordingborg Kommune', 390, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (28856075, 'Ærø Kommune', 492, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189854, 'Aabenraa Kommune', 580, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (29189420, 'Aalborg Kommune', 851, 't');
INSERT INTO basis.d_basis_ansvarlig_myndighed VALUES (55133018, 'Aarhus Kommune', 751, 't');

-- d_basis_bruger_id

-- INSERT INTO basis.d_basis_bruger_id (bruger_id, navn, aktiv) VALUES ();

INSERT INTO basis.d_basis_bruger_id (bruger_id, navn, rolle, aktiv) VALUES ('postgres', 'Administrator', 'a', 't');

-- d_basis_offentlig

INSERT INTO basis.d_basis_offentlig VALUES (1, 'Synlig for alle', 't');
INSERT INTO basis.d_basis_offentlig VALUES (2, 'Synlig for den ansvarlige myndighed', 't');
INSERT INTO basis.d_basis_offentlig VALUES (3, 'Synlig for alle myndigheder, men ikke offentligheden', 't');

-- d_basis_oprindelse

INSERT INTO basis.d_basis_oprindelse VALUES (0, 'Ikke udfyldt', 't', NULL);
INSERT INTO basis.d_basis_oprindelse VALUES (1, 'Ortofoto', 't', 'Der skelnes ikke mellem forskellige producenter og forskellige årgange');
INSERT INTO basis.d_basis_oprindelse VALUES (2, 'Matrikelkort', 't', 'Matrikelkort fra KMS (København og Frederiksberg). Det forudsættes, at der benyttes opdaterede matrikelkort for datoen for planens indberetning');
INSERT INTO basis.d_basis_oprindelse VALUES (3, 'Opmåling', 't', 'Kan være med GPS, andet instrument el. lign. Det er ikke et udtryk for præcisi-on, men at det er udført i marken');
INSERT INTO basis.d_basis_oprindelse VALUES (4, 'FOT / Tekniske kort', 't', 'FOT, DTK, Danmarks Topografisk kortværk eller andre raster kort samt kommunernes tekniske kort eller andre vektorkort. Indtil FOT er landsdækkende benyttes kort10 (jf. overgangsregler for FOT)');
INSERT INTO basis.d_basis_oprindelse VALUES (5, 'Modelberegning', 't', 'GIS analyser eller modellering');
INSERT INTO basis.d_basis_oprindelse VALUES (6, 'Tegning', 't', 'Digitaliseret på baggrund af PDF, billede eller andet tegningsmateriale');
INSERT INTO basis.d_basis_oprindelse VALUES (7, 'Felt-/markbesøg', 't', 'Registrering på baggrund af tilsyn i marken');
INSERT INTO basis.d_basis_oprindelse VALUES (8, 'Borgeranmeldelse', 't', 'Indberetning via diverse borgerløsninger – eks. "Giv et praj"');
INSERT INTO basis.d_basis_oprindelse VALUES (9, 'Luftfoto (historiske 1944-1993)', 't', 'Luftfoto er kendetegnet ved ikke at have samme nøjagtighed i georeferingen, men man kan se en del ting, der ikke er på de nuværende ortofoto.');
INSERT INTO basis.d_basis_oprindelse VALUES (10, 'Skråfoto', 't', 'Luftfoto tager fra de 4 verdenshjørner');
INSERT INTO basis.d_basis_oprindelse VALUES (11, 'Andre foto', 't', 'Foto taget i jordhøjde - "terræn foto" (street-view, sagsbehandlerfotos, borgerfotos m.v.). Her er det meget tydeligt at se de enkelte detaljer, men også her kan man normalt ikke direkte placere et punkt via fotoet, men må over at gøre det via noget andet.');
INSERT INTO basis.d_basis_oprindelse VALUES (12, '3D', 't', 'Laserscanning, Digital terrænmodel (DTM) afledninger, termografiske målinger (bestemmelse af temperaturforskelle) o.lign.');

-- d_basis_postnr

INSERT INTO basis.d_basis_postnr VALUES (800, 'Høje Taastrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (900, 'København C', 't');
INSERT INTO basis.d_basis_postnr VALUES (917, 'Københavns Pakkecent', 't');
INSERT INTO basis.d_basis_postnr VALUES (960, 'Udland', 't');
INSERT INTO basis.d_basis_postnr VALUES (999, 'København C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1000, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1050, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1051, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1052, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1053, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1054, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1055, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1056, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1057, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1058, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1059, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1060, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1061, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1062, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1063, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1064, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1065, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1066, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1067, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1068, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1069, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1070, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1071, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1072, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1073, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1074, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1092, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1093, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1095, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1098, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1100, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1101, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1102, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1103, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1104, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1105, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1106, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1107, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1110, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1111, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1112, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1113, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1114, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1115, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1116, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1117, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1118, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1119, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1120, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1121, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1122, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1123, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1124, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1125, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1126, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1127, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1128, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1129, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1130, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1131, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1140, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1147, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1148, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1150, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1151, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1152, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1153, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1154, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1155, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1156, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1157, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1158, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1159, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1160, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1161, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1162, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1164, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1165, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1166, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1167, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1168, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1169, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1170, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1171, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1172, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1173, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1174, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1175, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1200, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1201, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1202, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1203, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1204, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1205, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1206, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1207, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1208, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1209, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1210, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1211, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1213, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1214, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1215, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1216, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1217, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1218, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1219, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1220, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1221, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1240, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1250, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1251, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1253, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1254, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1255, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1256, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1257, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1259, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1260, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1261, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1263, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1264, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1265, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1266, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1267, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1268, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1270, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1271, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1300, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1301, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1302, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1303, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1304, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1306, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1307, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1308, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1309, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1310, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1311, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1312, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1313, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1314, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1315, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1316, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1317, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1318, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1319, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1320, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1321, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1322, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1323, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1324, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1325, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1326, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1327, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1328, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1329, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1350, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1352, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1353, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1354, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1355, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1356, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1357, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1358, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1359, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1360, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1361, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1362, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1363, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1364, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1365, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1366, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1367, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1368, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1369, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1370, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1371, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1400, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1401, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1402, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1403, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1406, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1407, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1408, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1409, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1410, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1411, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1412, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1413, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1414, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1415, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1416, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1417, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1418, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1419, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1420, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1421, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1422, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1423, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1424, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1425, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1426, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1427, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1428, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1429, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1430, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1431, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1432, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1433, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1434, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1435, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1436, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1437, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1438, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1439, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1440, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1441, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1448, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1450, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1451, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1452, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1453, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1454, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1455, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1456, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1457, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1458, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1459, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1460, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1462, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1463, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1464, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1466, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1467, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1468, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1470, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1471, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1472, 'København K', 't');
INSERT INTO basis.d_basis_postnr VALUES (1500, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1513, 'Centraltastning', 't');
INSERT INTO basis.d_basis_postnr VALUES (1532, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1533, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1550, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1551, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1552, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1553, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1554, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1555, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1556, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1557, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1558, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1559, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1560, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1561, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1562, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1563, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1564, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1566, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1567, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1568, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1569, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1570, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1571, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1572, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1573, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1574, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1575, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1576, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1577, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1592, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1599, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1600, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1601, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1602, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1603, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1604, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1606, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1607, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1608, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1609, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1610, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1611, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1612, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1613, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1614, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1615, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1616, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1617, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1618, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1619, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1620, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1621, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1622, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1623, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1624, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1630, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1631, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1632, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1633, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1634, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1635, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1650, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1651, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1652, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1653, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1654, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1655, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1656, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1657, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1658, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1659, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1660, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1661, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1662, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1663, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1664, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1665, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1666, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1667, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1668, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1669, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1670, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1671, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1672, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1673, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1674, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1675, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1676, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1677, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1699, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1700, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1701, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1702, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1703, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1704, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1705, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1706, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1707, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1708, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1709, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1710, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1711, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1712, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1714, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1715, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1716, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1717, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1718, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1719, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1720, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1721, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1722, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1723, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1724, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1725, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1726, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1727, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1728, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1729, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1730, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1731, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1732, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1733, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1734, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1735, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1736, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1737, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1738, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1739, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1749, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1750, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1751, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1752, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1753, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1754, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1755, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1756, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1757, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1758, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1759, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1760, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1761, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1762, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1763, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1764, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1765, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1766, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1770, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1771, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1772, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1773, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1774, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1775, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1777, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1780, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1785, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1786, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1787, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1790, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1799, 'København V', 't');
INSERT INTO basis.d_basis_postnr VALUES (1800, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1801, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1802, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1803, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1804, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1805, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1806, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1807, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1808, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1809, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1810, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1811, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1812, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1813, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1814, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1815, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1816, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1817, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1818, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1819, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1820, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1822, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1823, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1824, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1825, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1826, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1827, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1828, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1829, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1850, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1851, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1852, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1853, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1854, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1855, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1856, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1857, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1860, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1861, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1862, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1863, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1864, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1865, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1866, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1867, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1868, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1870, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1871, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1872, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1873, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1874, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1875, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1876, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1877, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1878, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1879, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1900, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1901, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1902, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1903, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1904, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1905, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1906, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1908, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1909, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1910, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1911, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1912, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1913, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1914, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1915, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1916, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1917, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1920, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1921, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1922, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1923, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1924, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1925, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1926, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1927, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1928, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1950, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1951, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1952, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1953, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1954, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1955, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1956, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1957, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1958, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1959, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1960, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1961, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1962, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1963, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1964, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1965, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1966, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1967, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1970, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1971, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1972, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1973, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (1974, 'Frederiksberg C', 't');
INSERT INTO basis.d_basis_postnr VALUES (2000, 'Frederiksberg', 't');
INSERT INTO basis.d_basis_postnr VALUES (2100, 'København Ø', 't');
INSERT INTO basis.d_basis_postnr VALUES (2150, 'Nordhavn', 't');
INSERT INTO basis.d_basis_postnr VALUES (2200, 'København N', 't');
INSERT INTO basis.d_basis_postnr VALUES (2300, 'København S', 't');
INSERT INTO basis.d_basis_postnr VALUES (2400, 'København NV', 't');
INSERT INTO basis.d_basis_postnr VALUES (2450, 'København SV', 't');
INSERT INTO basis.d_basis_postnr VALUES (2500, 'Valby', 't');
INSERT INTO basis.d_basis_postnr VALUES (2600, 'Glostrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (2605, 'Brøndby', 't');
INSERT INTO basis.d_basis_postnr VALUES (2610, 'Rødovre', 't');
INSERT INTO basis.d_basis_postnr VALUES (2620, 'Albertslund', 't');
INSERT INTO basis.d_basis_postnr VALUES (2625, 'Vallensbæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (2630, 'Taastrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (2635, 'Ishøj', 't');
INSERT INTO basis.d_basis_postnr VALUES (2640, 'Hedehusene', 't');
INSERT INTO basis.d_basis_postnr VALUES (2650, 'Hvidovre', 't');
INSERT INTO basis.d_basis_postnr VALUES (2660, 'Brøndby Strand', 't');
INSERT INTO basis.d_basis_postnr VALUES (2665, 'Vallensbæk Strand', 't');
INSERT INTO basis.d_basis_postnr VALUES (2670, 'Greve', 't');
INSERT INTO basis.d_basis_postnr VALUES (2680, 'Solrød Strand', 't');
INSERT INTO basis.d_basis_postnr VALUES (2690, 'Karlslunde', 't');
INSERT INTO basis.d_basis_postnr VALUES (2700, 'Brønshøj', 't');
INSERT INTO basis.d_basis_postnr VALUES (2720, 'Vanløse', 't');
INSERT INTO basis.d_basis_postnr VALUES (2730, 'Herlev', 't');
INSERT INTO basis.d_basis_postnr VALUES (2740, 'Skovlunde', 't');
INSERT INTO basis.d_basis_postnr VALUES (2750, 'Ballerup', 't');
INSERT INTO basis.d_basis_postnr VALUES (2760, 'Måløv', 't');
INSERT INTO basis.d_basis_postnr VALUES (2765, 'Smørum', 't');
INSERT INTO basis.d_basis_postnr VALUES (2770, 'Kastrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (2791, 'Dragør', 't');
INSERT INTO basis.d_basis_postnr VALUES (2800, 'Kongens Lyngby', 't');
INSERT INTO basis.d_basis_postnr VALUES (2820, 'Gentofte', 't');
INSERT INTO basis.d_basis_postnr VALUES (2830, 'Virum', 't');
INSERT INTO basis.d_basis_postnr VALUES (2840, 'Holte', 't');
INSERT INTO basis.d_basis_postnr VALUES (2850, 'Nærum', 't');
INSERT INTO basis.d_basis_postnr VALUES (2860, 'Søborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (2870, 'Dyssegård', 't');
INSERT INTO basis.d_basis_postnr VALUES (2880, 'Bagsværd', 't');
INSERT INTO basis.d_basis_postnr VALUES (2900, 'Hellerup', 't');
INSERT INTO basis.d_basis_postnr VALUES (2920, 'Charlottenlund', 't');
INSERT INTO basis.d_basis_postnr VALUES (2930, 'Klampenborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (2942, 'Skodsborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (2950, 'Vedbæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (2960, 'Rungsted Kyst', 't');
INSERT INTO basis.d_basis_postnr VALUES (2970, 'Hørsholm', 't');
INSERT INTO basis.d_basis_postnr VALUES (2980, 'Kokkedal', 't');
INSERT INTO basis.d_basis_postnr VALUES (2990, 'Nivå', 't');
INSERT INTO basis.d_basis_postnr VALUES (3000, 'Helsingør', 't');
INSERT INTO basis.d_basis_postnr VALUES (3050, 'Humlebæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (3060, 'Espergærde', 't');
INSERT INTO basis.d_basis_postnr VALUES (3070, 'Snekkersten', 't');
INSERT INTO basis.d_basis_postnr VALUES (3080, 'Tikøb', 't');
INSERT INTO basis.d_basis_postnr VALUES (3100, 'Hornbæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (3120, 'Dronningmølle', 't');
INSERT INTO basis.d_basis_postnr VALUES (3140, 'Ålsgårde', 't');
INSERT INTO basis.d_basis_postnr VALUES (3150, 'Hellebæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (3200, 'Helsinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (3210, 'Vejby', 't');
INSERT INTO basis.d_basis_postnr VALUES (3220, 'Tisvildeleje', 't');
INSERT INTO basis.d_basis_postnr VALUES (3230, 'Græsted', 't');
INSERT INTO basis.d_basis_postnr VALUES (3250, 'Gilleleje', 't');
INSERT INTO basis.d_basis_postnr VALUES (3300, 'Frederiksværk', 't');
INSERT INTO basis.d_basis_postnr VALUES (3310, 'Ølsted', 't');
INSERT INTO basis.d_basis_postnr VALUES (3320, 'Skævinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (3330, 'Gørløse', 't');
INSERT INTO basis.d_basis_postnr VALUES (3360, 'Liseleje', 't');
INSERT INTO basis.d_basis_postnr VALUES (3370, 'Melby', 't');
INSERT INTO basis.d_basis_postnr VALUES (3390, 'Hundested', 't');
INSERT INTO basis.d_basis_postnr VALUES (3400, 'Hillerød', 't');
INSERT INTO basis.d_basis_postnr VALUES (3450, 'Allerød', 't');
INSERT INTO basis.d_basis_postnr VALUES (3460, 'Birkerød', 't');
INSERT INTO basis.d_basis_postnr VALUES (3480, 'Fredensborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (3490, 'Kvistgård', 't');
INSERT INTO basis.d_basis_postnr VALUES (3500, 'Værløse', 't');
INSERT INTO basis.d_basis_postnr VALUES (3520, 'Farum', 't');
INSERT INTO basis.d_basis_postnr VALUES (3540, 'Lynge', 't');
INSERT INTO basis.d_basis_postnr VALUES (3550, 'Slangerup', 't');
INSERT INTO basis.d_basis_postnr VALUES (3600, 'Frederikssund', 't');
INSERT INTO basis.d_basis_postnr VALUES (3630, 'Jægerspris', 't');
INSERT INTO basis.d_basis_postnr VALUES (3650, 'Ølstykke', 't');
INSERT INTO basis.d_basis_postnr VALUES (3660, 'Stenløse', 't');
INSERT INTO basis.d_basis_postnr VALUES (3670, 'Veksø Sjælland', 't');
INSERT INTO basis.d_basis_postnr VALUES (3700, 'Rønne', 't');
INSERT INTO basis.d_basis_postnr VALUES (3720, 'Aakirkeby', 't');
INSERT INTO basis.d_basis_postnr VALUES (3730, 'Nexø', 't');
INSERT INTO basis.d_basis_postnr VALUES (3740, 'Svaneke', 't');
INSERT INTO basis.d_basis_postnr VALUES (3751, 'Østermarie', 't');
INSERT INTO basis.d_basis_postnr VALUES (3760, 'Gudhjem', 't');
INSERT INTO basis.d_basis_postnr VALUES (3770, 'Allinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (3782, 'Klemensker', 't');
INSERT INTO basis.d_basis_postnr VALUES (3790, 'Hasle', 't');
INSERT INTO basis.d_basis_postnr VALUES (4000, 'Roskilde', 't');
INSERT INTO basis.d_basis_postnr VALUES (4030, 'Tune', 't');
INSERT INTO basis.d_basis_postnr VALUES (4040, 'Jyllinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (4050, 'Skibby', 't');
INSERT INTO basis.d_basis_postnr VALUES (4060, 'Kirke Såby', 't');
INSERT INTO basis.d_basis_postnr VALUES (4070, 'Kirke Hyllinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (4100, 'Ringsted', 't');
INSERT INTO basis.d_basis_postnr VALUES (4130, 'Viby Sjælland', 't');
INSERT INTO basis.d_basis_postnr VALUES (4140, 'Borup', 't');
INSERT INTO basis.d_basis_postnr VALUES (4160, 'Herlufmagle', 't');
INSERT INTO basis.d_basis_postnr VALUES (4171, 'Glumsø', 't');
INSERT INTO basis.d_basis_postnr VALUES (4173, 'Fjenneslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (4174, 'Jystrup Midtsj', 't');
INSERT INTO basis.d_basis_postnr VALUES (4180, 'Sorø', 't');
INSERT INTO basis.d_basis_postnr VALUES (4190, 'Munke Bjergby', 't');
INSERT INTO basis.d_basis_postnr VALUES (4200, 'Slagelse', 't');
INSERT INTO basis.d_basis_postnr VALUES (4220, 'Korsør', 't');
INSERT INTO basis.d_basis_postnr VALUES (4230, 'Skælskør', 't');
INSERT INTO basis.d_basis_postnr VALUES (4241, 'Vemmelev', 't');
INSERT INTO basis.d_basis_postnr VALUES (4242, 'Boeslunde', 't');
INSERT INTO basis.d_basis_postnr VALUES (4243, 'Rude', 't');
INSERT INTO basis.d_basis_postnr VALUES (4250, 'Fuglebjerg', 't');
INSERT INTO basis.d_basis_postnr VALUES (4261, 'Dalmose', 't');
INSERT INTO basis.d_basis_postnr VALUES (4262, 'Sandved', 't');
INSERT INTO basis.d_basis_postnr VALUES (4270, 'Høng', 't');
INSERT INTO basis.d_basis_postnr VALUES (4281, 'Gørlev', 't');
INSERT INTO basis.d_basis_postnr VALUES (4291, 'Ruds Vedby', 't');
INSERT INTO basis.d_basis_postnr VALUES (4293, 'Dianalund', 't');
INSERT INTO basis.d_basis_postnr VALUES (4295, 'Stenlille', 't');
INSERT INTO basis.d_basis_postnr VALUES (4296, 'Nyrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (4300, 'Holbæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (4320, 'Lejre', 't');
INSERT INTO basis.d_basis_postnr VALUES (4330, 'Hvalsø', 't');
INSERT INTO basis.d_basis_postnr VALUES (4340, 'Tølløse', 't');
INSERT INTO basis.d_basis_postnr VALUES (4350, 'Ugerløse', 't');
INSERT INTO basis.d_basis_postnr VALUES (4360, 'Kirke Eskilstrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (4370, 'Store Merløse', 't');
INSERT INTO basis.d_basis_postnr VALUES (4390, 'Vipperød', 't');
INSERT INTO basis.d_basis_postnr VALUES (4400, 'Kalundborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (4420, 'Regstrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (4440, 'Mørkøv', 't');
INSERT INTO basis.d_basis_postnr VALUES (4450, 'Jyderup', 't');
INSERT INTO basis.d_basis_postnr VALUES (4460, 'Snertinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (4470, 'Svebølle', 't');
INSERT INTO basis.d_basis_postnr VALUES (4480, 'Store Fuglede', 't');
INSERT INTO basis.d_basis_postnr VALUES (4490, 'Jerslev Sjælland', 't');
INSERT INTO basis.d_basis_postnr VALUES (4500, 'Nykøbing Sj', 't');
INSERT INTO basis.d_basis_postnr VALUES (4520, 'Svinninge', 't');
INSERT INTO basis.d_basis_postnr VALUES (4532, 'Gislinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (4534, 'Hørve', 't');
INSERT INTO basis.d_basis_postnr VALUES (4540, 'Fårevejle', 't');
INSERT INTO basis.d_basis_postnr VALUES (4550, 'Asnæs', 't');
INSERT INTO basis.d_basis_postnr VALUES (4560, 'Vig', 't');
INSERT INTO basis.d_basis_postnr VALUES (4571, 'Grevinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (4572, 'Nørre Asmindrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (4573, 'Højby', 't');
INSERT INTO basis.d_basis_postnr VALUES (4581, 'Rørvig', 't');
INSERT INTO basis.d_basis_postnr VALUES (4583, 'Sjællands Odde', 't');
INSERT INTO basis.d_basis_postnr VALUES (4591, 'Føllenslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (4592, 'Sejerø', 't');
INSERT INTO basis.d_basis_postnr VALUES (4593, 'Eskebjerg', 't');
INSERT INTO basis.d_basis_postnr VALUES (4600, 'Køge', 't');
INSERT INTO basis.d_basis_postnr VALUES (4621, 'Gadstrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (4622, 'Havdrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (4623, 'Lille Skensved', 't');
INSERT INTO basis.d_basis_postnr VALUES (4632, 'Bjæverskov', 't');
INSERT INTO basis.d_basis_postnr VALUES (4640, 'Faxe', 't');
INSERT INTO basis.d_basis_postnr VALUES (4652, 'Hårlev', 't');
INSERT INTO basis.d_basis_postnr VALUES (4653, 'Karise', 't');
INSERT INTO basis.d_basis_postnr VALUES (4654, 'Faxe Ladeplads', 't');
INSERT INTO basis.d_basis_postnr VALUES (4660, 'Store Heddinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (4671, 'Strøby', 't');
INSERT INTO basis.d_basis_postnr VALUES (4672, 'Klippinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (4673, 'Rødvig Stevns', 't');
INSERT INTO basis.d_basis_postnr VALUES (4681, 'Herfølge', 't');
INSERT INTO basis.d_basis_postnr VALUES (4682, 'Tureby', 't');
INSERT INTO basis.d_basis_postnr VALUES (4683, 'Rønnede', 't');
INSERT INTO basis.d_basis_postnr VALUES (4684, 'Holmegaard', 't');
INSERT INTO basis.d_basis_postnr VALUES (4690, 'Haslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (4700, 'Næstved', 't');
INSERT INTO basis.d_basis_postnr VALUES (4720, 'Præstø', 't');
INSERT INTO basis.d_basis_postnr VALUES (4733, 'Tappernøje', 't');
INSERT INTO basis.d_basis_postnr VALUES (4735, 'Mern', 't');
INSERT INTO basis.d_basis_postnr VALUES (4736, 'Karrebæksminde', 't');
INSERT INTO basis.d_basis_postnr VALUES (4750, 'Lundby', 't');
INSERT INTO basis.d_basis_postnr VALUES (4760, 'Vordingborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (4771, 'Kalvehave', 't');
INSERT INTO basis.d_basis_postnr VALUES (4772, 'Langebæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (4773, 'Stensved', 't');
INSERT INTO basis.d_basis_postnr VALUES (4780, 'Stege', 't');
INSERT INTO basis.d_basis_postnr VALUES (4791, 'Borre', 't');
INSERT INTO basis.d_basis_postnr VALUES (4792, 'Askeby', 't');
INSERT INTO basis.d_basis_postnr VALUES (4793, 'Bogø By', 't');
INSERT INTO basis.d_basis_postnr VALUES (4800, 'Nykøbing F', 't');
INSERT INTO basis.d_basis_postnr VALUES (4840, 'Nørre Alslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (4850, 'Stubbekøbing', 't');
INSERT INTO basis.d_basis_postnr VALUES (4862, 'Guldborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (4863, 'Eskilstrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (4871, 'Horbelev', 't');
INSERT INTO basis.d_basis_postnr VALUES (4872, 'Idestrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (4873, 'Væggerløse', 't');
INSERT INTO basis.d_basis_postnr VALUES (4874, 'Gedser', 't');
INSERT INTO basis.d_basis_postnr VALUES (4880, 'Nysted', 't');
INSERT INTO basis.d_basis_postnr VALUES (4891, 'Toreby L', 't');
INSERT INTO basis.d_basis_postnr VALUES (4892, 'Kettinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (4894, 'Øster Ulslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (4895, 'Errindlev', 't');
INSERT INTO basis.d_basis_postnr VALUES (4900, 'Nakskov', 't');
INSERT INTO basis.d_basis_postnr VALUES (4912, 'Harpelunde', 't');
INSERT INTO basis.d_basis_postnr VALUES (4913, 'Horslunde', 't');
INSERT INTO basis.d_basis_postnr VALUES (4920, 'Søllested', 't');
INSERT INTO basis.d_basis_postnr VALUES (4930, 'Maribo', 't');
INSERT INTO basis.d_basis_postnr VALUES (4941, 'Bandholm', 't');
INSERT INTO basis.d_basis_postnr VALUES (4943, 'Torrig L', 't');
INSERT INTO basis.d_basis_postnr VALUES (4944, 'Fejø', 't');
INSERT INTO basis.d_basis_postnr VALUES (4951, 'Nørreballe', 't');
INSERT INTO basis.d_basis_postnr VALUES (4952, 'Stokkemarke', 't');
INSERT INTO basis.d_basis_postnr VALUES (4953, 'Vesterborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (4960, 'Holeby', 't');
INSERT INTO basis.d_basis_postnr VALUES (4970, 'Rødby', 't');
INSERT INTO basis.d_basis_postnr VALUES (4983, 'Dannemare', 't');
INSERT INTO basis.d_basis_postnr VALUES (4990, 'Sakskøbing', 't');
INSERT INTO basis.d_basis_postnr VALUES (5000, 'Odense C', 't');
INSERT INTO basis.d_basis_postnr VALUES (5200, 'Odense V', 't');
INSERT INTO basis.d_basis_postnr VALUES (5210, 'Odense NV', 't');
INSERT INTO basis.d_basis_postnr VALUES (5220, 'Odense SØ', 't');
INSERT INTO basis.d_basis_postnr VALUES (5230, 'Odense M', 't');
INSERT INTO basis.d_basis_postnr VALUES (5240, 'Odense NØ', 't');
INSERT INTO basis.d_basis_postnr VALUES (5250, 'Odense SV', 't');
INSERT INTO basis.d_basis_postnr VALUES (5260, 'Odense S', 't');
INSERT INTO basis.d_basis_postnr VALUES (5270, 'Odense N', 't');
INSERT INTO basis.d_basis_postnr VALUES (5290, 'Marslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (5300, 'Kerteminde', 't');
INSERT INTO basis.d_basis_postnr VALUES (5320, 'Agedrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (5330, 'Munkebo', 't');
INSERT INTO basis.d_basis_postnr VALUES (5350, 'Rynkeby', 't');
INSERT INTO basis.d_basis_postnr VALUES (5370, 'Mesinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (5380, 'Dalby', 't');
INSERT INTO basis.d_basis_postnr VALUES (5390, 'Martofte', 't');
INSERT INTO basis.d_basis_postnr VALUES (5400, 'Bogense', 't');
INSERT INTO basis.d_basis_postnr VALUES (5450, 'Otterup', 't');
INSERT INTO basis.d_basis_postnr VALUES (5462, 'Morud', 't');
INSERT INTO basis.d_basis_postnr VALUES (5463, 'Harndrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (5464, 'Brenderup Fyn', 't');
INSERT INTO basis.d_basis_postnr VALUES (5466, 'Asperup', 't');
INSERT INTO basis.d_basis_postnr VALUES (5471, 'Søndersø', 't');
INSERT INTO basis.d_basis_postnr VALUES (5474, 'Veflinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (5485, 'Skamby', 't');
INSERT INTO basis.d_basis_postnr VALUES (5491, 'Blommenslyst', 't');
INSERT INTO basis.d_basis_postnr VALUES (5492, 'Vissenbjerg', 't');
INSERT INTO basis.d_basis_postnr VALUES (5500, 'Middelfart', 't');
INSERT INTO basis.d_basis_postnr VALUES (5540, 'Ullerslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (5550, 'Langeskov', 't');
INSERT INTO basis.d_basis_postnr VALUES (5560, 'Aarup', 't');
INSERT INTO basis.d_basis_postnr VALUES (5580, 'Nørre Aaby', 't');
INSERT INTO basis.d_basis_postnr VALUES (5591, 'Gelsted', 't');
INSERT INTO basis.d_basis_postnr VALUES (5592, 'Ejby', 't');
INSERT INTO basis.d_basis_postnr VALUES (5600, 'Faaborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (5610, 'Assens', 't');
INSERT INTO basis.d_basis_postnr VALUES (5620, 'Glamsbjerg', 't');
INSERT INTO basis.d_basis_postnr VALUES (5631, 'Ebberup', 't');
INSERT INTO basis.d_basis_postnr VALUES (5642, 'Millinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (5672, 'Broby', 't');
INSERT INTO basis.d_basis_postnr VALUES (5683, 'Haarby', 't');
INSERT INTO basis.d_basis_postnr VALUES (5690, 'Tommerup', 't');
INSERT INTO basis.d_basis_postnr VALUES (5700, 'Svendborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (5750, 'Ringe', 't');
INSERT INTO basis.d_basis_postnr VALUES (5762, 'Vester Skerninge', 't');
INSERT INTO basis.d_basis_postnr VALUES (5771, 'Stenstrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (5772, 'Kværndrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (5792, 'Årslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (5800, 'Nyborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (5853, 'Ørbæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (5854, 'Gislev', 't');
INSERT INTO basis.d_basis_postnr VALUES (5856, 'Ryslinge', 't');
INSERT INTO basis.d_basis_postnr VALUES (5863, 'Ferritslev Fyn', 't');
INSERT INTO basis.d_basis_postnr VALUES (5871, 'Frørup', 't');
INSERT INTO basis.d_basis_postnr VALUES (5874, 'Hesselager', 't');
INSERT INTO basis.d_basis_postnr VALUES (5881, 'Skårup Fyn', 't');
INSERT INTO basis.d_basis_postnr VALUES (5882, 'Vejstrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (5883, 'Oure', 't');
INSERT INTO basis.d_basis_postnr VALUES (5884, 'Gudme', 't');
INSERT INTO basis.d_basis_postnr VALUES (5892, 'Gudbjerg Sydfyn', 't');
INSERT INTO basis.d_basis_postnr VALUES (5900, 'Rudkøbing', 't');
INSERT INTO basis.d_basis_postnr VALUES (5932, 'Humble', 't');
INSERT INTO basis.d_basis_postnr VALUES (5935, 'Bagenkop', 't');
INSERT INTO basis.d_basis_postnr VALUES (5953, 'Tranekær', 't');
INSERT INTO basis.d_basis_postnr VALUES (5960, 'Marstal', 't');
INSERT INTO basis.d_basis_postnr VALUES (5970, 'Ærøskøbing', 't');
INSERT INTO basis.d_basis_postnr VALUES (5985, 'Søby Ærø', 't');
INSERT INTO basis.d_basis_postnr VALUES (6000, 'Kolding', 't');
INSERT INTO basis.d_basis_postnr VALUES (6040, 'Egtved', 't');
INSERT INTO basis.d_basis_postnr VALUES (6051, 'Almind', 't');
INSERT INTO basis.d_basis_postnr VALUES (6052, 'Viuf', 't');
INSERT INTO basis.d_basis_postnr VALUES (6064, 'Jordrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (6070, 'Christiansfeld', 't');
INSERT INTO basis.d_basis_postnr VALUES (6091, 'Bjert', 't');
INSERT INTO basis.d_basis_postnr VALUES (6092, 'Sønder Stenderup', 't');
INSERT INTO basis.d_basis_postnr VALUES (6093, 'Sjølund', 't');
INSERT INTO basis.d_basis_postnr VALUES (6094, 'Hejls', 't');
INSERT INTO basis.d_basis_postnr VALUES (6100, 'Haderslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (6200, 'Aabenraa', 't');
INSERT INTO basis.d_basis_postnr VALUES (6230, 'Rødekro', 't');
INSERT INTO basis.d_basis_postnr VALUES (6240, 'Løgumkloster', 't');
INSERT INTO basis.d_basis_postnr VALUES (6261, 'Bredebro', 't');
INSERT INTO basis.d_basis_postnr VALUES (6270, 'Tønder', 't');
INSERT INTO basis.d_basis_postnr VALUES (6280, 'Højer', 't');
INSERT INTO basis.d_basis_postnr VALUES (6300, 'Gråsten', 't');
INSERT INTO basis.d_basis_postnr VALUES (6310, 'Broager', 't');
INSERT INTO basis.d_basis_postnr VALUES (6320, 'Egernsund', 't');
INSERT INTO basis.d_basis_postnr VALUES (6330, 'Padborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (6340, 'Kruså', 't');
INSERT INTO basis.d_basis_postnr VALUES (6360, 'Tinglev', 't');
INSERT INTO basis.d_basis_postnr VALUES (6372, 'Bylderup-Bov', 't');
INSERT INTO basis.d_basis_postnr VALUES (6392, 'Bolderslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (6400, 'Sønderborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (6430, 'Nordborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (6440, 'Augustenborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (6470, 'Sydals', 't');
INSERT INTO basis.d_basis_postnr VALUES (6500, 'Vojens', 't');
INSERT INTO basis.d_basis_postnr VALUES (6510, 'Gram', 't');
INSERT INTO basis.d_basis_postnr VALUES (6520, 'Toftlund', 't');
INSERT INTO basis.d_basis_postnr VALUES (6534, 'Agerskov', 't');
INSERT INTO basis.d_basis_postnr VALUES (6535, 'Branderup J', 't');
INSERT INTO basis.d_basis_postnr VALUES (6541, 'Bevtoft', 't');
INSERT INTO basis.d_basis_postnr VALUES (6560, 'Sommersted', 't');
INSERT INTO basis.d_basis_postnr VALUES (6580, 'Vamdrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (6600, 'Vejen', 't');
INSERT INTO basis.d_basis_postnr VALUES (6621, 'Gesten', 't');
INSERT INTO basis.d_basis_postnr VALUES (6622, 'Bække', 't');
INSERT INTO basis.d_basis_postnr VALUES (6623, 'Vorbasse', 't');
INSERT INTO basis.d_basis_postnr VALUES (6630, 'Rødding', 't');
INSERT INTO basis.d_basis_postnr VALUES (6640, 'Lunderskov', 't');
INSERT INTO basis.d_basis_postnr VALUES (6650, 'Brørup', 't');
INSERT INTO basis.d_basis_postnr VALUES (6660, 'Lintrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (6670, 'Holsted', 't');
INSERT INTO basis.d_basis_postnr VALUES (6682, 'Hovborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (6683, 'Føvling', 't');
INSERT INTO basis.d_basis_postnr VALUES (6690, 'Gørding', 't');
INSERT INTO basis.d_basis_postnr VALUES (6700, 'Esbjerg', 't');
INSERT INTO basis.d_basis_postnr VALUES (6705, 'Esbjerg Ø', 't');
INSERT INTO basis.d_basis_postnr VALUES (6710, 'Esbjerg V', 't');
INSERT INTO basis.d_basis_postnr VALUES (6715, 'Esbjerg N', 't');
INSERT INTO basis.d_basis_postnr VALUES (6720, 'Fanø', 't');
INSERT INTO basis.d_basis_postnr VALUES (6731, 'Tjæreborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (6740, 'Bramming', 't');
INSERT INTO basis.d_basis_postnr VALUES (6752, 'Glejbjerg', 't');
INSERT INTO basis.d_basis_postnr VALUES (6753, 'Agerbæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (6760, 'Ribe', 't');
INSERT INTO basis.d_basis_postnr VALUES (6771, 'Gredstedbro', 't');
INSERT INTO basis.d_basis_postnr VALUES (6780, 'Skærbæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (6792, 'Rømø', 't');
INSERT INTO basis.d_basis_postnr VALUES (6800, 'Varde', 't');
INSERT INTO basis.d_basis_postnr VALUES (6818, 'Årre', 't');
INSERT INTO basis.d_basis_postnr VALUES (6823, 'Ansager', 't');
INSERT INTO basis.d_basis_postnr VALUES (6830, 'Nørre Nebel', 't');
INSERT INTO basis.d_basis_postnr VALUES (6840, 'Oksbøl', 't');
INSERT INTO basis.d_basis_postnr VALUES (6851, 'Janderup Vestj', 't');
INSERT INTO basis.d_basis_postnr VALUES (6852, 'Billum', 't');
INSERT INTO basis.d_basis_postnr VALUES (6853, 'Vejers Strand', 't');
INSERT INTO basis.d_basis_postnr VALUES (6854, 'Henne', 't');
INSERT INTO basis.d_basis_postnr VALUES (6855, 'Outrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (6857, 'Blåvand', 't');
INSERT INTO basis.d_basis_postnr VALUES (6862, 'Tistrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (6870, 'Ølgod', 't');
INSERT INTO basis.d_basis_postnr VALUES (6880, 'Tarm', 't');
INSERT INTO basis.d_basis_postnr VALUES (6893, 'Hemmet', 't');
INSERT INTO basis.d_basis_postnr VALUES (6900, 'Skjern', 't');
INSERT INTO basis.d_basis_postnr VALUES (6920, 'Videbæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (6933, 'Kibæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (6940, 'Lem St', 't');
INSERT INTO basis.d_basis_postnr VALUES (6950, 'Ringkøbing', 't');
INSERT INTO basis.d_basis_postnr VALUES (6960, 'Hvide Sande', 't');
INSERT INTO basis.d_basis_postnr VALUES (6971, 'Spjald', 't');
INSERT INTO basis.d_basis_postnr VALUES (6973, 'Ørnhøj', 't');
INSERT INTO basis.d_basis_postnr VALUES (6980, 'Tim', 't');
INSERT INTO basis.d_basis_postnr VALUES (6990, 'Ulfborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (7000, 'Fredericia', 't');
INSERT INTO basis.d_basis_postnr VALUES (7007, 'Fredericia', 't');
INSERT INTO basis.d_basis_postnr VALUES (7080, 'Børkop', 't');
INSERT INTO basis.d_basis_postnr VALUES (7100, 'Vejle', 't');
INSERT INTO basis.d_basis_postnr VALUES (7120, 'Vejle Øst', 't');
INSERT INTO basis.d_basis_postnr VALUES (7130, 'Juelsminde', 't');
INSERT INTO basis.d_basis_postnr VALUES (7140, 'Stouby', 't');
INSERT INTO basis.d_basis_postnr VALUES (7150, 'Barrit', 't');
INSERT INTO basis.d_basis_postnr VALUES (7160, 'Tørring', 't');
INSERT INTO basis.d_basis_postnr VALUES (7171, 'Uldum', 't');
INSERT INTO basis.d_basis_postnr VALUES (7173, 'Vonge', 't');
INSERT INTO basis.d_basis_postnr VALUES (7182, 'Bredsten', 't');
INSERT INTO basis.d_basis_postnr VALUES (7183, 'Randbøl', 't');
INSERT INTO basis.d_basis_postnr VALUES (7184, 'Vandel', 't');
INSERT INTO basis.d_basis_postnr VALUES (7190, 'Billund', 't');
INSERT INTO basis.d_basis_postnr VALUES (7200, 'Grindsted', 't');
INSERT INTO basis.d_basis_postnr VALUES (7250, 'Hejnsvig', 't');
INSERT INTO basis.d_basis_postnr VALUES (7260, 'Sønder Omme', 't');
INSERT INTO basis.d_basis_postnr VALUES (7270, 'Stakroge', 't');
INSERT INTO basis.d_basis_postnr VALUES (7280, 'Sønder Felding', 't');
INSERT INTO basis.d_basis_postnr VALUES (7300, 'Jelling', 't');
INSERT INTO basis.d_basis_postnr VALUES (7321, 'Gadbjerg', 't');
INSERT INTO basis.d_basis_postnr VALUES (7323, 'Give', 't');
INSERT INTO basis.d_basis_postnr VALUES (7330, 'Brande', 't');
INSERT INTO basis.d_basis_postnr VALUES (7361, 'Ejstrupholm', 't');
INSERT INTO basis.d_basis_postnr VALUES (7362, 'Hampen', 't');
INSERT INTO basis.d_basis_postnr VALUES (7400, 'Herning', 't');
INSERT INTO basis.d_basis_postnr VALUES (7430, 'Ikast', 't');
INSERT INTO basis.d_basis_postnr VALUES (7441, 'Bording', 't');
INSERT INTO basis.d_basis_postnr VALUES (7442, 'Engesvang', 't');
INSERT INTO basis.d_basis_postnr VALUES (7451, 'Sunds', 't');
INSERT INTO basis.d_basis_postnr VALUES (7470, 'Karup J', 't');
INSERT INTO basis.d_basis_postnr VALUES (7480, 'Vildbjerg', 't');
INSERT INTO basis.d_basis_postnr VALUES (7490, 'Aulum', 't');
INSERT INTO basis.d_basis_postnr VALUES (7500, 'Holstebro', 't');
INSERT INTO basis.d_basis_postnr VALUES (7540, 'Haderup', 't');
INSERT INTO basis.d_basis_postnr VALUES (7550, 'Sørvad', 't');
INSERT INTO basis.d_basis_postnr VALUES (7560, 'Hjerm', 't');
INSERT INTO basis.d_basis_postnr VALUES (7570, 'Vemb', 't');
INSERT INTO basis.d_basis_postnr VALUES (7600, 'Struer', 't');
INSERT INTO basis.d_basis_postnr VALUES (7620, 'Lemvig', 't');
INSERT INTO basis.d_basis_postnr VALUES (7650, 'Bøvlingbjerg', 't');
INSERT INTO basis.d_basis_postnr VALUES (7660, 'Bækmarksbro', 't');
INSERT INTO basis.d_basis_postnr VALUES (7673, 'Harboøre', 't');
INSERT INTO basis.d_basis_postnr VALUES (7680, 'Thyborøn', 't');
INSERT INTO basis.d_basis_postnr VALUES (7700, 'Thisted', 't');
INSERT INTO basis.d_basis_postnr VALUES (7730, 'Hanstholm', 't');
INSERT INTO basis.d_basis_postnr VALUES (7741, 'Frøstrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (7742, 'Vesløs', 't');
INSERT INTO basis.d_basis_postnr VALUES (7752, 'Snedsted', 't');
INSERT INTO basis.d_basis_postnr VALUES (7755, 'Bedsted Thy', 't');
INSERT INTO basis.d_basis_postnr VALUES (7760, 'Hurup Thy', 't');
INSERT INTO basis.d_basis_postnr VALUES (7770, 'Vestervig', 't');
INSERT INTO basis.d_basis_postnr VALUES (7790, 'Thyholm', 't');
INSERT INTO basis.d_basis_postnr VALUES (7800, 'Skive', 't');
INSERT INTO basis.d_basis_postnr VALUES (7830, 'Vinderup', 't');
INSERT INTO basis.d_basis_postnr VALUES (7840, 'Højslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (7850, 'Stoholm Jyll', 't');
INSERT INTO basis.d_basis_postnr VALUES (7860, 'Spøttrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (7870, 'Roslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (7884, 'Fur', 't');
INSERT INTO basis.d_basis_postnr VALUES (7900, 'Nykøbing M', 't');
INSERT INTO basis.d_basis_postnr VALUES (7950, 'Erslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (7960, 'Karby', 't');
INSERT INTO basis.d_basis_postnr VALUES (7970, 'Redsted M', 't');
INSERT INTO basis.d_basis_postnr VALUES (7980, 'Vils', 't');
INSERT INTO basis.d_basis_postnr VALUES (7990, 'Øster Assels', 't');
INSERT INTO basis.d_basis_postnr VALUES (8000, 'Aarhus C', 't');
INSERT INTO basis.d_basis_postnr VALUES (8200, 'Aarhus N', 't');
INSERT INTO basis.d_basis_postnr VALUES (8210, 'Aarhus V', 't');
INSERT INTO basis.d_basis_postnr VALUES (8220, 'Brabrand', 't');
INSERT INTO basis.d_basis_postnr VALUES (8230, 'Åbyhøj', 't');
INSERT INTO basis.d_basis_postnr VALUES (8240, 'Risskov', 't');
INSERT INTO basis.d_basis_postnr VALUES (8245, 'Risskov Ø', 't');
INSERT INTO basis.d_basis_postnr VALUES (8250, 'Egå', 't');
INSERT INTO basis.d_basis_postnr VALUES (8260, 'Viby J', 't');
INSERT INTO basis.d_basis_postnr VALUES (8270, 'Højbjerg', 't');
INSERT INTO basis.d_basis_postnr VALUES (8300, 'Odder', 't');
INSERT INTO basis.d_basis_postnr VALUES (8305, 'Samsø', 't');
INSERT INTO basis.d_basis_postnr VALUES (8310, 'Tranbjerg J', 't');
INSERT INTO basis.d_basis_postnr VALUES (8320, 'Mårslet', 't');
INSERT INTO basis.d_basis_postnr VALUES (8330, 'Beder', 't');
INSERT INTO basis.d_basis_postnr VALUES (8340, 'Malling', 't');
INSERT INTO basis.d_basis_postnr VALUES (8350, 'Hundslund', 't');
INSERT INTO basis.d_basis_postnr VALUES (8355, 'Solbjerg', 't');
INSERT INTO basis.d_basis_postnr VALUES (8361, 'Hasselager', 't');
INSERT INTO basis.d_basis_postnr VALUES (8362, 'Hørning', 't');
INSERT INTO basis.d_basis_postnr VALUES (8370, 'Hadsten', 't');
INSERT INTO basis.d_basis_postnr VALUES (8380, 'Trige', 't');
INSERT INTO basis.d_basis_postnr VALUES (8381, 'Tilst', 't');
INSERT INTO basis.d_basis_postnr VALUES (8382, 'Hinnerup', 't');
INSERT INTO basis.d_basis_postnr VALUES (8400, 'Ebeltoft', 't');
INSERT INTO basis.d_basis_postnr VALUES (8410, 'Rønde', 't');
INSERT INTO basis.d_basis_postnr VALUES (8420, 'Knebel', 't');
INSERT INTO basis.d_basis_postnr VALUES (8444, 'Balle', 't');
INSERT INTO basis.d_basis_postnr VALUES (8450, 'Hammel', 't');
INSERT INTO basis.d_basis_postnr VALUES (8462, 'Harlev J', 't');
INSERT INTO basis.d_basis_postnr VALUES (8464, 'Galten', 't');
INSERT INTO basis.d_basis_postnr VALUES (8471, 'Sabro', 't');
INSERT INTO basis.d_basis_postnr VALUES (8472, 'Sporup', 't');
INSERT INTO basis.d_basis_postnr VALUES (8500, 'Grenaa', 't');
INSERT INTO basis.d_basis_postnr VALUES (8520, 'Lystrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (8530, 'Hjortshøj', 't');
INSERT INTO basis.d_basis_postnr VALUES (8541, 'Skødstrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (8543, 'Hornslet', 't');
INSERT INTO basis.d_basis_postnr VALUES (8544, 'Mørke', 't');
INSERT INTO basis.d_basis_postnr VALUES (8550, 'Ryomgård', 't');
INSERT INTO basis.d_basis_postnr VALUES (8560, 'Kolind', 't');
INSERT INTO basis.d_basis_postnr VALUES (8570, 'Trustrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (8581, 'Nimtofte', 't');
INSERT INTO basis.d_basis_postnr VALUES (8585, 'Glesborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (8586, 'Ørum Djurs', 't');
INSERT INTO basis.d_basis_postnr VALUES (8592, 'Anholt', 't');
INSERT INTO basis.d_basis_postnr VALUES (8600, 'Silkeborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (8620, 'Kjellerup', 't');
INSERT INTO basis.d_basis_postnr VALUES (8632, 'Lemming', 't');
INSERT INTO basis.d_basis_postnr VALUES (8641, 'Sorring', 't');
INSERT INTO basis.d_basis_postnr VALUES (8643, 'Ans By', 't');
INSERT INTO basis.d_basis_postnr VALUES (8653, 'Them', 't');
INSERT INTO basis.d_basis_postnr VALUES (8654, 'Bryrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (8660, 'Skanderborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (8670, 'Låsby', 't');
INSERT INTO basis.d_basis_postnr VALUES (8680, 'Ry', 't');
INSERT INTO basis.d_basis_postnr VALUES (8700, 'Horsens', 't');
INSERT INTO basis.d_basis_postnr VALUES (8721, 'Daugård', 't');
INSERT INTO basis.d_basis_postnr VALUES (8722, 'Hedensted', 't');
INSERT INTO basis.d_basis_postnr VALUES (8723, 'Løsning', 't');
INSERT INTO basis.d_basis_postnr VALUES (8732, 'Hovedgård', 't');
INSERT INTO basis.d_basis_postnr VALUES (8740, 'Brædstrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (8751, 'Gedved', 't');
INSERT INTO basis.d_basis_postnr VALUES (8752, 'Østbirk', 't');
INSERT INTO basis.d_basis_postnr VALUES (8762, 'Flemming', 't');
INSERT INTO basis.d_basis_postnr VALUES (8763, 'Rask Mølle', 't');
INSERT INTO basis.d_basis_postnr VALUES (8765, 'Klovborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (8766, 'Nørre Snede', 't');
INSERT INTO basis.d_basis_postnr VALUES (8781, 'Stenderup', 't');
INSERT INTO basis.d_basis_postnr VALUES (8783, 'Hornsyld', 't');
INSERT INTO basis.d_basis_postnr VALUES (8800, 'Viborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (8830, 'Tjele', 't');
INSERT INTO basis.d_basis_postnr VALUES (8831, 'Løgstrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (8832, 'Skals', 't');
INSERT INTO basis.d_basis_postnr VALUES (8840, 'Rødkærsbro', 't');
INSERT INTO basis.d_basis_postnr VALUES (8850, 'Bjerringbro', 't');
INSERT INTO basis.d_basis_postnr VALUES (8860, 'Ulstrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (8870, 'Langå', 't');
INSERT INTO basis.d_basis_postnr VALUES (8881, 'Thorsø', 't');
INSERT INTO basis.d_basis_postnr VALUES (8882, 'Fårvang', 't');
INSERT INTO basis.d_basis_postnr VALUES (8883, 'Gjern', 't');
INSERT INTO basis.d_basis_postnr VALUES (8900, 'Randers C', 't');
INSERT INTO basis.d_basis_postnr VALUES (8920, 'Randers NV', 't');
INSERT INTO basis.d_basis_postnr VALUES (8930, 'Randers NØ', 't');
INSERT INTO basis.d_basis_postnr VALUES (8940, 'Randers SV', 't');
INSERT INTO basis.d_basis_postnr VALUES (8950, 'Ørsted', 't');
INSERT INTO basis.d_basis_postnr VALUES (8960, 'Randers SØ', 't');
INSERT INTO basis.d_basis_postnr VALUES (8961, 'Allingåbro', 't');
INSERT INTO basis.d_basis_postnr VALUES (8963, 'Auning', 't');
INSERT INTO basis.d_basis_postnr VALUES (8970, 'Havndal', 't');
INSERT INTO basis.d_basis_postnr VALUES (8981, 'Spentrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (8983, 'Gjerlev J', 't');
INSERT INTO basis.d_basis_postnr VALUES (8990, 'Fårup', 't');
INSERT INTO basis.d_basis_postnr VALUES (9000, 'Aalborg', 't');
INSERT INTO basis.d_basis_postnr VALUES (9200, 'Aalborg SV', 't');
INSERT INTO basis.d_basis_postnr VALUES (9210, 'Aalborg SØ', 't');
INSERT INTO basis.d_basis_postnr VALUES (9220, 'Aalborg Øst', 't');
INSERT INTO basis.d_basis_postnr VALUES (9230, 'Svenstrup J', 't');
INSERT INTO basis.d_basis_postnr VALUES (9240, 'Nibe', 't');
INSERT INTO basis.d_basis_postnr VALUES (9260, 'Gistrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (9270, 'Klarup', 't');
INSERT INTO basis.d_basis_postnr VALUES (9280, 'Storvorde', 't');
INSERT INTO basis.d_basis_postnr VALUES (9293, 'Kongerslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (9300, 'Sæby', 't');
INSERT INTO basis.d_basis_postnr VALUES (9310, 'Vodskov', 't');
INSERT INTO basis.d_basis_postnr VALUES (9320, 'Hjallerup', 't');
INSERT INTO basis.d_basis_postnr VALUES (9330, 'Dronninglund', 't');
INSERT INTO basis.d_basis_postnr VALUES (9340, 'Asaa', 't');
INSERT INTO basis.d_basis_postnr VALUES (9352, 'Dybvad', 't');
INSERT INTO basis.d_basis_postnr VALUES (9362, 'Gandrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (9370, 'Hals', 't');
INSERT INTO basis.d_basis_postnr VALUES (9380, 'Vestbjerg', 't');
INSERT INTO basis.d_basis_postnr VALUES (9381, 'Sulsted', 't');
INSERT INTO basis.d_basis_postnr VALUES (9382, 'Tylstrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (9400, 'Nørresundby', 't');
INSERT INTO basis.d_basis_postnr VALUES (9430, 'Vadum', 't');
INSERT INTO basis.d_basis_postnr VALUES (9440, 'Aabybro', 't');
INSERT INTO basis.d_basis_postnr VALUES (9460, 'Brovst', 't');
INSERT INTO basis.d_basis_postnr VALUES (9480, 'Løkken', 't');
INSERT INTO basis.d_basis_postnr VALUES (9490, 'Pandrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (9492, 'Blokhus', 't');
INSERT INTO basis.d_basis_postnr VALUES (9493, 'Saltum', 't');
INSERT INTO basis.d_basis_postnr VALUES (9500, 'Hobro', 't');
INSERT INTO basis.d_basis_postnr VALUES (9510, 'Arden', 't');
INSERT INTO basis.d_basis_postnr VALUES (9520, 'Skørping', 't');
INSERT INTO basis.d_basis_postnr VALUES (9530, 'Støvring', 't');
INSERT INTO basis.d_basis_postnr VALUES (9541, 'Suldrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (9550, 'Mariager', 't');
INSERT INTO basis.d_basis_postnr VALUES (9560, 'Hadsund', 't');
INSERT INTO basis.d_basis_postnr VALUES (9574, 'Bælum', 't');
INSERT INTO basis.d_basis_postnr VALUES (9575, 'Terndrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (9600, 'Aars', 't');
INSERT INTO basis.d_basis_postnr VALUES (9610, 'Nørager', 't');
INSERT INTO basis.d_basis_postnr VALUES (9620, 'Aalestrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (9631, 'Gedsted', 't');
INSERT INTO basis.d_basis_postnr VALUES (9632, 'Møldrup', 't');
INSERT INTO basis.d_basis_postnr VALUES (9640, 'Farsø', 't');
INSERT INTO basis.d_basis_postnr VALUES (9670, 'Løgstør', 't');
INSERT INTO basis.d_basis_postnr VALUES (9681, 'Ranum', 't');
INSERT INTO basis.d_basis_postnr VALUES (9690, 'Fjerritslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (9700, 'Brønderslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (9740, 'Jerslev J', 't');
INSERT INTO basis.d_basis_postnr VALUES (9750, 'Østervrå', 't');
INSERT INTO basis.d_basis_postnr VALUES (9760, 'Vrå', 't');
INSERT INTO basis.d_basis_postnr VALUES (9800, 'Hjørring', 't');
INSERT INTO basis.d_basis_postnr VALUES (9830, 'Tårs', 't');
INSERT INTO basis.d_basis_postnr VALUES (9850, 'Hirtshals', 't');
INSERT INTO basis.d_basis_postnr VALUES (9870, 'Sindal', 't');
INSERT INTO basis.d_basis_postnr VALUES (9881, 'Bindslev', 't');
INSERT INTO basis.d_basis_postnr VALUES (9900, 'Frederikshavn', 't');
INSERT INTO basis.d_basis_postnr VALUES (9940, 'Læsø', 't');
INSERT INTO basis.d_basis_postnr VALUES (9970, 'Strandby', 't');
INSERT INTO basis.d_basis_postnr VALUES (9981, 'Jerup', 't');
INSERT INTO basis.d_basis_postnr VALUES (9982, 'Ålbæk', 't');
INSERT INTO basis.d_basis_postnr VALUES (9990, 'Skagen', 't');

-- d_basis_status

INSERT INTO basis.d_basis_status VALUES (0, 'Ukendt', 't');
INSERT INTO basis.d_basis_status VALUES (1, 'Kladde', 't');
INSERT INTO basis.d_basis_status VALUES (2, 'Forslag', 't');
INSERT INTO basis.d_basis_status VALUES (3, 'Gældende / Vedtaget', 't');
INSERT INTO basis.d_basis_status VALUES (4, 'Ikke gældende / Aflyst', 't');

-- d_basis_tilstand

INSERT INTO basis.d_basis_tilstand VALUES (1, 'Dårlig', 't', 'Udskiftning eller vedligeholdelse tiltrængt/påkrævet. Fungerer ikke efter hensigten eller i fare for det sker inden for kort tid.');
INSERT INTO basis.d_basis_tilstand VALUES (2, 'Middel', 't', 'Fungerer efter hensigten, men kunne trænge til vedligeholdelse for at forlænge levetiden/funktionen');
INSERT INTO basis.d_basis_tilstand VALUES (3, 'God', 't', 'Tæt på lige så god som et nyt.');
INSERT INTO basis.d_basis_tilstand VALUES (8, 'Andet', 't', 'Anden tilstand end Dårlig, Middel, God eller Ukendt.');
INSERT INTO basis.d_basis_tilstand VALUES (9, 'Ukendt', 't', 'Mangler viden til at kunne udfylde værdien med Dårlig, Middel eller God.');

-- Inserts in schema styles --

-- d_hex_rgb

INSERT INTO styles.d_hex_rgb VALUES ('0', 0);
INSERT INTO styles.d_hex_rgb VALUES ('1', 1);
INSERT INTO styles.d_hex_rgb VALUES ('2', 2);
INSERT INTO styles.d_hex_rgb VALUES ('3', 3);
INSERT INTO styles.d_hex_rgb VALUES ('4', 4);
INSERT INTO styles.d_hex_rgb VALUES ('5', 5);
INSERT INTO styles.d_hex_rgb VALUES ('6', 6);
INSERT INTO styles.d_hex_rgb VALUES ('7', 7);
INSERT INTO styles.d_hex_rgb VALUES ('8', 8);
INSERT INTO styles.d_hex_rgb VALUES ('9', 9);
INSERT INTO styles.d_hex_rgb VALUES ('a', 10);
INSERT INTO styles.d_hex_rgb VALUES ('b', 11);
INSERT INTO styles.d_hex_rgb VALUES ('c', 12);
INSERT INTO styles.d_hex_rgb VALUES ('d', 13);
INSERT INTO styles.d_hex_rgb VALUES ('e', 14);
INSERT INTO styles.d_hex_rgb VALUES ('f', 15);

-- d_tables

INSERT INTO styles.d_tables VALUES ('v_greg_flader', 'F');
INSERT INTO styles.d_tables VALUES ('v_greg_linier', 'L');
INSERT INTO styles.d_tables VALUES ('v_greg_punkter', 'P');

