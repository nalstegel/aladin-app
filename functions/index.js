/**
 * Potisna obvestila za Aladin.
 *
 * Vsa obvestila gredo na temo "zaposleni" — vsi zaposleni dobijo ista
 * obvestila, ker naročila niso dodeljena posameznikom. Aplikacija se na temo
 * naroči ob vklopu obvestil (lib/data/push.dart).
 *
 * Pred uvedbo je treba v Firebase konzoli vklopiti Cloud Messaging in projekt
 * preklopiti na plačljivi načrt (Blaze) — Cloud Functions brez njega ne
 * delujejo. Uvedba: firebase deploy --only functions
 */

const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const summaries = require("./summaries");

initializeApp();

const TOPIC = "zaposleni";
/**
 * Povzetki vsebujejo promet in cene, ki jih zaposleni v aplikaciji ne vidijo
 * (Statistika je samo za administratorje), zato gredo na ločeno temo. Nanjo se
 * naročijo samo administratorji (lib/data/push.dart).
 */
const ADMIN_TOPIC = "admini";
const REGION = "europe-west3";
const TZ = "Europe/Ljubljana";

/** Statusa, pri katerih naročilo čaka na stranko. */
const HANDOVER_READY = ["awaitingCollection", "awaitingDelivery"];

function send(title, body, data, topic = TOPIC) {
  return getMessaging().send({
    topic,
    notification: {title, body},
    data: data || {},
    android: {priority: "high", notification: {channelId: "aladin"}},
    apns: {payload: {aps: {sound: "default"}}},
  });
}

/**
 * Naročilo je pripravljeno za predajo.
 *
 * Sproži se ob spremembi statusa, ne ob vsakem zapisu — status naročila
 * izračuna aplikacija iz stanja kosov, zato se dokument posodobi tudi takrat,
 * ko se status ne spremeni.
 */
exports.orderReady = onDocumentUpdated(
    {document: "orders/{orderId}", region: REGION},
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();
      if (!before || !after) return;

      const wasReady = HANDOVER_READY.includes(before.status);
      const isReady = HANDOVER_READY.includes(after.status);
      if (wasReady || !isReady) return;

      const waiting = after.status === "awaitingCollection" ?
        "čaka na prevzem v obratu" :
        "čaka na vračilo";

      // Arhivirana naročila so izven poteka dela (plan.md §4.15).
      if (after.archivedAt) return;

      // `number` v bazi ne obstaja (je getter v Dartu) — shranjen je `id`.
      await send(
          `${after.id} je pripravljeno`,
          `${after.customerName} — ${waiting}.`,
          {orderId: event.params.orderId, kind: "ready"},
      );
    },
);

/**
 * Zamude.
 *
 * Zamuda ni dogodek v bazi — nastane s tem, da mine datum, zato je to lahko
 * samo urnik in ne sprožilec. Popoldne, da je dan še mogoče rešiti, in samo
 * kadar zamuda res obstaja.
 */
exports.overdueCheck = onSchedule(
    {schedule: "0 15 * * 1-6", timeZone: TZ, region: REGION},
    async () => {
      const db = getFirestore();
      const snap = await db.collection("orders").get();

      const now = new Date();
      const startOfDay = new Date(
          now.getFullYear(), now.getMonth(), now.getDate());

      const overdue = [];
      snap.forEach((doc) => {
        const o = doc.data();
        if (o.status === "completed" || o.status === "cancelled") return;
        if (o.archivedAt) return;
        const due = o.dueAt ? new Date(o.dueAt) : null;
        if (due && due < startOfDay) overdue.push(o.id);
      });

      if (overdue.length === 0) return;

      const list = overdue.slice(0, 3).join(", ");
      const more = overdue.length > 3 ? ` in še ${overdue.length - 3}` : "";

      await send(
          overdue.length === 1 ? "1 naročilo zamuja" :
            `${overdue.length} naročil zamuja`,
          `${list}${more}.`,
          {kind: "overdue"},
      );
    },
);

/**
 * Jutranji povzetek dneva: kaj je danes treba pobrati oziroma vrniti.
 */
exports.morningSummary = onSchedule(
    {schedule: "0 7 * * 1-6", timeZone: TZ, region: REGION},
    async () => {
      const db = getFirestore();
      const snap = await db.collection("orders").get();

      const now = new Date();
      const startOfDay = new Date(
          now.getFullYear(), now.getMonth(), now.getDate());
      const endOfDay = new Date(startOfDay.getTime() + 86400000);

      const isOpen = (o) =>
        o.status !== "completed" && o.status !== "cancelled" && !o.archivedAt;
      const at = (v) => (v ? new Date(v) : null);
      const today = (d) => d && d >= startOfDay && d < endOfDay;

      let pickups = 0;
      let deliveries = 0;
      let overdue = 0;

      snap.forEach((doc) => {
        const o = doc.data();
        if (!isOpen(o)) return;

        if (o.status === "scheduledPickup" && today(at(o.pickupAt))) pickups++;
        if (o.status === "awaitingDelivery" && today(at(o.deliveryAt))) {
          deliveries++;
        }

        const due = at(o.dueAt);
        if (due && due < startOfDay) overdue++;
      });

      const parts = [];
      if (pickups) parts.push(`${pickups} za prevzem`);
      if (deliveries) parts.push(`${deliveries} za vračilo`);
      if (overdue) parts.push(`${overdue} v zamudi`);

      // Brez dela ni obvestila — vsakodnevno "danes ni nič" bi ljudje utišali.
      if (parts.length === 0) return;

      await send("Današnji dan", parts.join(" · "), {kind: "summary"});
    },
);

// ------------------------------------------------------------------ povzetki

/**
 * Naročila in kosi, ki jih povzetek potrebuje: vsa odprta naročila (stanje
 * "zdaj") in vsa, zaključena od `sinceIso` naprej (obdobje + prejšnje obdobje
 * za primerjavo). Vseh zaključenih naročil ne beremo — z leti bi bilo
 * vsako jutro tisoče branj za nič.
 *
 * Datumi v bazi so nizi lokalnega časa, zato je primerjava nizov pravilna.
 */
async function loadSince(sinceIso) {
  const db = getFirestore();
  const [open, done] = await Promise.all([
    db.collection("orders")
        .where("status", "in", summaries.OPEN_STATUSES).get(),
    db.collection("orders").where("completedAt", ">=", sinceIso).get(),
  ]);

  const byId = new Map();
  [...open.docs, ...done.docs].forEach((d) => byId.set(d.id, d.data()));

  // Firestore `in` sprejme največ 30 vrednosti.
  const ids = [...byId.keys()];
  const chunks = [];
  for (let i = 0; i < ids.length; i += 30) chunks.push(ids.slice(i, i + 30));
  const snaps = await Promise.all(chunks.map((chunk) =>
    db.collection("items").where("orderId", "in", chunk).get()));

  return {
    orders: [...byId.values()],
    items: snaps.flatMap((s) => s.docs.map((d) => d.data())),
  };
}

async function sendSummary(kind, build) {
  const now = new Date();
  const {orders, items} = await loadSince(summaries.sinceIso(kind, now));
  const {title, body, quiet} = build(orders, items, now);

  // Dan, ko se ni zgodilo nič in nič ne čaka, ne bi smel zvoniti.
  if (quiet) return;
  await send(title, body, {kind: `${kind}Summary`}, ADMIN_TOPIC);
}

/**
 * Dnevni povzetek zvečer. Pon–sob kot ostali urniki; ob nedeljah delavnica
 * ne dela, zato bi obvestilo samo ponavljalo stanje.
 */
exports.dailySummary = onSchedule(
    {schedule: "0 18 * * 1-6", timeZone: TZ, region: REGION, timeoutSeconds: 120},
    () => sendSummary("daily", summaries.buildDaily),
);

/** Tedenski povzetek v ponedeljek zjutraj — za zadnji cel teden (pon–ned). */
exports.weeklySummary = onSchedule(
    {schedule: "0 8 * * 1", timeZone: TZ, region: REGION, timeoutSeconds: 120},
    () => sendSummary("weekly", summaries.buildWeekly),
);

/**
 * Mesečni povzetek prvi dan v mesecu — za prejšnji cel mesec. Ob 8:30, da ne
 * pride istočasno s tedenskim, kadar je 1. v mesecu ponedeljek.
 */
exports.monthlySummary = onSchedule(
    {schedule: "30 8 1 * *", timeZone: TZ, region: REGION, timeoutSeconds: 120},
    () => sendSummary("monthly", summaries.buildMonthly),
);
