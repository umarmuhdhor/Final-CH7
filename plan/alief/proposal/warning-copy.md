# Warning copy: plain-language detection reasons

> Proposal by Alief (Team App), 20 Nov 2026. Docs only: no code is changed by this file.
> Status: applied in PR #638 (20 Nov 2026). Alief chose to do the change in one PR instead of opening issues, so the issue drafts at the end are **not needed**; they are kept as the record of the questions, now asked as review points on PR #638.

## Why

In the usability test of 20 Nov 2026 the tester read the in-page warning reasons ("kata umpan di nama",
"angka di nama") and could not tell what they meant. Their words: "bacanya susah… bisa di-humanize",
"jarang sih kata-katanya". The reasons name *what the detector measured* (a hyphen, a port, a TLD), not
*what is wrong for the reader and why it is risky*.

Goal: every reason a user can see is understood by a non-technical parent in one read.

## Where reasons show, and who sees which wording

Every signal carries two texts (contracts/scan-result.schema.json `$defs.Signal`): `label` and `labelSimple`,
each `{ en, id }`. The rule is the same everywhere: **Guardian reads `label`, Protected (parent) reads
`labelSimple`** (DT-04). The in-page UI always uses `id` (`popup.js`, `pill.js`, `marks.js`, `blocked-page.js` hardcode `lang = "id"`).

| Screen | File | What it shows |
|---|---|---|
| In-page popup card | `ios/ShooExtension/Resources/popup.js:74-80` (`describe`) | The heaviest reason + the tier advice |
| Pill card (score chip) | `ios/ShooExtension/Resources/pill.js:48-54` (`reasonTexts`) | The heaviest reasons, deduped |
| Block page | `ios/ShooExtension/Resources/blocked-page.js:28-33` | All reasons (lookalike line moved under the chip) |
| Field / text marks bubble | `ios/ShooExtension/Resources/marks.js:65-80` (`reasonFor`) | Reason of the `asks_*` or text signal behind the mark, else `mark_why_<kind>` |
| App Detail, evidence cards | `ios/ShooApp/Features/Detail/EvidenceList.swift:34`, `EvidenceCard.swift:500-512` | Top 3 reasons + "Sinyal: <kind name>" |
| App Detail, address card | `ios/ShooApp/Features/Detail/AddressEvidence.swift:98-113` | A short note per address kind + "Yang asli: X" |
| App Detail, summary | `ios/ShooApp/Features/Detail/DetailSummaryCard.swift` | Two sentences built from signal ids (no detector text) |

So the confusing Guardian wording appears **twice**: in Safari and again in the app's Detail screen. A Guardian
is often an adult child, not a developer, so `label` must be plain too. It may carry one more detail than
`labelSimple` (the brand, the word, the number), never a technical term.

Not shown anywhere: `evidence` of layer 1–2 signals (reason codes such as `free_host,free_name_bait`), weights
except "+30 %" on Detail, and push bodies (`backend/api/src/services/push/notify.ts` sends status + name + score
only, no reason text; push copy is a separate proposal). `backend/` stores labels as sent
(`backend/api/src/routes/scans.ts:40-48`, max 500 chars, control/bidi chars stripped) and renders nothing.

## Copy rules used for the rewrites

1. Say what the reader would notice, not what the code measured: "nama situs berisi huruf dan angka acak", not "nama penuh angka".
2. Everyday Indonesian: *alamat* (not domain / host / TLD), *tanda strip* (not tanda hubung), *kata pancingan* (not kata umpan), *situs gratisan* (not hosting), *sambungan tidak aman* (not terenkripsi).
3. When a term cannot be avoided, show it as the reader sees it in the address bar: ".xyz", ":8080", "@".
4. Short. A reason phrase inside the link label stays under ~8 words; a full label under ~12.
5. Keep the detector's rule: a label holds **only our words**, never text taken from the URL or page. Examples such as "seperti "hadiah"" come from our own lists (`detector/data/link-rules.json`), marked with "seperti" so they do not claim to be the word on this page.
6. True to the check. Each row below says what the code actually tests; the rewrite never claims more.

## A. Link reasons (`suspicious_link`): owner Lead (`detector/`)

Source: `REASON_TEXT` in `detector/src/detector.js:333-358`, mirrored in
`ios/ShooExtension/Resources/detector.js:334-359` and `chrome/extension/detector.js`. Up to 3 of these phrases
are joined inside the `suspicious_link` **Guardian** label (`T.suspiciousLink`, `detector.js:319-322`):
"Tautan terlihat mencurigakan (kata umpan di nama, tahun atau jumlah di nama)". Codes marked *hidden* are filtered
out of that list (`linkSignal`, `detector.js:485`) unless nothing else is left.

New wrapper for the label (A0), then one phrase per code:

| # | Key | What the code checks (`dissectLink`) | Current `id` | Current `en` | Proposed `id` | Proposed `en` | Why it is risky (for tooltips / review) |
|---|---|---|---|---|---|---|---|
| A0 | `suspiciousLink` label wrapper (`detector.js:320`) | Joins the top 3 shown reasons | Tautan terlihat mencurigakan (a, b, c) | The link looks suspicious (a, b, c) | Alamat ini mirip alamat penipu: a, b, c. | This address looks like a scam link: a, b, c. | Says the conclusion first, then the plain reasons; no brackets |
| A1 | `userinfo` | Text before `@` in the URL (`https://bca.co.id@evil.com`) | host disembunyikan sebelum @ | hidden host before @ | ada nama samaran sebelum tanda @ | a decoy name before the @ sign | Browsers ignore the part before "@"; the real site is after it |
| A2 | `ip_host` | Host is an IPv4/IPv6 address | alamat IP mentah | raw IP address | alamatnya hanya deretan angka | the address is just numbers | Real shops and banks use a name, not bare numbers |
| A3 | `punycode` | A label starts with `xn--` (non-Latin letters) | huruf menyamar | disguised letters | ada huruf asing yang mirip huruf biasa | foreign letters that look like normal ones | "а" (Cyrillic) looks like "a"; the address only looks right |
| A4 | `many_labels` | 4+ dot parts before the ending | terlalu banyak titik | too many dots | nama aslinya tersembunyi di antara banyak titik | the real name is hidden among many dots | `bca.co.id.login.xyz-site.com`: the real owner is at the end |
| A5 | `many_hyphens` | One part has 3+ hyphens | terlalu banyak tanda hubung | too many hyphens | namanya disambung banyak tanda strip (-) | the name is strung together with many dashes | `bca-login-aman-resmi`: words glued to look official |
| A6 | `word_digit_subdomain` | Front part like `regs-apps14` (words-hyphen-number) | nama bergaya aplikasi dengan angka | app-style name with a number | bagian depan alamat berupa kata + angka buatan | a made-up word-and-number front part | Auto-made addresses from scam kits look like this |
| A7 | `hyphen_registrable` | The site name has a hyphen (not next to a brand or lure word) | tanda hubung di nama situs | hyphen in the site name | nama situs memakai tanda strip (-) | a dash in the site name | Weak sign alone; scammers glue words with dashes |
| A8 | `digit_label` | A piece of 6+ chars mixing letters and 3+ digits (`dp9hsk1cxr2y`) | nama penuh angka | name made of digits | nama situs berisi huruf dan angka acak | random letters and numbers in the name | Current text is also inaccurate: the check needs letters *and* digits |
| A9 | `rare_tld` | Ending in `rareTlds` (.info .pw .cc .ws .su) | akhiran jarang | rare ending | akhiran alamat yang jarang dipakai situs resmi | an ending real sites rarely use | Official Indonesian sites mostly end in .co.id / .com / .go.id |
| A10 | `odd_port` | A port other than 80/443 | port tak lazim | unusual port | ada angka aneh setelah nama situs (seperti :8080) | an odd number after the site name (like :8080) | Normal sites never show ":number" in the address |
| A11 | `random_name` | Last path part: 20+ chars, random-looking, has digits | nama file acak | random file name | nama halamannya kode acak | the page name is a random code | Scam pages get a throwaway random name |
| A12 | `file_ext` *hidden* | Last path part ends `.html/.php/.asp/.jsp` | akhiran file halaman | page file ending | alamatnya berakhiran .html atau .php | the address ends in .html or .php | Copied scam pages are often a single uploaded file |
| A13 | `slash_after_file` | `.php/` (slash after a file name) | garis miring setelah nama file | slash after file name | ada garis miring aneh setelah .html atau .php | an odd slash after .html or .php | A trick to dodge simple filters |
| A14 | `path_bait` | Path word in `keywords` or `pathBait` (klaim, verifikasi, kode, login…) | kata umpan di path | bait word in path | ada kata pancingan di alamat (seperti "klaim" atau "kode") | a lure word in the address (like "claim" or "code") | Scams put "klaim", "verifikasi", "kode" in the link to look urgent |
| A15 | `redirect_param` | Query `url=/redirect=/next=…` holding another link | mengalihkan ke tempat lain | redirects elsewhere | tautan ini melempar kamu ke situs lain | the link sends you on to another site | The page you land on is not the one named first |
| A16 | `email_param` | An email address in the query | email di tautan | email in link | ada alamat email di dalam tautan | an email address inside the link | The link was made for one target person |
| A17 | `long_query` | Query longer than 150 chars | tautan sangat panjang | very long link | tautannya sangat panjang sampai isinya tersembunyi | a link so long it hides what it does | Long tails hide where the link really goes |
| A18 | `url_in_fragment` | `#` part contains `http(s):` | tautan di dalam tautan | link inside link | ada alamat situs lain yang diselipkan | another site's address tucked inside | Hides a second destination |
| A19 | `long_url` *hidden* | Whole URL longer than 120 chars | tautan sangat panjang | very long link | tautannya sangat panjang | a very long link | Same text as A17 today; keep different so both never read twice |
| A20 | `http_no_tls` *hidden* | `http:` (no TLS) | tidak terenkripsi | not encrypted | sambungannya tidak aman (tanpa https) | the connection is not secure (no https) | Anyone on the network can read what you type |
| A21 | `free_host` *hidden* | Host on a free platform (blogspot, github.io, vercel.app…) | halaman hosting gratis | free hosting page | dibuat di layanan situs gratis | made on a free website service | Anyone can make one in minutes, no identity check |
| A22 | `free_name_bait` | Free-platform name has a lure word or courier name (`linkBait`, `carriers`) | kata umpan di nama | bait word in the name | situs gratisan dengan nama pancingan (seperti "bansos" atau nama kurir) | a free site named with lure words (like "aid" or a courier name) | `bansos-2025.blogspot.com`, `sicepat-paket.web.app`: the tester's "kata umpan di nama" |
| A23 | `free_name_number` | Free-platform name has `20xx` or an amount (`50gb`, `100rb`, `1jt`) | tahun atau jumlah di nama | year or amount in the name | ada tahun atau nominal promo di nama (seperti 2025 atau 50gb) | a year or promo amount in the name (like 2025 or 50GB) | Promo bait: "kuota gratis 50gb", "bansos 2025". The tester's "angka di nama" |
| A24 | `free_file_bait` | Free-platform page file name has a lure word | kata umpan di nama file | bait word in the file name | nama halamannya memakai kata pancingan | the page name uses lure words | Same trick as A22, in the page name |

Example, `kuota-gratis-50gb.blogspot.com` (Guardian, in Safari and in the app):

- Today: "Tautan terlihat mencurigakan (kata umpan di nama, tahun atau jumlah di nama)"
- Proposed: "Alamat ini mirip alamat penipu: situs gratisan dengan nama pancingan (seperti "bansos" atau nama kurir), ada tahun atau nominal promo di nama (seperti 2025 atau 50gb)."

That example is long. Option for the Lead: show only the **first** phrase in the label
("Alamat ini mirip alamat penipu: situs gratisan dengan nama pancingan.") and leave the rest to the app. Asked in issue draft 1, Q2.

## B. Other layer 1–2 signal labels: owner Lead (`detector/`)

Source: `T` and `FORM_TEXT` in `detector/src/detector.js:302-330` and `:532-538`, mirrored in
`ios/ShooExtension/Resources/detector.js:303-331`, `:533-539` and `chrome/extension/detector.js`.
`{b}` = brand display name, `{kw}` = keyword from our list, `{tld}` = ending.

| # | Signal / text | What it checks | Field | Current `id` | Current `en` | Proposed `id` | Proposed `en` |
|---|---|---|---|---|---|---|---|
| B1 | `lookalike_domain` (`T.lookalike`) | Address spelled like a brand (typo or homoglyph) | label | Nama domain meniru {b} | Domain spelled like {b} | Alamatnya dibuat mirip alamat {b} | The address is made to look like {b}'s |
| | | | labelSimple | Alamat ini mirip alamat {b}, tapi bukan yang asli | This address looks like {b}'s, but it is not the real one | keep | keep |
| B2 | `lookalike_domain` (`T.nameOnly`) | Brand name on an address not in the brand's list | label | Memakai nama {b} tapi bukan domain resmi {b} | Uses the name {b} but is not an official {b} domain | Memakai nama {b}, tapi bukan alamat resmi {b} | Uses the name {b}, but is not {b}'s official address |
| | | | labelSimple | Situs ini memakai nama {b}. Bisa jadi bukan yang asli | This site uses the name {b}. It may not be the real one | keep | keep |
| B3 | `brand_plus_keyword` (`T.brandKeyword`) | Brand + a lure word in the address (`bca-verifikasi`) | label | Nama brand ditambah kata lain ({b} + {kw}) | Brand name plus extra word ({b} + {kw}) | Nama {b} disambung kata "{kw}", bukan alamat resmi {b} | {b}'s name joined with "{kw}", not {b}'s official address |
| | | | labelSimple | Alamat ini menggabungkan {b} dengan kata "{kw}" | This address mixes {b} with the word "{kw}" | Alamat ini menempelkan kata "{kw}" ke nama {b}. Ini bukan alamat resmi {b} | This address adds "{kw}" to {b}'s name. It is not {b}'s official address |
| B4 | `cheap_tld` (`T.cheapTld`) | Ending in `cheapTlds` (.xyz .site .top …) | label | Akhiran domain murah .{tld} | Cheap domain ending .{tld} | Akhiran .{tld} murah dan sering dipakai penipu | The ending .{tld} is cheap and often used by scammers |
| | | | labelSimple | Situs ini memakai akhiran alamat murah yang sering dipakai penipu | This site uses a cheap address ending that scammers often use | keep | keep |
| B5 | `suspicious_link` (`T.suspiciousLink`) | Whole-link score ≥ 10 | label | see A0 | see A0 | see A0 | see A0 |
| | | | labelSimple | Alamat halaman ini mirip alamat yang biasa dipakai penipu | The address of this page looks like the ones scammers use | keep | keep |
| B6 | `db_match`, source `shoo` (`T.dbMatch`) | Host on Shoo's confirmed list | label | Dilaporkan dan dipastikan sebagai penipuan oleh Shoo | Reported and confirmed as a scam by Shoo | keep | keep |
| B7 | `db_match`, source `public` | Host on a public phishing list | label | Ada di daftar publik situs phishing | Found on a public list of phishing sites | Ada di daftar umum situs penipuan | Found on a public list of scam sites |
| | `db_match` (both) | | labelSimple | Situs ini sudah dikenal menipu orang. Jangan isi apa pun di sini | This site is known to cheat people. Do not enter anything here | keep | keep |
| B8 | `asks_pin/otp/card/cvv/ktp` (`FORM_TEXT`, layer 2C) | Field words on a page that already imitates a brand | label + labelSimple | e.g. Form meminta PIN atau kode sandi / Meminta PIN rahasia kamu | e.g. Form asks for a PIN or passcode / Asks for your secret PIN | keep, but "Form" → "Formulir" in all 5 labels; must stay identical to C1–C5 | keep |

## C. Layer 3–4 signal labels: owner Imelda (`ai/`)

These reach the user through `/analyze` and are shown exactly like layer 1–2 (same `label` / `labelSimple` rule).

| # | Signal | File:line | What it checks | Field | Current `id` | Current `en` | Proposed `id` | Proposed `en` |
|---|---|---|---|---|---|---|---|---|
| C1–C6 | `asks_pin/otp/password/card/cvv/ktp` | `ai/src/layer3/signals.js:16-39` | Form field asks for that data | label | Form meminta … | Form asks for … | keep; "Form" → "Formulir" (same as B8) | keep |
| | | | | labelSimple | e.g. Meminta PIN rahasia kamu | e.g. Asks for your secret PIN | keep (already plain) | keep |
| C7 | `asks_selfie_ktp` | `ai/src/layer3/signals.js:40-43` | Form asks for a selfie holding the KTP | label | Form meminta selfie dengan KTP | Form asks for a selfie with KTP | Formulir meminta foto selfie sambil memegang KTP | Form asks for a photo of you holding your ID card |
| C8 | `urgent_language` | `ai/src/layer3/signals.js:69-70` | A phrase from our urgency list | label | Kalimat mendesak: "{phrase}" | Urgent language: "{phrase}" | Kalimat yang membuat buru-buru: "{phrase}" | Words that rush you: "{phrase}" |
| | | | | labelSimple | Memaksa kamu cepat-cepat bertindak | Rushes you to act fast | keep | keep |
| C9 | `brand_logo_offsite` (logo) | `ai/src/layer3/signals.js:81-82` | Brand logo / name on a non-official site | label | Logo {b} di situs tidak resmi | {b} logo on an unofficial site | keep | keep |
| C10 | `brand_logo_offsite` (copied form) | `ai/src/layer3/signals.js:99-100` | Sign-in form copied from a brand | label | Form login {b} ditiru di situs tidak resmi | {b} sign-in form copied on an unofficial site | Halaman masuk {b} ditiru di situs yang bukan milik {b} | {b}'s sign-in page copied on a site {b} does not own |
| | both C9, C10 | | | labelSimple | Berpura-pura menjadi {b} | Pretends to be {b} | keep | keep |
| C11 | `new_domain` | `ai/src/layer3/signals.js:120-121` | Domain age from RDAP < 91 days | label | Umur domain {n} hari | Domain age {n} days | Situs ini baru dibuat {n} hari lalu | This site was made {n} days ago |
| | | | | labelSimple | Situs ini baru dibuat {n} hari lalu | This site was made {n} days ago | keep | keep |
| C12 | `impersonation_model` | `ai/src/layer3/model/impersonation.js:473-474` | Model says the page copies another site | label | Halaman ini mirip tiruan situs lain | Page looks like a fake copy of another site | Tampilan halaman ini seperti tiruan situs lain | This page looks like a copy of another site |
| | | | | labelSimple | Terlihat seperti situs palsu | Looks like a fake site | keep | keep |
| C13 | `unreasonable_request` (layer 4) | `ai/src/layer4/reality.js:119-120` | LLM: the data asked does not fit the page type | label | Data yang diminta tidak wajar untuk jenis halaman ini | The data requested does not fit this kind of page | Halaman seperti ini biasanya tidak meminta data itu | A page like this does not normally ask for that |
| | | | | labelSimple | Halaman asli seperti ini tidak akan meminta ini | A real page of this kind would not ask for this | keep | keep |

Constraint for C11: the app reads the day count from the reason text (`AddressEvidence.days(in:)`,
`ios/ShooApp/Features/Detail/AddressEvidence.swift:215`, first run of digits). The new label must keep exactly one number.

## D. Extension UI strings near the reasons: owner Lead (`ios/ShooExtension/Resources/_locales/id/messages.json`)

Already plain; listed so the reasons above match their tone. No change proposed.

| Key | Current `id` | Shown on |
|---|---|---|
| `mark_why_pin` | Bank dan aplikasi asli tidak pernah meminta PIN lewat website. | Mark bubble, "Kenapa?" |
| `mark_why_otp` | OTP hanya untukmu. Siapa pun yang memintanya bisa mengambil alih akunmu. | Mark bubble |
| `mark_why_card` | Data kartu yang diketik di sini bisa dipakai untuk mengambil uangmu. | Mark bubble |
| `mark_why_ktp` | Nomor KTP-mu bisa disalahgunakan untuk pinjaman atas namamu. | Mark bubble |
| `mark_why_password` | Halaman ini mungkin menyamar jadi situs lain untuk mencuri password-mu. | Mark bubble |
| `popup_body_1`, `popup_body_2` | Hati-hati sebelum memasukkan data pribadi di sini. / Jangan masukkan PIN, OTP, password, atau nomor kartu di halaman ini. | Popup advice after the reason |

These are the tone to aim for: what is wrong, then what it means for you.

## E. App strings: owner Alief (`ios/ShooApp/`), listed only, not changed yet

All in `ios/ShooApp/Resources/Localizable.xcstrings` (key = English source unless it is a dotted key).

| # | Key | Used at | Current `id` | Current `en` | Proposed `id` | Proposed `en` |
|---|---|---|---|---|---|---|
| E1 | `Signal:` | `Features/Detail/EvidenceCard.swift:506` | Sinyal: | Signal: | Jenis tanda: | Sign: |
| E2 | `signal.sensitiveForm` | `EvidenceCard.swift:39` | Formulir sensitif | Sensitive form | Meminta data rahasia | Asks for private data |
| E3 | `signal.copiedLogo` | `EvidenceCard.swift:40` | Logo tiruan | Copied logo | keep | keep |
| E4 | `signal.lookalikeDomain` | `EvidenceCard.swift:41` | Alamat mirip | Look-alike address | Alamat tiruan | Copycat address |
| E5 | `signal.brandInAddress` | `EvidenceCard.swift:42` | Nama merek di alamat | Brand name in address | keep | keep |
| E6 | `signal.cheapEnding` | `EvidenceCard.swift:43` | Akhiran domain murah | Cheap domain ending | Akhiran alamat murah | Cheap address ending |
| E7 | `signal.suspiciousLink` | `EvidenceCard.swift:44` | Tautan mencurigakan | Suspicious link | Alamat mencurigakan | Suspicious address |
| E8 | `signal.newDomain` | `EvidenceCard.swift:45` | Umur domain | Domain age | Situs baru | New site |
| E9 | `signal.urgentWording` | `EvidenceCard.swift:46` | Bahasa mendesak | Urgent wording | Kalimat terburu-buru | Rushing words |
| E10 | `signal.unusualRequest` | `EvidenceCard.swift:47` | Permintaan tidak wajar | Unusual request | keep | keep |
| E11 | `signal.hoax` | `EvidenceCard.swift:48` | Klaim hoaks | Hoax claim | keep | keep |
| E12 | `signal.knownScam` | `EvidenceCard.swift:49` | Daftar penipuan | Known scam list | Penipuan yang sudah dikenal | Known scam |
| E13 | `signal.other` | `EvidenceCard.swift:50` | Sinyal lain | Other signal | Tanda lain | Other sign |
| E14 | `Address is %lld days old` / `Address is 1 day old` | `AddressEvidence.swift:103` | Umur alamat %lld hari / Umur alamat 1 hari | (source) | Situs ini baru berumur %lld hari / Situs ini baru berumur 1 hari | This site is only %lld days old / only 1 day old |
| E15 | `Address made recently` | `AddressEvidence.swift:105` | Alamat baru dibuat | (source) | Situs ini baru dibuat | This site was made recently |
| E16 | `On a scam list` | `AddressEvidence.swift:107` | Ada di daftar penipuan | (source) | keep | keep |
| E17 | `Cheap ending often used by scam sites` | `AddressEvidence.swift:108` | Akhiran murah yang sering dipakai situs penipuan | (source) | keep | keep |
| E18 | `Not the brand's official address` | `AddressEvidence.swift:109` | Bukan alamat resmi brand ini | (source) | Bukan alamat resmi merek ini | keep |
| E19 | `Brand name with extra words` | `AddressEvidence.swift:110` | Nama brand ditambah kata lain | (source) | Nama merek disambung kata lain | Brand name with extra words glued on |
| E20 | `The link itself looks like a scam link` | `AddressEvidence.swift:111` | Link-nya sendiri mirip link penipuan | (source) | Alamatnya sendiri mirip alamat penipu | The address itself looks like a scam address |
| E21 | `Something is off with this address` | `AddressEvidence.swift:112` | Ada yang janggal dengan alamat ini | (source) | keep | keep |
| E22 | `Real: %@` | `AddressEvidence.swift:87` | Yang asli: %@ | (source) | Alamat asli: %@ | Real address: %@ |
| E23 | `%@, adds %lld percent to the risk score` | `EvidenceList.swift:55` (VoiceOver) | %@, menambah %lld persen ke skor risiko | (source) | keep | keep |
| E24 | `detail.summary.*` | `DetailSummaryCard.swift:49-102` | e.g. Halaman %1$@ palsu yang meminta %2$@ kamu. | e.g. A fake %1$@ page that asks for your %2$@. | keep (already plain) | keep |

The detector text itself (sections A–C) shows in the app as-is (`signal.label.text(for:)`); the mandate says the app
must not translate or rewrite it. So the app fix for the tester's complaint comes from sections A–C, not from E.

## F. `contracts/` and `backend/`: no user text

- `contracts/detector-interface.md:87,122` lists the reason codes (`free_host,free_name_bait` …) as `evidence`; they are never shown. The rewrites change only `label` / `labelSimple` strings, so **no contract change** (no new field, no new id). Fixtures in `contracts/fixtures/*.json` keep their old wording until the lead refreshes them; nothing breaks, they are mock data.
- `backend/` stores the label strings (≤ 500 chars, validated in `backend/api/src/routes/scans.ts:40-48`). Old scans keep old wording until the 14-day retention clears them.
- App mock data with the old wording: `ios/ShooApp/Data/Fixtures/corpus-scans.json`, `ios/ShooApp/Data/MockScenarios.swift`. Alief refreshes them after the detector change lands.

## Keep in sync (for whoever applies A–C)

- Three copies of the detector: `detector/src/detector.js`, `ios/ShooExtension/Resources/detector.js`, `chrome/extension/detector.js`.
- B8 (`FORM_TEXT`, layer 2C) and C1–C6 (`ai/src/layer3/signals.js`) must stay word-for-word equal: `mergeSignals` keeps the heaviest per id, so the user can see either one.
- The A0 wrapper with 3 phrases can get long; the backend cap is 500 chars, which it stays well under.

---

## Issue draft 1: Lead (detector + extension)

> **Not needed, done in PR #638** (Alief, 20 Nov 2026: "kita aja yang kerjain gk usah issue"). @umarmuhdhor is asked for review there instead.

**Title:** `EX-08 / detector: plain wording for warning reasons (usability test 20 Nov)`

**PRD ID / area:** EX-08, DT-04 · `detector/`

**Context**

Usability test 20 Nov 2026: the tester read the in-page reasons "kata umpan di nama" and "angka di nama" and did not
understand them ("bacanya susah… bisa di-humanize", "jarang sih kata-katanya"). These are the `REASON_TEXT` phrases
joined inside the `suspicious_link` label (`detector/src/detector.js:319-358`). The same `label` is shown to Guardians
in Safari (popup, pill, block page) and again in the app's Detail screen, so the jargon shows twice.

Full inventory, what each code checks, and proposed rewrites: `plan/alief/proposal/warning-copy.md` sections A, B.

**Proposal**

1. Replace the 24 `REASON_TEXT` phrases with the plain versions in section A (A1–A24). Each one says what the reader would notice ("nama situs berisi huruf dan angka acak") instead of what the code measured ("nama penuh angka"). A8 also fixes an inaccuracy: `digit_label` needs letters *and* digits.
2. Change the `suspicious_link` label wrapper (A0) from "Tautan terlihat mencurigakan (a, b, c)" to "Alamat ini mirip alamat penipu: a, b, c."
3. Plainer `label` for `lookalike_domain`, `brand_plus_keyword`, `cheap_tld`, `db_match` public (section B: B1–B4, B7). `labelSimple` stays except B3.
4. "Form" → "Formulir" in the 5 `FORM_TEXT` labels (B8), only if Imelda makes the same change in `ai/` (issue draft 2), so they stay identical.
5. Apply to all three copies: `detector/src/detector.js`, `ios/ShooExtension/Resources/detector.js`, `chrome/extension/detector.js`.

No contract change: only `label` / `labelSimple` strings change, ids and `evidence` stay.

**Questions**

1. OK to apply A0–A24 and B1–B4, B7 as written? Edit any line you disagree with.
2. Should the `suspicious_link` label list up to 3 phrases (today) or only the first one, to keep the popup card short?
3. Guardians read `label` in Safari too. Should Guardians in Safari get `labelSimple` instead (the in-page card is a quick glance; the full `label` stays in the app's Detail)?
4. The examples in A14 and A22–A23 ("seperti "klaim"", "seperti 2025 atau 50gb") come from our own lists, not the URL. OK with that, or drop the examples?

**Until answered**

Alief changes nothing in `detector/` or `ios/ShooExtension/`. App Detail keeps showing the detector's text as-is. The
app-side names (section E) wait for this answer so the words match on both sides.

---

## Issue draft 2: Team AI (layer 3–4 labels)

> **Not needed, done in PR #638** (Alief, 20 Nov 2026). @imeldamayanti is asked for review there instead.

**Title:** `ai/layer3-4: plainer Guardian labels for 5 signals (usability test 20 Nov)`

**PRD ID / area:** DT-04 · `ai/`

**Context**

Usability test 20 Nov 2026: the tester found the warning reasons hard to read and asked for plain words. Most
layer 3–4 `labelSimple` texts are already plain. A few Guardian `label` texts still use technical terms ("Umur
domain", "Form login", "tidak wajar untuk jenis halaman ini"). Guardians see `label` in Safari and in the app.

Full inventory and rewrites: `plan/alief/proposal/warning-copy.md` section C.

**Proposal**

1. `new_domain` label: "Umur domain {n} hari" → "Situs ini baru dibuat {n} hari lalu" (C11). Keep exactly one number in it: the app reads the day count from the text (`AddressEvidence.days(in:)`).
2. `brand_logo_offsite` (copied form) label: "Form login {b} ditiru di situs tidak resmi" → "Halaman masuk {b} ditiru di situs yang bukan milik {b}" (C10).
3. `unreasonable_request` label: → "Halaman seperti ini biasanya tidak meminta data itu" (C13).
4. `urgent_language` label: "Kalimat mendesak: …" → "Kalimat yang membuat buru-buru: …" (C8).
5. `impersonation_model` label → "Tampilan halaman ini seperti tiruan situs lain" (C12); `asks_selfie_ktp` label → "Formulir meminta foto selfie sambil memegang KTP" (C7).
6. "Form" → "Formulir" in the `asks_*` labels (C1–C6), together with the Lead's `FORM_TEXT` copy so both stay word-for-word equal.

No contract change: ids, weights and `evidence` stay.

**Questions**

1. OK to apply C7, C8, C10–C13 as written? Edit any line you disagree with.
2. OK to rename "Form" → "Formulir" in the `asks_*` labels, in step with the Lead's `FORM_TEXT` (issue draft 1, item 4)?
3. Does any test or eval in `ai/` match these label strings exactly, so it needs an update in the same PR?

**Until answered**

Alief changes nothing in `ai/`. The app keeps showing the labels as sent.
