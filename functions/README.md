# Potisna obvestila — kaj mora narediti lastnik

Koda je napisana in prevedljiva, **obvestila pa še ne delujejo**. Vse spodnje
korake je mogoče opraviti samo z Googlovim računom lastnika, zato jih agent ni
mogel izvesti.

## Kaj je že narejeno

- `lib/data/push.dart` — vklop/izklop obvestil, naročnina na temo `zaposleni`,
  dovoljenje uporabnika.
- Stikalo v aplikaciji: **Več → Nastavitve → Potisna obvestila**.
- `functions/index.js` — tri obvestila:
  - `orderReady` — sproži se, ko naročilo preide v čakanje na prevzem/vračilo,
  - `overdueCheck` — vsak dan ob 15:00, samo če kakšno naročilo zamuja,
  - `morningSummary` — vsak dan ob 7:00, samo če je za ta dan kaj dela.
- `AndroidManifest.xml` — dovoljenje `POST_NOTIFICATIONS` in privzeti kanal.
- Zvonček na zaslonu Danes dela **tudi brez vsega spodnjega** — obvestila
  izračuna iz podatkov, ki so že v bazi.

## Koraki, po vrsti

1. **Vklopi Cloud Messaging** v Firebase konzoli (Project settings → Cloud
   Messaging).

2. **Preklopi projekt na Blaze.** Cloud Functions brez plačljivega načrta ne
   delujejo. Za tako majhno rabo je strošek praktično nič, a kartico je treba
   vpisati.

3. **Namesti odvisnosti in uvedi:**
   ```bash
   cd functions && npm install
   firebase deploy --only functions
   ```

4. **Preveri.** V aplikaciji vklopi obvestila, potem v Firestore konzoli
   kakšnemu naročilu ročno nastavi `status` na `awaitingCollection`. V nekaj
   sekundah mora priti obvestilo.

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
- Ob odjavi se telefon odjavi tudi s teme, sicer bi odjavljena naprava še
  naprej dobivala obvestila o naročilih.
