--
-- DISABLE TRIGGERS
--

ALTER TABLE greg.t_greg_flader
	DISABLE TRIGGER a_t_greg_flader_generel_trg_iud,
	DISABLE TRIGGER t_greg_flader_trg_i,
--	DISABLE TRIGGER t_greg_omraader_flader_trg_a_iud -- Only polygons define area boundaries
	DISABLE TRIGGER t_greg_omraader_upt_trg_a_iud; -- All features define area boundaries

ALTER TABLE greg.t_greg_linier
	DISABLE TRIGGER a_t_greg_linier_generel_trg_iud,
	DISABLE TRIGGER t_greg_linier_trg_i,
	DISABLE TRIGGER t_greg_omraader_upt_trg_a_iud; -- All features define area boundaries

ALTER TABLE greg.t_greg_punkter
	DISABLE TRIGGER a_t_greg_punkter_generel_trg_iud,
	DISABLE TRIGGER t_greg_punkter_trg_i,
	DISABLE TRIGGER t_greg_omraader_upt_trg_a_iud; -- All features define area boundaries

ALTER TABLE greg.t_greg_omraader
	DISABLE TRIGGER t_greg_omraader_trg_iu;

--
-- TRUNCATE AND INSERTS
--

-- d_basis_bruger_id
TRUNCATE greg.d_basis_bruger_id CASCADE;
INSERT INTO greg.d_basis_bruger_id (bruger_id, navn) VALUES ('postgres', 'Ikke angivet');
INSERT INTO greg.d_basis_bruger_id (bruger_id, navn, aktiv) SELECT bruger_id, navn, 't' FROM xgreg.d_basis_bruger_id WHERE aktiv = 1 AND bruger_id NOT IN (SELECT bruger_id FROM greg.d_basis_bruger_id);
INSERT INTO greg.d_basis_bruger_id (bruger_id, navn, aktiv) SELECT bruger_id, navn, 'f' FROM xgreg.d_basis_bruger_id WHERE aktiv = 0 AND bruger_id NOT IN (SELECT bruger_id FROM greg.d_basis_bruger_id);

-- d_basis_kommunal_kontakt
TRUNCATE greg.d_basis_kommunal_kontakt RESTART IDENTITY CASCADE;
INSERT INTO greg.d_basis_kommunal_kontakt (navn, telefon, email, aktiv) SELECT navn, telefon, email, 't' FROM xgreg.d_basis_kommunal_kontakt WHERE aktiv = 1;
INSERT INTO greg.d_basis_kommunal_kontakt (navn, telefon, email, aktiv) SELECT navn, telefon, email, 'f' FROM xgreg.d_basis_kommunal_kontakt WHERE aktiv = 0;

-- d_basis_udfoerer
TRUNCATE greg.d_basis_udfoerer RESTART IDENTITY CASCADE;
INSERT INTO greg.d_basis_udfoerer (udfoerer, aktiv) SELECT udfoerer, 't' FROM xgreg.d_basis_udfoerer WHERE aktiv = 1;
INSERT INTO greg.d_basis_udfoerer (udfoerer, aktiv) SELECT udfoerer, 'f' FROM xgreg.d_basis_udfoerer WHERE aktiv = 0;

-- d_basis_udfoerer_entrep
TRUNCATE greg.d_basis_udfoerer_entrep RESTART IDENTITY CASCADE;
INSERT INTO greg.d_basis_udfoerer_entrep (udfoerer_entrep, aktiv) SELECT navn, 't' FROM xgreg.d_basis_udfoerer_entrep WHERE aktiv = 1;
INSERT INTO greg.d_basis_udfoerer_entrep (udfoerer_entrep, aktiv) SELECT navn, 'f' FROM xgreg.d_basis_udfoerer_entrep WHERE aktiv = 0;

-- d_basis_udfoerer_kontakt
TRUNCATE greg.d_basis_udfoerer_kontakt RESTART IDENTITY CASCADE;
INSERT INTO greg.d_basis_udfoerer_kontakt (udfoerer_kode, navn, telefon, email, aktiv) SELECT b.udfoerer_kode, a.navn, a.telefon, a.email, 't' FROM xgreg.d_basis_udfoerer_kontakt a LEFT JOIN greg.d_basis_udfoerer b ON a.udfoerer = b.udfoerer WHERE a.aktiv = 1;
INSERT INTO greg.d_basis_udfoerer_kontakt (udfoerer_kode, navn, telefon, email, aktiv) SELECT b.udfoerer_kode, a.navn, a.telefon, a.email, 'f' FROM xgreg.d_basis_udfoerer_kontakt a LEFT JOIN greg.d_basis_udfoerer b ON a.udfoerer = b.udfoerer WHERE a.aktiv = 0;

-- d_basis_vejnavn
TRUNCATE greg.d_basis_vejnavn CASCADE;
INSERT INTO greg.d_basis_vejnavn (vejkode, vejnavn, aktiv, cvf_vejkode, postnr, kommunekode) SELECT vejkode, vejnavn, 't', cvf_vejkode, postnr, kommunekode FROM xgreg.d_basis_vejnavn WHERE aktiv = 1;
INSERT INTO greg.d_basis_vejnavn (vejkode, vejnavn, aktiv, cvf_vejkode, postnr, kommunekode) SELECT vejkode, vejnavn, 'f', cvf_vejkode, postnr, kommunekode FROM xgreg.d_basis_vejnavn WHERE aktiv = 0;

-- d_basis_distrikt_type
TRUNCATE greg.d_basis_distrikt_type RESTART IDENTITY CASCADE;
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Ukendt', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Uden for drift', 't');
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) VALUES ('Vejarealer', 't'); -- Relevant for trigger function
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) SELECT pg_distrikt_type, 't' FROM xgreg.d_basis_distrikt_type WHERE aktiv = 1 AND pg_distrikt_type NOT IN (SELECT pg_distrikt_type FROM greg.d_basis_distrikt_type);
INSERT INTO greg.d_basis_distrikt_type (pg_distrikt_type, aktiv) SELECT pg_distrikt_type, 'f' FROM xgreg.d_basis_distrikt_type WHERE aktiv = 0 AND pg_distrikt_type NOT IN (SELECT pg_distrikt_type FROM greg.d_basis_distrikt_type);

-- d_basis_omraadenr
TRUNCATE greg.d_basis_omraadenr CASCADE;
INSERT INTO greg.d_basis_omraadenr SELECT pg_distrikt_nr FROM xgreg.t_greg_omraader;

-- e_basis_hovedelementer
TRUNCATE greg.e_basis_hovedelementer CASCADE;
INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovedelement_tekst, aktiv) SELECT hovedelement_kode, hovedelement_tekst, 't' FROM xgreg.d_basis_hovedelementer WHERE aktiv = 1;
INSERT INTO greg.e_basis_hovedelementer (hovedelement_kode, hovedelement_tekst, aktiv) SELECT hovedelement_kode, hovedelement_tekst, 'f' FROM xgreg.d_basis_hovedelementer WHERE aktiv = 0;

-- e_basis_elementer
TRUNCATE greg.e_basis_elementer CASCADE;
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) SELECT hovedelement_kode, element_kode, element_tekst, 't' FROM xgreg.d_basis_elementer WHERE aktiv = 1;
INSERT INTO greg.e_basis_elementer (hovedelement_kode, element_kode, element_tekst, aktiv) SELECT hovedelement_kode, element_kode, element_tekst, 'f' FROM xgreg.d_basis_elementer WHERE aktiv = 0;

-- e_basis_underelementer
TRUNCATE greg.e_basis_underelementer CASCADE;
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) SELECT element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris, 0.00, 0.00, enhedspris_klip, 't' FROM xgreg.d_basis_underelementer WHERE aktiv = 1 AND pris_enhed = 'kr/stk' AND LEFT(element_kode, 3) <> 'REN';
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) SELECT element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris, 0.00, 0.00, enhedspris_klip, 'f' FROM xgreg.d_basis_underelementer WHERE aktiv = 0 AND pris_enhed = 'kr/stk' AND LEFT(element_kode, 3) <> 'REN';

INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) SELECT element_kode, underelement_kode, underelement_tekst, objekt_type, 0.00, enhedspris, 0.00, enhedspris_klip, 't' FROM xgreg.d_basis_underelementer WHERE aktiv = 1 AND pris_enhed = 'kr/lbm' AND LEFT(element_kode, 3) <> 'REN';
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) SELECT element_kode, underelement_kode, underelement_tekst, objekt_type, 0.00, enhedspris, 0.00, enhedspris_klip, 'f' FROM xgreg.d_basis_underelementer WHERE aktiv = 0 AND pris_enhed = 'kr/lbm' AND LEFT(element_kode, 3) <> 'REN';

INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) SELECT element_kode, underelement_kode, underelement_tekst, objekt_type, 0.00, 0.00, enhedspris, enhedspris_klip, 't' FROM xgreg.d_basis_underelementer WHERE aktiv = 1 AND pris_enhed = 'kr/m2' AND LEFT(element_kode, 3) <> 'REN';
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) SELECT element_kode, underelement_kode, underelement_tekst, objekt_type, 0.00, 0.00, enhedspris, enhedspris_klip, 'f' FROM xgreg.d_basis_underelementer WHERE aktiv = 0 AND pris_enhed = 'kr/m2' AND LEFT(element_kode, 3) <> 'REN';

INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) SELECT element_kode, underelement_kode, underelement_tekst, objekt_type, 0.00, 0.00, 0.00, enhedspris, 't' FROM xgreg.d_basis_underelementer WHERE aktiv = 1 AND LEFT(element_kode, 3) = 'REN';
INSERT INTO greg.e_basis_underelementer (element_kode, underelement_kode, underelement_tekst, objekt_type, enhedspris_point, enhedspris_line, enhedspris_poly, enhedspris_speciel, aktiv) SELECT element_kode, underelement_kode, underelement_tekst, objekt_type, 0.00, 0.00, 0.00, enhedspris, 'f' FROM xgreg.d_basis_underelementer WHERE aktiv = 0 AND LEFT(element_kode, 3) = 'REN';

-- t_greg_omraader
INSERT INTO greg.t_greg_omraader (	objekt_id,
									pg_distrikt_nr,
									pg_distrikt_tekst,
									pg_distrikt_type_kode,
									geometri,
									vejkode,
									vejnr,
									postnr,
									note,
									link,
									aktiv)	SELECT
												a.objekt_id,
												a.pg_distrikt_nr,
												a.pg_distrikt_tekst,
												b.pg_distrikt_type_kode,
												a.geometri,
												a.vejkode,
												a.vejnr,
												a.postnr,
												a.note,
												a.link,
												CASE
													WHEN a.aktiv = 1 THEN TRUE
													WHEN a.aktiv = 0 THEN FALSE
												END AS aktiv
											FROM xgreg.t_greg_omraader a
											LEFT JOIN greg.d_basis_distrikt_type b ON a.pg_distrikt_type = b.pg_distrikt_type;

-- t_greg_flader
INSERT INTO greg.t_greg_flader (versions_id,
								objekt_id,
								systid_fra,
								systid_til,
								oprettet,
								geometri, 
								cvr_kode, 
								bruger_id_start, 
								oprindkode, 
								statuskode, 
								off_kode, 
								note, 
								link, 
								vejkode, 
								tilstand_kode, 
								anlaegsaar,
								arbejdssted, 
								underelement_kode, 
								hoejde, 
								klip_sider, 
								litra)	SELECT 
											versions_id,
											objekt_id,
											systid_fra,
											systid_til,
											oprettet,
											geometri, 
											cvr_kode, 
											bruger_id, 
											oprindkode, 
											statuskode, 
											off_kode, 
											note, 
											link, 
											vejkode, 
											tilstand_kode, 
											anlaegsaar,  
											arbejdssted, 
											underelement_kode, 
											hoejde, 
											klip_sider, 
											litra
										FROM xgreg.t_greg_flader;

-- t_greg_flader
INSERT INTO greg.t_greg_flader (versions_id,
								objekt_id,
								systid_fra,
								systid_til,
								oprettet,
								geometri, 
								cvr_kode, 
								bruger_id_start, 
								oprindkode, 
								statuskode, 
								off_kode, 
								note, 
								link, 
								vejkode, 
								tilstand_kode, 
								anlaegsaar, 
								arbejdssted, 
								underelement_kode, 
								hoejde, 
								klip_sider, 
								litra)	SELECT 
											versions_id,
											objekt_id,
											systid_fra,
											systid_til,
											oprettet,
											geometri, 
											cvr_kode, 
											bruger_id, 
											oprindkode, 
											statuskode, 
											off_kode, 
											note, 
											link, 
											vejkode, 
											tilstand_kode, 
											anlaegsaar, 
											arbejdssted, 
											underelement_kode, 
											hoejde, 
											klip_sider, 
											litra
										FROM xgreg_history.t_greg_flader;

-- t_greg_linier
INSERT INTO greg.t_greg_linier (versions_id,
								objekt_id,
								systid_fra,
								systid_til,
								oprettet,
								geometri,
								cvr_kode, 
								bruger_id_start, 
								oprindkode, 
								statuskode, 
								off_kode,
								note,
								link,
								vejkode,
								tilstand_kode,
								anlaegsaar,
								arbejdssted,
								underelement_kode,
								bredde,
								hoejde,
								litra)	SELECT
											versions_id,
											objekt_id,
											systid_fra,
											systid_til,
											oprettet,
											geometri,
											cvr_kode, 
											bruger_id, 
											oprindkode, 
											statuskode, 
											off_kode,
											note,
											link,
											vejkode,
											tilstand_kode,
											anlaegsaar,
											arbejdssted,
											underelement_kode,
											bredde,
											hoejde,
											litra
										FROM xgreg.t_greg_linier;

-- t_greg_linier
INSERT INTO greg.t_greg_linier (versions_id,
								objekt_id,
								systid_fra,
								systid_til,
								oprettet,
								geometri,
								cvr_kode, 
								bruger_id_start, 
								oprindkode, 
								statuskode, 
								off_kode,
								note,
								link,
								vejkode,
								tilstand_kode,
								anlaegsaar,
								arbejdssted,
								underelement_kode,
								bredde,
								hoejde,
								litra)	SELECT
											versions_id,
											objekt_id,
											systid_fra,
											systid_til,
											oprettet,
											geometri,
											cvr_kode, 
											bruger_id, 
											oprindkode, 
											statuskode, 
											off_kode,
											note,
											link,
											vejkode,
											tilstand_kode,
											anlaegsaar,
											arbejdssted,
											underelement_kode,
											bredde,
											hoejde,
											litra
										FROM xgreg_history.t_greg_linier;

-- t_greg_punkter
INSERT INTO greg.t_greg_punkter (versions_id,
								objekt_id,
								systid_fra,
								systid_til,
								oprettet,
								geometri,
								cvr_kode, 
								bruger_id_start, 
								oprindkode, 
								statuskode, 
								off_kode,
								note,
								link,
								vejkode,
								tilstand_kode,
								anlaegsaar,
								arbejdssted,
								underelement_kode,
								diameter,
								hoejde,
								slaegt,
								art,
								litra)	SELECT
											versions_id,
											objekt_id,
											systid_fra,
											systid_til,
											oprettet,
											geometri,
											cvr_kode, 
											bruger_id, 
											oprindkode, 
											statuskode, 
											off_kode,
											note,
											link,
											vejkode,
											tilstand_kode,
											anlaegsaar,
											arbejdssted,
											underelement_kode,
											diameter,
											hoejde,
											slaegt,
											art,
											litra
	FROM xgreg.t_greg_punkter;

-- t_greg_punkter
INSERT INTO greg.t_greg_punkter (versions_id,
								objekt_id,
								systid_fra,
								systid_til,
								oprettet,
								geometri,
								cvr_kode, 
								bruger_id_start,
								oprindkode, 
								statuskode, 
								off_kode,
								note,
								link,
								vejkode,
								tilstand_kode,
								anlaegsaar,
								arbejdssted,
								underelement_kode,
								diameter,
								hoejde,
								slaegt,
								art,
								litra)	SELECT
											versions_id,
											objekt_id,
											systid_fra,
											systid_til,
											oprettet,
											geometri,
											cvr_kode, 
											bruger_id, 
											oprindkode, 
											statuskode, 
											off_kode,
											note,
											link,
											vejkode,
											tilstand_kode,
											anlaegsaar,
											arbejdssted,
											underelement_kode,
											diameter,
											hoejde,
											slaegt,
											art,
											litra
										FROM xgreg_history.t_greg_punkter;

-- t_greg_delomraader
TRUNCATE greg.t_greg_delomraader;
INSERT INTO greg.t_greg_delomraader (geometri,
									pg_distrikt_nr,
									delnavn)	SELECT
													geometri,
													pg_distrikt_nr,
													delnavn
												FROM xgreg.t_greg_delomraader;


--
-- ENABLE TRIGGERS
--

ALTER TABLE greg.t_greg_flader
	ENABLE TRIGGER a_t_greg_flader_generel_trg_iud,
	ENABLE TRIGGER t_greg_flader_trg_i,
--	ENABLE TRIGGER t_greg_omraader_flader_trg_a_iud -- Only polygons define area boundaries
	ENABLE TRIGGER t_greg_omraader_upt_trg_a_iud; -- All features define area boundaries

ALTER TABLE greg.t_greg_linier
	ENABLE TRIGGER a_t_greg_linier_generel_trg_iud,
	ENABLE TRIGGER t_greg_linier_trg_i,
	ENABLE TRIGGER t_greg_omraader_upt_trg_a_iud; -- All features define area boundaries

ALTER TABLE greg.t_greg_punkter
	ENABLE TRIGGER a_t_greg_punkter_generel_trg_iud,
	ENABLE TRIGGER t_greg_punkter_trg_i,
	ENABLE TRIGGER t_greg_omraader_upt_trg_a_iud; -- All features define area boundaries

ALTER TABLE greg.t_greg_omraader
	ENABLE TRIGGER t_greg_omraader_trg_iu;