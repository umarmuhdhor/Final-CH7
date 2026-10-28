// Owner: lead. Chrome only. The shared scripts (copied from the Safari extension) call `browser.*`;
// Chrome MV3 has the same APIs as `chrome.*`, promise-based when no callback is passed.
// Loaded first: in manifest.json content_scripts and in blocked.html. background.js uses messaging.js instead.

globalThis.browser ??= globalThis.chrome;
