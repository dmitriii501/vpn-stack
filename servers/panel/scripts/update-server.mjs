#!/usr/bin/env node
// Обновляет строку в таблице servers (PGlite) на панели.
//
// Использование (на панели, при остановленном vpn-web):
//   systemctl stop vpn-web
//   node update-server.mjs --country DE --uuid <uuid> --public-key <pbk> --short-id <hex8> --active true
//   systemctl start vpn-web
//
// Безопасно: правит только переданные поля.
import * as mod from "/opt/vpn-web/functions/__server.func/_libs/electric-sql__pglite.mjs";

const PGlite = mod.t?.PGlite ?? mod.PGlite;
if (!PGlite) throw new Error("PGlite export not found");

const args = process.argv.slice(2);
const opt = {};
for (let i = 0; i < args.length; i += 2) opt[args[i].replace(/^--/, "")] = args[i + 1];

const country = opt.country;
if (!country) {
  console.error("required: --country <DE|PL|NL|...>");
  process.exit(1);
}

const fields = [];
const vals = [];
const map = {
  uuid: "uuid",
  "public-key": "public_key",
  "short-id": "short_id",
  sni: "sni",
  host: "host",
  port: "port",
  path: "path",
  mode: "mode",
  active: "active",
};
for (const [k, col] of Object.entries(map)) {
  if (opt[k] === undefined) continue;
  fields.push(col);
  vals.push(opt[k] === "true" ? true : opt[k] === "false" ? false : opt[k]);
}
if (!fields.length) {
  console.error("nothing to update");
  process.exit(1);
}

const db = new PGlite("/opt/vpn-web/pgdata");
await db.waitReady;

const setSql = fields.map((f, i) => `${f} = $${i + 1}`).join(", ");
const sql = `update servers set ${setSql} where country = $${fields.length + 1} returning id, country, uuid, public_key, short_id, active`;
const res = await db.query(sql, [...vals, country]);
console.log(JSON.stringify(res.rows, null, 2));
await db.close();
