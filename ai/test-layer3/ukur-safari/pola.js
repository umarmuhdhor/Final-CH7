// Three Telegram-sending patterns, kept in one place so Node (ukur-telegram.mjs)
// and the Safari measuring page (ukur-safari/ukur.js) search with the same regexes.
// Plain script, no module syntax: the server inlines it into the nonce'd page,
// Node imports it for its side effect on globalThis.
globalThis.ShooPola = (() => {
    const POLA = {
        host: /api\.telegram\.org/,
        // Plan pattern \d{8,10}:[A-Za-z0-9_-]{35}; the lookbehind only stops a match starting mid-number.
        token: /(?<!\d)\d{8,10}:[A-Za-z0-9_-]{35}/,
        method: /\bsend(?:Message|Document|Photo)\b/,
    };
    const KOLOM = ["host", "token", "method"];

    function scanTeks(teks) {
        return {
            host: POLA.host.test(teks),
            token: POLA.token.test(teks),
            method: POLA.method.test(teks),
        };
    }

    return { POLA, KOLOM, scanTeks };
})();
