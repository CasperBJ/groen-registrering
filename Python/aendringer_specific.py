##Aendringer=name
##dummy=vector
##Antal_dage=string
##dummy_out=output vector


fl = "CREATE OR REPLACE VIEW greg.v_aendring_flader AS SELECT objekt_id, geometri::public.geometry('MultiPolygon', 25832) AS geometri, handling, dato, arbejdssted, underelement FROM greg.f_tot_flader(" + Antal_dage  + ")"
li = "CREATE OR REPLACE VIEW greg.v_aendring_linier AS SELECT objekt_id, geometri::public.geometry('MultiLineString', 25832) AS geometri, handling, dato, arbejdssted, underelement FROM greg.f_tot_linier(" + Antal_dage  + ")"
pkt = "CREATE OR REPLACE VIEW greg.v_aendring_punkter AS SELECT objekt_id, geometri::public.geometry('MultiPoint', 25832) AS geometri, handling, dato, arbejdssted, underelement FROM greg.f_tot_punkter(" + Antal_dage  + ")"
omr = "CREATE OR REPLACE VIEW greg.v_aendring_omraader AS SELECT objekt_id, geometri::public.geometry('MultiPolygon', 25832) AS geometri, handling, dato, arbejdssted FROM greg.f_tot_omraader(" + Antal_dage  + ")"

outputs_GDALOGREXECUTESQL_4=processing.runalg('gdalogr:executesql', dummy,fl,0,dummy_out)
outputs_GDALOGREXECUTESQL_3=processing.runalg('gdalogr:executesql', dummy,li,0,dummy_out)
outputs_GDALOGREXECUTESQL_2=processing.runalg('gdalogr:executesql', dummy,pkt,0,dummy_out)
outputs_GDALOGREXECUTESQL_1=processing.runalg('gdalogr:executesql', dummy,omr,0,dummy_out)