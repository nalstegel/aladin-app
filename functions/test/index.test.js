"use strict";

// Preizkus lepila v index.js (branje iz Firestora, tema, tihi dan) brez Firebase:
// firebase-* moduli so nadomeščeni s pomnilniško lažno bazo.

const test = require("node:test");
const assert = require("node:assert/strict");
const Module = require("node:module");

const sent = [];
let db = null;

const originalLoad = Module._load;
Module._load = function(request, ...rest) {
  if (request.startsWith("firebase-functions")) {
    return {
      onSchedule: (options, handler) => ({options, handler}),
      onDocumentUpdated: (options, handler) => ({options, handler}),
    };
  }
  if (request === "firebase-admin/app") return {initializeApp() {}};
  if (request === "firebase-admin/firestore") return {getFirestore: () => db};
  if (request === "firebase-admin/messaging") {
    return {getMessaging: () => ({send: async (m) => sent.push(m)})};
  }
  return originalLoad.call(this, request, ...rest);
};
const functions = require("../index");
Module._load = originalLoad;

/** Najmanjša lažna baza: where(==, in, >=) + get(). Beleži poizvedbe. */
function fakeDb(collections) {
  const queries = [];
  const matches = (doc, [field, op, value]) => {
    if (op === "in") return value.includes(doc[field]);
    if (op === ">=") return typeof doc[field] === "string" && doc[field] >= value;
    throw new Error(`unsupported op ${op}`);
  };
  const query = (name, filters) => ({
    where: (f, op, v) => query(name, [...filters, [f, op, v]]),
    async get() {
      queries.push({name, filters});
      if (filters.some(([, op, v]) => op === "in" && v.length > 30)) {
        throw new Error("Firestore: 'in' supports at most 30 values");
      }
      const docs = collections[name]
          .filter((d) => filters.every((f) => matches(d, f)))
          .map((d) => ({id: d.id, data: () => d}));
      return {docs};
    },
  });
  return {queries, collection: (name) => query(name, [])};
}

const at18 = () => test.mock.timers.enable({
  apis: ["Date"],
  now: new Date("2026-11-01T17:00:00Z"), // nedelja 1. 11., 18:00 po ljubljanskem času
});

test("dailySummary: reads in chunks of 30, sends to the admin topic only", async () => {
  at18();
  sent.length = 0;
  const orders = [];
  const items = [];
  for (let n = 1; n <= 70; n++) {
    const id = `LJ-${n}`;
    orders.push({id, status: "inProduction", channel: "dropoff", createdAt: "2026-10-01T09:00:00"});
    items.push({id: `${id}-1`, orderId: id, status: "awaitingWash", history: []});
  }
  // Staro zaključeno naročilo je pred `sinceIso` in se ne sme prebrati.
  orders.push({id: "OLD", status: "completed", completedAt: "2025-01-01T09:00:00"});
  db = fakeDb({orders, items});

  await functions.dailySummary.handler();

  assert.equal(sent.length, 1);
  assert.equal(sent[0].topic, "admini");
  assert.equal(sent[0].notification.title, "Povzetek dneva · 1. 11.");
  assert.match(sent[0].notification.body, /Še čaka pranje: 70 kosov/);
  assert.deepEqual(sent[0].data, {kind: "dailySummary"});

  const itemQueries = db.queries.filter((q) => q.name === "items");
  assert.equal(itemQueries.length, 3); // 70 naročil → 30 + 30 + 10
  const ids = itemQueries.flatMap((q) => q.filters[0][2]);
  assert.equal(ids.length, 70);
  assert.ok(!ids.includes("OLD"));
  test.mock.timers.reset();
});

test("dailySummary: a quiet day sends nothing", async () => {
  at18();
  sent.length = 0;
  db = fakeDb({orders: [], items: []});
  await functions.dailySummary.handler();
  assert.equal(sent.length, 0);
  test.mock.timers.reset();
});

test("weeklySummary and monthlySummary always send, to admins", async () => {
  test.mock.timers.enable({apis: ["Date"], now: new Date("2026-11-01T07:30:00Z")});
  sent.length = 0;
  db = fakeDb({orders: [], items: []});
  await functions.weeklySummary.handler();
  await functions.monthlySummary.handler();
  assert.deepEqual(sent.map((m) => m.topic), ["admini", "admini"]);
  assert.deepEqual(sent.map((m) => m.data.kind), ["weeklySummary", "monthlySummary"]);
  assert.match(sent[1].notification.title, /^Povzetek meseca: oktober 2026$/);
  test.mock.timers.reset();
});

test("schedules: daily Mon-Sat 18:00, weekly Monday 08:00, monthly 1st 08:30", () => {
  const s = (f) => [f.options.schedule, f.options.timeZone];
  assert.deepEqual(s(functions.dailySummary), ["0 18 * * 1-6", "Europe/Ljubljana"]);
  assert.deepEqual(s(functions.weeklySummary), ["0 8 * * 1", "Europe/Ljubljana"]);
  assert.deepEqual(s(functions.monthlySummary), ["30 8 1 * *", "Europe/Ljubljana"]);
});
