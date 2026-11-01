"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const s = require("../summaries");
const pricingCases = require("./fixtures/pricing_cases.json");

// Po koncu poletnega časa (25. 10. 2026) je Ljubljana UTC+1.
// 1. 11. 2026 je nedelja.
const at = (iso) => new Date(iso);
const SUN_1800 = at("2026-11-01T17:00:00Z"); // nedelja 1. 11., 18:00
const MON_0800 = at("2026-11-02T07:00:00Z"); // ponedeljek 2. 11., 08:00
const FIRST_0830 = at("2026-11-01T07:30:00Z"); // 1. 11., 08:30

let n = 0;
/** Naročilo v obliki `WorkOrder.toJson()` (lokalni čas brez odmika). */
function order(over = {}) {
  n++;
  return {
    id: `LJ-${String(n).padStart(3, "0")}`,
    location: "ljubljana",
    channel: "dropoff",
    handover: "customerCollects",
    status: "inProduction",
    customerId: `c${n}`,
    customerName: "Stranka",
    itemCount: 1,
    createdAt: "2026-10-01T09:00:00.000000",
    deliveryFee: 0,
    orderExtras: [],
    ...over,
  };
}

/** Kos v obliki `RugItem.toJson()`; `events` = [[status, "čas"], ...]. */
function item(o, over = {}, events = []) {
  return {
    id: `${o.id}-1`,
    orderId: o.id,
    index: 1,
    ofTotal: 1,
    status: "awaitingWash",
    extras: [],
    history: events.map(([status, time]) => ({status, at: time})),
    ...over,
  };
}

test("pricing matches the Dart billing (shared fixture)", () => {
  for (const c of pricingCases) {
    assert.equal(
        Number(s.orderTotal(c.order, c.items).toFixed(2)), c.total, c.name);
  }
});

test("local ISO strings without offset are wall-clock; offsets are converted", () => {
  const wall = (iso) => new Date(s.wallMs(iso)).toISOString();
  // Telefon (Dart toIso8601String) zapiše mikrosekunde brez odmika.
  assert.equal(wall("2026-11-01T18:04:12.345678"), "2026-11-01T18:04:12.345Z");
  // Z-niz je trenutek: pozimi +1 h, poleti +2 h.
  assert.equal(wall("2026-01-15T10:00:00Z"), "2026-01-15T11:00:00.000Z");
  assert.equal(wall("2026-07-01T10:00:00Z"), "2026-07-01T12:00:00.000Z");
  assert.equal(s.wallMs(null), null);
  assert.equal(s.wallMs("not a date"), null);
});

test("Slovenian plural forms match Fmt.pluralForm", () => {
  const forms = [1, 2, 3, 5, 11, 12, 13, 14, 21, 22, 23, 101, 111].map(s.pluralForm);
  assert.deepEqual(forms, [0, 1, 2, 3, 3, 3, 3, 3, 0, 1, 2, 0, 3]);
});

test("change(): sign, rounding, and no division by zero", () => {
  assert.equal(s.change(112, 100), "+12 %");
  assert.equal(s.change(97, 100), "−3 %");
  assert.equal(s.change(100, 100), "0 %");
  assert.equal(s.change(0, 0), "0 %");
  assert.equal(s.change(5, 0), "—");
});

// ------------------------------------------------------------------ dnevni

function dailyFixture() {
  const orders = [];
  const items = [];
  const add = (o, its = []) => {
    orders.push(o);
    items.push(...its);
    return o;
  };

  // Pripeljano danes: 2 naročili, 5 kosov. Včerajšnje, dostava in
  // polnočna meja se ne štejejo.
  add(order({createdAt: "2026-11-01T09:00:00.1", itemCount: 3}));
  add(order({createdAt: "2026-11-01T23:59:59.9", itemCount: 2}));
  add(order({createdAt: "2026-10-31T23:59:59.9", itemCount: 7}));
  add(order({createdAt: "2026-11-01T10:00:00", itemCount: 4, channel: "delivery"}));

  // Vrnjeno danes: 60 € (dropoff) — in eno včeraj.
  const done = add(order({
    status: "completed", completedAt: "2026-11-01T16:00:00",
    createdAt: "2026-10-20T09:00:00",
  }), []);
  items.push(item(done, {status: "returned", widthCm: 200, lengthCm: 300, pricePerM2: 10}));
  add(order({status: "completed", completedAt: "2026-10-31T16:00:00"}));

  // Oprano 2 kosa, pripravljena 2 kosa (6 m² + 1 m²), 3 čakajo pranje.
  const w = add(order());
  items.push(
      item(w, {id: `${w.id}-a`, status: "drying"}, [["awaitingWash", "2026-10-30T08:00:00"], ["drying", "2026-11-01T09:00:00"]]),
      item(w, {id: `${w.id}-b`, status: "drying"}, [["drying", "2026-11-01T11:00:00"]]),
      item(w, {id: `${w.id}-c`, status: "ready", widthCm: 200, lengthCm: 300, confirmedPrice: 60},
          [["drying", "2026-10-29T11:00:00"], ["ready", "2026-11-01T12:00:00"]]),
      // Ročni popravek: znova Pripravljeno — šteje samo prvič (včeraj).
      item(w, {id: `${w.id}-d`, status: "ready", widthCm: 100, lengthCm: 100, confirmedPrice: 10},
          [["ready", "2026-10-31T12:00:00"], ["ready", "2026-11-01T13:00:00"]]),
      item(w, {id: `${w.id}-e`, status: "ready", widthCm: 100, lengthCm: 100, confirmedPrice: 10},
          [["ready", "2026-11-01T14:00:00"]]),
      item(w, {id: `${w.id}-f`}), item(w, {id: `${w.id}-g`}), item(w, {id: `${w.id}-h`}),
  );

  // V kombiju 1 (drugo, brez kombija, ne šteje); neklicani: ena stranka z dvema
  // naročiloma (šteje enkrat), eno klicano, eno mlajše od 24 h.
  add(order({status: "awaitingDelivery", inVanAt: "2026-11-01T08:00:00"}));
  add(order({status: "awaitingDelivery"}));
  add(order({status: "awaitingCollection", customerId: "same", readyAt: "2026-10-30T09:00:00"}));
  add(order({status: "awaitingCollection", customerId: "same", readyAt: "2026-10-29T09:00:00"}));
  add(order({status: "awaitingCollection", readyAt: "2026-10-29T09:00:00", calledAt: "2026-10-30T09:00:00"}));
  add(order({status: "awaitingCollection", readyAt: "2026-10-31T18:30:00"}));

  return {orders, items};
}

test("daily summary: every line from the ticket", () => {
  const {orders, items} = dailyFixture();
  const r = s.buildDaily(orders, items, SUN_1800);

  assert.equal(r.title, "Povzetek dneva · 1. 11.");
  assert.equal(r.quiet, false);
  assert.deepEqual(r.body.split("\n"), [
    "Pripeljano: 2 naročili / 5 kosov",
    "Vrnjeno: 1 naročilo / 60,00 €",
    "Oprano: 2 kosa",
    "Pripravljeno: 2 kosa / 7,00 m²",
    "Še čaka pranje: 3 kosi",
    "Še v kombiju: 1 naročilo",
    "Ni klicano >24 h: 1 stranka",
  ]);
});

test("daily summary: archived orders are invisible", () => {
  const {orders, items} = dailyFixture();
  const archived = orders.map((o) => ({...o, archivedAt: "2026-11-01T12:00:00"}));
  const r = s.buildDaily(archived, items, SUN_1800);
  assert.equal(r.quiet, true);
});

test("daily summary: nothing happened and nothing waits -> quiet", () => {
  const r = s.buildDaily([], [], SUN_1800);
  assert.equal(r.quiet, true);
  assert.equal(r.body.split("\n").length, 7);
});

test("daily summary: day boundary is Ljubljana midnight, not UTC", () => {
  // 00:30 po lokalnem času 2. 11. je 23:30Z 1. 11. — v UTC bi bil še "včeraj".
  const o = order({createdAt: "2026-11-02T00:30:00"});
  const r = s.buildDaily([o], [], at("2026-11-02T17:00:00Z"));
  assert.match(r.body, /^Pripeljano: 1 naročilo \/ 1 kos/);
});

// ------------------------------------------------------------- tedenski

function weeklyFixture() {
  const orders = [];
  const items = [];
  // Obdobje: pon 26. 10. – ned 1. 11. Prejšnji teden: 19.–25. 10.
  const mk = (over, its) => {
    const o = order(over);
    orders.push(o);
    (its || []).forEach((i) => items.push(item(o, i.over, i.events)));
    return o;
  };

  // Ta teden: 3 prejeta naročila (LJ, LJ, MB), 4+1+2 kosov.
  mk({createdAt: "2026-10-26T08:00:00", itemCount: 4, customerId: "a"});
  mk({createdAt: "2026-11-01T22:00:00", itemCount: 1, customerId: "a"});
  mk({createdAt: "2026-10-28T08:00:00", itemCount: 2, customerId: "b", location: "maribor", channel: "delivery"});
  // Ta teden vrnjeno: 100 € in 200 € (200 m² kosi), pripravljena v tednu.
  mk({status: "completed", completedAt: "2026-10-27T10:00:00", createdAt: "2026-10-10T08:00:00", location: "celje"}, [
    {over: {status: "returned", widthCm: 100, lengthCm: 100, pricePerM2: 10, confirmedPrice: 100},
      events: [["ready", "2026-10-26T10:00:00"]]},
  ]);
  mk({status: "completed", completedAt: "2026-10-30T10:00:00", createdAt: "2026-10-10T08:00:00"}, [
    {over: {status: "returned", widthCm: 200, lengthCm: 100, pricePerM2: 10, confirmedPrice: 200},
      events: [["ready", "2026-10-29T10:00:00"]]},
  ]);
  // Odprta so le 3 prejeta naročila.
  // Prejšnji teden: 1 prejeto naročilo, vrnjeno 100 €, 1 m².
  mk({status: "completed", completedAt: "2026-10-22T10:00:00", createdAt: "2026-10-19T08:00:00"}, [
    {over: {status: "returned", widthCm: 100, lengthCm: 100, pricePerM2: 10, confirmedPrice: 100},
      events: [["ready", "2026-10-21T10:00:00"]]},
  ]);
  return {orders, items};
}

test("weekly summary: last full Mon-Sun week vs the one before", () => {
  const {orders, items} = weeklyFixture();
  const r = s.buildWeekly(orders, items, MON_0800);

  assert.equal(r.title, "Povzetek tedna 26. 10.–1. 11.");
  assert.deepEqual(r.body.split("\n"), [
    "Prejeto: 3 naročila / 7 kosov",
    "Oprano: 3,00 m²",
    "Vrnjeno: 2 naročili · promet 300,00 €",
    "Potrjena vrednost: 300,00 €",
    "Povprečno naročilo: 150,00 €",
    "Prejeto po regijah: LJ 2 · MB 1 · CE 0 · DOL 0",
    "Še odprtih: 3 naročila",
    // Prejšnji teden: promet 100 €, 1 m², 1 naročilo.
    "Proti prejšnjemu tednu: promet +200 % · m² +200 % · naročila +200 %",
  ]);
});

test("weekly summary: runs on any weekday, always the last full week", () => {
  const {orders, items} = weeklyFixture();
  const midweek = at("2026-11-04T10:00:00Z"); // sreda
  assert.equal(
      s.buildWeekly(orders, items, midweek).title, "Povzetek tedna 26. 10.–1. 11.");
});

// ------------------------------------------------------------- mesečni

test("monthly summary: October, with top days, channels and comparison", () => {
  const orders = [];
  const items = [];
  const mk = (over, its) => {
    const o = order(over);
    orders.push(o);
    (its || []).forEach((i) => items.push(item(o, i.over, i.events)));
    return o;
  };
  const priced = (price, m2w, ready) => ({
    over: {status: "returned", widthCm: m2w * 100, lengthCm: 100, pricePerM2: price / m2w, confirmedPrice: price},
    events: [["ready", ready]],
  });

  // Oktober, vrnjeno: 14. 10. 300 €, 21. 10. 200 €, 2. 10. 100 €, 9. 10. 50 €.
  mk({status: "completed", completedAt: "2026-10-14T09:00:00", createdAt: "2026-10-01T08:00:00", customerId: "a", location: "maribor", channel: "delivery", itemCount: 2}, [priced(100, 2, "2026-10-13T09:00:00"), priced(200, 4, "2026-10-13T09:30:00")]);
  mk({status: "completed", completedAt: "2026-10-21T09:00:00", createdAt: "2026-10-02T08:00:00", customerId: "b"}, [priced(200, 4, "2026-10-20T09:00:00")]);
  mk({status: "completed", completedAt: "2026-10-02T09:00:00", createdAt: "2026-09-28T08:00:00", customerId: "a"}, [priced(100, 2, "2026-10-01T09:00:00")]);
  mk({status: "completed", completedAt: "2026-10-09T09:00:00", createdAt: "2026-10-05T08:00:00", customerId: "c", location: "celje"}, [priced(50, 1, "2026-10-08T09:00:00")]);
  // Prejeto v novembru ne šteje v oktober.
  mk({createdAt: "2026-11-01T01:00:00"});
  // September: vrnjeno 400 € (za primerjavo), 4 m².
  mk({status: "completed", completedAt: "2026-09-15T09:00:00", createdAt: "2026-09-10T08:00:00"}, [priced(400, 4, "2026-09-14T09:00:00")]);

  const r = s.buildMonthly(orders, items, FIRST_0830);
  assert.equal(r.title, "Povzetek meseca: oktober 2026");
  assert.deepEqual(r.body.split("\n"), [
    "Prihodki: 650,00 € (vrnjeno 4 naročila)",
    "Oprano: 13,00 m²",
    // Prejeto v oktobru: A, B, D (C je bil prejet septembra, E novembra).
    "Prejeto: 3 naročila / 4 kosi / 3 stranke",
    "Povprečna cena: 50,00 €/m²",
    "Povprečno naročilo: 162,50 €",
    "Prejeto po regijah: LJ 1 · MB 1 · CE 1 · DOL 0",
    "Prihodki po regijah: LJ 300,00 € · MB 300,00 € · CE 50,00 € · DOL 0,00 €",
    "Dostava 1 · Pripeljano 2",
    "Top dnevi: 14. 10. (300,00 €) · 21. 10. (200,00 €) · 2. 10. (100,00 €)",
    "Proti prejšnjemu mesecu: prihodki +63 % · m² +225 % · naročila +50 %",
  ]);
});

test("monthly summary: January looks back at December of the previous year", () => {
  const r = s.buildMonthly([], [], at("2027-01-01T07:30:00Z"));
  assert.equal(r.title, "Povzetek meseca: december 2026");
  assert.match(r.body, /Top dnevi: —/);
});

test("sinceIso reaches back one period further than the summary needs", () => {
  assert.equal(s.sinceIso("daily", SUN_1800), "2026-10-31T00:00:00");
  assert.equal(s.sinceIso("weekly", MON_0800), "2026-10-18T00:00:00");
  assert.equal(s.sinceIso("monthly", FIRST_0830), "2026-08-31T00:00:00");
});
