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
NAROČILO                          POSAMEZNA PREPROGA (#1847-2)
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
    store.dart        shramba (lokalna JSON datoteka / pomnilnik za teste)
    seed.dart         demo podatki
    providers.dart    Riverpod dostop do stanja
  ui/
    dashboard/   "Danes" — kdo je za prevzem, kdo za vračilo, kaj je v obratu
    orders/      trije zavihki (dostava / osebni prevzem / B2B), etikete, vračilo
    rugs/        posamezna preproga, vnos mer, končna obdelava in cena
    scanner/     QR skener (navadni in hitri način)
    customers/   CRM
    settings/    cenik, doplačila, zaposleni
```

## QR etikete

QR koda vsebuje ID kosa, npr. `1847-2`. Skeniranje vedno odpre točno tisto
preprogo, ne celotnega naročila. Etikete se tiskajo kot A4 pola z mrežo 3 × 6
(**Naročilo → ikona QR → Natisni**); na etiketi so ime stranke, številka
naročila, `KOS 2/3` in koda.

Skener ima dva načina:

- **Odpri kos** — skeniranje odpre podrobnosti preproge
- **Hitri način** — vsak skeniran kos gre samodejno korak naprej (delo ob stroju)

## Cene

`osnova = obračunani m² × cena vrste` — z upoštevanjem minimalnega obračuna
(npr. 3 m²). Nato doplačila (%, €/m², pavšal) in popust. Popust, dogovorjen s
stranko, se predlaga samodejno. Delavec lahko končno ceno tudi ročno določi.

## Trenutno stanje in naslednji korak

Podatki so shranjeni **lokalno na napravi** (JSON datoteka). Aplikacija je v
celoti delujoča, a se med telefoni še ne sinhronizira.

Za skupno delo več zaposlenih je predviden Firebase. Zamenjati je treba samo
izvedbo `DataStore` v `lib/data/store.dart` — `Repository` in celoten UI ostaneta
nespremenjena. Koraki:

1. `flutterfire configure` (potrebna je prijava v Google račun)
2. dodati `firebase_core`, `cloud_firestore`, `firebase_auth`, `firebase_storage`
3. `FirestoreStore implements DataStore` — zbirke `orders`, `items`,
   `customers`, `rugTypes`, `extras`, `users`
4. podpise prestaviti iz base64 v Firebase Storage
5. prijavo zaposlenih preklopiti z izbirnika imen na Firebase Auth

Firestore ima offline persistence vgrajen, kar je za delo v pralnici brez
zanesljivega signala bistveno.

## Za iOS

Na tem računalniku Xcode ni nameščen, zato je bila aplikacija razvita in
preizkušena na Androidu. Za iOS gradnjo je potreben Xcode; dovoljenje za kamero
je v `ios/Runner/Info.plist` že pripravljeno.
