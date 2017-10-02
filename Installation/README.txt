Installation

For nem installation trykkes på Installation.bat

Skriv koden til superbrugeren postgres to gange. Første gang laver databasen groenreg og anden gang giver adgang til en konsol med adgang til databasen.

Herefter skrives \ir install og databasen bliver lavet.

Installationen består af tre moduler. Det ene laver selve databasen og indsætter de grundlæggende data (groenreg.sql), det andet indsætter eksempel-data fra Frederikssund Kommune i relevante look-up tabeller (INSERTS.sql). Det sidste indsætter et eksempel data-sæt (test_data.sql).

Modulerne med eksempel-data kan fjernes fra install-filen (åbnes i text editor), eksempelvis fjernes \ir 'Scripts/test_data.sql', hvis der ikke ønskes et eksempel data-sæt.

Til sidst skrives \q for at afslutte.