// Figma parity QA (figma-parity-2026-10-31.md): exports every iOS frame of the High Fidelity sections as PNG @1x
// through the TalkToFigma relay (plugin open in the file, channel joined). Then: sips to JPEG 402 px wide.
//   node plan/alief/qa/figma-export.mjs <outDir> [channel]
import fs from "node:fs"; import path from "node:path"; import crypto from "node:crypto";
const out = process.argv[2]; fs.mkdirSync(out, { recursive: true });
const CH = process.argv[3] ?? "aul6g56c";
const SECTIONS = ["141:6094","141:5987","413:1778","450:4935","416:9961","455:9046","480:6835"];
const ws = new WebSocket("ws://localhost:3055");
const pending = new Map();
ws.onmessage = (ev) => { const d = JSON.parse(ev.data); const m = d.message; if (m && m.id && pending.has(m.id) && ("result" in m || "error" in m)) { const p = pending.get(m.id); pending.delete(m.id); m.error ? p.rej(new Error(m.error)) : p.res(m.result); } };
const send = (command, params) => new Promise((res, rej) => { const id = crypto.randomUUID(); pending.set(id, { res, rej }); ws.send(JSON.stringify({ id, type: "message", channel: CH, message: { id, command, params: { ...params, commandId: id } } })); setTimeout(() => { if (pending.delete(id)) rej(new Error("timeout " + command)); }, 120000); });
await new Promise(r => ws.onopen = r);
ws.send(JSON.stringify({ type: "join", channel: CH }));
await new Promise(r => setTimeout(r, 500));
const code = `const ids = params.ids; const out = [];
for (const sid of ids) { const s = await figma.getNodeByIdAsync(sid); if (!s) continue;
  const walk = (n, sec) => { for (const c of n.children || []) {
    if ((c.type === 'FRAME' || c.type === 'INSTANCE' || c.type === 'COMPONENT') && c.width >= 360 && c.width <= 440 && c.height >= 700) out.push({ id: c.id, name: c.name, section: sec, sectionId: s.id, x: Math.round(c.x), y: Math.round(c.y), w: Math.round(c.width), h: Math.round(c.height) });
    else if (c.type === 'SECTION' || (c.type === 'FRAME' && c.width > 440)) walk(c, sec + ' / ' + c.name); } };
  walk(s, s.name); }
return out;`;
const frames = process.argv[3] ? process.argv[3].split(",").map(id => ({ id })) : await send("run_script", { code, params: { ids: SECTIONS } });
if (!process.argv[3]) fs.writeFileSync(path.join(out, "frames.json"), JSON.stringify(frames, null, 2));
console.log("frames", frames.length);
let ok = 0;
for (const f of frames) {
  const file = path.join(out, f.id.replace(/[:;]/g, "-") + ".png");
  if (fs.existsSync(file)) { ok++; continue; }
  try { const r = await send("export_node_as_image", { nodeId: f.id, format: "PNG", scale: 1 }); fs.writeFileSync(file, Buffer.from(r.imageData, "base64")); ok++; }
  catch (e) { console.log("fail", f.id, e.message); }
}
console.log("exported", ok); ws.close(); process.exit(0);
