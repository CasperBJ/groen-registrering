-- groenreg.sql
1)
Har du ikke en oprindelig 'groenreg' database med det tidligere script fra Frederikssund Kommune,
skal du blot lave en ny database med navnet 'groenreg'. Evt. tilføje 'postgis' og 'uuid-ossp' extensions.

Åbn Query Tool og Copy-Paste indholdet fra 'groenreg.sql' ind i Query Tool'et og Execute (F5).

2)
Har du en oprindelig 'groenreg' database med det tidligere script fra Frederikssund Kommune,
så benyt denne.
Navngiv de oprindelige skemaer 'greg' og 'greg_history' til hhv. 'xgreg' og 'xgreg_history'.

Åbn Query Tool og Copy-Paste indholdet fra 'groenreg.sql' ind i Query Tool'et og Execute (F5).

Dernæst se nedenfor


-- overfør data fra oprindelig registrering.sql

For at overføre de oprindelige data til den nye databasestruktur benyttes scriptet
'overfør data fra oprindelig registrering.sql'.

Copy-Paste indholdet fra 'overfør data fra oprindelig registrering.sql' ind i Query Tool'et og Execute (F5).
