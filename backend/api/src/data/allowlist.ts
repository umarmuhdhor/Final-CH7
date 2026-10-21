/**
 * Domains that never enter the global blocklist queue (R2 §5 butir 1, SECURITY T5): official
 * Indonesian banks, e-wallets, public services and very popular sites, plus government and
 * education suffixes. A family's own not_safe verdict still applies to that family.
 * Lowercase registrable domains; a subdomain of an entry also matches.
 */
const ALLOWLIST = new Set([
  // Government, education, military (whole suffix)
  "go.id", "ac.id", "sch.id", "mil.id", "desa.id",
  // Banks
  "bca.co.id", "klikbca.com", "bri.co.id", "bankmandiri.co.id", "livin.id", "bni.co.id", "btn.co.id",
  "bankbsi.co.id", "cimbniaga.co.id", "danamon.co.id", "permatabank.com", "ocbc.id", "maybank.co.id",
  "panin.co.id", "bankmega.com", "btpn.com", "jenius.com", "seabank.co.id", "bankjago.com",
  "blubybcadigital.id", "bi.go.id", "ojk.go.id", "lps.go.id",
  // E-wallets, payments
  "dana.id", "ovo.id", "gopay.co.id", "linkaja.id", "shopeepay.co.id", "doku.com", "midtrans.com", "xendit.co",
  // Marketplaces, transport, travel, telco, utilities, post
  "tokopedia.com", "shopee.co.id", "bukalapak.com", "lazada.co.id", "blibli.com", "gojek.com", "grab.com",
  "traveloka.com", "tiket.com", "kai.id", "telkomsel.com", "indihome.co.id", "telkom.co.id", "xl.co.id",
  "indosatooredoo.com", "pln.co.id", "posindonesia.co.id", "pertamina.com", "jne.co.id", "jntexpress.id",
  // Global popular
  "google.com", "google.co.id", "youtube.com", "facebook.com", "instagram.com", "whatsapp.com", "tiktok.com",
  "x.com", "twitter.com", "apple.com", "icloud.com", "microsoft.com", "live.com", "outlook.com", "yahoo.com",
  "wikipedia.org", "linkedin.com", "netflix.com", "spotify.com", "amazon.com", "github.com", "zoom.us",
  // Indonesian news
  "detik.com", "kompas.com", "tribunnews.com", "liputan6.com", "cnnindonesia.com", "tempo.co", "kumparan.com",
]);

/**
 * Public suffixes and shared hosting roots (exact match only): approving one would block a whole
 * TLD or every site on that host. Their subdomains are separate sites and may be queued.
 */
const SHARED_ROOTS = new Set([
  "co.id", "or.id", "web.id", "my.id", "biz.id", "net.id", "ponpes.id", "co.uk", "com.au", "com.sg", "com.my",
  "github.io", "gitlab.io", "vercel.app", "netlify.app", "pages.dev", "workers.dev", "web.app", "firebaseapp.com",
  "herokuapp.com", "onrender.com", "blogspot.com", "wordpress.com", "wixsite.com", "weebly.com", "carrd.co",
  "000webhostapp.com", "glitch.me", "replit.app", "framer.website", "notion.site", "linktr.ee", "s.id", "bit.ly",
]);

/** True when a not_safe verdict on this domain must never enter the global review queue. */
export function neverQueue(domain: string): boolean {
  return SHARED_ROOTS.has(domain) || isAllowlisted(domain);
}

export function isAllowlisted(domain: string): boolean {
  const labels = domain.split(".");
  for (let i = 0; i < labels.length - 1; i++) {
    if (ALLOWLIST.has(labels.slice(i).join("."))) return true;
  }
  return false;
}
