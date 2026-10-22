// Development source: invented domains from ai/data/public-blocklist.seed.json. NOT a real feed.
// Used by `npm run dev` and tests; the Worker entry never imports it.
import seed from "../../data/public-blocklist.seed.json" with { type: "json" };
import { createStaticSource } from "./source.js";

export const fixtureSource = createStaticSource({ name: seed.source, license: seed.license, entries: seed.entries });
