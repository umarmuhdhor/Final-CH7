import fs from "node:fs";
import { dissect } from "./dissect-lib.mjs";
(0,eval)(fs.readFileSync("/Users/imelda/Documents/Swift/Final-CH/Final-CH7/ios/ShooExtension/Resources/detector.js","utf8"));
globalThis.ShooLists={match:async()=>null};
for (const url of [
"https://d33wubrfki0l68.cloudfront.net/a24ce9fe-3a25-440e-923c-70c96b668dc8/dhl123.html",
"https://simgratisonine.blogspot.com/",
"https://bantuannbansos2026.blogspot.com/",
"https://gratiskuota60gb.blogspot.com/"]) {
  const r = dissect(url);
  const old = await globalThis.ShooDetector.analyzeLocal({url});
  console.log(`\n${url}\n  prototipe: ${r.score}  ${r.parts.map(p=>p.part+"+"+p.weight).join(" ")||"-"}\n  detector lama: ${old.reduce((a,b)=>a+b.weight,0)}  ${old.map(s=>s.id).join(",")||"-"}`);
}
