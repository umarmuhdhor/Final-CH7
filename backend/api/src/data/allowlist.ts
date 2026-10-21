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

export function isAllowlisted(domain: string): boolean {
  const labels = domain.split(".");
  for (let i = 0; i < labels.length - 1; i++) {
    if (ALLOWLIST.has(labels.slice(i).join("."))) return true;
  }
  return false;
}
