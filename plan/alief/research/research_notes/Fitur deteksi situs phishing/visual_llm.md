# Visual-similarity and LLM / multimodal approaches to phishing / scam website detection

Scope note: researched 2026-10-26. Primary sources (USENIX / AAAI / arXiv full text, MDN browser-compat-data JSON, WebKit blog) were opened where possible. Numbers marked "(secondary)" came from a search-engine summary or a third-party review and were not confirmed in the original paper. Shoo context: on-device layers already have brand hint from `<img alt>`, urgent-language list (ID + EN), sensitive form-field checks (PIN, OTP, password, card, CVV, KTP, selfie-with-KTP). The server layer 4 (Cloudflare Workers) calls an LLM with only host, title (<=120 chars), up to 12 field labels, and fired rule IDs.

## 1. Reference-based visual detectors (VisualPhishNet, Phishpedia, PhishIntention, DynaPhish, KnowPhish, PhishLLM, PhishAgent): accuracy, false positives, unknown brands, reference-list size

### Takeaway
Reference-based detectors find the brand a page claims to be (logo, screenshot, or text) and flag it when the domain does not belong to that brand. Lab precision is very high (about 98-99%), but recall depends on how many brands the reference list covers. With the classic 277-brand list, recall is only 33-40%. With a 20k-brand knowledge base it is 73-87%. An independent 451k-site study found real-world detection rates far below the lab numbers, and up to 16% false positives on benign pages for Phishpedia. Logo removal or manipulation defeats the vision-only models.

### Cited Findings
**VisualPhishNet (CCS 2020)**
- Abdelnabi, Krombholz, Fritz. "VisualPhishNet: Zero-Day Phishing Website Detection by Visual Similarity", ACM CCS 2020. It is a triplet CNN that learns visual profiles of legitimate sites and flags pages by screenshot similarity. It shipped the VisualPhish dataset — [arXiv 1909.00300](https://arxiv.org/abs/1909.00300); DOI [10.1145/3372297.3417233](https://doi.org/10.1145/3372297.3417233)
- In an independent re-test, VisualPhishNet's real-world detection rate was 39-41%. Its brand identification was 66% correct, and its false positive rate on 2,500 benign pages was 13.52%. Its base reference list has 155 brands — [Ji et al., "Evaluating the Effectiveness and Robustness of Visual Similarity-based Phishing Detection Models", arXiv 2405.19598 (2024/2025)](https://arxiv.org/html/2405.19598v2)
- At comparable precision, VisualPhishNet's recall was below 15%, while multimodal LLMs reached about 90% (test set: 835 benign, 612 phishing) — [Lee, Lim, Hooi, Divakaran, "Multimodal LLMs for Phishing Webpage Detection and Identification", APWG eCrime 2024, arXiv 2408.05941](https://arxiv.org/html/2408.05941v1)

**Phishpedia (USENIX Security 2021)**
- Lin et al. "Phishpedia: A Hybrid Deep Learning Based Approach to Visually Identify Phishing Webpages", USENIX Security 2021, pp. 3793-3810. It detects the logo in a screenshot (Faster R-CNN), matches it with a Siamese network against a brand reference list, and checks the domain. It needs no training on phishing samples — [USENIX](https://www.usenix.org/conference/usenixsecurity21/presentation/lin)
- The paper's logo target list had 181 brands; the maintainers later expanded it to 277. In a live deployment it found 1,113 phishing sites not flagged by VirusTotal (the PDF says 1,133; the sources conflict) — [USENIX abstract](https://www.usenix.org/conference/usenixsecurity21/presentation/lin), via search summary
- Independent re-test, real-world detection rate: 74.46% on brands in the list, 60.97% on all brands (70.47% with an extended list). False positive rate on 2,500 benign pages: 16.24% (406 pages). Under logo elimination, detection fell to 9.09% (benign-looking URL) — [Ji et al., arXiv 2405.19598](https://arxiv.org/html/2405.19598v2)
- On KnowPhish's TR-OP benchmark (10k pages), Phishpedia with its original 277-brand list had 99.16% precision and 40.16% recall at 0.25 s per page. In a Singapore field scan its precision was only 31.48% (17 of 54 reports were true) — [Li et al., KnowPhish, USENIX Security 2024](https://arxiv.org/html/2403.02253v2)

**PhishIntention (USENIX Security 2022)**
- Liu, Lin, Yang, Ng, Divakaran, Dong. "Inferring Phishing Intention via Webpage Appearance and Dynamics: A Deep Vision Based Approach", USENIX Security 2022, pp. 1633-1650. It adds a credential-requiring-page (CRP) classifier and dynamic CRP navigation to the brand-domain check. Dataset: 50K pages. Two-month field study: 1,942 new phishing pages, 1,368 of them not reported by VirusTotal. It had 139 false positives against 1,033 for the best baseline (an 86.5% reduction) — [USENIX](https://www.usenix.org/conference/usenixsecurity22/presentation/liu-ruofan)
- Independent re-test: 0% false positives, but only 49-66% detection. Under visible logo manipulation its detection fell to 5.04%, and under logo elimination to 0.0% — [Ji et al., arXiv 2405.19598](https://arxiv.org/html/2405.19598v2)
- TR-OP with the original list: 99.76% precision, 33.32% recall — [KnowPhish](https://arxiv.org/html/2403.02253v2)

**DynaPhish (USENIX Security 2023)**
- Liu, Lin, Zhang, Lee, Dong. "Knowledge Expansion and Counterfactual Interaction for Reference-Based Phishing Detection", USENIX Security 2023. It expands the reference list dynamically (with legitimacy validation through web search) and adds a counterfactual interaction step. It reports +28% recall over the state of the art at "negligible" precision cost and 9x more phishing found in the wild. Dataset: 6,344 interactable phishing pages — [USENIX](https://www.usenix.org/conference/usenixsecurity23/presentation/liu-ruofan)
- Its cost is latency: about 5.9-12 s per page because of the live search validation — [KnowPhish Tables 2-3](https://arxiv.org/html/2403.02253v2). Its median cost is 11.50 USD per 1K sites — [PhishLLM, USENIX Security 2024](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)
- In the independent re-test, DynaPhish detected only 22.03% of sampled real-world phishing (0% false positives) — [Ji et al.](https://arxiv.org/html/2405.19598v2)

**KnowPhish (USENIX Security 2024)**
- Li, Huang, Deng, Lock, Cao, Oo, Lim, Hooi. "KnowPhish: Large Language Models Meet Multimodal Knowledge Graphs for Enhancing Reference-Based Phishing Detection", USENIX Security 2024, pp. 793-810. It builds an automatic multimodal brand knowledge base of about 20k brands from Wikidata industries and Tranco popularity, adding logos, aliases, and domains. An LLM (default GPT-3.5-turbo-instruct) extracts the brand from HTML text, so logo-less pages are caught. A text CRP classifier (XLM-RoBERTa, 2,555 labeled samples) is included — [arXiv 2403.02253](https://arxiv.org/html/2403.02253v2); [USENIX](https://www.usenix.org/conference/usenixsecurity24/presentation/li-yuexin)
- Effect of list size (TR-OP, 10k pages): Phishpedia recall went from 40.16% (277 brands) to 72.80% (KnowPhish 20k) with precision 99.16% to 98.27%. KPD with KnowPhish reached 97.84% precision, 86.90% recall, and 92.05 F1 at 2.02 s per page — [KnowPhish Table 2](https://arxiv.org/html/2403.02253v2)
- Singapore field scan (10k pages, Aug 2023-Jan 2024): KPD + KnowPhish flagged 699 pages at 97.42% precision (18 false positives) at 1.64 s per page. Phishpedia with the original list flagged only 54 pages at 31.48% precision — [KnowPhish Table 3](https://arxiv.org/html/2403.02253v2)
- Brands not in Wikidata stay false negatives (for example Bank Promerica and Minnesota Unemployment Insurance). The paper does not evaluate non-English pages directly — [KnowPhish](https://arxiv.org/html/2403.02253v2)
- With GPT-4, brand extraction was 85.50% and CRP classification 90.25%. Overall detection was similar across GPT-3.5, GPT-4, and LLaMA-2-7B — [KnowPhish](https://arxiv.org/html/2403.02253v2)

**PhishLLM (USENIX Security 2024)**
- Liu, Lin, et al. "Less Defined Knowledge and More True Alarms: Reference-based Phishing Detection without a Pre-defined Reference List", USENIX Security 2024. It asks the LLM for the brand-to-domain mapping (from OCR text and logo caption) instead of using a list. A Google-search popularity check controls hallucination, and an LLM CRP prediction step follows. Reported recall gain over Phishpedia and PhishIntention: 21% to 66%, with negligible precision loss — [USENIX PDF](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)
- Small field study: precision 0.96 with a median runtime of 1.22 s. It reported 132 phishing pages over 126 brands, 115 of them outside the static list. Comparison: Phishpedia 0.65 / 0.35 s, PhishIntention 0.83 / 0.38 s, DynaPhish+PhishIntention 0.85 / 5.89 s — [PhishLLM Table 6](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)
- Large field study (90K CertStream sites): 1,340 verified phishing reports versus 178 (Phishpedia) and 107 (PhishIntention). On a sampled 3k subset, PhishLLM had precision 1.00 and recall 0.70, against recall 0.07 and 0.04 for the two baselines. Of the 1,340 reports, 1,105 targeted 939 brands not in the reference list — [PhishLLM Table 7](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)
- Its recall on public phishing feeds was 0.84 against 0.66 and 0.47. Misses included crypto "connect wallet" phishing that asks for no classic credentials — [PhishLLM](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)
- Limitation: domain-level popularity validation misses phishing hosted on compromised legitimate domains — [PhishLLM](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)

**PhishAgent (AAAI 2025)**
- Cao, Huang, Li, Wang, He, Oo, Hooi. "PhishAgent: A Robust Multimodal Agent for Phishing Webpage Detection", AAAI 2025, vol. 39, pp. 27869-27877, DOI [10.1609/aaai.v39i27.35003](https://doi.org/10.1609/aaai.v39i27.35003). It is an MLLM agent with online and offline brand knowledge bases. Its inputs are a screenshot, HTML, and URL, with the logo cropped by a detector. Results on TR-OP (4k pages): accuracy 96.10%, precision 95.24%, recall 97.05%, 2.25 s per page. ChatPhishDetector with GPT-4o got 95.80% accuracy at 6.93 s. KPD+KnowPhish got 92.05% at 1.49 s — [arXiv 2408.10738v3](https://arxiv.org/html/2408.10738v3)
- On SG-SCAN-1k, pure MLLM detection (ChatPhishDetector/GPT-4o) fell to 83.50% accuracy, while PhishAgent held at about 94%. Field scan: 4,139 flags at 95.10% precision. The implied false positive rate on TR-OP is about 4.9% (my calculation from precision and recall; the paper does not report it) — [arXiv 2408.10738v3](https://arxiv.org/html/2408.10738v3)
- PhishLLM follow-up: "PhishIntel: Toward Practical Deployment of Reference-Based Phishing Detection" (WWW 2025 Companion) — [arXiv 2412.09057](https://arxiv.org/pdf/2412.09057) (not read in full)

**Independent real-world evaluation and robustness**
- Ji, Lee, Koo, You, Choo, Kim, Kim (arXiv 2405.19598, v2 Jan 2025) tested 7 models on 451,514 real phishing sites. Only 110 of the 270 brands in the data are in the models' reference lists. Logo-based models lose 13-19 points when brands outside the list are included. Models also mislabel benign out-of-list sites as known brands (an open-set problem), and a legitimate Santander domain missing from the list was flagged as phishing — [arXiv HTML v2](https://arxiv.org/html/2405.19598v2)
- The same study found evasion by (1) attacking the model pipeline, (2) mimicking benign logos, and (3) simply removing the logo. Perturbation attacks (ViT black-box, PGD white-box) hurt Phishpedia and PhishIntention. Its recommendations: keep reference lists updated, include old logos, combine text (OCR) with visual signals, and use dynamic thresholds — [arXiv 2405.19598](https://arxiv.org/html/2405.19598v2)

### Inferences
- Reference-list coverage is the dominant variable. Going from 277 brands to about 20k brands roughly doubles recall at the same precision (KnowPhish). For Shoo, the list must cover the brands actually targeted in Indonesia: banks, e-wallets, couriers, marketplaces, government (BPJS, DJP, Dukcapil), and telcos. Global top brands are not enough. A few hundred well-curated Indonesian brand-to-official-domain entries is likely the right starting size, but no paper measures a country-specific list, so this is an estimate.
- Precision in these systems comes from the brand-domain inconsistency AND credential intent (CRP) gate together. PhishIntention reduced false positives by 86.5% by adding a CRP check. Shoo's form-field checks (PIN, OTP, password, card, CVV, KTP) are a CRP signal, so Shoo already has the "intent" half. The weak half is brand identification, which today relies only on `<img alt>`.
- Vision models (Faster R-CNN + Siamese) are fragile: logo removal drops PhishIntention to 0% detection. Text-based brand extraction (KnowPhish, PhishLLM) catches logo-less pages. That favors Shoo's text-first design (title, alt, labels) over adding a screenshot model.

### Gaps
- I could not open the exact precision and recall tables of the Phishpedia paper (181-brand version) or of DynaPhish (absolute numbers). The abstract-level claims above are what I could verify.
- No paper measures how many brands are "enough" for a single-country deployment. KnowPhish's Wikidata-based base may under-cover Indonesian banks and e-wallets; this is unverified.
- I did not verify VisualPhishNet's original in-paper accuracy numbers, only the independent re-tests.

## 2. Favicon / logo hashing (perceptual hash vs official brand favicon)

### Takeaway
Peer-reviewed evidence is thin. Favicon hashing is widely used in threat-intelligence tooling to cluster and hunt impersonating domains, but I found no large benchmark of false positives on legitimate sites. The one academic perceptual-hash system found (PhishSnap) reports only about 0.79 accuracy (secondary). Hashing is cheap and on-device-friendly, but it is a weak signal alone and easy to evade with a pixel change or a missing favicon.

### Cited Findings
- PhishSnap ("Image-Based Phishing Detection Using Perceptual Hashing") hashes screenshots perceptually and compares them to known pages. It reports accuracy 0.79, precision 0.76, recall 0.78 on a 10,000-URL dataset, with scans under 1 s. Takedowns reduced the sample quality (secondary review; original paper not opened) — [Moonlight review](https://www.themoonlight.io/en/review/phishsnap-image-based-phishing-detection-using-perceptual-hashing)
- Google Threat Intelligence / VirusTotal documents hunting domains that share a brand's favicon dhash, filtered by malicious verdict, for brand monitoring — [GTI docs](https://gtidocs.virustotal.com/docs/use-cases-phishing-brand-monitoring)
- Silent Push uses Murmur3 favicon hashes to flag domains that reuse a brand's icon — [Silent Push docs](https://help.silentpush.com/docs/favicon-impersonation.md)
- A US patent (11483343) describes comparing page favicons with stored brand and phishing icons using ML plus exact hashes. It includes no independent evaluation — [USPTO](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11483343)
- Logo-based visual models were the ones most sensitive to visible logo edits (removal, rotation, scaling) — [Ji et al., arXiv 2405.19598](https://arxiv.org/html/2405.19598v2). Hash matching is weaker than learned matching against such edits (inference from the same mechanism).
- Phishing kits load logos dynamically through JavaScript instead of `<img>`, and they randomize input attributes. One example is a Meta campaign on `.click` domains — [PhishLLM §4.5](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf). This also limits `<img alt>`-based brand hints.

### Inferences
- An on-device favicon dHash/pHash match is a cheap "brand hint" feature: a 16x16 or 32x32 image, a 64-bit hash, and a Hamming distance against a small table of Indonesian brand favicon hashes, all a few KB. It should only raise suspicion when combined with domain mismatch plus a sensitive form field, never block alone.
- Risk: legitimate resellers, partners, and payment pages show bank logos (for example virtual-account payment pages showing BCA or Mandiri logos). Brand-match plus domain-mismatch without a credential field will cause false positives. Ji et al.'s open-set finding supports this.
- Technical caveat to verify: drawing a cross-origin favicon into a `<canvas>` taints it, so `getImageData` fails unless the image is CORS-enabled. Phishing kits usually self-host copied favicons (same-origin), so this may work in the common case. This is unverified for Safari content scripts.

### Gaps
- No peer-reviewed favicon-pHash benchmark with false positive rates on benign sites was found.
- I could not open the original PhishSnap paper (authors and venue unverified).
- The ">99.5% accuracy with favicon + DNS + PageRank" claim in a CTI blog ([andreafortuna.org](https://andreafortuna.org/2025/04/29/digital-breadcrumbs-tracking-threat-actors-through-favicon-hashes/)) traces to an unverified ResearchGate source. Do not use it.

## 3. LLM-based detection (2023-2026): accuracy vs cost vs latency, which input matters, prompt injection, small/on-device models

### Takeaway
Frontier LLMs and MLLMs reach about 92-99% F1 on curated sets when given HTML and/or a screenshot. GPT-4V (ChatPhishDetector) reports 98.7% precision and 99.6% recall. Pure-LLM detection degrades on harder real-world sets (GPT-4o fell to 83.5% accuracy on SG-SCAN). Hybrid designs work better: the LLM extracts the brand and credential intent, and a deterministic check compares that brand with the domain (PhishLLM, PhishAgent, KnowPhish). Latency is about 1.2-7 s per page and LLM cost about USD 1-6 per 1K pages (2024 prices). Prompt injection from page text is real: recall dropped 0.89 without input encapsulation and only 0.01 with it. Small open models (8-70B) reach F1 0.86-0.89 on raw HTML, and 1-1.5B models failed to produce usable output.

### Cited Findings
**Accuracy**
- Koide, Fukushi, Nakano, Chiba. "Detecting Phishing Sites Using ChatGPT" (arXiv 2306.05816, 2023), published as ChatPhishDetector in IEEE Access (Jan 2024). It feeds a crawled page (URL, HTML, OCR text, optionally a screenshot) with a chain-of-thought prompt. Results: GPT-4 text mode 98.3% precision / 98.4% recall, GPT-4V 98.7% / 99.6%, GPT-3.5 recall 86.7% — [arXiv](https://arxiv.org/abs/2306.05816v3); [IEEE Access via DOAJ](https://doaj.org/article/65167bb3a0cf49c8a73e53024b029787)
- Lee, Lim, Hooi, Divakaran (eCrime 2024) built a two-phase pipeline: the MLLM first identifies the brand, then checks the domain. Dataset: 4,480 pages, 1,882 brands. F1: GPT-4 about 0.92, Claude 3 about 0.90, Gemini Pro 1.0 about 0.81. Adding the domain-check phase raised Claude's (screenshot-only) recall from about 65% to about 92% — [arXiv 2408.05941](https://arxiv.org/html/2408.05941v1)
- PhishAgent (AAAI 2025): the GPT-4o pure-MLLM baseline got 95.8% accuracy on TR-OP but 83.5% on SG-SCAN-1k. The agent with a knowledge base and recheck held at about 94-96% — [arXiv 2408.10738](https://arxiv.org/html/2408.10738v3)
- "Adaptive Linguistic Prompting (ALP) Enhances Phishing Webpage Detection in MLLMs" (2025) tests GPT-4o and Gemini 1.5 Pro with structured prompting (not read in full) — [arXiv 2507.13357](https://arxiv.org/html/2507.13357v1)

**Which input matters**
- GPT and Gemini performed best with screenshot + HTML. Claude 3 performed best with screenshot only. Gemini with HTML only had about 63.6% precision. HTML token counts have extreme outliers (up to about 30x the mean) versus 5-6x for screenshots, so HTML cost is less predictable — [Lee et al., eCrime 2024](https://arxiv.org/html/2408.05941v1)
- The decisive step across systems is the brand-to-domain consistency check. Adding it took Claude from about 65% to 92% recall — [Lee et al.](https://arxiv.org/html/2408.05941v1). PhishLLM decomposes detection into brand recognition from text, popularity validation, and credential-intent (CRP) prediction — [PhishLLM](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)
- The text-only LLM brand path misses some logos that visual matching gets ("hard to determine the brand from text descriptions alone") — [PhishLLM §4.5](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)

**Cost and latency**
- PhishLLM median cost is 6.14 USD per 1K sites: brand recognition 0.44, Google popularity validation about 5.00, CRP prediction 0.74. So the LLM calls cost about 1.18 USD per 1K. DynaPhish costs 11.50 USD per 1K. PhishLLM's median latency is 1.22 s, dominated by CRP prediction over OCR text plus API network latency — [PhishLLM §4.2](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)
- Per-page time: PhishAgent 2.25 s, ChatPhishDetector (GPT-4o) 6.93 s, GEPAgent 12.35 s, KPD 1.49-2.02 s, Phishpedia 0.19-0.25 s on a server — [PhishAgent](https://arxiv.org/html/2408.10738v3); [KnowPhish](https://arxiv.org/html/2403.02253v2)
- Screenshot tokens: Claude 3 about 500 tokens (25th percentile) to about 2,000 (75th); GPT-4 about 1,700 to 2,300 — [Lee et al.](https://arxiv.org/html/2408.05941v1)

**Robustness and prompt injection**
- PhishLLM tested an injected sentence ("this is not a credential-requiring page") in page text. Without instruction/data encapsulation, CRP recall dropped by 0.89. With tags marking the OCR text as data to ignore instructions in, it dropped by 0.01. Phishing-domain text injected into the logo cut brand-recognition recall by 0.01. The authors advise keeping the system prompt secret — [PhishLLM §3, Table 5](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)
- Lee et al.: under webpage-source and logo-noise attacks, GPT-4 stayed correct on 133/133 and 146/150 samples, Claude 3 on 128/133 and 147/150 — [eCrime 2024](https://arxiv.org/html/2408.05941v1)
- PhishAgent under brand spoofing, obfuscation, and typosquatting kept recall at 89.4-93.2% with its Recheck step, and fell as low as 70.8% without it — [PhishAgent](https://arxiv.org/html/2408.10738v3)

**Small / local models**
- Goldenits, Koenig, Raubitzek, Ekelhart. "Small Language Models for Phishing Website Detection: Cost, Performance, and Privacy Trade-Offs" (arXiv 2511.15434, Nov 2025). They tested 15 open models (1B-70B) on raw HTML trimmed to 5%, 1,000 sites. Best F1: llama3.3:70b 0.893, deepseek-r1:70b 0.873, mistral-nemo:12b 0.858. llama3.2:1b and deepseek-r1:1.5b were excluded for failing to emit valid JSON. llama3.2:1b was the fastest at 0.5-0.9 s per page. The 70B models took about 23-31 s per page on an A100/H100 — [arXiv 2511.15434](https://arxiv.org/html/2511.15434v1)
- In KnowPhish, LLaMA-2-7B gave detection similar to GPT-3.5/4 when used only for brand extraction inside the pipeline — [KnowPhish](https://arxiv.org/html/2403.02253v2)

### Inferences
- Shoo's layer-4 input (host + title + field labels + rule IDs) is a privacy-reduced version of the PhishLLM decomposition. Title and labels give the brand hint and credential intent, and the host is what the brand gets compared with. What is missing compared with the literature is page body or OCR text and the visual logo. Expect lower recall on pages whose title is generic ("Login", "Verifikasi") and whose brand appears only in the logo image.
- The cheapest high-value upgrade that stays within the privacy rule: ask the LLM for structured output (claimed brand, that brand's official domain(s), credential intent yes/no). Then do the brand-domain comparison in code, not in the LLM's free-text verdict. Validate the claimed official domain against a server-side Indonesian allowlist instead of Google search. This copies the PhishLLM and Lee et al. two-phase design, which gave the largest recall gains.
- Title and field labels are attacker-controlled, and the prompt-injection result applies directly. Wrap them in delimited data blocks, cap their length (already 120 chars / 12 labels), strip instruction-like text, and never let the LLM output alone downgrade a strong on-device verdict.
- On-device LLMs are not practical in an iOS Safari extension: 1-1.5B models failed basic output formatting even on servers. A server-side small model (8-12B) on Workers AI could replace a frontier API to cut cost, at roughly F1 0.86 on full HTML (lower expected on Shoo's sparse inputs). This is an inference; it was not measured on Shoo's input format.

### Gaps
- No paper measures LLM detection with ONLY title + host + form labels (Shoo's format). Accuracy on that input is unknown and needs an internal eval.
- I did not verify "ChatSpamDetector" (Koide et al.); it targets email, not websites.
- I found no 2025-2026 per-page USD costs for current models such as GPT-4o-mini, Claude Haiku, or Gemini Flash. The 2024 figures above use older pricing.

## 4. Text / NLP content approaches (urgency language, brand mention vs domain, transformers), especially non-English / Indonesian

### Takeaway
Text-based brand extraction plus a credential-intent classifier is now standard inside reference-based systems. Multilingual transformers (XLM-RoBERTa) and LLMs handle non-English pages reasonably, but no web-phishing paper evaluates Indonesian pages specifically. Indonesian-language evidence exists only for email (IndoBERT) and URL rules.

### Cited Findings
- KnowPhish uses an XLM-RoBERTa text classifier for credential-requiring pages and an LLM for brand extraction from HTML text. Its Wikidata aliases include names in many languages. Non-English pages were not evaluated separately — [KnowPhish](https://arxiv.org/html/2403.02253v2)
- PhishLLM uses PaddleOCR (over 80 languages) plus an LLM. Of 1,340 phishing pages found, 67% were English, 5% German, 4% Spanish, 3% Chinese. Phishers prepare multilingual copies of the same kit — [PhishLLM §4.5.3](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)
- An Indonesian-language phishing email detector (IndoBERT or FastText features with CNN/LSTM) reached 98.44% accuracy. It covers email headers, not web pages — ["Enhancing detection of zero-day phishing email attacks in the Indonesian language using deep learning algorithms", Bulletin of EEI](https://beei.org/index.php/EEI/article/view/8759) (numbers via search summary)
- Ji et al. recommend combining text recognition with visual analysis because logo-only models miss logo-less pages — [arXiv 2405.19598](https://arxiv.org/html/2405.19598v2)

### Inferences
- Shoo's urgent-phrase list is a hand-built version of the text signal. The literature's more robust text signal is "brand named in text, not owned by host" plus "credential intent", rather than urgency words alone. Urgency is common on legitimate promo pages too. No paper quantifies the false positive rate of an urgency word list.
- IndoBERT or multilingual MiniLM-class models could classify title + labels server-side. A distilled model in the browser is theoretically possible but not proven on iOS Safari (see section 6).

### Gaps
- No Indonesian web-phishing page-text benchmark was found. No paper measures urgency-lexicon precision for Indonesian.

## 5. Indonesian-specific scam patterns and datasets

### Takeaway
Academic literature on Indonesian phishing websites is small. It consists mostly of URL-feature and rule-based studies in local journals with small datasets. I found no academic dataset of Indonesian bank, e-wallet, courier, or "undangan pernikahan" APK scam pages.

### Cited Findings
- A rule-based Indonesian phishing-website detector using multi-layer URL filtering ("IndoPhis-D") reports 98.99% accuracy on 6,112 `.id` URLs validated by Indonesia's national cyber authority (80:20 split). The source attribution is from a search summary; I could not open the full text — [Telkom University repository](https://repository.telkomuniversity.ac.id/pustaka/245173/adaptive-rule-based-detection-of-indonesian-phishing-website-through-multi-layered-filtering-based-on-url-features-dalam-bentuk-buku-karya-ilmiah.html); possibly also [IJEECS](https://ijeecs.iaescore.com/index.php/IJEECS/article/download/37209/18732)
- An Indonesian URL + content-feature study used about 102 legitimate and 364 phishing sites — [ITS Scholar](https://scholar.its.ac.id/en/publications/classification-model-based-on-url-and-content-feature-approach-fo/) (via search summary)
- An Indonesian paper cites PANDI (the .id registry) as recording 34,622 phishing cases over 5 years. I could not confirm which paper or the original PANDI source — search summary only

### Inferences
- Indonesian scam variety (APK "undangan pernikahan" or courier-receipt files sent over WhatsApp, fake bank or e-wallet "verifikasi" pages that ask for OTP, PIN, or KTP) leans toward credential and KYC harvesting. Shoo's form-field checks (OTP, PIN, KTP, selfie-with-KTP) match this better than visual similarity does. APK-delivery scams have no web form to analyze, so detection must rely on URL and host plus download behavior; this is outside the visual and LLM literature.

### Gaps
- No academic dataset was found for Indonesian bank, e-wallet, or courier phishing pages, or for APK wedding-invite scams. OJK, Kominfo/Komdigi, IASC, or APWG Indonesia statistics were not researched here; that belongs to another note. KnowPhish's coverage of Indonesian brands is unknown.

## 6. Practicality for an iPhone Safari Web Extension + Cloudflare Workers server layer (on-device vs server, data leaving the phone)

### Takeaway
iOS Safari 15+ supports `tabs.captureVisibleTab` (per MDN browser-compat-data), and Safari 26 ships WebGPU on iOS. So screenshot capture and GPU inference are technically available. But WebKit has documented WebAssembly memory instability on iOS, and Apple documents no memory budget for extension background pages. Running a Phishpedia-class detector (Faster R-CNN + Siamese, GPU server at 0.2 s per page) in an iOS extension is unproven and risky. The practical split: cheap text, DOM, and favicon-hash signals on device, and brand-domain reasoning on the server using only already-allowed metadata. Screenshot or HTML upload would break Shoo's privacy rule.

### Cited Findings
- `tabs.captureVisibleTab` is supported in Safari 14 (macOS) and Safari on iOS 15. Notes: the default format is JPEG and `<all_urls>` is optional. `tabs.captureTab` is not supported — [MDN browser-compat-data, webextensions/api/tabs.json](https://github.com/mdn/browser-compat-data/blob/main/webextensions/api/tabs.json); [MDN captureVisibleTab](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/tabs/captureVisibleTab)
- The API needs the `<all_urls>` or `activeTab` permission — [MDN](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/tabs/captureVisibleTab)
- Manifest V3 `content_security_policy.extension_pages` is supported from Safari 15.4 (iOS mirrors it) — [MDN BCD, manifest/content_security_policy.json](https://github.com/mdn/browser-compat-data/blob/main/webextensions/manifest/content_security_policy.json). I did not find whether Safari accepts `'wasm-unsafe-eval'` in extension CSP.
- WebGPU "is now shipping in Safari 26.0 for macOS, iOS, iPadOS, and visionOS" — [WebKit, "WebKit Features in Safari 26.0"](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/). The post says nothing about WebGPU or WebAssembly in extension contexts.
- WebKit bug 269777: only about 300 MB of RAM is reliably available to WebAssembly pages; on one iPhone Xs, allocation fell as low as 28 MB after reload — [WebKit Bugzilla 269777](https://bugs.webkit.org/show_bug.cgi?id=269777). Bug 221530: when `memory.grow()` exceeds limits, Safari kills or reloads the tab instead of failing gracefully — [WebKit Bugzilla 221530](https://bugs.webkit.org/show_bug.cgi?id=221530). Both concern normal pages, not extension background pages.
- Reference model costs on a server: Phishpedia about 0.16-0.25 s per page; PhishAgent's retriever needs about 1.6 GB of GPU memory — [KnowPhish](https://arxiv.org/html/2403.02253v2); [PhishAgent](https://arxiv.org/html/2408.10738v3)

### Per-approach feasibility (inference, based on the findings above)
| Approach | On device in iOS Safari? | Needs server? | Data leaving phone | Evidence of value |
|---|---|---|---|---|
| Brand-domain consistency from text hints (alt, title, og:site_name, label text) against an Indonesian brand allowlist | Yes (pure JS, small table) | Optional (list updates) | None | High: core of KnowPhish and PhishLLM; list coverage drives recall |
| Favicon dHash/pHash vs brand table | Likely yes (canvas + 64-bit hash; cross-origin taint unverified) | No | None | Low to medium; no benign false positive benchmark |
| Credential-intent (CRP) from form fields | Yes (already in Shoo) | No | None | High: PhishIntention cut false positives 86.5% |
| Logo detection CNN on screenshot (Phishpedia/PhishIntention style) | Unproven: captureVisibleTab exists (iOS 15+), but model size, WASM memory instability, and background lifetime are risks | Practically yes | The screenshot (breaks privacy rule) if done on server | Medium; fragile to logo removal (0-9% detection) |
| LLM on host + title + labels (current layer 4) | No | Yes | Host, title (<=120), <=12 labels, rule IDs (current) | Unmeasured for this input; the two-phase brand-then-domain design is the best-evidenced pattern |
| MLLM on screenshot + HTML (ChatPhishDetector, PhishAgent) | No | Yes | Full HTML and/or screenshot (may contain PII, account numbers) | High (95-99% on curated sets) but conflicts with privacy rule; 2-7 s per page |
| On-device small LLM (1-3B) | Not realistic: 1-1.5B failed JSON output even on servers | No | None | Poor |
| Server-side open 8-12B model (Workers AI-class) | No | Yes | Same as current layer 4 | F1 about 0.86 on HTML (mistral-nemo 12B); lower expected on sparse input |

### Inferences
- The best evidence-backed improvement that keeps the privacy rule is to strengthen brand identification on device: favicon hash, `og:site_name`, title tokens, and visible brand words in text. Pair it with a curated Indonesian brand-to-official-domain table and keep the CRP (form-field) gate. Send only the derived claimed-brand ID plus host to the server, not page text. This is the KnowPhish/PhishLLM recipe without the screenshot.
- If a screenshot path is ever considered, it should run fully on device (WebGPU, Safari 26+) and send only a brand ID. Uploading screenshots contradicts the privacy rule, and a screenshot can contain account numbers, OTP, or KTP data.

### Gaps
- No Apple or WebKit documentation was found stating the memory limit or lifetime of iOS Safari extension background pages or service workers. Whether WebAssembly, `'wasm-unsafe-eval'`, ONNX Runtime Web, or TensorFlow.js work in an iOS Safari extension context is unverified (not in MDN BCD or the WebKit Safari 26 post). This needs a device test.
- Whether WebGPU is exposed to extension background or content-script contexts on iOS 26 is unverified.
- Whether `captureVisibleTab` works from a non-persistent MV3 background on iOS without a user gesture (activeTab semantics) is unverified. MDN only lists support from iOS 15.
