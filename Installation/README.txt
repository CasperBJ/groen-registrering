Installation

For nem installation trykkes p� Installation.bat

Skriv koden til superbrugeren postgres to gange. F�rste gang laver databasen groenreg og anden gang giver adgang til en konsol med adgang til databasen.

Herefter skrives \ir install og databasen bliver lavet.

Installationen best�r af tre moduler. Det ene laver selve databasen og inds�tter de grundl�ggende data (groenreg.sql), det andet inds�tter eksempel-data fra Frederikssund Kommune i relevante look-up tabeller (INSERTS.sql). Det sidste inds�tter et eksempel data-s�t (test_data.sql).

Modulerne med eksempel-data kan fjernes fra install-filen (�bnes i text editor), eksempelvis fjernes \ir 'Scripts/test_data.sql', hvis der ikke �nskes et eksempel data-s�t.

Til sidst skrives \q for at afslutte.