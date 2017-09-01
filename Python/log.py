##Log=name
##dummy=vector
##Aar=string
##dummy_out=output vector


log = "CREATE OR REPLACE VIEW greg.v_log_historik AS SELECT * FROM greg.f_aendring_log(" + Aar + ")"

outputs_GDALOGREXECUTESQL_1=processing.runalg('gdalogr:executesql', dummy,log,0,dummy_out)