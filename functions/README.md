# Potisna obvestila — kaj mora narediti lastnik

Koda je napisana in preizkušena (`npm test`), **obvestila pa še ne delujejo**.
Vse spodnje korake je mogoče opraviti samo z Googlovim računom lastnika, zato
jih agent ni mogel izvesti.

## Kaj je že narejeno

- `lib/data/push.dart` — vklop/izklop obvestil, naročnina na temi, dovoljenje
  uporabnika. Tema `zaposleni` je za vse, tema `admini` samo za administratorje.
- Stikalo v aplikaciji: **Več → Nastavitve → Potisna obvestila**.
- `functions/index.js` — šest funkcij:

  | Funkcija | Kdaj | Komu | Kaj |
  |---|---|---|---|
  | `orderReady` | ob spremembi statusa naročila | `zaposleni` | naročilo je pripravljeno |
  | `overdueCheck` | pon–sob 15:00 | `zaposleni` | samo če kakšno naročilo zamuja |
  | `morningSummary` | pon–sob 7:00 | `zaposleni` | kaj je danes za prevzem/vračilo |
  | `dailySummary` | pon–sob 18:00 | `admini` | dnevni povzetek |
  | `weeklySummary` | ponedeljek 8:00 | `admini` | povzetek zadnjega celega tedna (pon–ned) |
  | `monthlySummary` | 1. v mesecu 8:30 | `admini` | povzetek prejšnjega celega meseca |

- `functions/summaries.js` — izračun povzetkov (čist, brez Firebase; preizkus v
  `functions/test/`).
- `AndroidManifest.xml` — dovoljenje `POST_NOTIFICATIONS` in privzeti kanal.
- Zvonček na zaslonu Danes dela **tudi brez vsega spodnjega** — obvestila
  izračuna iz podatkov, ki so že v bazi.

### Povzetki: kaj točno se šteje

Povzetki gredo **samo administratorjem**, ker vsebujejo promet in cene, ki jih
zaposleni v aplikaciji ne vidijo (Statistika je samo za administratorje). Če
želiš dnevni povzetek poslati vsem, v `sendSummary` zamenjaj `ADMIN_TOPIC` s
`TOPIC` — vendar bo potem vsak zaposleni videl znesek pri „Vrnjeno“.

Arhivirana naročila se ne štejejo nikjer (kot v Statistiki). Denar je prepis
`billingFor()` iz `lib/data/billing.dart`; skupna datoteka
`functions/test/fixtures/pricing_cases.json` preverja, da se obe strani ujemata
(`test/summary_pricing_test.dart` in `npm test`).

**Dnevni** (danes po ljubljanskem času):

| Vrstica | Pomen |
|---|---|
| Pripeljano | naročila s kanalom *Pripeljano*, ustvarjena danes / njihovi kosi |
| Vrnjeno | naročila, zaključena danes / njihov znesek (`billingFor`) |
| Oprano | kosi, ki so danes prvič prešli z „Na pranju“ v „V sušenju“ |
| Pripravljeno | kosi, ki so danes prvič postali „Pripravljeno“ / njihovi m² |
| Še čaka pranje | kosi v statusu „Na pranju“ zdaj |
| Še v kombiju | naročila, označena V kombi, zdaj |
| Ni klicano >24 h | stranke z naročilom, ki čaka na osebni prevzem >24 h brez klica |

Če se ni zgodilo nič in nič ne čaka, obvestila ni.

**Tedenski in mesečni** — vse temelji na dogodkih v obdobju, zato je primerjava s
prejšnjim obdobjem poštena:

| Vrstica | Pomen |
|---|---|
| Prejeto | naročila (in kosi, stranke), ustvarjena v obdobju |
| Oprano m² | m² kosov, ki so v obdobju prvič postali „Pripravljeno“ (m² je znan šele ob merjenju po sušenju) |
| Vrnjeno / promet / prihodki | naročila, zaključena v obdobju, in njihov znesek |
| Potrjena vrednost | cene kosov, potrjene v obdobju (brez dostave, Vnos/Iznos in minimuma 50 €) |
| Povprečno naročilo | promet / število vrnjenih (kot v Statistiki) |
| Povprečna cena | potrjene cene kosov / m² teh kosov |
| Še odprtih | vsa odprta naročila **zdaj** (stanje, ne tok) |
| Po regijah | prejeta naročila po območju (LJ, MB, CE, DOL); mesečni še prihodki po območju |
| Top dnevi | trije dnevi z največ prometa (po dnevu zaključka) |

## Koraki, po vrsti

1. **Preklopi projekt na Blaze.** Cloud Functions in Cloud Scheduler brez
   plačljivega načrta ne delujejo. Firebase konzola → spodaj levo **Upgrade** →
   Blaze → poveži plačilni račun (kartica). Za tako majhno rabo je strošek
   nekaj centov na mesec (Cloud Scheduler ima 3 brezplačna opravila, tu jih je
   5). **Takoj nastavi opozorilo na porabo:** Google Cloud konzola → Billing →
   Budgets & alerts → npr. 5 €/mesec.

2. **Preveri Cloud Messaging.** Firebase konzola → ⚙ Project settings →
   zavihek **Cloud Messaging** → „Firebase Cloud Messaging API (V1)“ mora biti
   **Enabled**. Če ni: tri pike → *Manage API in Google Cloud Console* →
   **Enable**. („Legacy“ API ni potreben.)

3. **Namesti odvisnosti in uvedi:**
   ```bash
   npm install -g firebase-tools    # samo če ukaza še nimaš
   firebase login
   cd functions && npm install && npm test
   cd .. && firebase deploy --only functions
   ```
   Ob prvi uvedbi CLI vpraša, ali sme vklopiti API-je (Cloud Functions, Cloud
   Build, Artifact Registry, Cloud Scheduler, Eventarc) — odgovori **Y**.
   Če uvedba pade z napako o *Eventarc Service Agent* ali *permission denied*,
   počakaj 3–5 minut in ukaz ponovi; dovoljenja se razširijo z zamikom.
   Indeksov v Firestoru ni treba nastavljati.

4. **Preveri, da so funkcije tam.** Firebase konzola → **Build → Functions**:
   vidnih mora biti vseh šest. Google Cloud konzola → **Cloud Scheduler**: pet
   opravil `firebase-schedule-…-europe-west3`.

5. **Preizkusi povzetek takoj, brez čakanja.** Cloud Scheduler → opravilo
   `firebase-schedule-dailySummary-europe-west3` → tri pike → **Force run**.
   (Tedenski in mesečni računata zadnji celi teden/mesec, ne glede na to, kdaj
   ju zaženeš.) Obvestilo pride samo na telefone administratorjev z vklopljenimi
   obvestili. Napake: Functions → zavihek **Logs**, ali
   `firebase functions:log --only dailySummary`.

6. **Aplikacija.** `push.dart` se je spremenil, zato izdaj novo Android različico
   (`./tool/release_android.sh "povzetki"`). Na telefonu vsakega administratorja:
   **Več → Nastavitve → Potisna obvestila** vklopi (Android 13+ vpraša za
   dovoljenje). Kdo je administrator, se nastavi v *Nastavitve → Zaposleni*.
   Naročnino na temo `admini` telefon uskladi z vlogo ob vsakem zagonu, zato
   degradiran administrator preneha dobivati povzetke, ko aplikacijo naslednjič
   zažene.

7. **Preveri pripravljeno naročilo.** V aplikaciji vklopi obvestila, potem v
   Firestore konzoli kakšnemu naročilu ročno nastavi `status` na
   `awaitingCollection`. V nekaj sekundah mora priti obvestilo.

## iOS

Obvestila na iPhonu **niso mogoča**, dokler ni urejeno dvoje:

- Apple Developer račun ($99/leto) — glej `plan.md`, razdelek 4.3. Brez njega
  iOS aplikacije sploh ni mogoče namestiti na telefon.
- APNs ključ, naložen v Firebase konzolo (Project settings → Cloud Messaging →
  Apple app configuration).

Android deluje takoj po 3. koraku.

## Opombe

- Obvestila gredo vsem zaposlenim hkrati, ker naročila niso dodeljena
  posameznikom. Če bo kdaj potrebna dodelitev, je treba v `WorkOrder` dodati
  polje in v `functions/index.js` zamenjati temo z žetoni naprav.
- Kanal `aladin` v `AndroidManifest.xml` ni nikjer ustvarjen. Android v tem
  primeru uporabi privzeti kanal — obvestila pridejo, v nastavitvah telefona pa
  se skupina imenuje splošno. Če to moti, dodaj `flutter_local_notifications`
  in kanal ustvari ob zagonu.
- Ob odjavi se telefon odjavi tudi z obeh tem, sicer bi odjavljena naprava še
  naprej dobivala obvestila o naročilih in promet.
- Povzetki so dolgi (7–10 vrstic). Android jih pokaže razširjene; iPhone na
  zaklenjenem zaslonu skrajša besedilo — celotno se vidi ob dolgem pritisku.
- Čas: telefoni v bazo zapišejo lokalni čas brez odmika, strežnik teče v UTC.
  `summaries.js` zato vse pretvori v uro Europe/Ljubljana. `overdueCheck` in
  `morningSummary` tega ne počneta, a ob urah, ko tečeta (7:00, 15:00), je
  datum v UTC enak lokalnemu, zato tam ni napake.
