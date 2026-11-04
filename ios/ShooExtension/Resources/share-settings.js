// Owner: lead. What a Protected user agreed to share with the guardian (PF-01, #183). ES module, used by background.js.
// `blocked` always goes out: the block screen only reopens on the guardian's verdict, and the guardian
// can't decide on a scan they never got. Only `warning` scans can stay on the phone.

/**
 * @param {string} status  ScanResult status
 * @param {{autoSend?: boolean, shareWarnings?: boolean}} session  getSession reply. Missing = on (older app).
 * @returns {boolean} true when POST /scans may run
 */
export function mayReport(status, session) {
    if (status === "blocked") return true;
    return session?.autoSend !== false && session?.shareWarnings !== false;
}
