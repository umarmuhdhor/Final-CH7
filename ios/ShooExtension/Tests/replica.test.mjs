// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";

await import("../Resources/replica.js");
import { assemble, buildReplica, processCss } from "../Resources/replica-build.js";
const { capture, shareableLink, CSP } = globalThis.ShooReplica;

// Minimal DOM stand-in: replica.js only reads nodeType, childNodes, data, localName, attributes,
// getAttribute, shadowRoot, sheet/textContent (styles), currentSrc (images) and getBoundingClientRect.
const text = (data) => ({ nodeType: 3, data });
function h(localName, attrs = {}, ...children) {
    const el = {
        nodeType: 1,
        localName,
        attributes: Object.entries(attrs).map(([name, value]) => ({ name, value })),
        childNodes: children.map((c) => (typeof c === "string" ? text(c) : c)),
        getAttribute: (key) => attrs[key] ?? null,
        getBoundingClientRect: () => ({ width: 300, height: 150 }),
    };
    return el;
}
const page = { url: "https://bca-verifikasi.site/login", viewport: { width: 390, height: 844 }, scrollY: 0, now: "2026-10-29T03:00:00.000Z" };
const docOf = (body, headChildren = []) => ({
    documentElement: h("html", { lang: "id" }, h("head", {}, ...headChildren), body),
    baseURI: "https://bca-verifikasi.site/login",
    doctype: {},
});
const run = (body, head) => capture(docOf(body, head), page);

test("scripts, handlers and javascript: URLs never reach the replica", () => {
    const { html } = run(
        h("body", { onload: "steal()", title: "javascript basics" },
            h("script", {}, "steal()"),
            h("noscript", {}, "enable js"),
            h("div", { onclick: "x()", "data-x": "javascript:alert(1)", "data-y": " java\tscript:alert(2)", title: "ok" }, "Halo"),
            h("svg", {}, h("script", {}, "svg()"), h("set", { attributeName: "href", to: "javascript:alert(1)" })),
        ),
    );
    assert.doesNotMatch(html, /steal|svg\(\)|onclick|onload|script:|enable js|alert/i);
    assert.match(html, /<body title="javascript basics">/); // plain text that merely starts with the word stays
    assert.match(html, /<div title="ok">Halo<\/div>/);
});

test("typed input never leaves the phone: no value, no textarea text, editable areas emptied (PRD §10)", () => {
    const { html } = run(
        h("body", {},
            h("form", { action: "https://evil.example/collect" },
                h("input", { type: "password", name: "pin", value: "123456" }),
                h("input", { name: "nik", value: "3201010101010001" }),
                h("input", { type: "hidden", name: "sid", value: "abc" }),
                h("input", { type: "submit", value: "Kirim" }),
                h("textarea", { name: "msg" }, "my address"),
            ),
            h("div", { contenteditable: "" }, "typed in a composer"),
            h("div", { contenteditable: "plaintext-only" }, "typed too"),
            h("div", { role: "textbox" }, "typed again"),
            h("div", { contenteditable: "false" }, "page text stays"),
        ),
    );
    assert.doesNotMatch(html, /123456|3201010101010001|abc|my address|typed/);
    assert.doesNotMatch(html, /evil\.example|action=/); // no form target either
    assert.match(html, /value="Kirim"/); // a button's label isn't typed input
    assert.match(html, /page text stays/);
});

test("form fields keep only their look: a page script can't smuggle typed text out through other attributes", () => {
    const { html } = run(
        h("body", {},
            h("input", { type: "text", name: "pin", class: "f", placeholder: "Masukkan PIN", "data-value": "123456", "aria-valuetext": "123456", title: "123456" }),
            h("select", { name: "bank", "data-picked": "mandiri" }, h("option", {}, "BCA")),
            h("textarea", { rows: "3", "data-draft": "my address" }),
            h("div", { role: "searchbox" }, "typed search"),
            h("div", { role: "Combobox" }, "typed combo"),
        ),
    );
    assert.doesNotMatch(html, /123456|mandiri|my address|typed/);
    assert.match(html, /<input type="text" name="pin" class="f" placeholder="Masukkan PIN">/);
    assert.match(html, /<select name="bank"><option>BCA<\/option><\/select>/);
});

test("designMode on: the whole page is editable, so the body stays empty", () => {
    const doc = { ...docOf(h("body", { class: "b" }, h("p", {}, "typed anywhere"))), designMode: "on" };
    const { html } = capture(doc, page);
    assert.doesNotMatch(html, /typed anywhere/);
    assert.match(html, /<body class="b"><\/body>/);
});

test("a $ pattern in the page URL can't splice the document into the meta tag", () => {
    const url = "https://bca-verifikasi.site/a$'b$&c$`d";
    const { html } = capture(docOf(h("body", {}, "Halo")), { ...page, url });
    const meta = JSON.parse(html.match(/name="shoo-replica" content="([^"]*)"/)[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&"));
    assert.equal(meta.url, url);
    assert.equal(html.match(/<body>/g).length, 1);
});

test("frames, media and embeds become grey boxes of the same size", () => {
    const { html } = run(h("body", {}, h("iframe", { src: "https://other.example/form" }), h("video", { src: "a.mp4" }), h("object", { data: "x.pdf" })));
    assert.doesNotMatch(html, /other\.example|a\.mp4|x\.pdf|<iframe|<video|<object/);
    assert.equal(html.match(/data-shoo-box=/g).length, 3);
    assert.match(html, /width:300px;height:150px/);
});

test("links keep their look but never open; the target is kept as origin + path for the Guardian", () => {
    const { html } = run(h("body", {}, h("a", { href: "/reset?token=secret#x", class: "btn", target: "_blank" }, "Reset"), h("a", { href: "javascript:void(0)" }, "JS")));
    assert.match(html, /<a href="#" data-shoo-href="https:\/\/bca-verifikasi\.site\/reset" class="btn">Reset<\/a>/);
    assert.match(html, /<a>JS<\/a>/);
    assert.doesNotMatch(html, /secret|_blank/);
    assert.equal(shareableLink("mailto:cs@bank.example?body=hi"), "mailto:cs@bank.example");
    assert.equal(shareableLink("ftp://x"), null);
});

test("head starts with charset, the CSP, the viewport and our metadata", () => {
    const { html } = capture(docOf(h("body", {}, "x"), [h("meta", { "http-equiv": "refresh", content: "0;url=https://x" }), h("base", { href: "https://x/" }), h("title", {}, "KlikBCA")]), {
        ...page,
        focus: { top: 300 },
        scrollY: 1000,
    });
    assert.ok(html.startsWith('<!doctype html><html lang="id"><head><meta charset="utf-8">'));
    assert.ok(html.includes(`<meta http-equiv="Content-Security-Policy" content="${CSP}">`));
    assert.match(html, /<meta name="viewport" content="width=390">/);
    assert.doesNotMatch(html, /refresh|<base/);
    assert.match(html, /<title>KlikBCA<\/title>/);
    const meta = JSON.parse(html.match(/name="shoo-replica" content="([^"]*)"/)[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&"));
    assert.deepEqual(meta, { v: 1, url: page.url, capturedAt: page.now, viewport: page.viewport, focusY: 1284, truncated: false });
});

test("text and attributes are escaped, so page content can't become markup", () => {
    const { html } = run(h("body", {}, h("p", { title: 'a"><script>x</script>' }, "<img src=x onerror=y> & co")));
    assert.match(html, /<p title="a&quot;&gt;&lt;script&gt;x&lt;\/script&gt;">&lt;img src=x onerror=y&gt; &amp; co<\/p>/);
});

test("our own UI (shoo-*) is left out", () => {
    const { html } = run(h("body", {}, h("shoo-live-score", {}, "41"), h("shoo-warning", {}, "Careful"), "page"));
    assert.doesNotMatch(html, /shoo-live|shoo-warning|Careful/);
});

test("open shadow roots become declarative shadow DOM", () => {
    const card = h("bank-card", {});
    card.shadowRoot = { nodeType: 11, childNodes: [h("b", {}, "Saldo")] };
    const { html } = run(h("body", {}, card));
    assert.match(html, /<bank-card><template shadowrootmode="open"><b>Saldo<\/b><\/template><\/bank-card>/);
});

test("images and stylesheets become tokens the background fills in", () => {
    const style = h("style", {});
    style.sheet = { cssRules: [{ cssText: ".logo { background: url(img/bg.png); }" }] };
    const crossOrigin = h("link", { rel: "stylesheet", href: "https://cdn.example/site.css", media: "screen" });
    crossOrigin.sheet = {
        get cssRules() {
            throw new Error("SecurityError");
        },
    };
    const img = h("img", { src: "logo.png", srcset: "logo@2x.png 2x", alt: "BCA" });
    img.currentSrc = "https://bca-verifikasi.site/logo@2x.png";
    const draft = run(h("body", { style: "background:url('/bg.jpg')" }, img, h("img", { src: "data:image/png;base64,AAAA" })), [style, crossOrigin, h("link", { rel: "icon", href: "/favicon.ico" })]);
    const n = draft.nonce;
    assert.deepEqual(draft.resources, ["https://bca-verifikasi.site/bg.jpg", "https://bca-verifikasi.site/logo@2x.png"]);
    assert.deepEqual(draft.sheets, [
        { text: ".logo { background: url(img/bg.png); }\n", base: "https://bca-verifikasi.site/login" },
        { href: "https://cdn.example/site.css", base: "https://cdn.example/site.css" },
    ]);
    assert.ok(draft.html.includes(`<style>${n}-s-0</style><style media="screen">${n}-s-1</style>`));
    assert.ok(draft.html.includes(`<body style="background:url(${n}-i-0)">`));
    assert.ok(draft.html.includes(`<img src="${n}-i-1" alt="BCA">`));
    assert.ok(draft.html.includes(`<img src="data:image/png;base64,AAAA">`));
    assert.doesNotMatch(draft.html, /favicon|srcset/);
});

test("a huge page is cut instead of serialized forever", () => {
    const rows = Array.from({ length: 25000 }, (_, i) => h("p", {}, `row ${i}`));
    const draft = run(h("body", {}, ...rows));
    assert.equal(draft.truncated, true);
    assert.ok(draft.html.endsWith("</body></html>"));
});

// ---- replica-build.js -------------------------------------------------------------------

const io = (files = {}, images = {}) => ({
    fetched: [],
    async fetchText(url) {
        this.fetched.push(url);
        if (!(url in files)) throw new Error("404");
        return files[url];
    },
    async fetchImage(url, max) {
        this.fetched.push(url);
        const data = images[url];
        return data && data.length * 0.75 <= max ? data : null;
    },
});

test("css: @import is inlined, url()s become image tokens, fonts and non-image data dropped, </style defused", async () => {
    const files = { "https://cdn.example/base.css": "body { color: red; }" };
    const seen = [];
    const css = await processCss(
        '@import url("base.css") screen; .a { background: url(../img/a.png) } @font-face { src: url(f.woff2) } .b { background: url("data:text/html,x") } .c::after { content: "</style><script>" }',
        "https://cdn.example/css/site.css",
        { fetchText: async (u) => files[u.replace("/css/", "/")] ?? files[u], imageToken: (u) => (seen.push(u), `T${seen.length - 1}`) },
    );
    assert.deepEqual(seen, ["https://cdn.example/img/a.png"]);
    assert.match(css, /background: url\(T0\)/);
    assert.match(css, /src: none/);
    assert.match(css, /\.b \{ background: none \}/);
    assert.doesNotMatch(css, /<\/style/i);
});

test("assemble fills stylesheets and images; a missing image becomes a grey placeholder", async () => {
    const style = h("style", {});
    style.sheet = { cssRules: [{ cssText: ".hero { background: url(hero.jpg) }" }] };
    const draft = run(h("body", {}, h("img", { src: "logo.png" }), h("img", { src: "gone.png" })), [style]);
    const files = io({}, { "https://bca-verifikasi.site/logo.png": "data:image/png;base64,TE9HTw==", "https://bca-verifikasi.site/hero.jpg": "data:image/jpeg;base64,SEVSTw==" });
    const html = await assemble(draft, files);
    assert.doesNotMatch(html, new RegExp(draft.nonce));
    assert.match(html, /<style>\.hero \{ background: url\(data:image\/jpeg;base64,SEVSTw==\) \}\s*<\/style>/);
    assert.match(html, /<img src="data:image\/png;base64,TE9HTw==">/);
    assert.match(html, /<img src="data:image\/svg\+xml;base64,[^"]+">/); // gone.png
    assert.ok(files.fetched.every((u) => u.startsWith("https://")));
});

test("too big → again without images, then without css, then no replica", async () => {
    const style = h("style", {});
    style.sheet = { cssRules: [{ cssText: ".x { color: red }" }] };
    const draft = run(h("body", {}, h("img", { src: "logo.png" }), "text"), [style]);
    const files = io({}, { "https://bca-verifikasi.site/logo.png": "data:image/png;base64,TE9HTw==" });
    const tries = [];
    const sizes = [500 * 1024, 500 * 1024, 10];
    const out = await buildReplica(draft, files, { compress: async (html) => (tries.push(html), "x".repeat(sizes[tries.length - 1])) });
    assert.equal(out, "x".repeat(10));
    assert.match(tries[0], /TE9HTw==/);
    assert.doesNotMatch(tries[1], /TE9HTw==/);
    assert.match(tries[1], /color: red/);
    assert.doesNotMatch(tries[2], /color: red/);
    assert.equal(await buildReplica(draft, files, { compress: async () => "x".repeat(500 * 1024) }), null);
    assert.equal(await buildReplica(null, files), null);
});

test("gzip output round-trips to the same document", async () => {
    const draft = run(h("body", {}, h("h1", {}, "Verifikasi akun Anda")));
    const packed = await buildReplica(draft, io());
    const bytes = Uint8Array.from(atob(packed), (c) => c.charCodeAt(0));
    const html = await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"))).text();
    assert.match(html, /<h1>Verifikasi akun Anda<\/h1>/);
    assert.ok(html.startsWith("<!doctype html>"));
});
