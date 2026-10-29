// Layer 3 form signals: asks_pin, asks_otp, asks_password, asks_card, asks_cvv, asks_ktp, asks_selfie_ktp.
// Every signal: positive ID, positive EN, negative. Anti false positive tests come first in importance.
import test from "node:test";
import assert from "node:assert/strict";
import { analyzeSnapshot } from "../src/analyze.js";
import { WEIGHTS } from "../src/layer3/signals.js";
import { field, page, ids, BRANDS, SCAM_URL } from "./helpers.mjs";

const scam = (fields) => analyzeSnapshot(page(SCAM_URL, fields));
const only = (fields) => ids(scam(fields));
const OFFICIAL = BRANDS.brands.flatMap((b) => b.domains);

function expectSignal(id, fields, why) {
    assert.deepEqual(only(fields), [id], why);
}
function expectNone(fields, why) {
    assert.deepEqual(only(fields), [], why);
}

// ---- f. asks_pin -----------------------------------------------------------
test("f. asks_pin: Indonesian wording", () => {
    expectSignal("asks_pin", [field({ type: "password", name: "pin" })], "name=pin");
    expectSignal("asks_pin", [field({ label: "Masukkan PIN m-banking Anda" })], "label");
    expectSignal("asks_pin", [field({ placeholder: "Kode sandi" })], "placeholder kode sandi");
    expectSignal("asks_pin", [field({ label: "Kode akses" })], "label kode akses");
    expectSignal("asks_pin", [field({ id: "kode_akses_6_digit" })], "id with underscores");
});
test("f. asks_pin: English wording and name styles", () => {
    expectSignal("asks_pin", [field({ label: "Enter your passcode" })], "passcode label");
    expectSignal("asks_pin", [field({ id: "passcode" })], "id=passcode");
    expectSignal("asks_pin", [field({ name: "user-pin" })], "dash");
    expectSignal("asks_pin", [field({ name: "userPin" })], "camelCase");
    expectSignal("asks_pin", [field({ name: "PIN6" })], "digit suffix");
    expectSignal("asks_pin", [field({ label: "Pass code" })], "two words");
});
test("f. asks_pin: a password-type field named pin is a PIN, not also a password", () => {
    expectSignal("asks_pin", [field({ type: "password", name: "pin" })]);
});
test("f. asks_pin: negatives", () => {
    expectNone([field({ name: "pinjaman" })], "pinjaman (loan)");
    expectNone([field({ label: "Shipping address" })], "shipping");
    expectNone([field({ name: "mapping", id: "spinner", label: "Opinion, Pinterest, pinned" })], "words that contain pin");
    expectNone([field({ label: "Kode pos", autocomplete: "postal-code" })], "postal code");
    expectNone([field({ label: "PIN code", autocomplete: "postal-code" })], "India-style PIN code that is a postal code");
});

// ---- g. asks_otp -----------------------------------------------------------
test("g. asks_otp: Indonesian and English", () => {
    expectSignal("asks_otp", [field({ name: "otp" })], "name=otp");
    expectSignal("asks_otp", [field({ label: "Kode verifikasi" })], "kode verifikasi");
    expectSignal("asks_otp", [field({ placeholder: "Masukkan kode OTP dari SMS" })], "kode OTP");
    expectSignal("asks_otp", [field({ label: "Verification code" })], "verification code");
    expectSignal("asks_otp", [field({ label: "One-time password" })], "one-time");
    expectSignal("asks_otp", [field({ label: "One time code" })], "one time");
    expectSignal("asks_otp", [field({ autocomplete: "one-time-code" })], "autocomplete one-time-code");
    expectSignal("asks_otp", [field({ name: "sms_otp_1" })], "otp inside a name");
});
test("g. asks_otp: negatives", () => {
    expectNone([field({ name: "hotp", label: "Footprint, photo, hotpot" })], "otp inside other words");
    expectNone([field({ label: "Kode promo" }), field({ label: "Kode voucher" }), field({ label: "Kode pos" })], "other kinds of codes");
    expectNone([field({ label: "Verification status" })], "verification alone");
});

// ---- h. asks_password ------------------------------------------------------
test("h. asks_password: type=password on a non-official domain", () => {
    expectSignal("asks_password", [field({ type: "password", name: "p" })]);
    expectSignal("asks_password", [field({ type: "password", label: "Kata sandi" })]);
    expectSignal("asks_password", [field({ type: "PASSWORD", name: "pw" })], "type is case-insensitive");
});
test("h. asks_password: other types and words do not count", () => {
    expectNone([field({ type: "text", name: "email", label: "Email" })]);
    expectNone([field({ type: "text", label: "Password hint" })], "needs type=password");
});

// ---- i. asks_card / asks_cvv -----------------------------------------------
test("i. asks_card: Indonesian and English", () => {
    expectSignal("asks_card", [field({ label: "Nomor kartu kredit" })]);
    expectSignal("asks_card", [field({ placeholder: "No. kartu debit" })]);
    expectSignal("asks_card", [field({ label: "Card number" })]);
    expectSignal("asks_card", [field({ name: "cardnumber" })]);
    expectSignal("asks_card", [field({ name: "card_number" })]);
    expectSignal("asks_card", [field({ autocomplete: "cc-number" })]);
});
test("i. asks_card: negatives", () => {
    expectNone([field({ label: "Nomor kartu keluarga" })], "family card");
    expectNone([field({ label: "Nomor kartu member" })], "member card");
    expectNone([field({ autocomplete: "cc-name" }), field({ autocomplete: "cc-exp" }), field({ label: "Card holder name" })], "other card fields");
});
test("i. asks_cvv: Indonesian and English", () => {
    expectSignal("asks_cvv", [field({ name: "cvv" })]);
    expectSignal("asks_cvv", [field({ name: "cvc2" })]);
    expectSignal("asks_cvv", [field({ label: "CVC" })]);
    expectSignal("asks_cvv", [field({ label: "Kode keamanan kartu" })]);
    expectSignal("asks_cvv", [field({ label: "Card security code" })]);
    expectSignal("asks_cvv", [field({ autocomplete: "cc-csc" })]);
});
test("i. asks_cvv: negatives", () => {
    expectNone([field({ label: "Security question" }), field({ label: "Keamanan akun" }), field({ label: "Kode pos" })]);
});
test("i. a card form (number + expiry + CVV) is ONE card request: asks_card only (review #60)", () => {
    assert.deepEqual(only([field({ name: "cardnumber" }), field({ name: "exp" }), field({ name: "cvv" })]), ["asks_card"]);
    assert.deepEqual(only([field({ name: "cvv" })]), ["asks_cvv"], "a CVV with no card number still counts");
});

// ---- j. asks_ktp / asks_selfie_ktp ----------------------------------------
test("j. asks_ktp: Indonesian and English", () => {
    expectSignal("asks_ktp", [field({ name: "nik" })]);
    expectSignal("asks_ktp", [field({ label: "Nomor KTP" })]);
    expectSignal("asks_ktp", [field({ label: "Nomor Induk Kependudukan" })]);
    expectSignal("asks_ktp", [field({ placeholder: "16 digit NIK" })]);
    expectSignal("asks_ktp", [field({ label: "National ID number" })]);
    expectSignal("asks_ktp", [field({ type: "file", label: "Upload e-KTP" })]);
});
test("j. asks_ktp: negatives", () => {
    expectNone([field({ label: "Nikmati diskon" }), field({ name: "nikon" }), field({ label: "Nama lengkap" }), field({ label: "Order ID" })]);
});
test("j. asks_selfie_ktp: selfie holding the ID", () => {
    expectSignal("asks_selfie_ktp", [field({ type: "file", label: "Foto selfie sambil memegang KTP" })], "ID");
    expectSignal("asks_selfie_ktp", [field({ type: "file", label: "Upload a selfie holding your ID card" })], "EN");
    expectSignal("asks_selfie_ktp", [field({ type: "file", name: "selfie_ktp" })], "name");
});
test("j. asks_selfie_ktp: selfie field next to a KTP field in the same form", () => {
    const got = only([field({ type: "file", label: "Selfie" }), field({ name: "nik" })]);
    assert.deepEqual(got.sort(), ["asks_ktp", "asks_selfie_ktp"]);
});
test("j. asks_selfie_ktp: negatives (selfie alone, KTP alone)", () => {
    expectNone([field({ type: "file", label: "Take a selfie for your profile" })], "profile selfie");
    expectNone([field({ type: "file", label: "Foto profil" })]);
    expectSignal("asks_ktp", [field({ type: "file", label: "Upload KTP" })], "KTP upload alone is asks_ktp only");
});
test("j. asks_selfie_ktp: front-camera upload (capture=user) in a form that asks for the KTP (C8)", () => {
    const camera = (over = {}) => field({ type: "file", name: "foto", capture: "user", ...over });
    assert.deepEqual(only([camera(), field({ name: "nik" })]).sort(), ["asks_ktp", "asks_selfie_ktp"], "no selfie word needed");
    assert.deepEqual(only([camera({ accept: "image/*" }), field({ label: "Nomor KTP" })]).sort(), ["asks_ktp", "asks_selfie_ktp"]);
    assert.deepEqual(only([camera({ accept: ".jpg,.png" }), field({ name: "nik" })]).sort(), ["asks_ktp", "asks_selfie_ktp"], "image extensions");
    assert.deepEqual(only([camera({ capture: " USER " }), field({ name: "nik" })]).sort(), ["asks_ktp", "asks_selfie_ktp"], "case and spaces");
    expectSignal("asks_selfie_ktp", [camera({ label: "Foto KTP" })], "front camera on the KTP field itself");
    assert.deepEqual(only([camera({ label: "Foto profil" }), field({ name: "nik" })]).sort(), ["asks_ktp", "asks_selfie_ktp"], "a profile word in a label does not switch the camera off");
});
test("j. capture=user negatives: no KTP, back camera, accept alone, non-photo accept", () => {
    expectNone([field({ type: "file", name: "foto", capture: "user", accept: "image/*" })], "front camera without KTP");
    expectSignal("asks_ktp", [field({ type: "file", name: "foto", capture: "environment" }), field({ name: "nik" })], "back camera = photo of the card");
    expectSignal("asks_ktp", [field({ type: "file", name: "foto", capture: "" }), field({ name: "nik" })], "bare capture attribute");
    expectSignal("asks_ktp", [field({ type: "file", label: "Upload foto", accept: "image/*" }), field({ name: "nik" })], "accept=image/* alone is not a selfie");
    expectSignal("asks_ktp", [field({ type: "file", name: "doc", capture: "user", accept: "application/pdf" }), field({ name: "nik" })], "not a photo");
    expectSignal("asks_ktp", [field({ type: "text", name: "foto", capture: "user" }), field({ name: "nik" })], "capture only means something on file inputs");
});
test("j. selfie in one form and KTP in another form are not paired", () => {
    const snap = page(SCAM_URL, [], { forms: [{ action: null, fields: [field({ type: "file", label: "Selfie" })] }, { action: null, fields: [field({ name: "nik" })] }] });
    assert.deepEqual(ids(analyzeSnapshot(snap)), ["asks_ktp"]);
});

// ---- k. official domains ---------------------------------------------------
const SENSITIVE = () => [field({ type: "password", name: "pwd" }), field({ name: "otp" }), field({ name: "pin" }), field({ name: "cardnumber" }), field({ name: "cvv" }), field({ name: "nik" }), field({ type: "file", label: "Selfie KTP" })];
test("k. official domains from brands.json give no signals, even with every sensitive field", () => {
    assert.ok(OFFICIAL.length > 10);
    for (const domain of OFFICIAL) {
        for (const host of [domain, `www.${domain}`, `ibank.m.${domain}`]) {
            assert.deepEqual(analyzeSnapshot(page(`https://${host}/login`, SENSITIVE())), [], host);
        }
    }
});
test("k. lookalikes of official domains are NOT official", () => {
    for (const host of ["bca.co.id.evil.example", "notbca.co.id", "bca.co.id-login.example", "klikbca.com.xyz", "xbca.co.id", "evil.example/bca.co.id"]) {
        const url = host.includes("/") ? `https://${host}` : `https://${host}/`;
        assert.ok(analyzeSnapshot(page(url, SENSITIVE())).length > 0, host);
    }
});
test("k. official check uses the URL host, not a claimed snapshot.domain", () => {
    const snap = page(SCAM_URL, SENSITIVE(), { domain: "bca.co.id" });
    assert.ok(analyzeSnapshot(snap).length > 0);
});

// ---- l. ordinary shops -----------------------------------------------------
test("l. checkout / contact forms of an ordinary shop give no signal", () => {
    const checkout = [
        field({ name: "fullname", label: "Nama lengkap", autocomplete: "name" }),
        field({ name: "email", type: "email", label: "Email", autocomplete: "email" }),
        field({ name: "phone", type: "tel", label: "Nomor telepon / No. HP", autocomplete: "tel" }),
        field({ name: "address", label: "Alamat lengkap", autocomplete: "street-address" }),
        field({ name: "city", label: "Kota" }),
        field({ name: "zip", label: "Kode pos", autocomplete: "postal-code" }),
        field({ name: "note", label: "Catatan untuk penjual" }),
        field({ name: "shipping", label: "Shipping method" }),
        field({ name: "voucher", label: "Kode voucher" }),
        field({ type: "checkbox", name: "pin_address", label: "Pin address on map" }),
    ];
    expectNone(checkout);
});
test("l. a plain shop login gives only asks_password, below the first popup threshold", () => {
    const out = scam([field({ type: "email", name: "email" }), field({ type: "password", name: "password" })]);
    assert.deepEqual(ids(out), ["asks_password"]);
    assert.ok(out[0].weight < 30);
});
test("l. hidden and button fields never count", () => {
    expectNone([field({ type: "hidden", name: "pin" }), field({ type: "submit", name: "otp", label: "Kirim OTP" }), field({ type: "button", label: "Masukkan PIN" }), field({ type: "checkbox", label: "Simpan kartu" })]);
});

// ---- n. signal content -----------------------------------------------------
const JARGON = ["otp", "cvv", "cvc", "nik", "kyc", "html", "field", "form", "input", "layer", "weight"];
test("n. every signal: layer 3, R1 weight, bilingual labels, plain labelSimple, evidence is the field name/id", () => {
    const expected = { asks_pin: "pin", asks_otp: "otp", asks_password: "pwd", asks_card: "cardnumber", asks_cvv: "cvv", asks_ktp: "nik", asks_selfie_ktp: "selfie_ktp" };
    const fields = [field({ name: "pin" }), field({ name: "otp" }), field({ type: "password", name: "pwd" }), field({ name: "cardnumber" }), field({ name: "nik" }), field({ type: "file", id: "selfie_ktp" })];
    const out = [...scam(fields), ...scam([field({ name: "cvv" })])]; // CVV next to a card number folds into asks_card
    assert.deepEqual(ids(out).sort(), Object.keys(expected).sort());
    for (const s of out) {
        assert.equal(s.layer, 3);
        assert.equal(s.weight, WEIGHTS[s.id], `${s.id} weight`);
        assert.deepEqual(Object.keys(s.label).sort(), ["en", "id"]);
        assert.deepEqual(Object.keys(s.labelSimple).sort(), ["en", "id"]);
        assert.notEqual(s.label.en, s.label.id);
        assert.notEqual(s.labelSimple.en, s.labelSimple.id);
        for (const lang of ["en", "id"]) {
            const words = s.labelSimple[lang].toLowerCase().split(/[^a-z0-9]+/);
            for (const j of JARGON) assert.ok(!words.includes(j), `${s.id} labelSimple.${lang} has "${j}"`);
        }
        assert.equal(s.evidence, expected[s.id], `${s.id} evidence`);
    }
});
test("n. weights after phase 07 calibration (D-imelda-12 / D-imelda-30; R1 started at 30 for otp, card, cvv, ktp)", () => {
    assert.deepEqual(WEIGHTS, { asks_pin: 35, asks_otp: 25, asks_password: 15, asks_card: 20, asks_cvv: 25, asks_ktp: 25, asks_selfie_ktp: 35 });
});
test("n. evidence falls back to id, then is omitted; it is never a typed value", () => {
    assert.equal(scam([field({ id: "kode_pin" })])[0].evidence, "kode_pin");
    assert.equal("evidence" in scam([field({ label: "PIN" })])[0], false);
    const withValue = analyzeSnapshot({ ...page(SCAM_URL), forms: [{ fields: [{ type: "text", name: "pin", value: "246810" }] }] });
    assert.equal(withValue[0].evidence, "pin");
    assert.ok(!JSON.stringify(withValue).includes("246810"));
});

// ---- o. no duplicates, deterministic ---------------------------------------
test("o. same signal for several fields -> one signal, evidence of the first field", () => {
    const out = scam([field({ name: "pin1" }), field({ name: "pin2" }), field({ label: "PIN" })]);
    assert.deepEqual(ids(out), ["asks_pin"]);
    assert.equal(out[0].evidence, "pin1");
});
test("o. one field gives at most one signal (priority picks the most specific)", () => {
    assert.deepEqual(only([field({ name: "pin_or_otp", label: "PIN / OTP" })]), ["asks_otp"]);
    assert.deepEqual(only([field({ type: "password", label: "PIN" })]), ["asks_pin"]);
    assert.deepEqual(only([field({ label: "Nomor kartu dan CVV" })]).length, 1);
});
test("o. output order is deterministic: weight desc, then id", () => {
    const fields = [field({ type: "password", name: "pwd" }), field({ name: "cvv" }), field({ name: "pin" }), field({ name: "nik" }), field({ name: "otp" })];
    const a = ids(scam(fields));
    const b = ids(scam([...fields].reverse()));
    assert.deepEqual(a, ["asks_pin", "asks_cvv", "asks_ktp", "asks_otp", "asks_password"]);
    assert.deepEqual(b, a);
    assert.deepEqual(scam(fields), scam(fields));
});

// ---- lphone-login shape ------------------------------------------------------
test("lphone-login style page: Apple-ID password + 6-digit passcode give pin + password", () => {
    const out = analyzeSnapshot(page("https://lphone-login.com/tRrQ", [field({ type: "text", name: "appleId", label: "Apple ID" }), field({ type: "password", name: "password", label: "Password" }), field({ type: "tel", name: "passcode", label: "Passcode" })]));
    assert.deepEqual(ids(out), ["asks_pin", "asks_password"]);
});

// ---- code-review findings: more false-positive and unicode cases -------------
test("review: captcha / school / donation / map-pin fields do not fire", () => {
    expectNone([field({ label: "Masukkan kode keamanan" }), field({ label: "Enter the security code shown" })], "captcha");
    expectNone([field({ label: "Nomor Induk Mahasiswa" }), field({ label: "Employee ID card number" })], "NIM / employee card");
    expectNone([field({ label: "One-time donation amount" })], "one-time donation");
    expectNone([field({ label: "Pin location" })], "map pin");
    expectNone([field({ type: "file", label: "Foto profil selfie" })], "profile selfie");
});
test("review: card context keeps 'kode keamanan' / 'security code' working", () => {
    expectSignal("asks_cvv", [field({ label: "Kode keamanan kartu" })]);
    expectSignal("asks_cvv", [field({ label: "Card security code" })]);
});
test("review: 'Nomor Induk Kependudukan' still ktp; mpin is a pin", () => {
    expectSignal("asks_ktp", [field({ label: "Nomor Induk Kependudukan (NIK)" })]);
    expectSignal("asks_pin", [field({ name: "mpin" })]);
});
test("review: NBSP, ellipsis, curly quotes and full-width colon split words", () => {
    expectSignal("asks_card", [field({ label: "Nomor Kartu" })]);
    expectSignal("asks_pin", [field({ label: "Masukkan PIN… Anda" })]);
    expectSignal("asks_pin", [field({ label: "“PIN”：" })]);
});
test("review: 'Kode Pos / PIN' still asks for a PIN", () => {
    expectSignal("asks_pin", [field({ label: "Kode Pos / PIN" })]);
});
test("review: selfie with a KTP field nearby but also a profile word does not pair", () => {
    assert.deepEqual(only([field({ type: "file", label: "Foto profil selfie" }), field({ name: "nik" })]), ["asks_ktp"]);
});

test("security: a harmless word in another attribute cannot switch a signal off", () => {
    expectSignal("asks_pin", [field({ name: "pin", id: "zip" })]);
    expectSignal("asks_pin", [field({ name: "pin", placeholder: "location" })]);
    expectSignal("asks_card", [field({ name: "card_number", id: "holder", placeholder: "exp name" })]);
    expectSignal("asks_ktp", [field({ name: "nik", id: "student" })]);
    expectSignal("asks_selfie_ktp", [field({ type: "file", name: "selfie_ktp", id: "profile" })]);
});
test("security: invisible characters, full-width letters and Cyrillic look-alikes do not evade", () => {
    expectSignal("asks_pin", [field({ name: "p\u200bin" })]);
    expectSignal("asks_pin", [field({ name: "pi\u00adn" })]);
    expectSignal("asks_otp", [field({ name: "\uff4f\uff54\uff50" })]);
    expectSignal("asks_pin", [field({ name: "\u0440in" })]);
    expectSignal("asks_card", [field({ label: "Nomor K\u0430rtu" })]);
});
test("security: user-content hosts of official domains are not exempt", () => {
    for (const url of ["https://docs.google.com/forms/d/e/abc/viewform", "https://sites.google.com/view/promo", "https://forms.office.com/r/abc", "https://drive.google.com/file/d/x"]) {
        assert.ok(ids(analyzeSnapshot(page(url, SENSITIVE()))).length > 0, url);
    }
    assert.deepEqual(analyzeSnapshot(page("https://accounts.google.com/signin", SENSITIVE())), [], "first-party google still exempt");
});

// ---- bank token fields count as one-time codes --------------------------------
test("asks_otp: bank token fields (mobile token, token lunak, KeyBCA)", () => {
    expectSignal("asks_otp", [field({ type: "password", name: "mobileToken" })], "camelCase mobileToken");
    expectSignal("asks_otp", [field({ label: "Masukkan Token Lunak" })], "token lunak");
    expectSignal("asks_otp", [field({ name: "inputRespons", label: "Respon KeyBCA" })], "KeyBCA");
});
test("asks_otp: a CSRF or API token is not a one-time code", () => {
    expectNone([field({ name: "csrf_token" })], "csrf_token");
    expectNone([field({ name: "_token" })], "_token");
    expectNone([field({ label: "API token" })], "api token");
});
test("asks_otp: autocomplete=one-time-code", () => {
    expectSignal("asks_otp", [field({ autocomplete: "one-time-code" })], "iPhone OTP autofill");
});
