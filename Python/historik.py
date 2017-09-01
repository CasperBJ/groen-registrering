##Historik=name
##dummy=vector
##Dag=string
##Maaned=string
##Aar=string
##dummy_out=output vector


fl = "CREATE OR REPLACE VIEW greg.v_greg_flader_historik AS SELECT * FROM greg.f_dato_flader(" + Dag + ", " + Maaned + ", " + Aar + ")"
li = "CREATE OR REPLACE VIEW greg.v_greg_linier_historik AS SELECT * FROM greg.f_dato_linier(" + Dag + ", " + Maaned + ", " + Aar + ")"
pkt = "CREATE OR REPLACE VIEW greg.v_greg_punkter_historik AS SELECT * FROM greg.f_dato_punkter(" + Dag + ", " + Maaned + ", " + Aar + ")"
omr = "CREATE OR REPLACE VIEW greg.v_greg_omraader_historik AS SELECT * FROM greg.f_dato_omraader(" + Dag + ", " + Maaned + ", " + Aar + ")"
mngd = "CREATE OR REPLACE VIEW greg.v_maengder_historik AS SELECT * FROM greg.f_maengder(" + Dag + ", " + Maaned + ", " + Aar + ")"

outputs_GDALOGREXECUTESQL_5=processing.runalg('gdalogr:executesql', dummy,mngd,0,dummy_out)
outputs_GDALOGREXECUTESQL_4=processing.runalg('gdalogr:executesql', dummy,fl,0,dummy_out)
outputs_GDALOGREXECUTESQL_3=processing.runalg('gdalogr:executesql', dummy,li,0,dummy_out)
outputs_GDALOGREXECUTESQL_2=processing.runalg('gdalogr:executesql', dummy,pkt,0,dummy_out)
outputs_GDALOGREXECUTESQL_1=processing.runalg('gdalogr:executesql', dummy,omr,0,dummy_out)