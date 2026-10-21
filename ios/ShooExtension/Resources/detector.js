// GENERATED from detector/ by detector/scripts/sync-to-extension.sh — DO NOT EDIT HERE.
// Owner: Team AI. Layer 1 (database) + layer 2 (link name). Contract: contracts/detector-interface.md
// Stub: returns no signals until the real rules land.

globalThis.ShooDetector = {
    version: "0.0.1",

    /**
     * @param {object} snapshot PageSnapshot
     * @returns {Promise<Array<{id: string, layer: number, weight: number, label: {en: string, id: string}, labelSimple: {en: string, id: string}, evidence?: string}>>}
     */
    analyzeLocal: async (snapshot) => {
        try {
            return [];
        } catch (error) {
            return [];
        }
    },
};
