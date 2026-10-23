// Cloudflare Worker entry (module syntax): the Hono app is the fetch handler.
import { createApp } from "./app.js";

// Real network only here; createApp() alone never calls out.
export default createApp({ fetch: (...args) => fetch(...args), llmFetch: (...args) => fetch(...args) });
// /public-blocklist stays an empty list until Imelda approves a feed (plan/imelda/TODO.md A3); see ai/README.md.
