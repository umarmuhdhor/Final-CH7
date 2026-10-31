import fs from "node:fs";
import { dissect } from "./dissect-lib.mjs";
import { dissect2 } from "./dissect2.mjs";
const show = (label, url) => { const a = dissect(url).score, b = dissect2(url); console.log(`${String(a).padStart(3)} -> ${String(b.score).padStart(3)}  ${label.padEnd(14)} ${url.slice(0, 70)}\n${b.parts.filter(p=>["freehost","free-label","free-number","free-path"].includes(p.part)).map(p=>`            +${p.weight} ${p.why}`).join("\n")}`.trimEnd()); };
console.log("== 4 link dari lu (v1 -> v2) ==");
for (const u of ["https://d33wubrfki0l68.cloudfront.net/a24ce9fe-3a25-440e-923c-70c96b668dc8/dhl123.html","https://simgratisonine.blogspot.com/","https://bantuannbansos2026.blogspot.com/","https://gratiskuota60gb.blogspot.com/"]) show("SCAM", u);
console.log("\n== helpnets (harus tetap 34) ==");
show("SCAM", "https://helpnets.info/0442827f6o7cfb43933ba59e2881cc906b7c.html/");
console.log("\n== legit di hosting gratis (false positive?) ==");
for (const u of [
 "https://resepnusantara.blogspot.com/",
 "https://catatanprogrammer.blogspot.com/2024/05/belajar-swift.html",
 "https://tipskeuanganku.blogspot.com/2026/10/cara-cek-saldo-bca.html",
 "https://user.github.io/portfolio/",
 "https://myapp.netlify.app/",
 "https://d111abcdef.cloudfront.net/assets/logo.png",
 "https://sekolahku2026.blogspot.com/",
 "https://infopaketwisata.blogspot.com/",
]) show("legit", u);
console.log("\n== regresi: seluruh corpus ==");
const base = "/Users/imelda/Documents/Swift/Final-CH/Final-CH7/ai/eval/data/";
const rows = [];
for (const k of ["scam","legit"]) for (const f of fs.readdirSync(base+k).filter(f=>f.endsWith(".json"))) { let j=JSON.parse(fs.readFileSync(`${base}${k}/${f}`,"utf8")); j=Array.isArray(j)?j:[j]; for (const s of j) rows.push({k,id:s.id,url:s.snapshot.url,v1:dissect(s.snapshot.url).score,v2:dissect2(s.snapshot.url).score}); }
for (const k of ["scam","legit"]) { const r=rows.filter(x=>x.k===k); console.log(k, "v1 >=15:", r.filter(x=>x.v1>=15).length, " v2 >=15:", r.filter(x=>x.v2>=15).length, " v2 >=30:", r.filter(x=>x.v2>=30).length, " changed:", r.filter(x=>x.v1!==x.v2).length); }
for (const x of rows.filter(x=>x.v1!==x.v2)) console.log("  changed", x.k, x.v1, "->", x.v2, x.url);
