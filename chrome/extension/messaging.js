// Owner: lead. Chrome only. ES module, used by background.js.
// Safari's runtime.onMessage takes a listener that returns a Promise; Chrome ignores the returned Promise
// and closes the channel. listen() keeps one promise-returning handler and answers through sendResponse.

/**
 * @param {{ addListener(fn): void }} onMessage  chrome.runtime.onMessage
 * @param {(message, sender) => Promise<object>|object} handler  never sees sendResponse
 */
export function listen(onMessage, handler) {
    onMessage.addListener((message, sender, sendResponse) => {
        Promise.resolve()
            .then(() => handler(message, sender))
            .then(
                (reply) => sendResponse(reply),
                (error) => {
                    console.warn("[Shoo] message failed", message?.type, error);
                    sendResponse({ ok: false, error: "internal" });
                },
            );
        return true; // keeps the channel open until sendResponse
    });
}
