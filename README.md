# Projekt 'Grøn Registrering', Version 2.0
System til registrering af grønne områder i Frederikssund Kommune.


Af Casper Bertelsen, Have- og parkingenigørstuderende


Version 1.0:
Udarbejdet
- i forbindelse med praktikophold Sept '16 - Jan '17
- i samarbejde med
	Frederikssund Kommunes Vej & Park-afdeling
	Bo Victor Thomsen, Frederikssund Kommunes GIS-afdeling

Version 2.0:
Udarbejdet i perioden Jan '17 og frem


Systemet er udarbejdet på baggrund af datamodellen fra det Fælles Kommunale Geodatasamarbejde (FKG) - Der vil derfor være elementer, som knytter sig hertil.

Systemet er bygget op af en databasestruktur i PostgreSQL / PostGIS, en QGIS-projektskabelon, samt en håndfuld Excel-filer, som danner diverse rapportfunktioner.

Alle filer er sat op til at kære på localhost, og disse skal ændres til en anden server.

Alle logins til Excel-ark benytter user: 'qgis_reader' password: 'qgis_reader'.

Grundet links til andre databaser internt i Frederikssund Kommune vil der være nogle lag, som ikke kan findes og således ses som *bad layers*.
Det omfatter følgende:
- Kommunale vej
- Privat fællesveje
- Bygrænse
- Kyst
- Bygning
- VEJKANT
- Kommunegrænse
- Matrikelskel
- Skov
- Sø

Her trykkes der bare på krydset.


### Indhold

#### PostgreSQL / PostGIS

Databasenavn: groenreg

Databasestrukturen består af et SQL script, som kan køres i PostgreSQL. Dette script danner den grundlæggende databasestruktur med tabeller, triggers mv.
Det dannes to login ved køre scriptet. det ene er user: 'qgis_reader' password: 'qgis_reader', som giver læseadgang til filerne. Alternativt kan login på filerne ændres til en superuser.
Det andet login er user: 'backadm' password: 'qgis', som benyttes i et kommandoscript til hurtig backup af databasen.

#### QGIS

Version 2.18.10 er benyttet

I mappen ligger der en projektfil.

QGIS-projektet indeholder følgende lagstruktur:
- Områder (Gruppe)
  - Områder (Lag)
  - Delområder (Lag)
  - Atlas (Lag)
- Historik (Gruppe) (Til genering af historik-lag)
- Ændringer (Gruppe)
  - Ændringer - 14 dage (Lag - hhv. flader, linier og punkter)
- ELEMENTER (Gruppe)
  - Punkter (Lag)
  - Linier (Lag)
  - Flader (Lag)
- Grunddata (Ikke tilgængelig) (Bliver til 'bad layers', da de er tilknyttet andre databaser i kommunen - Dog ikke Skærmkort + Ortofoto)
- Opsætning og opslag (Gruppe)
  - Elementer (Gruppe) (Opsætning af elementtyper i hierarkisk struktur hovedelement -> element -> underelement)
  - Andet (Gruppe) (Opsætning af andre grunddata)
  - Look-up (Gruppe) (På forhånd defineret grunddata, som ikke kan ændres)

Filerne i mappen kan importeres ind i QGIS under processing (bearbejder) > Toolbox > Scripts.

Historik.py kan tilknyttes vedlagte .qml-filer (Under mappen Styles). Højreklik på Historik i Toolbox og tryk Edit rendering styles for outputs.

Historik.py danner tre lag over registreringens indhold på en bestemt dato.
Aendring.py danner tre lag over ændringer i registreringen indenfor x antal dage (Præcist som lagene i gruppen Ændringer) - Disse er dog ikke dynamiske.

Filen i mappen Logos kan udskiftes med eget logo.

#### Excel

For at benytte Excel-filerne kræver det en 32-bit ODBC-driver, som hentes via PostgreSQL Stack Builder.

#### Backup

For at foretage en backup af databasen trykkes på Backup.bat i mappen BAT. Der skrives en kode og der dannes en fil påført dato.