/**
 * Dnevni, tedenski in mesečni povzetek.
 *
 * Čist izračun brez odvisnosti od Firebase — vhod so dokumenti iz zbirk
 * `orders` in `items` (oblika je `toJson()` v lib/models), izhod naslov in
 * besedilo obvestila. Tako ga je mogoče preizkusiti z `npm test`.
 *
 * Tri stvari, ki jih je lahko zlomiti:
 *
 * 1. ČAS. Telefoni zapišejo lokalni čas brez odmika ("2026-11-01T18:04:12.3")
 *    — strežnik pa teče v UTC. Zato vse pretvorimo v "stensko uro"
 *    Europe/Ljubljana (UTC-časovnica, ki kaže lokalno uro) in računamo samo
 *    na njej. Dan je potem preprosto `Math.floor(ms / DAY)`.
 * 2. DENAR. `orderTotal` je prepis `billingFor()` iz lib/data/billing.dart.
 *    Obe strani preverja skupna datoteka test/fixtures/pricing_cases.json
 *    (Dart: test/summary_pricing_test.dart) — če spremeniš obračun v
 *    aplikaciji, se mora spremeniti tudi tu.
 * 3. ARHIV. Arhivirana naročila niso nikjer (plan.md §4.15), tudi v
 *    povzetkih ne — enako kot v Statistiki.
 */

"use strict";

const TZ = "Europe/Ljubljana";
const HOUR = 3600000;
const DAY = 24 * HOUR;

/** Kot `alerts.dart` `uncalledAfter`. */
const UNCALLED_AFTER_MS = 24 * HOUR;
/** Kot `billing.dart` `minimumDeliveryOrderTotal`. */
const MIN_DELIVERY_ORDER_TOTAL = 50;

const REGIONS = [
  ["ljubljana", "LJ"],
  ["maribor", "MB"],
  ["celje", "CE"],
  ["dolenjska", "DOL"],
];

/** Kot `OrderChannel.label` v lib/models/enums.dart. */
const CHANNELS = [
  ["delivery", "Dostava"],
  ["dropoff", "Pripeljano"],
  ["b2b", "B2B"],
];

const MONTHS = [
  "januar", "februar", "marec", "april", "maj", "junij",
  "julij", "avgust", "september", "oktober", "november", "december",
];

// ------------------------------------------------------------------- čas

const HAS_OFFSET = /(?:Z|[+-]\d{2}:?\d{2})$/;

/** Stenska ura Europe/Ljubljana za dani trenutek, kot UTC milisekunde. */
function wallOfInstant(date) {
  const parts = {};
  new Intl.DateTimeFormat("en-GB", {
    timeZone: TZ,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(date).forEach((p) => {
    parts[p.type] = Number(p.value);
  });
  return Date.UTC(
      parts.year, parts.month - 1, parts.day,
      parts.hour, parts.minute, parts.second);
}

/** ISO niz iz baze → stenska ura (ms), ali null. */
function wallMs(iso) {
  if (!iso || typeof iso !== "string") return null;
  const ms = HAS_OFFSET.test(iso) ?
    wallOfInstant(new Date(iso)) :
    Date.parse(`${iso}Z`);
  return Number.isNaN(ms) ? null : ms;
}

const dayStart = (ms) => Math.floor(ms / DAY) * DAY;
const dayKey = (ms) => new Date(ms).toISOString().slice(0, 10);
const inRange = (ms, from, to) => ms !== null && ms >= from && ms < to;

/** Naiven ISO niz, primerljiv z zapisi iz baze (leksikografsko). */
const isoOfWall = (ms) => new Date(ms).toISOString().slice(0, 19);

function dayShort(ms) {
  const d = new Date(ms);
  return `${d.getUTCDate()}. ${d.getUTCMonth() + 1}.`;
}

// ----------------------------------------------------------------- obračun

const round2 = (v) => Number(v.toFixed(2));

function extraAmount(e, base, m2) {
  switch (e.kind) {
    case "fixed": return e.value;
    case "perM2": return e.value * m2;
    case "percent": return (base * e.value) / 100;
    default: return 0;
  }
}

/** `RugItem.m2` */
function itemM2(i) {
  if (i.manualM2 != null && i.manualM2 > 0) return i.manualM2;
  if (i.widthCm == null || i.lengthCm == null) return 0;
  return (i.widthCm * i.lengthCm) / 10000;
}

/** `RugItem.price` (potrjena cena, sicer izračunana). */
function itemPrice(i) {
  if (i.confirmedPrice != null) return i.confirmedPrice;
  const m2 = itemM2(i);
  const minM2 = i.minChargeM2 || 0;
  const charge = m2 < minM2 ? minM2 : m2;
  const base = charge * (i.pricePerM2 || 0);
  const extras = (i.extras || []).reduce(
      (s, e) => s + extraAmount(e, base, charge), 0);
  const total = base + extras - ((base + extras) * (i.discountPercent || 0)) / 100;
  return total < 0 ? 0 : round2(total);
}

/** `billingFor(order, items).total` — kosi + doplačila + dostava + minimum. */
function orderTotal(order, items) {
  const itemsTotal = items.reduce((s, i) => s + itemPrice(i), 0);
  const allPriced = items.length > 0 &&
    items.every((i) => i.status === "ready" || i.status === "returned");
  const extras = (order.orderExtras || []).reduce(
      (s, e) => s + extraAmount(e, 0, 0), 0);
  const subtotal = itemsTotal + extras + (order.deliveryFee || 0);
  const topUp = order.channel === "delivery" && allPriced &&
    subtotal < MIN_DELIVERY_ORDER_TOTAL ?
    round2(MIN_DELIVERY_ORDER_TOTAL - subtotal) : 0;
  return subtotal + topUp;
}

// ------------------------------------------------------------------ podatki

const isOpen = (o) => o.status !== "completed" && o.status !== "cancelled";

/** Brez arhiviranih naročil; kosi samo od preostalih naročil. */
function index(orderDocs, itemDocs) {
  const live = orderDocs.filter((o) => !o.archivedAt);
  const ids = new Set(live.map((o) => o.id));
  const byOrder = new Map();
  for (const i of itemDocs) {
    if (!ids.has(i.orderId)) continue;
    if (!byOrder.has(i.orderId)) byOrder.set(i.orderId, []);
    byOrder.get(i.orderId).push(i);
  }
  return {
    orders: live,
    items: [...byOrder.values()].flat(),
    itemsOf: (id) => byOrder.get(id) || [],
  };
}

/**
 * Kdaj je kos PRVIČ dosegel status. Prvi, ne zadnji: če kos po ročnem
 * popravku znova gre skozi isti korak, se v obdobju ne sme šteti dvakrat.
 */
function firstEvent(item, status) {
  const e = (item.history || []).find((h) => h.status === status);
  return e ? wallMs(e.at) : null;
}

const regionOf = (o) => o.location || "ljubljana";

// -------------------------------------------------------------- oblikovanje

/** Kot `Fmt.money` / `Fmt.m2`. */
const money = (v) => `${v.toFixed(2).replace(".", ",")} €`;
const m2fmt = (v) => `${v.toFixed(2).replace(".", ",")} m²`;

/** Kot `Fmt.pluralForm`. */
function pluralForm(n) {
  const mod100 = n % 100;
  const mod10 = n % 10;
  if (mod100 === 1 || (mod10 === 1 && mod100 !== 11)) return 0;
  if (mod100 === 2 || (mod10 === 2 && mod100 !== 12)) return 1;
  if ((mod10 === 3 || mod10 === 4) && mod100 !== 13 && mod100 !== 14) return 2;
  return 3;
}

const plural = (n, forms) => `${n} ${forms[pluralForm(n)]}`;
const nOrders = (n) => plural(n, ["naročilo", "naročili", "naročila", "naročil"]);
const nPieces = (n) => plural(n, ["kos", "kosa", "kosi", "kosov"]);
const nCustomers = (n) => plural(n, ["stranka", "stranki", "stranke", "strank"]);

/** "+12 %", "−3 %"; brez prejšnjega obdobja ni primerjave. */
function change(cur, prev) {
  if (prev === 0) return cur === 0 ? "0 %" : "—";
  const p = Math.round(((cur - prev) / prev) * 100);
  if (p === 0) return "0 %";
  return `${p > 0 ? "+" : "−"}${Math.abs(p)} %`;
}

const sum = (list, fn) => list.reduce((s, x) => s + fn(x), 0);

// ------------------------------------------------------------------- dnevni

function dailyStats(data, nowMs) {
  const from = dayStart(nowMs);
  const to = from + DAY;

  const brought = data.orders.filter((o) =>
    o.channel === "dropoff" && inRange(wallMs(o.createdAt), from, to));
  const returned = data.orders.filter((o) =>
    o.status === "completed" && inRange(wallMs(o.completedAt), from, to));
  const washed = data.items.filter((i) =>
    inRange(firstEvent(i, "drying"), from, to));
  const ready = data.items.filter((i) =>
    inRange(firstEvent(i, "ready"), from, to));
  const waiting = data.items.filter((i) => i.status === "awaitingWash");
  const inVan = data.orders.filter((o) =>
    o.status === "awaitingDelivery" && o.inVanAt);
  const uncalled = data.orders.filter((o) => {
    const readyAt = wallMs(o.readyAt);
    return o.status === "awaitingCollection" && !o.calledAt &&
      readyAt !== null && nowMs - readyAt >= UNCALLED_AFTER_MS;
  });

  return {
    brought: {orders: brought.length, pieces: sum(brought, (o) => o.itemCount || 0)},
    returned: {
      orders: returned.length,
      revenue: sum(returned, (o) => orderTotal(o, data.itemsOf(o.id))),
    },
    washed: washed.length,
    // m² je znan šele ob merjenju (po sušenju), zato je ob "Pripravljeno".
    ready: {pieces: ready.length, m2: sum(ready, itemM2)},
    waiting: waiting.length,
    inVan: inVan.length,
    uncalled: new Set(uncalled.map((o) => o.customerId || o.id)).size,
  };
}

/**
 * @return {{title: string, body: string, quiet: boolean}} `quiet`: nič se ni
 *   zgodilo in nič ne čaka — takega obvestila ne pošiljamo.
 */
function buildDaily(orderDocs, itemDocs, now = new Date()) {
  const nowMs = wallOfInstant(now);
  const s = dailyStats(index(orderDocs, itemDocs), nowMs);

  const body = [
    `Pripeljano: ${nOrders(s.brought.orders)} / ${nPieces(s.brought.pieces)}`,
    `Vrnjeno: ${nOrders(s.returned.orders)} / ${money(s.returned.revenue)}`,
    `Oprano: ${nPieces(s.washed)}`,
    `Pripravljeno: ${nPieces(s.ready.pieces)} / ${m2fmt(s.ready.m2)}`,
    `Še čaka pranje: ${nPieces(s.waiting)}`,
    `Še v kombiju: ${nOrders(s.inVan)}`,
    `Ni klicano >24 h: ${nCustomers(s.uncalled)}`,
  ].join("\n");

  const quiet = s.brought.orders + s.returned.orders + s.washed +
    s.ready.pieces + s.waiting + s.inVan + s.uncalled === 0;
  return {title: `Povzetek dneva · ${dayShort(dayStart(nowMs))}`, body, quiet};
}

// ------------------------------------------------------ tedenski, mesečni

/** Vse, kar potrebujeta tedenski in mesečni povzetek, za [from, to). */
function periodStats(data, from, to) {
  const received = data.orders.filter((o) =>
    inRange(wallMs(o.createdAt), from, to));
  const returned = data.orders.filter((o) =>
    o.status === "completed" && inRange(wallMs(o.completedAt), from, to));
  const ready = data.items.filter((i) =>
    inRange(firstEvent(i, "ready"), from, to));
  const measured = ready.filter((i) => itemM2(i) > 0);

  const totals = new Map(returned.map(
      (o) => [o.id, orderTotal(o, data.itemsOf(o.id))]));
  const revenue = sum([...totals.values()], (v) => v);

  const count = (list, key, keys) =>
    Object.fromEntries(keys.map((k) => [k, list.filter((o) => key(o) === k).length]));
  const regionKeys = REGIONS.map(([k]) => k);

  const revenueByDay = new Map();
  for (const o of returned) {
    const day = dayKey(wallMs(o.completedAt));
    revenueByDay.set(day, (revenueByDay.get(day) || 0) + totals.get(o.id));
  }

  return {
    received: {
      orders: received.length,
      pieces: sum(received, (o) => o.itemCount || 0),
      customers: new Set(received.map((o) => o.customerId || o.id)).size,
      byRegion: count(received, regionOf, regionKeys),
      byChannel: count(received, (o) => o.channel, CHANNELS.map(([k]) => k)),
    },
    returned: {
      orders: returned.length,
      revenue,
      average: returned.length ? revenue / returned.length : 0,
      revenueByRegion: Object.fromEntries(regionKeys.map((k) => [
        k, sum(returned.filter((o) => regionOf(o) === k), (o) => totals.get(o.id)),
      ])),
      topDays: [...revenueByDay.entries()]
          .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
          .slice(0, 3),
    },
    // "Oprano" = kosi, ki so v obdobju prvič postali Pripravljeno: takrat je
    // znan m² in potrjena cena. Dogodek je ob koncu obdobja dokončen, zato je
    // primerjava s prejšnjim obdobjem poštena.
    washed: {
      m2: sum(ready, itemM2),
      value: sum(ready, itemPrice),
      pricePerM2: sum(measured, itemM2) > 0 ?
        sum(measured, itemPrice) / sum(measured, itemM2) : 0,
    },
  };
}

const regionLine = (counts) =>
  REGIONS.map(([k, code]) => `${code} ${counts[k]}`).join(" · ");

/** Zadnji celi teden (pon–ned) pred danes in teden pred njim. */
function weekBounds(now) {
  const today = dayStart(wallOfInstant(now));
  const monday = today - ((new Date(today).getUTCDay() + 6) % 7) * DAY;
  return {from: monday - 7 * DAY, to: monday, prevFrom: monday - 14 * DAY};
}

/** Prejšnji celi koledarski mesec in mesec pred njim. */
function monthBounds(now) {
  const t = new Date(wallOfInstant(now));
  const y = t.getUTCFullYear();
  const m = t.getUTCMonth();
  return {
    from: Date.UTC(y, m - 1, 1),
    to: Date.UTC(y, m, 1),
    prevFrom: Date.UTC(y, m - 2, 1),
  };
}

function buildWeekly(orderDocs, itemDocs, now = new Date()) {
  const data = index(orderDocs, itemDocs);
  const {from, to, prevFrom} = weekBounds(now);
  const cur = periodStats(data, from, to);
  const prev = periodStats(data, prevFrom, from);

  const body = [
    `Prejeto: ${nOrders(cur.received.orders)} / ${nPieces(cur.received.pieces)}`,
    `Oprano: ${m2fmt(cur.washed.m2)}`,
    `Vrnjeno: ${nOrders(cur.returned.orders)} · promet ${money(cur.returned.revenue)}`,
    `Potrjena vrednost: ${money(cur.washed.value)}`,
    `Povprečno naročilo: ${money(cur.returned.average)}`,
    `Prejeto po regijah: ${regionLine(cur.received.byRegion)}`,
    `Še odprtih: ${nOrders(data.orders.filter(isOpen).length)}`,
    "Proti prejšnjemu tednu: " + [
      `promet ${change(cur.returned.revenue, prev.returned.revenue)}`,
      `m² ${change(cur.washed.m2, prev.washed.m2)}`,
      `naročila ${change(cur.received.orders, prev.received.orders)}`,
    ].join(" · "),
  ].join("\n");

  return {title: `Povzetek tedna ${dayShort(from)}–${dayShort(to - DAY)}`, body};
}

function buildMonthly(orderDocs, itemDocs, now = new Date()) {
  const data = index(orderDocs, itemDocs);
  const {from, to, prevFrom} = monthBounds(now);
  const cur = periodStats(data, from, to);
  const prev = periodStats(data, prevFrom, from);

  const channels = CHANNELS
      .filter(([k]) => k !== "b2b" || cur.received.byChannel[k] > 0)
      .map(([k, label]) => `${label} ${cur.received.byChannel[k]}`)
      .join(" · ");
  const topDays = cur.returned.topDays.length ?
    cur.returned.topDays
        .map(([day, v]) => `${dayShort(Date.parse(`${day}T00:00:00Z`))} (${money(v)})`)
        .join(" · ") :
    "—";
  const revenueByRegion = REGIONS
      .map(([k, code]) => `${code} ${money(cur.returned.revenueByRegion[k])}`)
      .join(" · ");

  const body = [
    `Prihodki: ${money(cur.returned.revenue)} (vrnjeno ${nOrders(cur.returned.orders)})`,
    `Oprano: ${m2fmt(cur.washed.m2)}`,
    `Prejeto: ${nOrders(cur.received.orders)} / ${nPieces(cur.received.pieces)} / ` +
      nCustomers(cur.received.customers),
    `Povprečna cena: ${money(cur.washed.pricePerM2)}/m²`,
    `Povprečno naročilo: ${money(cur.returned.average)}`,
    `Prejeto po regijah: ${regionLine(cur.received.byRegion)}`,
    `Prihodki po regijah: ${revenueByRegion}`,
    channels,
    `Top dnevi: ${topDays}`,
    "Proti prejšnjemu mesecu: " + [
      `prihodki ${change(cur.returned.revenue, prev.returned.revenue)}`,
      `m² ${change(cur.washed.m2, prev.washed.m2)}`,
      `naročila ${change(cur.received.orders, prev.received.orders)}`,
    ].join(" · "),
  ].join("\n");

  const d = new Date(from);
  return {title: `Povzetek meseca: ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`, body};
}

/**
 * Od kdaj naprej je treba prebrati naročila, da povzetek ni okrnjen:
 * obdobje + prejšnje obdobje za primerjavo, z dnevom rezerve.
 */
function sinceIso(kind, now = new Date()) {
  const today = dayStart(wallOfInstant(now));
  const start = {
    daily: today,
    weekly: weekBounds(now).prevFrom,
    monthly: monthBounds(now).prevFrom,
  }[kind];
  return isoOfWall(start - DAY);
}

module.exports = {
  buildDaily,
  buildWeekly,
  buildMonthly,
  sinceIso,
  // Za teste.
  orderTotal,
  itemPrice,
  itemM2,
  wallMs,
  pluralForm,
  change,
  OPEN_STATUSES: ["scheduledPickup", "inProduction", "awaitingCollection", "awaitingDelivery"],
};
