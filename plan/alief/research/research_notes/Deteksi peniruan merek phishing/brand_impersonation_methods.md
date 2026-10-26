# Brand-impersonation ("reference-based") phishing detection: methods, measured accuracy, failure modes, inputs, and on-device feasibility for Shoo

Scope note: researched 2026-10-26. Primary PDFs were downloaded and read as text for Phishpedia, PhishIntention, DynaPhish, KnowPhish, PhishLLM, Ji et al. (USENIX Sec 2025), VisualPhishNet, Oest et al. "Sunrise to Sunset", PhishEye, Bijmans et al., Cui et al., PhishIntel, and Mishra & Varshney. Abstracts only (via OpenAlex or Semantic Scholar) were read for CANTINA, CANTINA+, Geng et al. (favicon), Chiew et al. (favicon), Hao et al. CCS 2021, and Kondracki et al. CCS 2021. "(calc)" marks a number I derived from the paper's own counts. "[older]" marks pre-2019 seminal work. This note builds on `../Fitur deteksi situs phishing/visual_llm.md` and `html_headers_redirect.md`, and corrects them where marked **Correction**.

Target scenario: a pixel-perfect Microsoft login clone on an unrelated domain. It uses the real Microsoft favicon and the real field ids (`loginfmt`, `i0116`, `i0118`, `idSIButton9`), and it loads assets from a third-party domain. Microsoft is the single most-impersonated brand in these datasets (see Q1).

## Q1. Reference-based visual/brand detectors (VisualPhishNet, Phishpedia, PhishIntention, DynaPhish, KnowPhish, PhishLLM, follow-ups): exact metrics, the CRP gate, and how brand-domain consistency is checked

### Takeaway
Every strong system uses the same rule: a page is phishing if (1) it shows brand X, (2) it asks for credentials (a CRP, credential-requiring page), and (3) its domain is not one of X's legitimate domains. Brand alone gives many false positives, because legitimate pages show other brands' logos (SSO buttons, ads, templates). Phishpedia's field precision fell from 93.6% to 66.7% once those pages were included. A CRP alone is not a verdict either, because every real login page is a CRP. Adding the CRP gate (PhishIntention) cut field false positives by 86.5%. Recall then depends on how many brands the reference list covers and how well it handles new brands: about 40% with 277 brands, and 69-87% with dynamic or 20k-brand knowledge. An independent USENIX Sec 2025 study shows that real-world detection is far below lab numbers, and that removing the logo defeats the logo-only models.

### Cited Findings
**Detection rule, CRP definition, and brand-domain check**
- PhishIntention defines the rule: an alert fires when a page "(1) intends to take credential, (2) conveys brand intention of a company r, while (3) its domain does not align with that of r". For each protected brand it keeps "its logos and legitimate domains". In the algorithm, a page is benign if the brand is null or `url.domain ∈ brand.domains`, and phishing only if `is_CRP` is true and the domain ∉ `brand.domains`. — [Liu, Lin, Yang, Ng, Divakaran, Dong, "Inferring Phishing Intention via Webpage Appearance and Dynamics: A Deep Vision Based Approach", USENIX Security 2022](https://www.usenix.org/system/files/sec22-liu-ruofan.pdf)
- Distribution of CRPs in about 29.5K phishing pages (PhishIntention Table 1): 86.1% (25,403) ask for credentials directly, 11.2% (3,310) link to a CRP (a login or sign-up button), 2.4% (704) use "non-textual credential" flows such as QR codes or CAPTCHA, and 0.3% are feed false positives. This is why PhishIntention adds a CRP locator plus click emulation for non-CRP landing pages. — [PhishIntention](https://www.usenix.org/system/files/sec22-liu-ruofan.pdf)
- Why brand alone over-fires: "Benign webpages may refer to the big social media companies (e.g, Facebook) for login and registration via single sign-on method, article sharing, or advertisement promotion". Figure 2 shows Phishpedia flagging a benign page as Instagram phishing because of a top-right Instagram logo. Figure 12 shows Phishpedia matching an NSK text logo to Visa. — [PhishIntention](https://www.usenix.org/system/files/sec22-liu-ruofan.pdf)
- Why a heuristic HTML CRP check is not enough: "Defining HTML-based heuristics (e.g., looking for specific HTML forms) can serve as a classifier for CRP. However, it is easy to be bypassed by HTML obfuscation attack". PhishIntention therefore uses a vision-based CRP classifier (screenshot plus layout channels). — [PhishIntention](https://www.usenix.org/system/files/sec22-liu-ruofan.pdf)
- [older] CANTINA+ already used a "login form filter, which directly classifies Web pages with no identified login form as legitimate", together with a hash-based near-duplicate phish detector. Results: over 92% TP on unique phish, over 99% TP on near-duplicates, about 0.4% FP (randomized evaluation), and about 1.4% FP in a time-based evaluation; corpus 8,118 phish and 4,883 legitimate pages. — [Xiang, Hong, Rose, Cranor, "CANTINA+", ACM TISSEC 14(2), 2011, DOI 10.1145/2019599.2019606](https://doi.org/10.1145/2019599.2019606)
- Ways the brand-domain check is done:
  - Phishpedia: a static per-brand "list of logo variants and a list of legitimate domains" — [Phishpedia](https://www.usenix.org/system/files/sec21fall-lin.pdf).
  - DynaPhish: "popularity validation". Conditions include the page being indexed by Google, search metadata, and WHOIS data; new brand-domain pairs are added only if they pass — [DynaPhish](https://www.usenix.org/system/files/usenixsecurity23-liu-ruofan.pdf).
  - KnowPhish: about 20k brands with logos, aliases, and domains built from Wikidata — [KnowPhish](https://www.usenix.org/system/files/usenixsecurity24-li-yuexin.pdf).
  - PhishLLM: the LLM proposes the brand's domain, and Google-search popularity validation controls hallucination — [PhishLLM](https://www.usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf).

**VisualPhishNet (CCS 2020), whole-screenshot similarity**
- Triplet CNN (VGG16 base). The VisualPhish dataset covers 155 trusted websites with 9,363 screenshots and 1,195 phishing pages. Best result: top-1 match 81.03%, ROC AUC 0.9879, but the partial ROC area at a 1% FPR cut-off is only 0.0087 (maximum possible 0.01). Adding 32 SimilarWeb sites (187 total) lowered results to 78.3% and 0.9764. — [Abdelnabi, Krombholz, Fritz, "VisualPhishNet", ACM CCS 2020, DOI 10.1145/3372297.3417233](https://arxiv.org/pdf/1909.00300). **Correction:** the earlier note listed these in-paper numbers as a gap.

**Phishpedia (USENIX Sec 2021), logo detection plus Siamese matching**
- Pipeline: Faster R-CNN (ResNet50 backbone) detects the identity logo and input boxes; a Siamese model compares the logo to the reference logos. Target list: 181 brands, "covering 99.1% of phishing attacks" in their data. Top 100 brands cover 95.8% of about 30K OpenPhish pages. Top brands: Microsoft (7,962), PayPal (4,811), Chase (1,085), Facebook (993), Amazon (807). — [Lin et al., "Phishpedia: A Hybrid Deep Learning Based Approach to Visually Identify Phishing Webpages", USENIX Security 2021](https://www.usenix.org/system/files/sec21fall-lin.pdf)
- Lab results (about 30K phishing and about 30K Alexa benign pages, Table 2):

  | Method | Identification | Precision | Recall | Time per page |
  |---|---|---|---|---|
  | Phishpedia | 99.2% | 98.2% | 87.1% | 0.19 s |
  | EMD_more_ref | 96.7% | 89.0% | 74.4% | 15.6 s |
  | PhishZoo | 28.5% | 68.9% | 81.8% | 18.2 s |
  | LogoSENSE | 37.8% | 20.5% | 26.9% | 27.2 s |

  Capturing the screenshot adds about 1.88 s per URL. — [Phishpedia](https://www.usenix.org/system/files/sec21fall-lin.pdf)
- Logo presence: of 5,000 sampled phishing pages, only 70 had no logo, so "the ratio of phishing webpages with logos is about 98.6%". — [Phishpedia](https://www.usenix.org/system/files/sec21fall-lin.pdf)
- 30-day CertStream field study (Sep 10 – Oct 9, 2020): 1,820 reports, of which 1,704 were real phishing (precision 93.6%, calc). 1,133 were not flagged by any VirusTotal engine, 74.6% were still unflagged a week later, and they spanned 88 brands. Baselines on 1,000 top-ranked reports found few real phish: URLNet 13, StackModel 9, PhishZoo 8, EMD 3, PhishCatcher 5. — [Phishpedia §6, Table 9](https://www.usenix.org/system/files/sec21fall-lin.pdf). **Correction:** the PDF body says 1,133, which resolves the 1,113 vs 1,133 conflict in the earlier note.
- Measured false positives on benign pages that show big-brand logos:
  - Main causes: cPanel/webmail template pages that keep the default logo, and benign pages showing Google, Facebook, or LinkedIn logos "for the purposes of advertisement or Single Sign-On (SSO)".
  - In 131,975 CertStream URLs, 47 pages (0.036%) showed such logos. Phishpedia flagged 7 of them, and only 4 were real phishing, so precision on this subset was about 4/7 (fractions garbled in the PDF text).
  - On a PhishCatcher-filtered subset: Phishpedia precision 87.50%, recall 87.50%; VirusTotal 28.00% / 43.75%.

  — [Phishpedia §6.4.2, Table 10](https://www.usenix.org/system/files/sec21fall-lin.pdf)
- "Plausible URL/domain is not a strong indicator for phishing": PhishCatcher (name-plausibility scoring) reported 1,421,323 URLs, but only 5 of its top 1,000 were real phishing. — [Phishpedia §6.4.1](https://www.usenix.org/system/files/sec21fall-lin.pdf)

**PhishIntention (USENIX Sec 2022), brand intention plus credential intention plus dynamic CRP search**
- Reference list: 277 brands, 3,061 logos (and 9,334 screenshots for the screenshot baselines). At FPR 10⁻³, recall is 0.9, "more than twice the recall of Phishpedia". At recall 0.9, the FPR is about 10⁻³ versus about 10⁻¹ for Phishpedia. Mean/median runtime is 0.58 s / 0.69 s (as printed), versus Phishpedia 0.39 / 0.41 s and VisualPhishNet 0.26 / 0.23 s. — [PhishIntention §6.3](https://www.usenix.org/system/files/sec22-liu-ruofan.pdf)
- "Misleading legitimacy" adversary: on 3,049 benign pages built to look like brand pages, baselines reached a 45.5–60.1% FPR, and PhishIntention 5.10%. — [PhishIntention §9.2](https://www.usenix.org/system/files/sec22-liu-ruofan.pdf)
- Two-month field study (from April 2021):

  | | Reports | True positives | Precision (calc) | Not in VirusTotal |
  |---|---|---|---|---|
  | PhishIntention | 2,081 | 1,942 | 93.3% | 1,368 |
  | Phishpedia | 3,104 | 2,071 | 66.7% | 1,514 |

  That is 139 vs 1,033 false positives (86.5% fewer) for about 6% fewer true positives. — [PhishIntention §10.2](https://www.usenix.org/system/files/sec22-liu-ruofan.pdf)

**DynaPhish (USENIX Sec 2023), dynamic reference expansion plus counterfactual interaction for brandless pages**
- Motivation: a predefined reference list "can become obsolete by 31.3%" in 15 days, and about 1.5% of phishing pages are brandless. Brandless pages are tested by submitting fake credentials and watching for "evasion intention" (for example, a redirect to the original domain). — [Liu, Lin, Zhang, Lee, Dong, "Knowledge Expansion and Counterfactual Interaction for Reference-Based Phishing Detection", USENIX Security 2023](https://www.usenix.org/system/files/usenixsecurity23-liu-ruofan.pdf)
- Lab results on DynaPD (6,344 live phishing kits), Table 2. With 3,903 added references:

  | Configuration | Precision | Recall |
  |---|---|---|
  | PhishIntention alone | 99.85% | 40.98% |
  | PhishIntention + DynaPhish | 99.84% | 68.63% |
  | Phishpedia alone | 99.86% | 44.80% |
  | Phishpedia + DynaPhish | 98.97% | 74.04% |
  | Web interaction only | 100% | 43.00% |

  — [DynaPhish Table 2](https://www.usenix.org/system/files/usenixsecurity23-liu-ruofan.pdf)
- Wild study (precision and recall measured on a 3K sample, Table 6):

  | Configuration | Precision | Recall | Real phish found |
  |---|---|---|---|
  | PhishIntention | 1.00 | 0.10 | 127 |
  | Phishpedia | 1.00 | 0.05 | 137 |
  | PhishIntention + DynaPhish | 1.00 | 0.71 | 1,327 |
  | Phishpedia + DynaPhish | 0.56 | 0.79 | 1,366 |
  | VirusTotal | 0.01 | 0.02 | 36 |

  Top targets moved from Microsoft, Facebook, and Apple (days 1–5) to Cisco, Microsoft, and SonicWall (later days). — [DynaPhish Tables 6–7](https://www.usenix.org/system/files/usenixsecurity23-liu-ruofan.pdf). **Correction:** the earlier note had no absolute DynaPhish numbers; these fill that gap.
- Cost: about 13.36 s per sample including Google Search API calls — [Ji et al. 2025, Table 4](https://www.usenix.org/system/files/usenixsecurity25-ji.pdf).

**KnowPhish (USENIX Sec 2024) and PhishLLM (USENIX Sec 2024), LLM and knowledge-based brand identification from text**
- KnowPhish:
  - Knowledge base of about 20k brands from Wikidata. KPD (its detector) also extracts the brand from HTML text with an LLM, so it catches logo-less pages.
  - On TR-OP: Phishpedia recall rises from 40.16% (277 brands) to 72.80% when given the KnowPhish base. KPD + KnowPhish reaches precision 97.84% and recall 86.90%.
  - Singapore field study: KPD + KnowPhish precision 97.42%; Phishpedia with its original list 31.48%. The field gain "mainly comes from the detection of logo-less phishing webpages".

  — [Li et al., "KnowPhish", USENIX Security 2024](https://www.usenix.org/system/files/usenixsecurity24-li-yuexin.pdf) (numbers as in the earlier note, confirmed in the arXiv version)
- KnowPhish robustness (Table 5): rendering page text as images ("Text-to-Image") cut LLM brand-extraction accuracy from 81.00% to 5.00%, and text-CRP accuracy from 92.50% to 0.00%. With a multimodal defense, the two recovered to 60.00% and 70.00%. A prompt-injection suffix cut brand extraction to 55.50% (63.50% with defense). — [KnowPhish Table 5](https://www.usenix.org/system/files/usenixsecurity24-li-yuexin.pdf)
- PhishLLM: no predefined list; brand-to-domain knowledge comes from the LLM, checked by Google popularity validation.
  - Field results: 1,340 phishing reports versus 178 (Phishpedia) and 107 (PhishIntention). 1,105 of them targeted brands outside the static reference list.
  - Small field study: precision 0.96, median 1.22 s.
  - Stated evasions: "Dynamic Logo Loading" via JavaScript, multilingual kit copies, and phishing on compromised legitimate domains that pass popularity checks.

  — [Liu et al., "Less Defined Knowledge and More True Alarms", USENIX Security 2024](https://www.usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)

**Follow-ups 2024–2026**
- PhishIntel (WWW Companion 2025, DOI 10.1145/3701716.3715192) is a deployment architecture. A fast path checks local blacklists and a result cache; a slow path crawls the page and runs the reference-based detector. It addresses detector latency of "up to ten seconds" per URL. Deployments: a web platform and an Outlook plugin, not a browser extension. — [Li et al., "PhishIntel"](https://arxiv.org/pdf/2412.09057)
- PhishAgent (AAAI 2025, DOI 10.1609/aaai.v39i27.35003): MLLM agent with brand knowledge bases. TR-OP accuracy 96.10%; field precision 95.10%. — [arXiv 2408.10738](https://arxiv.org/html/2408.10738v3) (from earlier note)
- Ji, Lee, Koo, You, Choo, Kim, Kim, "Evaluating the Effectiveness and Robustness of Visual Similarity-based Phishing Detection Models", **USENIX Security 2025** (**Correction:** the earlier note cited this only as an arXiv preprint). It tested 7 models on 451k real phishing sites plus 2,500 Tranco benign pages.
  - Benign false positives: Phishpedia 406 (16.24%), VisualPhishNet 338 (13.52%), EMD 26.36%, PhishZoo 93.92%, PhishIntention 0, DynaPhish 0.
  - Under logo "Elimination", PhishIntention detected 0/110 in-list samples.
  - Model cost: Phishpedia 65.40M parameters / 212.35G FLOPs / 0.34 s; PhishIntention and DynaPhish 88.92M / 215.66G; VisualPhishNet 21.27M / 92.49G / 2.27 s.

  — [USENIX PDF](https://www.usenix.org/system/files/usenixsecurity25-ji.pdf); [presentation page](https://www.usenix.org/conference/usenixsecurity25/presentation/ji)
- I found no 2025–2026 reference-based detector at USENIX, NDSS, IEEE S&P, or CCS beyond Ji et al. (an evaluation study) and the venues above. Several 2025 LLM-agent variants are arXiv-only (PhishDebate 2506.15656, PhishIntentionLLM 2507.15419, ALP 2507.13357, MemoPhishAgent 2602.21394). They are unreviewed and not analysed here. — [search results](https://arxiv.org/pdf/2507.15419)

### Inferences
- For the target Microsoft clone, a reference-based detector fires on all three conditions: brand = Microsoft (logo, title, favicon), CRP = yes (an email/password form), and host ∉ Microsoft's domain list. This is the single best-evidenced verdict rule for this attack. Shoo already has the CRP half (sensitive-field detection). What it needs is a reliable brand signal plus a brand-to-official-domain table.
- The false-positive evidence argues for always requiring all three conditions. Brand + domain mismatch without a CRP is the "SSO button / ad / partner page" case, which produced Phishpedia's 16% benign false-positive rate and PhishIntention's 45–60% baseline false-positive rate on misleading pages.
- Microsoft is the number-one target in the Phishpedia (26.5% of about 30K, calc) and DynaPhish data. A hand-curated Microsoft entry (domains plus assets, see Q5) covers a large share of real attacks on its own. Coverage of Indonesian brands must be added by hand, because KnowPhish's Wikidata coverage of Indonesian banks and e-wallets is unverified (see the earlier note).

### Gaps
- No reference-based paper reports a false-positive rate measured on mobile browsing or on Indonesian sites.
- The Phishpedia "4/7 precision on the SSO-logo subset" fractions are garbled in the PDF text extraction. The numerator and denominator are inferred from the surrounding text ("four of them are real", "reports 7").

## Q2. Favicon and logo hashing or matching: evaluations, kit reuse of brand favicons and logos, and false positives on legitimate brand-logo pages

### Takeaway
Favicon-based brand identification has peer-reviewed support, but it is older. Geng et al. (eCrime 2013) [older] reported over 99.50% TPR at 0.15% FPR. Chiew et al. (2018) reported 96.93% TPR at 4.13% FPR. Both resolve the brand with an online lookup (PageRank/DNS or Google image search), not a local hash table. Phishing pages almost always carry a logo (98.6%), and kits copy brand assets so exactly that researchers fingerprint kits by brand-asset file paths. Perceptual hashes and learned logo matchers are both evadable: pHash by adversarial images (CCS 2021), logo matchers by adversarial or diffusion logos (up to 95% evasion; humans spot them at only 0.59). Exact-hash favicon matching has no published false-positive benchmark.

### Cited Findings
- [older] Geng, Lee, Thomas, Yates, "Favicon – a clue to phishing sites detection", APWG eCrime Researchers Summit 2013, DOI 10.1109/eCRS.2013.6805775.
  - Claim: the favicon is "widely used by phishers"; "only some lowest-quality phishing campaigns do not use such favicons".
  - Method: favicon detection and recognition finds suspicious brand sites, then "PageRank and DNS filtering" separates the sites with branding rights from fakes.
  - Results: 3,642 phishing cases with favicons and 19,585 legitimate pages gave "over 99.50% TPR and 0.15% FPR". A one-month live run reported 517 unique phishing URLs.

  — [abstract via OpenAlex](https://api.openalex.org/works/doi:10.1109/eCRS.2013.6805775); [Semantic Scholar](https://www.semanticscholar.org/paper/Favicon-a-clue-to-phishing-sites-detection-Geng-Lee/654e16b4391d74fc6dc05a07bc36d0a60a2aba2f)
- Chiew, Choo, Sze et al., "Leverage Website Favicon to Detect Phishing Websites", Security and Communication Networks 2018, DOI 10.1155/2018/7251750 (Hindawi/Wiley; lower-tier than the requested venues, flag). Method: the favicon goes to Google image search to "reveal the identity of a website", plus a "Domain Name Amplification" feature and fallback features when there is no favicon. Results on 5,000 PhishTank and 5,000 Alexa sites: 96.93% TPR, 4.13% FPR. — [DOI](https://doi.org/10.1155/2018/7251750); [abstract via OpenAlex](https://api.openalex.org/works/doi:10.1155/2018/7251750)
- Logos are nearly universal on phishing pages: 98.6% of 5,000 sampled pages had one — [Phishpedia §5.2.1](https://www.usenix.org/system/files/sec21fall-lin.pdf)
- Kits copy brand asset files verbatim. Bijmans et al. fingerprint kit families partly by asset paths. Example: a page resource `https://domain.com/rabobank/background.png` "matches fingerprint rabobank/background.png". A domain counts as a kit match when at least 10% of a fingerprint is found. — [Bijmans, Booij, Schwedersky, Nedgabat, van Wegberg, "Catching Phishers By Their Bait", USENIX Security 2021](https://www.usenix.org/system/files/sec21-bijmans.pdf)
- Anti-phishing systems already "use known filenames of scripts, images, favicons, and archives as one type of fingerprinting". Oest et al. argue this is why many phishing pages hot-link instead of self-hosting (see Q5). — [Oest et al., "Sunrise to Sunset", USENIX Security 2020 §8.2](https://www.usenix.org/system/files/sec20-oest-sunrise.pdf)
- Perceptual-hash robustness: black-box attacks on pHash and a robust variant "enlarge the hash distance to the original image while introducing minimal visual changes". The attack was highly successful against TinEye and Bing and moderately successful against Google and Yandex. — [Hao, Luo, Jan, Wang, "It's Not What It Looks Like: Manipulating Perceptual Hashing based Applications", ACM CCS 2021, DOI 10.1145/3460120.3484559](https://doi.org/10.1145/3460120.3484559)
- Learned logo matchers:
  - Generative adversarial logos evaded deep-learning logo detectors with "evasion rate of up to 95%", and users could not notice differences — [Lee, Xin, See, Sabharwal, Apruzzese, Divakaran, "Attacking logo-based phishing website detectors with adversarial perturbations", ESORICS 2023, DOI 10.1007/978-3-031-51479-1_9](https://doi.org/10.1007/978-3-031-51479-1_9).
  - LogoMorph: font swaps and diffusion-generated logo variants; human detection of the adversarial pages was 0.59 in a 150-person study — [Hao et al., "It Doesn't Look Like Anything to Me: Using Diffusion Model to Subvert Visual Phishing Detectors", USENIX Security 2024](https://www.usenix.org/conference/usenixsecurity24/presentation/hao-qingying).
- Simple logo edits also work. In Ji et al., logo Elimination left PhishIntention at 0/110 and Phishpedia at 10/110 (9.09%). Phishers also "bypass detectors by simply altering company name styles and stretching logos". — [Ji et al., USENIX Security 2025](https://www.usenix.org/system/files/usenixsecurity25-ji.pdf)
- False positives on legitimate pages that show brand logos (the key risk for "Sign in with Microsoft" or payment-logo pages):
  - Phishpedia: 16.24% of 2,500 Tranco benign pages — [Ji et al.](https://www.usenix.org/system/files/usenixsecurity25-ji.pdf).
  - Misleading legitimacy pages: 45.5–60.1% FPR for baselines, 5.10% for PhishIntention — [PhishIntention](https://www.usenix.org/system/files/sec22-liu-ruofan.pdf).
  - SSO and advertising logos are a named false-positive class — [Phishpedia §6.4.2](https://www.usenix.org/system/files/sec21fall-lin.pdf).
- Industry favicon-hash hunting (Shodan, Censys, VirusTotal dhash, Silent Push Murmur3) is vendor practice without peer-reviewed false-positive figures. See the earlier note. Context only. — [earlier note](../Fitur%20deteksi%20situs%20phishing/visual_llm.md)

### Inferences
- In the target scenario the clone uses Microsoft's real favicon. An exact hash (SHA-256 of the favicon bytes) or a 64-bit dHash of the decoded icon would match Microsoft's table entry exactly. This is a high-precision brand hint that is cheap on device. Its weaknesses are the published ones: a re-encoded or one-pixel-changed favicon breaks the exact hash, and an adversarial image breaks pHash (Hao et al.). Treat it as one brand-evidence source among several (favicon, title, logo alt or text, `og:site_name`, asset origin), never as the verdict.
- A favicon match without a CRP must not alert. Legitimate partner and SSO pages show Microsoft branding, and the logo-based false-positive rates above (13–16%) show what happens without the CRP gate.
- Geng and Chiew get their brand-ownership truth from online lookups (PageRank/DNS, Google image search). On device, Shoo needs that truth as a shipped brand-to-domain allowlist instead, which removes the privacy cost of a lookup.

### Gaps
- No peer-reviewed study (2019–2026) measures how often kits reuse the brand's byte-identical favicon or logo file, as opposed to a re-encoded copy. Geng's statement is qualitative.
- No peer-reviewed false-positive benchmark exists for exact or perceptual favicon-hash matching against benign sites that legitimately embed brand favicons or logos.
- I did not open the full Geng or Chiew papers. Their thresholds and per-brand behaviour are unknown.

## Q3. DOM/HTML similarity to the legitimate page, clone detection, and phishing-kit fingerprinting (including AiTM reverse-proxy kits)

### Takeaway
Most phishing pages are copies of earlier ones, so structural similarity works. Cui et al. found over 90% of 19,066 attacks were replicas or variants. A cheap 107-dimensional HTML tag-count vector detected them at 0.08% FPR on 24,800 legitimate sites. CANTINA+ caught near-duplicates at over 99% TP. Kit fingerprinting by asset paths and strings found 1,363 Dutch bank phishing domains, and 61 of 1,504 matches were false positives (4.1%). The approach only catches kits or targets you have a reference for, and it is evaded by DOM randomisation. AiTM reverse-proxy kits serve the real brand DOM, so DOM similarity is maximal by construction. They were detected through network-level features instead (99.9% accuracy), and the domain still mismatches the brand.

### Cited Findings
- [older, seminal] Cui, Jourdan, von Bochmann, Couturier, Onut, "Tracking Phishing Attacks Over Time", WWW 2017, DOI 10.1145/3038912.3052654.
  - Data: 19,066 PhishTank attacks over ten months; "over 90% of these attacks were actually replicas or variations of other attacks", in only 1,216 "flagged clusters".
  - Feature: a "tag vector" counting each of 107 HTML tags, compared with a proportional distance; optimal threshold about 0.32.
  - False positives: "Testing our method with 24,800 legitimate sites only yields 20 false positive (0.08%)".

  — [PDF](https://www.site.uottawa.ca/~bochmann/Curriculum/Pub/2017%20-%20Tracking%20phishing%20attacks%20over%20time.pdf); [DOI](https://doi.org/10.1145/3038912.3052654)
- [older] CANTINA+ near-duplicate filter (hashing): over 99% TP on near-duplicate phish — [TISSEC 2011](https://doi.org/10.1145/2019599.2019606)
- Bijmans et al. (USENIX Sec 2021):
  - Collected 70 kits from Telegram, grouped into 10 families, and fingerprinted them by file structure and landing-page strings.
  - Three-layer matching: (1) loaded resource paths, (2) page strings, (3) wFuzz probing for unlinked kit files.
  - Results: certificate-transparency scoring flagged 7,936 domains; fingerprints matched on 1,504; 61 were removed as false positives ("fingerprint not being specific enough" or servers answering every GET); 1,363 phishing domains were kept, with a median uptime of about 24 hours.

  — [Bijmans et al.](https://www.usenix.org/system/files/sec21-bijmans.pdf)
- Kit component reuse persists: in 1,300 kits (2020–2023), key page components were "very similar or even identical across kits", and 21.8% used no evasion (preprint, flag) — [Ousat et al., arXiv 2608.07451](https://arxiv.org/abs/2608.07451) (from earlier note)
- Evasion of DOM/attribute fingerprints: kits load the logo through JavaScript and randomise input attributes — [PhishLLM §4.5](https://www.usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf). PhishIntention notes that HTML obfuscation "preserving the website appearance" defeats HTML-heuristic CRP classifiers, so it moved to vision — [PhishIntention §9](https://www.usenix.org/system/files/sec22-liu-ruofan.pdf)
- Script behaviour differs from the original: phishing pages share only about 11% of their browser APIs with the brand login pages they copy (preprint, flag) — [Nahapetyan et al., arXiv 2509.13186](https://arxiv.org/html/2509.13186v2) (from earlier note)
- AiTM reverse-proxy kits: Kondracki, Azad, Starov, Nikiforakis, "Catching Transparent Phish: Analyzing and Detecting MITM Phishing Toolkits", ACM CCS 2021, DOI 10.1145/3460120.3484765.
  - Behaviour: the kits act as "malicious reverse proxy servers of online services, mirroring live content to users while extracting credentials and session cookies".
  - Detection: a classifier on "intrinsic network-level properties" reached 99.9% accuracy.
  - Scale: 1,220 MITM phishing sites captured over a year. Only 43.7% of their domains and 18.9% of their IPs were on blocklists.
  - Source conflict: an earlier poster by the same authors gives 98.9% accuracy and 348 sites, apparently a preliminary version. Use the CCS abstract figures.

  — [abstract via Semantic Scholar](https://api.semanticscholar.org/graph/v1/paper/DOI:10.1145/3460120.3484765?fields=title,abstract); [poster](https://www3.cs.stonybrook.edu/~grd/GRD-2021/posters/GRD_poster_kondracki%20-%20Brian%20Kondracki.pdf)
- Vendor context (not peer-reviewed): TLSH or ssdeep hashes of the post-script DOM cluster EvilProxy/Tycoon AiTM kit pages — [Obsidian Security blog](https://www.obsidiansecurity.com/blog/detecting-aitm-phishing-sites-with-fuzzy-hashing)

### Inferences
- The target clone keeps Microsoft's real field ids (`loginfmt`, `i0116`, `i0118`, `idSIButton9`). This is a DOM fingerprint of the Microsoft sign-in page itself. A rule like "Microsoft sign-in DOM signature present AND host ∉ Microsoft domains AND a password or email field" is a brand-identification signal in the spirit of Bijmans' string fingerprints. It identifies the brand from markup, not pixels, so it survives logo removal and text-to-image tricks that defeat KnowPhish and PhishIntention. It is cheap in a content script (a few `querySelector` calls). No paper measures this exact id-based rule. Expect very low false positives, because those ids should appear only on Microsoft-owned sign-in hosts. One exception to verify: Microsoft or partner embeds on customer domains (for example, custom-domain Entra branding) may reuse the same markup.
- The weakness is the one in PhishLLM: kits can randomise ids and attributes. So id fingerprints should raise brand evidence, not be required for it.
- A Cui-style tag vector over 107 tags is tiny and cheap. It could compare a page against a few shipped reference vectors (the Microsoft, Google, and Indonesian-bank login pages). Its published 0.08% FPR, however, was for "is a replica of a known phish", not "is similar to a brand's real page".
- AiTM proxies make DOM, favicon, and visual signals match perfectly. Only the brand-domain mismatch (with Microsoft branding on an unrelated host) or network and timing features separate them. A content script cannot see TLS fingerprints, so for AiTM the host-versus-brand check is the key signal.

### Gaps
- I found no peer-reviewed benchmark (2019–2026) of simhash, ssdeep, or TLSH DOM similarity against the brand's own legitimate page, with false-positive rates on benign pages that embed the brand's real widgets. The Q1 2026 tree-structured clustering preprint (arXiv 2608.16158) and PhishSim (arXiv 2207.10801) were not read and are unreviewed.
- I could not open CANTINA+'s near-duplicate threshold details or the Jail-Phish paper (Computers & Security 2019, DOI 10.1016/j.cose.2019.02.011). Its abstract was unavailable via OpenAlex.
- The Oest et al. eCrime 2018 paper "Inside a Phisher's Mind" ([APWG PDF](https://docs.apwg.org/ecrimeresearch/2018/5349207.pdf)) concerns `.htaccess` cloaking filters in kits. It was not read in full, and no brand-asset figures were extracted.

## Q4. Brand mention in title or text versus domain: measured effect

### Takeaway
Text-based brand extraction compared with the domain is what lifted recall most in the 2024 systems. KnowPhish's field gain "mainly comes from" logo-less pages caught by text brand extraction, and PhishLLM found 1,340 phish versus 178 for Phishpedia. Classic content methods (CANTINA, about 95% TP [older]) use the same idea with TF-IDF terms plus search. The big failure mode is text rendered as an image, which dropped LLM brand extraction from 81% to 5% accuracy. Domain-name plausibility alone (brand string in the URL) was nearly useless in Phishpedia's field test.

### Cited Findings
- [older] CANTINA (WWW 2007): TF-IDF content terms plus heuristics; "correctly labeling approximately 95% of phishing sites" — [Zhang, Hong, Cranor, WWW 2007, DOI 10.1145/1242572.1242659](https://doi.org/10.1145/1242572.1242659). The false-positive figure is not in the abstract.
- KnowPhish (USENIX Sec 2024): the LLM extracts the brand from HTML text. Ablation and field results are in Q1. The field improvement over image-only detectors "mainly comes from the detection of logo-less phishing webpages". Text attacks (Table 5):
  - Typosquatted brand text in the title: 78.00% brand-extraction accuracy; across all texts: 72.00%.
  - Text-to-Image rendering: 5.00% (60.00% with the multimodal defense).

  — [KnowPhish](https://www.usenix.org/system/files/usenixsecurity24-li-yuexin.pdf)
- PhishLLM: brand from OCR text and logo caption, then LLM brand-to-domain mapping plus popularity check. Recall 0.70 on a 3k field sample, versus 0.07 (Phishpedia) and 0.04 (PhishIntention). Text-only brand recognition misses some logo-only cases. — [PhishLLM](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf)
- Lee, Lim, Hooi, Divakaran (APWG eCrime 2024): with an MLLM, adding the explicit brand-then-domain check raised Claude 3 recall from about 65% to about 92% — [arXiv 2408.05941](https://arxiv.org/html/2408.05941v1) (from earlier note)
- URL plausibility versus content: PhishCatcher, which scores brand names in domains, had 5 real phish in its top 1,000 reports. Benign domains such as "amazoninnpousada.com" were flagged, and "we find less correlation between name plausibility and phishing suspiciousness" — [Phishpedia §6.4.1](https://www.usenix.org/system/files/sec21fall-lin.pdf). In Sunrise to Sunset, 28.70% of phishing URLs had "no deceptive content whatsoever" and only 27.90% had deceptive domains — [Oest et al. 2020](https://www.usenix.org/system/files/sec20-oest-sunrise.pdf)
- Mishra & Varshney, "A Study of Effectiveness of Brand Domain Identification Features for Phishing Detection in 2025" (listed as ACNS 2025 in search results; venue below the requested tier, read as arXiv 2503.06487, flag). Data: 4,667 legitimate and 4,561 phishing sites; five features coded 1 (match), −1 (mismatch), or 0 (absent): certificate CN, logo domain, form-action domain, most-common-link domain, cookie domain. Results:
  - Random Forest with all five: 99.7% accuracy at 0.08 s.
  - Single features: most-common-link domain 87.8%, logo domain 87.6%.
  - Best three-feature combinations: 99.8%.

  — [arXiv 2503.06487](https://arxiv.org/pdf/2503.06487)
- PhiUSIIL (Computers & Security 2024) includes `URLTitleMatchScore` (title versus URL). Its individual importance was not verified — [earlier note](../Fitur%20deteksi%20situs%20phishing/html_headers_redirect.md); [DOI 10.1016/j.cose.2023.103545](https://doi.org/10.1016/j.cose.2023.103545)

### Inferences
- For the target clone, the title ("Sign in to your account"), visible text ("Microsoft"), and `<img alt>` all name Microsoft. Text extraction on device plus an allowlist check is the cheapest strong brand signal. The kit can push the brand text into images or canvas (KnowPhish's text-to-image result), so combine text with non-text evidence: the favicon hash (Q2), DOM ids (Q3), and asset origin (Q5).
- Do not use "brand string in the URL" as a phishing signal by itself. The evidence says it is weak and false-positive prone. "Brand in content, but host not in the brand's domain list" is the evidence-backed form.

### Gaps
- No peer-reviewed paper isolates the precision of a simple "brand keyword in title or text, but not in the domain" rule (without an LLM) on real traffic.
- The Mishra & Varshney accuracies come from a curated balanced dataset. No field false-positive rate is given.

## Q5. Resource-origin features: assets loaded from the brand's own domain (hot-linking) or from third-party hosts

### Takeaway
Phishing pages often load resources from third parties, including the impersonated brand itself. A single financial brand watching its own web logs (resource requests and Referer headers) gained visibility into 39.1% of all known phishing hostnames targeting it. Hot-linking is a deliberate trade-off: self-hosted copies get fingerprinted by filename, while hot-linking exposes the page to the brand. "Logo domain ≠ page domain" alone reached 87.6% accuracy in a 2025 study. Brand CDNs legitimately differ from the sign-in host (Microsoft serves sign-in assets from `*.msftauth.net` / `*.msauth.net`), so the check must be brand-aware: "assets from the brand's CDN, but host not the brand".

### Cited Findings
- Oest, Zhang, Wardman, Nunes, Burgis, Zand, Thomas, Doupé, Ahn, "Sunrise to Sunset: Analyzing the End-to-end Life Cycle and Effectiveness of Phishing Attacks at Scale", USENIX Security 2020.
  - Key observation: "despite cloaking and related evasive efforts, a substantial proportion of phishing pages make requests for web resources (e.g., images and scripts) hosted by third-parties, including the websites that attackers impersonate". In a June 2018 manual check they saw that phishing sites "routinely embed resources (e.g., images, fonts, or JavaScript) hosted on third-party domains, including domains which belong to the organizations being impersonated", and that some redirect victims back to the real site after submission.
  - Method: the "Golden Hour" framework ingests the brand's own web events (image and style requests, referring URLs), whitelists the brand's and approved partners' referrers, and matches the rest against phishing feeds.
  - Results: 404,628 distinct phishing URLs. Visibility into "39.1% of all hostnames and 40.9% of all URLs" in feeds targeting the organisation. 37.73% of victim traffic came after detection. Mobile devices made up 62.73% of victim traffic, with Safari Mobile at 22.38%.
  - Why phishers hot-link: anti-phishing systems "use known filenames of scripts, images, favicons, and archives as one type of fingerprinting", so pages "which only link to external files can avoid such fingerprinting entirely".
  - Evasion: phishers "could deliberately evade our approach by excluding any trackable third-party files and avoiding redirecting victims back".

  — [Oest et al.](https://www.usenix.org/system/files/sec20-oest-sunrise.pdf)
- [older] PhishEye (CCS 2016): of 643 kits uploaded to a honeypot (474 installed live), "10 kits made use of resources directly fetched from the content distribution network (CDN) of the target organization" (about 2.1% of live kits, calc). Another 98 kits contacted attacker-controlled hosts. — [Han, Kheir, Balzarotti, "PhishEye: Live Monitoring of Sandboxed Phishing Kits", ACM CCS 2016, DOI 10.1145/2976749.2978330](https://www.s3.eurecom.fr/docs/ccs16_phisheye.pdf)
- The two sources measure different things and so differ widely. PhishEye counts kits that fetch from the brand's CDN (about 2%, 2015–16). Oest et al. count hostnames seen through brand traffic, which includes referrals and redirects as well as embedded resources (39.1%, 2019). Neither gives the share of phishing pages that hot-link brand images specifically. — [Oest](https://www.usenix.org/system/files/sec20-oest-sunrise.pdf); [PhishEye](https://www.s3.eurecom.fr/docs/ccs16_phisheye.pdf)
- Logo-host feature: "Logo Domain" (the most frequent domain of `<img>` sources containing "logo") alone gave 87.6% accuracy (MLP). With certificate-CN info it gave 97.7% (SVM). The authors' rationale: "Phishing sites, on the other hand, often use logos hosted on third-party or suspicious domains". — [Mishra & Varshney 2025, arXiv 2503.06487](https://arxiv.org/pdf/2503.06487) (flag: venue below the requested tier)
- Classic "Request_URL" (share of embedded objects from other domains) is a long-standing top feature but weak for modern legitimate sites that use CDNs — [earlier note](../Fitur%20deteksi%20situs%20phishing/html_headers_redirect.md)
- Vendor documentation (context): Microsoft's sign-in safelisting guidance lists `login.microsoftonline.com`, `*.aadcdn.msftauth.net`, `*.logincdn.msftauth.net`, `*.msauth.net`, and `login.live.com` together. The US-government endpoint tables list `*.msftauth.net` and `*.msauth.net` as required. — [Microsoft Q&A](https://learn.microsoft.com/en-in/answers/questions/1822636/what-is-the-subnet-for-*-msftauth-net-and-*-msftau); [Microsoft 365 GCC High endpoints](https://learn.microsoft.com/sk-SK/microsoft-365/enterprise/microsoft-365-u-s-government-gcc-high-endpoints?view=o365-21vianet); [Microsoft 365 endpoints](https://learn.microsoft.com/en-us/microsoft-365/enterprise/microsoft-365-endpoints?view=o365-worldwide)

### Inferences
- Two variants of the target clone, both detectable from the page itself without network monitoring (content script reads `img.src`, `link[rel=icon].href`, `link[rel=stylesheet]`, `script.src`, `performance.getEntriesByType('resource')`):
  - (a) Assets hot-linked from Microsoft's CDN (`*.msftauth.net`, `*.msauth.net`) on a non-Microsoft host. This is strong brand evidence plus a mismatch: the page claims Microsoft through Microsoft's own files. Legitimate Microsoft sign-in hosts are on the allowlist, so they do not fire.
  - (b) Assets from an unrelated third-party host, as in the user's scenario. The Mishra-style logo-domain feature fires (−1). Generic CDNs (jsdelivr, cloudflare, googleapis) are normal on benign pages, so this should be a weak, additive signal and not a brand identifier.
- A naive rule "logo or favicon host ≠ page host" would misfire on legitimate Microsoft sign-in, because `login.microsoftonline.com` loads from `aadcdn.msftauth.net`. The brand table needs two lists per brand, `login_domains` and `asset_domains`, and the check is against the union.
- Resource origin is observable on device with no data leaving the phone. It costs the kit little to evade (self-host everything), but self-hosting reintroduces filename and hash fingerprintability (Oest §8.2; Bijmans). The signals complement each other.

### Gaps
- No 2019–2026 peer-reviewed measurement gives the percentage of phishing pages that hot-link the brand's own image, CSS, or favicon versus self-host copies. Oest's 39.1% is a visibility figure that mixes resource loads, referrals, and redirects.
- No study measures false positives of a brand-aware "brand CDN asset on non-brand host" rule. Legitimate cases include partner sites embedding brand widgets, payment pages showing card-network logos from the network's CDN, and SSO buttons hot-linking Microsoft or Google button images. These need allowlisting or the CRP gate.

## Q6. What can run on device in an iOS Safari extension, and what needs a server or screenshot (privacy cost)

### Takeaway
The vision models (Phishpedia, PhishIntention, VisualPhishNet) are 21–89M-parameter CNNs at 92–216 GFLOPs per screenshot, benchmarked on server GPUs at 0.2–2.3 s plus about 1.9 s for screenshot capture. Running them in an iOS Safari extension is unproven and risky. The LLM and knowledge systems (KnowPhish, PhishLLM, DynaPhish, PhishAgent) need cloud LLMs and live web search (1.2–13 s), and their inputs are HTML, OCR text, or screenshots, so they need a server and break Shoo's privacy rule. What fits on device are the cheap, deterministic brand-evidence signals plus a shipped brand-to-domain table and the existing CRP gate. Each signal's ingredients are peer-reviewed, but no paper measures this exact combination.

### Cited Findings
- Model cost (Ji et al. Table 4, server measurements): Phishpedia 65.40M parameters, 212.35G FLOPs, 0.34 s; PhishIntention and DynaPhish 88.92M, 215.66G (DynaPhish 13.36 s with Google Search API calls); VisualPhishNet 21.27M, 92.49G, 2.27 s; EMD 23.54 s; PhishZoo 16 min. — [Ji et al., USENIX Security 2025](https://www.usenix.org/system/files/usenixsecurity25-ji.pdf)
- Screenshot capture costs "approximately 1.88s on average" per URL before any model runs — [Phishpedia §5.2.3](https://www.usenix.org/system/files/sec21fall-lin.pdf)
- PhishLLM median latency is 1.22 s; it depends on cloud LLM APIs and Google search (6.14 USD per 1K sites) — [PhishLLM](https://usenix.org/system/files/usenixsecurity24-liu-ruofan.pdf). KnowPhish KPD takes about 1.5–2 s per page with a cloud LLM — [KnowPhish](https://www.usenix.org/system/files/usenixsecurity24-li-yuexin.pdf). PhishIntel puts reference-based detectors on a "slow task" path because of latency "up to ten seconds", serving most requests from blacklist and cache — [PhishIntel, WWW Companion 2025](https://arxiv.org/pdf/2412.09057)
- Non-visual brand-domain features are fast: 0.08 s average response for the five-feature domain-consistency model — [Mishra & Varshney 2025](https://arxiv.org/pdf/2503.06487). The Cui tag vector is a 107-integer count — [Cui et al. WWW 2017](https://doi.org/10.1145/3038912.3052654)
- iOS platform facts (from the earlier note): `tabs.captureVisibleTab` is supported on iOS 15+, and WebGPU ships in Safari 26. WebKit bugs document unstable WebAssembly memory on iOS (about 300 MB reliably available, sometimes as low as 28 MB). Apple documents no memory budget for extension background pages. — [earlier note §6](../Fitur%20deteksi%20situs%20phishing/visual_llm.md)
- Vendor context (not peer-reviewed): Chrome Enhanced Protection runs Gemini Nano locally on desktop to flag tech-support scams. On a local hit, it sends the model output and site metadata to Safe Browsing for a final verdict. This is a local-first, escalate-on-suspicion pattern. — [BleepingComputer](https://www.bleepingcomputer.com/news/security/google-chrome-to-use-on-device-ai-to-detect-tech-support-scams/)

### Per-method placement (inference from the findings above)
| Method | Inputs | On device (iOS Safari ext.)? | Server? | Data leaving phone | Catches target Microsoft clone? | Main evasion |
|---|---|---|---|---|---|---|
| Brand-domain table (login + asset domains per brand) | host, brand ID | Yes (small JSON) | Updates only | None | Yes, it is the verdict core | Compromised legitimate domains (PhishLLM) |
| CRP gate (sensitive form fields) | DOM inputs | Yes (exists) | No | None | Yes (email/password) | JS-built or canvas forms; HTML obfuscation (PhishIntention §9) |
| Brand text (title, alt, `og:site_name`, visible text) | DOM text | Yes | No | None | Yes | Text-to-image (5% accuracy in KnowPhish) |
| Favicon exact hash / dHash | favicon bytes or pixels | Likely yes (same-origin; cross-origin canvas taint unverified) | No | None | Yes (real favicon) | Re-encode or pixel change; adversarial pHash (CCS 2021) |
| DOM signature (e.g. `loginfmt`/`i0116`/`idSIButton9`) or 107-tag vector | DOM | Yes | No | None | Yes, also for AiTM | Id and attribute randomisation (PhishLLM) |
| Asset origin (brand CDN on non-brand host; logo host ≠ page) | resource URLs | Yes | No | None | Yes (both hot-link and third-party variants) | Self-host everything (then filename fingerprintable) |
| Logo CNN + Siamese (Phishpedia/PhishIntention) | screenshot | Unproven (65–89M params, about 212 GFLOPs) | Practically yes | Screenshot if server-side | Yes | Logo removal (0–9%), adversarial logos (up to 95% evasion) |
| LLM/MLLM brand extraction (KnowPhish, PhishLLM, PhishAgent) | HTML, OCR text, screenshot | No | Yes | Page content (privacy cost) | Yes | Prompt injection, text-to-image |
| Network-level AiTM classifier (Kondracki) | TLS and timing | No (not visible to the content script) | Yes (active probe) | URL | Only AiTM variant | — |

### Inferences
- Recommended evidence-backed design for Shoo (my synthesis): `verdict = CRP ∧ brand_evidence ≥ threshold ∧ host ∉ brand.login_domains`.
  - `brand_evidence` sums independent on-device signals: favicon hash match, brand text in title/alt/text, a known brand DOM signature, and brand CDN assets on a non-brand host.
  - This copies PhishIntention's three-condition rule (86.5% fewer false positives than brand-only) while replacing the screenshot CNN with signals that need no data upload.
  - Using several brand-evidence sources hedges each one's published evasion: logo removal, text-to-image, attribute randomisation, and favicon re-encoding.
- For the target pixel-perfect Microsoft clone, at least four of the on-device signals fire at once (favicon, title/text, field ids, asset origin), plus the CRP gate and a host outside the Microsoft domains. The design should catch it with high confidence. A brand-domain mismatch on its own, without a CRP, should stay silent, protecting "Sign in with Microsoft" and partner pages.
- The server layer should receive only the derived brand ID, the host, and the fired rule IDs, consistent with the privacy rule. A server-side reference-based detector with a screenshot or HTML would add recall on logo-only or obfuscated pages, but at the privacy cost these papers never address. All of them assume a crawler, not a user's browser.

### Gaps
- No paper evaluates any reference-based detector running inside a mobile browser extension. On-device latency, memory, and battery numbers for iOS Safari are unknown and need a device test.
- No peer-reviewed study measures the combined on-device signal set above (favicon + text + DOM id + asset origin + CRP + domain table). Its precision and recall on Shoo traffic, especially Indonesian brands, must be measured internally.
- Whether a Safari content script can read cross-origin favicon pixels (canvas taint) or `performance` resource entries for every asset on iOS is unverified (see the earlier note's §6 gaps).
