// Domains that must NEVER be published, even if a feed lists them (poisoning, or a legit site that was hacked).
// A wrong block of a bank or a big site is worse than a missed scam, so this list errs on the safe side.
import brands from "../../../detector/data/brands.json" with { type: "json" };

/** Official domains of every brand in detector/data/brands.json (shared with layers 2 and 3). */
export const OFFICIAL = new Set(brands.brands.flatMap((b) => b.domains.map((d) => d.toLowerCase())));

/** Popular sites (global + Indonesia), registrable domains. Starting list; extend it freely. */
export const POPULAR = new Set([
    "google.com", "youtube.com", "facebook.com", "instagram.com", "whatsapp.com", "twitter.com", "x.com", "linkedin.com",
    "microsoft.com", "live.com", "outlook.com", "office.com", "apple.com", "icloud.com", "amazon.com", "netflix.com",
    "wikipedia.org", "yahoo.com", "bing.com", "duckduckgo.com", "reddit.com", "pinterest.com", "tiktok.com", "twitch.tv",
    "zoom.us", "dropbox.com", "adobe.com", "paypal.com", "ebay.com", "spotify.com", "telegram.org", "discord.com",
    "github.com", "gitlab.com", "stackoverflow.com", "cloudflare.com", "openai.com", "anthropic.com", "mozilla.org", "medium.com",
    "bbc.com", "cnn.com", "nytimes.com", "theguardian.com", "tripadvisor.com", "booking.com", "airbnb.com", "uber.com",
    "grab.com", "gojek.com", "tokopedia.com", "shopee.co.id", "lazada.co.id", "bukalapak.com", "blibli.com", "traveloka.com",
    "tiket.com", "olx.co.id", "jd.id", "zalora.co.id", "sociolla.com", "bri.co.id", "bni.co.id", "bca.co.id",
    "mandiri.co.id", "cimbniaga.co.id", "danamon.co.id", "permatabank.com", "btn.co.id", "ocbc.id", "uob.co.id", "jenius.com",
    "gopay.co.id", "ovo.id", "dana.id", "linkaja.id", "shopeepay.co.id", "kompas.com", "detik.com", "tribunnews.com",
    "liputan6.com", "cnnindonesia.com", "tempo.co", "kumparan.com", "idntimes.com", "antaranews.com", "go.id", "kominfo.go.id",
    "bpjs-kesehatan.go.id", "bpjsketenagakerjaan.go.id", "pajak.go.id", "kemenkeu.go.id", "kemdikbud.go.id", "kemkes.go.id",
    "kemensos.go.id", "polri.go.id", "indonesia.go.id", "telkomsel.com", "indosatooredoo.com", "xl.co.id", "smartfren.com",
    "pln.co.id", "pertamina.com", "jne.co.id", "jet.co.id", "sicepat.com", "pos.co.id", "anteraja.id", "tiki.id",
    "googleapis.com", "gstatic.com", "googleusercontent.com", "amazonaws.com", "ruangguru.com", "traveloka.co.id", "kaskus.co.id", "gramedia.com", "halodoc.com", "alodokter.com", "tokopedia.link",
]);

/**
 * Platforms where anyone can host a page or a subdomain. The platform itself is never published.
 * Customer sites on them (`bad.github.io`) are separate registrable domains under the Public Suffix List
 * and may be published one by one. Apex names that are NOT on the Public Suffix List belong here too.
 */
export const SHARED_HOSTS = new Set([
    "wordpress.com", "blogspot.com", "blogger.com", "wixsite.com", "wix.com", "weebly.com", "squarespace.com", "webflow.io",
    "github.io", "githubusercontent.com", "gitlab.io", "vercel.app", "netlify.app", "pages.dev", "workers.dev", "web.app",
    "firebaseapp.com", "herokuapp.com", "glitch.me", "repl.co", "onrender.com", "fly.dev", "000webhostapp.com", "infinityfreeapp.com",
    "sites.google.com", "docs.google.com", "drive.google.com", "forms.gle", "bit.ly", "tinyurl.com", "t.co", "goo.gl",
    "ngrok.io", "ngrok-free.app", "trycloudflare.com", "azurewebsites.net", "amazonaws.com", "cloudfront.net", "s3.amazonaws.com",
    "sharepoint.com", "googleapis.com", "gstatic.com", "googleusercontent.com", "linktr.ee", "youtu.be", "t.me", "wa.me", "fb.me",
    "fbcdn.net", "akamaihd.net", "fastly.net", "mzstatic.com", "tumblr.com", "mediafire.com", "mega.nz", "canva.site", "godaddysites.com",
    "rebrand.ly", "is.gd", "cutt.ly", "linkedin.cn", "office365.com", "microsoftonline.com", "windows.net", "live.net", "onedrive.com",
    "notion.site", "carrd.co", "typedream.app", "framer.app", "webwave.me", "mystrikingly.com", "yolasite.com", "jimdofree.com",
]);
