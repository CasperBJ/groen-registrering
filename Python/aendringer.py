##AEndringer=name
##dummy=vector
##Antal_dage=number
##AEndringer_Flader=output vector
##AEndringer_Linier=output vector
##AEndringer_Punkter=output vector


fl = "SELECT * FROM greg.f_tot_flader(" + Antal_dage + ")"
li = "SELECT * FROM greg.f_tot_linier(" + Antal_dage + ")"
pkt = "SELECT * FROM greg.f_tot_punkter(" + Antal_dage + ")"

outputs_GDALOGREXECUTESQL_3=processing.runalg('gdalogr:executesql', dummy,fl,0,AEndringer_Flader)
outputs_GDALOGREXECUTESQL_2=processing.runalg('gdalogr:executesql', dummy,li,0,AEndringer_Linier)
outputs_GDALOGREXECUTESQL_1=processing.runalg('gdalogr:executesql', dummy,pkt,0,AEndringer_Punkter)