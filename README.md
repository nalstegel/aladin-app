# Aladin

Interna aplikacija za pralnico preprog. Namenjena zaposlenim, ne strankam.

Zamenjuje papirnate liste za prevzeme in dostave, ročno evidenco preprog in
sledenje cenam. V ozadju se iz vsakodnevnega dela sam gradi CRM z zgodovino
vsake stranke.

## Glavna ideja

Naročilo je skupek preprog. **Vsaka preproga ima svojo QR etiketo in svojo pot
skozi proizvodnjo.** Status naročila se nikoli ne nastavlja ročno — aplikacija
ga vedno izračuna iz stanja posameznih kosov.

```
NAROČILO                          POSAMEZNA PREPROGA (LJ-001-2)
────────                          ────────────────────────────
Za prevzem        ──────────────  Za prevzem
        │                                 │  skeniraj / "Prevzeto"
V obdelavi        ──────────────  Čaka na pranje
        │                                 │  skeniraj po pranju
        │                         Sušenje
        │                                 │  skeniraj iz sušilnice
        │                         Končna obdelava   ← vnos mer + vrste
        │                                 │  potrditev cene
        │                         READY
        ▼
Čaka na prevzem / Čaka na vračilo   (ko so vsi kosi READY)
        │
        │  poskeniraj vse kose + podpis stranke
        ▼
Zaključeno
```

Če ima naročilo 3 kose in sta 2 READY, prikaže **2/3 READY** in naročilo še ni
pripravljeno. Ko je 3/3, se samodejno prestavi:

- stranka je pripeljala sama → **Čaka na prevzem**
- mi smo pobrali → **Čaka na vračilo**

## Fail-safe pri vračilu

Naročila ni mogoče zaključiti, dokler niso poskenirani vsi kosi. Šele takrat se
pojavi **POTRDI VRAČILO** in stranka se s prstom podpiše na telefon.

Shrani se: datum in ura, seznam poskeniranih kosov, zaposleni, ki je izvedel
predajo, ime prevzemnika in podpis. Če stranka podpisa ne more ali noče dati,
ima administrator obvod z obveznim razlogom — naročilo se nikoli ne blokira.

## Zagon

```bash
flutter run
```

Ob prvem zagonu se naložijo demo podatki (naročila #1842–#1848, med njimi
primer iz koncepta: Novak, 3 kosi, 2/3 READY). Ponastaviš jih v zavihku
**Več → Ponastavi demo podatke**.

Testi poslovne logike:

```bash
flutter test
```

## Struktura

```
lib/
  models/      podatkovni model (naročilo, preproga, stranka, cenik, dokazilo)
  data/
    repository.dart   vsa poslovna logika in prehodi stanj
    app_state.dart    nespremenljivo stanje celotne aplikacije
    store.dart        shramba (Firestore / pomnilnik za teste)
    auth.dart         prijava zaposlenih
    alerts.dart       obvestila, izpeljana iz stanja naročil
    push.dart         potisna obvestila
    seed.dart         demo podatki
    providers.dart    Riverpod dostop do stanja
  ui/
    dashboard/     "Danes" — kdo je za prevzem, kdo za vračilo, kaj je v obratu
    orders/        aktivna in zaključena naročila, etikete, vračilo
    rugs/          posamezna preproga, vnos mer, končna obdelava in cena
    scanner/       QR skener, delovni seznami po korakih
    customers/     CRM
    notifications/ zvonček z obvestili
    more/          cenik, statistika, uporabniki, navodila, podpora
functions/       potisna obvestila (Cloud Functions) — glej functions/README.md
```

## Zasloni

Spodnja vrstica ima pet zavihkov: **Danes**, **Naročila**, veliki gumb za
**skeniranje** na sredini, **Stranke** in **Več**.

Naročila so v enem seznamu z zavihkoma *Aktivna* in *Zaključena*; kanal
(dostava / pripeljano / B2B) je oznaka na kartici in filter v glavi, ne več
ločen zavihek.

## Naročila in ID-ji

Vsako naročilo dobi zaporedno številko glede na območje, ki ga delavec
izbere ob sprejemu: **LJ-001, LJ-002, … LJ-999, LJ1-001, LJ1-002, …** za
Ljubljano, enako z **MB** za Maribor in **CE** za Celje (glej
`lib/core/order_id.dart`).

## QR etikete

QR koda vsebuje ID kosa, npr. `LJ-001-2` (številka naročila + zaporedna
številka kosa). Skeniranje vedno odpre točno tisto preprogo, ne celotnega
naročila. Etikete se tiskajo neposredno na termalni tiskalnik Zebra ZD230 na
omrežju (**Naročilo → ikona QR → Natisni**); na etiketi so številka
naročila, ime stranke, mere preproge in QR koda.

Skeniranje odpre podrobnosti preproge. Za delo ob stroju je **hitri način**:
vsak skeniran kos gre samodejno korak naprej, brez dotikanja zaslona.

Pod okvirjem kamere so bližnjice do delovnih seznamov po korakih (kaj čaka na
pranje, kaj je v sušenju …). Če je etiketa strgana, je tam tudi **ročni vnos
kode**.

## Cene

`osnova = obračunani m² × cena vrste` — z upoštevanjem minimalnega obračuna
(npr. 3 m²). Nato doplačila (%, €/m², pavšal) in popust. Popust, dogovorjen s
stranko, se predlaga samodejno. Delavec lahko končno ceno tudi ročno določi.

## Podatki

Podatki so v skupni bazi (Firebase Firestore). Vsi zaposleni vidijo iste
podatke, spremembe se sproti prenašajo med telefoni. Vsak zaposleni ima svoj
račun (e-naslov in geslo), da je v zgodovini vsakega kosa zapisano, kdo je
korak dejansko izvedel.

Firestore ima vgrajeno delo brez povezave, kar je v pralnici brez zanesljivega
signala bistveno: aplikacija dela naprej, spremembe se oddajo, ko se signal
vrne.

## Obvestila

Zvonček na zaslonu **Danes** dela takoj — obvestila (pripravljena naročila,
zamude) izračuna iz podatkov, ki so že v bazi.

**Potisna obvestila so napisana, a še ne delujejo.** Zahtevajo nekaj korakov v
Firebase konzoli, ki jih lahko opravi samo lastnik računa — opisani so v
[functions/README.md](functions/README.md).

## Stanje po platformah

- **Android** — razvito in preizkušeno, vključno s podpisanimi izdajami
  (`tool/release_android.sh`).
- **iOS** — nastavitve so pripravljene, dovoljenje za kamero je v
  `ios/Runner/Info.plist`. Podrobno stanje in kaj še manjka je v
  [plan.md](plan.md), razdelek 4.

Podrobnosti o tem, kaj je narejeno in kaj še ne, so v [plan.md](plan.md) —
tam je tudi izvirna zahteva lastnika.
