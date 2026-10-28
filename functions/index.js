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

initializeApp();

const TOPIC = "zaposleni";
const REGION = "europe-west3";
const TZ = "Europe/Ljubljana";

/** Statusa, pri katerih naročilo čaka na stranko. */
const HANDOVER_READY = ["awaitingCollection", "awaitingDelivery"];

function send(title, body, data) {
  return getMessaging().send({
    topic: TOPIC,
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

      await send(
          `${after.number} je pripravljeno`,
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
        const due = o.dueAt ? new Date(o.dueAt) : null;
        if (due && due < startOfDay) overdue.push(o.number);
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

      const isOpen = (o) => o.status !== "completed" && o.status !== "cancelled";
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
