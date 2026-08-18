//  Repair API reference links in the authored pages.
//
//  GNATdoc names every anchor by a hash of the entity, so changing a
//  subprogram's profile changes its anchor and silently breaks every link
//  to it. The site check catches that, but what it reports is a pair of
//  hashes, which says nothing about which entity moved. This resolves the
//  link text against the generated search index and rewrites the href.
//
//  Only broken links are touched. A link that still resolves is left
//  alone, so an intended overload is never quietly swapped for another.

import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const site = join(root, "build", "site");
const areas = ["api", "n3-api", "sparql-api"];

if (!existsSync(site)) {
  console.error("build/site is missing; run scripts/build-site.sh first");
  process.exit(1);
}

//  Every id present in each generated page, so a link can be tested.
const ids = new Map();
//  Every documented entity, by qualified name and by short name.
const byQualified = new Map();
const byShort = new Map();

for (const area of areas) {
  const dir = join(site, area);
  for (const file of readdirSync(dir)) {
    if (!file.endsWith(".html")) continue;
    const text = readFileSync(join(dir, file), "utf8");
    const found = new Set();
    for (const m of text.matchAll(/\sid=([0-9a-f]{64})/g)) found.add(m[1]);
    ids.set(area + "/" + file, found);
  }

  const index = join(dir, "search-index.js");
  if (!existsSync(index)) continue;
  const source = readFileSync(index, "utf8");
  const entries = JSON.parse(
    source.slice(source.indexOf("["), source.lastIndexOf("]") + 1)
  );
  for (const entry of entries) {
    if (!entry.href || !entry.href.includes("#")) continue;
    const target = { area, href: entry.href };
    for (const pair of [
      [byQualified, entry.qualifiedName],
      [byShort, entry.name],
    ]) {
      const map = pair[0];
      const key = pair[1];
      if (!key) continue;
      const slot = area + " " + key;
      if (!map.has(slot)) map.set(slot, []);
      map.get(slot).push(target);
    }
  }
}

const pattern =
  /href="((?:\.\.\/)?)(api|n3-api|sparql-api)\/([0-9a-f]{64}\.html)#([0-9a-f]{64})"><code>([^<]+)<\/code>/g;

let repaired = 0;
let unresolved = 0;

const pages = [];
const walk = (dir) => {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.name.endsWith(".html")) pages.push(full);
  }
};
walk(join(root, "website"));

for (const page of pages) {
  const before = readFileSync(page, "utf8");
  const after = before.replace(
    pattern,
    (whole, up, area, file, anchor, label) => {
      const present = ids.get(area + "/" + file);
      if (present && present.has(anchor)) return whole;

      const candidates =
        byQualified.get(area + " " + label) ??
        byShort.get(area + " " + label) ??
        [];

      if (candidates.length !== 1) {
        unresolved += 1;
        console.error(
          page + ": cannot repair " + label +
          " (" + candidates.length + " matches in " + area + ")"
        );
        return whole;
      }

      repaired += 1;
      const moved = candidates[0].href.split("#")[1];
      console.log(
        label + ": " + anchor.slice(0, 12) + " becomes " + moved.slice(0, 12)
      );
      return 'href="' + up + area + "/" + candidates[0].href +
             '"><code>' + label + "</code>";
    }
  );
  if (after !== before) writeFileSync(page, after);
}

console.log("repaired " + repaired + ", unresolved " + unresolved);
process.exit(unresolved > 0 ? 1 : 0);
