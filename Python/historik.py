##Historik=name
##dummy=vector
##Dag=string
##Maaned=string
##Aar=string
##Historik_Flader=output vector
##Historik_Linier=output vector
##Historik_Punkter=output vector


fl = "SELECT * FROM greg.f_dato_flader(" + Dag + ", " + Maaned + ", " + Aar + ")"
li = "SELECT * FROM greg.f_dato_linier(" + Dag + ", " + Maaned + ", " + Aar + ")"
pkt = "SELECT * FROM greg.f_dato_punkter(" + Dag + ", " + Maaned + ", " + Aar + ")"

outputs_GDALOGREXECUTESQL_3=processing.runalg('gdalogr:executesql', dummy,fl,0,Historik_Flader)
outputs_GDALOGREXECUTESQL_2=processing.runalg('gdalogr:executesql', dummy,li,0,Historik_Linier)
outputs_GDALOGREXECUTESQL_1=processing.runalg('gdalogr:executesql', dummy,pkt,0,Historik_Punkter)