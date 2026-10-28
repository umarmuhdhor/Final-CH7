// Owner: lead. Content-script side of the layer-1 lists (contracts/detector-interface.md "ShooLists").
// Loaded first (manifest.json) so detector.js can call it. The lists themselves live in background.js.

globalThis.ShooLists = {
    /** @returns {Promise<{source: "shoo"|"public", domain: string, addedAt: string|null} | null>} never rejects */
    async match(hostname) {
        try {
            const reply = await browser.runtime.sendMessage({ type: "listMatch", hostname });
            return reply?.match ?? null;
        } catch {
            return null;
        }
    },
};
