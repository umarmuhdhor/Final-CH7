# webRequest probe on a real iPhone (26 Oct 2026)

**Question:** can a Safari Web Extension on iOS read response headers, status codes and redirect hops via `browser.webRequest`?

**Answer: yes, on iOS 27.0.1.** Apple's "Assessing your Safari web extension's browser compatibility" page still says "webRequest: Not supported in iOS … opt_extraInfoSpec not supported for any of the events"; that page is out of date. MDN browser-compat-data (iOS 18, full `extraInfoSpec` from 18.4) matches what we saw.

## Setup
- Device: iPhone 17 "af", iOS 27.0.1, connected to Mac, Web Inspector via Develop → af → Shoo background.
- Build: local branch `test/webrequest-probe` (not pushed). Manifest `permissions` + `"webRequest"`; temporary `ios/ShooExtension/Resources/webrequest-probe.js` imported from `background.js`. Listeners on all 8 events, filter `{ urls: ["*://*/*"] }`, `extraInfoSpec: ["responseHeaders"]` on onHeadersReceived / onBeforeRedirect / onResponseStarted / onCompleted.
- The probe logs host+path, status, header **names** only (no values, no query, no bodies).

## Results
| Check | Result |
|---|---|
| `typeof browser.webRequest` | `"object"` |
| All 8 events have `addListener` | yes |
| Listener registration with `responseHeaders` | `ok` for all 8 (no fallback needed) |
| Status codes | 200, 302, 404 seen |
| Response header names | e.g. `location, content-type, date, content-length, access-control-allow-origin, server`; custom `x-shoo-test` from `httpbin.org/response-headers?X-Shoo-Test=1` |
| Redirect hops (`https://httpbin.org/redirect/3`) | 3 × `onBeforeRedirect` 302: `→ relative-redirect/2 → relative-redirect/1 → get`, then 200 |
| Subresources | `favicon.ico` seen as `type: "image"` |

## Real case: helpnets.info (Microsoft login clone)
Opened `https://helpnets.info/0442827f6o7cfb43933ba59e2881cc906b7c.html/` in Safari on the phone. What `webRequest` saw:

| Request | Type | Status | Redirect | Response header names |
|---|---|---|---|---|
| `helpnets.info/0442827f6o7cfb43933ba59e2881cc906b7c.html/` | `main_frame` | 200 | none | `content-type, content-encoding, report-to, date, x-amz-server-side-encryption, nel, server, cf-cache-status, x-amz-version-id, x-amz-expiration, cf-ray` (+ `set-cookie` at `onCompleted`) |
| `lp.cybeready.net/beefree_images/cybeready_images/microsoft_favicon_a.ico` | `image` | 200 | none | (not logged) |

Header values from the earlier curl of the same URL (header names match): `server: cloudflare`, `x-amz-expiration: expiry-date="Mon, 23 Nov 2026 00:00:00 GMT", rule-id="DeleteAfter30Days"`.

What this gives a detector:
- **No redirect, status 200**: nothing from redirect-chain or status features.
- **`x-amz-*` behind `server: cloudflare`**: the page is a file in an S3 bucket fronted by Cloudflare; `x-amz-expiration … DeleteAfter30Days` means it deletes itself after 30 days. Weak alone (legit sites use S3 too), but "short-lived bucket page asking for a password" is a reasonable extra signal.
- **Favicon `microsoft_favicon_a.ico` loaded from `lp.cybeready.net`**: a brand-named asset from a domain that is neither the page's nor Microsoft's. This is the useful network signal here; it confirms the brand-vs-domain mismatch the DOM already shows.
- The three SVGs in the page (`microsoft_logo.svg`, `microsoft_arrow_left.svg`, `microsoft_signinoptions.svg`, all `lp.cybeready.net`) did not appear in the log. Cause not checked (memory cache, or the 40-row log window).
- `set-cookie` appears in the header names at `onCompleted`, although Apple's page says "webRequest.HTTPHeaders cookies not supported".

Proposed network signals and the helpnets score walk (`brand_asset_offsite` +25, `no_brand_origin` +10, `ephemeral_hosting` +10 → 60 with the existing `asks_password` 15; +30 layer 4 with a brand hint → 90 blocked) are in issue umarmuhdhor/Final-CH7#139, section "Cara menilai scam dari data network". Weights are untested proposals.

## Quirks
- After each redirect, Safari keeps the **original** URL (`httpbin.org/redirect/3`) in `details.url` for the next hops; Chrome reports the new URL. Follow the chain via `redirectUrl` of `onBeforeRedirect`.
- `ip` was `null` on every event.
- Observe only. Blocking (`webRequestBlocking`) was not tested; Apple lists it as not supported.

## Not yet tested
- iOS 18.x / 26.x devices (Shoo supports iOS 17+; MDN says partial before 18.4, none before 18).
- Whether adding `webRequest` changes the permission prompt / App Review / privacy label.
- Background lifetime: do listeners keep firing after the non-persistent background has been idle?
- `helpnets.info` headers seen from the phone.
