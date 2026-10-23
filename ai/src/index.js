// Cloudflare Worker entry (module syntax): the Hono app is the fetch handler.
import { createApp } from "./app.js";

// Real network only here; createApp() alone never calls out.
export default createApp({ fetch: (...args) => fetch(...args) });
