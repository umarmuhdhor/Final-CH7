// Android (Team App). The add-on's settings page in Firefox for Android: link it to the Shoo app with the
// one-time code the app shows (Profile → Firefox → Show code). The app answers on 127.0.0.1 only while that
// code is on screen (AddonBridge.kt). Never shows or logs the token.

import { SESSION_KEY, validateAppSession } from "./native-bridge.js";

const BRIDGE_URL = "http://127.0.0.1:47613/pair";

const TEXT = {
    id: {
        linked: "Terhubung dengan aplikasi Shoo",
        detail: (s) => `${s.name || "—"} · ${s.mode === "guardian" ? "Guardian" : "Dilindungi"}${s.guardianName ? ` · Guardian: ${s.guardianName}` : ""}`,
        unlink: "Putuskan",
        unlinked: "Belum terhubung",
        steps: ["Buka aplikasi Shoo di HP ini.", "Profil → Perlindungan di Firefox → Tampilkan kode.", "Masukkan kode 6 digit di bawah."],
        codeLabel: "Kode dari aplikasi Shoo",
        connect: "Hubungkan",
        connecting: "Menghubungkan…",
        done: "Selesai. Shoo sekarang memeriksa halaman di Firefox.",
        unlinkedDone: "Add-on tidak lagi terhubung. Halaman tetap diperiksa di HP, tapi tidak dikirim ke Guardian.",
        noApp: "Aplikasi Shoo tidak menjawab. Buka aplikasi, tekan Tampilkan kode, lalu coba lagi.",
        wrong: "Kode salah. Periksa kode di aplikasi Shoo.",
        locked: "Terlalu banyak kode salah. Tampilkan kode baru di aplikasi.",
        expired: "Kode berakhir. Tampilkan kode baru di aplikasi.",
        notOnboarded: "Selesaikan pendaftaran di aplikasi Shoo dulu.",
        bad: "Jawaban aplikasi tidak bisa dipakai. Perbarui aplikasi Shoo.",
    },
    en: {
        linked: "Connected to the Shoo app",
        detail: (s) => `${s.name || "—"} · ${s.mode === "guardian" ? "Guardian" : "Protected"}${s.guardianName ? ` · Guardian: ${s.guardianName}` : ""}`,
        unlink: "Disconnect",
        unlinked: "Not connected",
        steps: ["Open the Shoo app on this phone.", "Profile → Protection in Firefox → Show code.", "Enter the 6-digit code below."],
        codeLabel: "Code from the Shoo app",
        connect: "Connect",
        connecting: "Connecting…",
        done: "Done. Shoo now checks pages in Firefox.",
        unlinkedDone: "The add-on is disconnected. Pages are still checked on the phone, but nothing is sent to a Guardian.",
        noApp: "The Shoo app didn't answer. Open the app, tap Show code, then try again.",
        wrong: "Wrong code. Check the code in the Shoo app.",
        locked: "Too many wrong codes. Show a new code in the app.",
        expired: "The code expired. Show a new code in the app.",
        notOnboarded: "Finish setup in the Shoo app first.",
        bad: "The app's answer can't be used. Update the Shoo app.",
    },
};
// Like the extension: English only on an English phone, else Bahasa Indonesia.
const t = (navigator.language || "").toLowerCase().startsWith("en") ? TEXT.en : TEXT.id;
const $ = (id) => document.getElementById(id);

function say(text, isError = false) {
    $("message").textContent = text;
    $("message").className = isError ? "error" : "";
}

async function render() {
    const session = validateAppSession((await browser.storage.local.get(SESSION_KEY))[SESSION_KEY]);
    $("linked").hidden = !session;
    $("unlinked").hidden = Boolean(session);
    if (session) $("linked-detail").textContent = t.detail(session);
}

async function pair(code) {
    let response;
    try {
        response = await fetch(BRIDGE_URL, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ code }),
            cache: "no-store",
        });
    } catch {
        return say(t.noApp, true);
    }
    const reply = await response.json().catch(() => null);
    if (!response.ok || !reply?.ok) {
        const error = reply?.error;
        const text = { code_invalid: t.wrong, locked: t.locked, expired: t.expired, not_onboarded: t.notOnboarded }[error] ?? t.noApp;
        return say(text, true);
    }
    const session = validateAppSession(reply.session);
    if (!session) return say(t.bad, true);
    const now = Date.now();
    await browser.storage.local.set({ [SESSION_KEY]: { ...session, linkedAt: now, refreshedAt: now } });
    say(t.done);
    await render();
}

$("linked-title").textContent = t.linked;
$("unlink").textContent = t.unlink;
$("unlinked-title").textContent = t.unlinked;
$("code-label").textContent = t.codeLabel;
$("connect").textContent = t.connect;
for (const step of t.steps) $("steps").append(Object.assign(document.createElement("li"), { textContent: step }));

$("code").addEventListener("input", (event) => {
    event.target.value = event.target.value.replace(/\D/g, "").slice(0, 6);
});
$("pair").addEventListener("submit", async (event) => {
    event.preventDefault();
    const code = $("code").value;
    if (!/^\d{6}$/.test(code)) return;
    $("connect").disabled = true;
    $("connect").textContent = t.connecting;
    say("");
    await pair(code);
    $("connect").disabled = false;
    $("connect").textContent = t.connect;
});
$("unlink").addEventListener("click", async () => {
    await browser.storage.local.remove(SESSION_KEY);
    say(t.unlinkedDone);
    await render();
});

render();
