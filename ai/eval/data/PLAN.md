# Eval corpus plan (phase 04, M2)

Goal: 50+ scam and 50+ legit labelled samples (D-imelda-19..22). This file says what is needed per category and where each sample comes from. Status is updated as samples land; `node ai/eval/tools/check-corpus.mjs` prints the live counts.

## Source rules
- **Scam:** no public phishing feed with a clear licence is available to copy from (OpenPhish forbids redistribution and derivative works without written permission; PhishTank and URLhaus publish no usable licence on their pages, and URLhaus is malware only). So scam samples are (a) the real page already in the repo (`lphone-login`), (b) the three domains from `contracts/fixtures/`, and (c) `synthetic: true` samples written by hand from documented scam patterns. No scam page is fetched.
- **Legit:** public pages of official and popular sites, fetched only with `tools/capture.mjs` (static GET, no JavaScript, no cookies, public hosts only). Only the static part of a login or checkout page is kept. Every real sample is read by Imelda before `redacted: true` is set.
- **Synthetic** samples are invented from a pattern, never copied from a real scam page, and are not counted for any claim about the mandate targets (R2 §4).
- **Holdout:** about 30%, chosen by `sha256(seed:id)` with the seed in `HOLDOUT.json`; never picked by hand and never used when tuning weights in phase 07.

## Categories
| Class | Tag | Target | Source | Status |
|---|---|---|---|---|
| scam | bank | 10 | seed + synthetic | planned |
| scam | e-wallet | 8 | synthetic | planned |
| scam | courier | 8 | seed + synthetic | planned |
| scam | prize | 8 | seed + synthetic | planned |
| scam | government | 8 | seed + synthetic | planned |
| scam | apple | 4 | real `lphone-login` + synthetic | planned |
| scam | other | 4 | synthetic (job offer, loan, crypto, marketplace) | planned |
| legit | bank-login | 8 | real, static part of official login pages | needs approval |
| legit | checkout | 12 | real, public cart/checkout shells | needs approval |
| legit | official-gov | 8 | real, official `.go.id` pages | needs approval |
| legit | popular | 10 | real, popular Indonesian sites | needs approval |
| legit | lookalike-trap | 12 | synthetic + a few real | planned |

## Traps that must be present (false-positive risks from phase 03)
Shop with a bank logo at checkout ("Logo BCA"), "diskon terakhir hari ini", "dikirim dalam 24 jam", a blog that mentions a brand ("Cara cek saldo BCA"), a "Sign in with Google" button, Facebook/Instagram share icons, shared hosts (github.io, blogspot), and a legitimate fintech KYC page that asks for KTP/OTP. A scam whose login form sits in an iframe is tagged `credential-iframe`.

## Candidate real legit URLs (NOT fetched yet, waiting for approval)
- bank-login: BCA KlikBCA, BRI, Mandiri, BNI, CIMB Niaga, BSI, Permata, Danamon login pages
- checkout: Tokopedia, Shopee, Bukalapak, Blibli, Lazada, tiket.com, Traveloka cart/checkout shells
- official-gov: kemensos.go.id, bpjs-kesehatan.go.id, pajak.go.id, komdigi.go.id, dukcapil.kemendagri.go.id, bi.go.id, ojk.go.id, polri.go.id
- popular: detik.com, kompas.com, cnnindonesia.com, liputan6.com, tempo.co, kaskus.co.id, idntimes.com, id.wikipedia.org, tribunnews.com, kumparan.com

The exact list is shown to Imelda before any request is made. A URL that fails or returns a page with no text is dropped or replaced, and the real/synthetic split is reported as it ends up.
