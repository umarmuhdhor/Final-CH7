// Courier scams (jnex.cc, 23 Nov 2026): "delivery failed, address incomplete, pay a redelivery fee" pages, then a card form.
// Couriers never ask for card data on someone else's site, so a card ask next to a courier lure weighs enough to block.
import test from "node:test";
import assert from "node:assert/strict";
import { analyzeSnapshot } from "../src/analyze.js";
import { COURIER_CARD_WEIGHT } from "../src/layer3/courier.js";
import { page, field, ids } from "./helpers.mjs";

const card = [
    field({ name: "cardnumber", label: "Nomor Kartu", autocomplete: "cc-number" }),
    field({ name: "exp", label: "Masa Berlaku", autocomplete: "cc-exp" }),
    field({ name: "cvv", label: "CVV", autocomplete: "cc-csc" }),
];
const byId = (signals, id) => signals.find((s) => s.id === id);
const total = (signals) => signals.reduce((sum, s) => sum + s.weight, 0);

// Text as jnex.cc shows it, minus its look-alike letters (those are a separate topic).
const JNEX_TEXT = "Nomor Resi 120040042107018 Pengiriman Gagal Alamat tujuan tidak lengkap. Sedang Diantar Kurir Pengiriman belum berhasil karena alamat tujuan tidak lengkap. Silakan periksa dan lengkapi alamat penerima. Perbarui Alamat Download Aplikasi MyJNE!";

test("courier lure text alone: urgent_language with the exact page text as evidence", () => {
    const s = analyzeSnapshot(page("https://jnex.cc/id", [], { title: "jnex.cc", text: JNEX_TEXT }));
    const urgent = byId(s, "urgent_language");
    assert.ok(urgent, "lure phrase found");
    assert.ok(JNEX_TEXT.toLowerCase().includes(urgent.evidence.toLowerCase()), `evidence is page text: ${urgent.evidence}`);
    assert.equal(urgent.layer, 3);
    assert.ok(urgent.label.id && urgent.label.en && urgent.labelSimple.id && urgent.labelSimple.en, "bilingual");
});

test("courier lure + card form on an unofficial site -> card ask weighs enough to block on its own", () => {
    const s = analyzeSnapshot(page("https://jnex.cc/id/bayar", card, { text: "Paket Anda tertahan. Bayar biaya pengiriman ulang Rp 12.500." }));
    const ask = byId(s, "asks_card");
    assert.equal(ask.weight, COURIER_CARD_WEIGHT);
    assert.ok(COURIER_CARD_WEIGHT >= 80, "blocks without RDAP or the model");
    assert.match(ask.label.id, /kurir/i);
    assert.match(ask.label.en, /courier/i);
    assert.equal(ask.evidence, "cardnumber", "still the field name, never typed values");
    assert.ok(total(s) >= 80);
});

test("courier named in the title or a logo alt + card form -> same lift, even without a lure phrase", () => {
    for (const over of [{ title: "JNE - Pembayaran Ongkir" }, { imageAlts: ["Logo J&T Express"] }, { title: "SiCepat Ekspres | Pembayaran" }]) {
        const s = analyzeSnapshot(page("https://cek-paket-kiriman.com/bayar", card, over));
        assert.equal(byId(s, "asks_card")?.weight, COURIER_CARD_WEIGHT, JSON.stringify(over));
    }
});

test("a CVV-only form next to a courier lure is lifted too", () => {
    const s = analyzeSnapshot(page("https://jnex.cc/id/bayar", [field({ name: "cvv", label: "CVV" })], { text: "Pengiriman gagal. Bayar biaya pengiriman ulang." }));
    assert.equal(byId(s, "asks_cvv")?.weight, COURIER_CARD_WEIGHT);
});

test("legit shop checkout that lists JNE as a shipping option keeps the normal card weight", () => {
    const s = analyzeSnapshot(page("https://tokobaju-contoh.com/checkout", card, { title: "Checkout - Toko Baju", text: "Ringkasan pesanan. Kemeja putih Rp 150.000. Pengiriman: JNE REG (2-3 hari). Bayar dengan kartu kredit." }));
    assert.equal(byId(s, "asks_card")?.weight, 20);
    assert.equal(byId(s, "urgent_language"), undefined, "a shipping option is not a lure");
});

test("ordinary shop wording is not a lure: 'lengkapi alamat pengiriman', 'cek resi', 'ongkir'", () => {
    const s = analyzeSnapshot(page("https://tokobaju-contoh.com/checkout", card, { text: "Lengkapi alamat pengiriman Anda. Cek resi setelah barang dikirim. Ongkir gratis di atas Rp 200.000." }));
    assert.equal(byId(s, "asks_card")?.weight, 20);
    assert.ok(!ids(s).includes("urgent_language"));
});

test("official courier domain stays silent, lure words or not", () => {
    const s = analyzeSnapshot(page("https://www.jne.co.id/tracking", card, { title: "JNE", text: "Pengiriman gagal, alamat tidak lengkap." }));
    assert.deepEqual(s, []);
});

test("English lure phrases count too", () => {
    const s = analyzeSnapshot(page("https://parcel-redelivery.example.xyz/pay", card, { text: "Delivery failed: incomplete address. Pay the redelivery fee to reschedule." }));
    assert.equal(byId(s, "asks_card")?.weight, COURIER_CARD_WEIGHT);
    assert.ok(byId(s, "urgent_language"));
});

test("an account-threat phrase still wins the urgent_language slot (one urgent signal at most)", () => {
    const s = analyzeSnapshot(page("https://jnex.cc/id", card, { text: "Akun anda akan diblokir. Pengiriman gagal." }));
    assert.equal(s.filter((x) => x.id === "urgent_language").length, 1);
    assert.match(byId(s, "urgent_language").label.id, /diblokir/);
});
