# Systematic reviews, SoKs and large-scale measurements (2020–2026): which signal families decide "phishing vs legitimate", how production systems combine them, and why "asks for a password" is not a verdict

Scope note (researched 2026-10-26). This file adds only material that is not already in the sibling notes. Those notes already cover the following, and this file only points to them:
- Phishpedia, PhishIntention (including the CRP classifier and CRP distribution), DynaPhish, KnowPhish, PhishLLM, Ji et al. (USENIX Sec 2025), the brand+CRP+domain rule, and favicon/logo hashing: `brand_impersonation_methods.md` and `Fitur deteksi situs phishing/visual_llm.md`.
- URL, WHOIS, TLS/CT, DNS/ASN, squatting, PhiUSIIL and UCI dataset critiques, and Mia et al. (NSysS 2024): `url_domain_tls.md`.
- DOM, header and redirect features, CrawlPhish, PhishFarm, kit/Telegram exfiltration, and Bijmans et al.: `html_headers_redirect.md`.
- Google Safe Browsing real-time and OHTTP, Chrome CSD (Pourmohamad et al.), Safari FWW, Edge Scareware Blocker, warning studies, and Sunrise to Sunset: `safari_ios_deployment.md`.
- APWG 2025 quarterly reports and Interisle Phishing Landscape 2025.

Primary texts read in full (PDF to text) for this note: PHILTER (USENIX Sec 2026), Das et al. SoK (arXiv version of IEEE COMST 2020), Arp et al. (USENIX Sec 2022), and Whittaker et al. (Google, NDSS 2010). Read from HTML: PhreshPhish (arXiv), PhishTime (authors' markdown copy), and Divakaran & Oest (ar5iv). Everything else is abstract-level or a search summary, and is labelled as such. "[preprint]" means not peer-reviewed. "[vendor]" means company material.

## Q1. What do recent systematic reviews and SoK papers conclude about the most effective and most robust feature families?

### Takeaway
The newest and strongest SoK, PHILTER (USENIX Security 2026, 55 AI-based detectors), finds that **no published detector meets all functionality and security requirements**. The weakest dimension across the field is evaluation on diverse benign pages: 75% of studies score low. Identity-based detectors (infer the brand, then check whether the domain belongs to it) are the only family with 100% high interpretability. They also adapt best to new targets, but they score 100% low on privacy because they send screenshots or content off-device. Feature-based (URL/HTML ML) detectors are the most privacy-friendly and the most drift- and evasion-prone. Older surveys agree on the same structural flaws: balanced datasets, popular-only negatives, no collection dates, and accuracy as the headline metric. Together these show that high reported accuracy says little about which signal families decide in the field.

### Cited Findings
**PHILTER: the 2026 SoK**
- Alam, Rahman, Paul, Hays, Hussain, Huq, Saxena, "SoK: PHILTER: Uncovering Security and Functional Gaps in AI-based Phishing Website Detection Literature via an LLM-based Reasoning Framework", USENIX Security 2026, pp. 4981–5000. It assesses 55 academic AI-based phishing-website detectors against 4 functionality metrics (F1 tactic diversity, F2 benign-page diversity, F3 interpretability, F4 evaluation transparency) and 3 security metrics (S1 concept-drift adaptation, S2 resistance to active attacks, S3 privacy). "No study meets all functionality and security requirements". — [USENIX page](https://www.usenix.org/conference/usenixsecurity26/presentation/alam); [PDF](https://www.usenix.org/system/files/usenixsecurity26-alam.pdf)
- Taxonomy and counts: feature-based 35, similarity-based 7, identity-based 4, hybrid 9. The identity-based family "infer[s] the intended brand from logos, page text, and URLs, then verif[ies] whether the hosting domain is genuinely associated with that brand". — [PHILTER §5.2, Table 4](https://www.usenix.org/system/files/usenixsecurity26-alam.pdf)
- Overall fulfilment across all 55 studies (Table 4, % High / Medium / Low): F1 0/84/16; F2 5/20/75; F3 18/29/53; F4 31/67/2; S1 16/35/49; S2 9/36/55; S3 33/0/67. — [PHILTER Table 4](https://www.usenix.org/system/files/usenixsecurity26-alam.pdf)
- By family (Table 4 and §6.1):
  - Feature-based (n=35): F2 83% low; S1 69% low; S2 74% low; S3 43% high, because these methods often run client-side.
  - Similarity-based (n=7): F2 29% high; S1 86% medium, because they "rely on fixed reference lists"; S3 71% low.
  - Identity-based (n=4): F3 100% high, because "decisions are explained through brand–domain matching"; S1 25% high and 75% medium; S3 100% low, because of "reliance on external lookups".
  - Hybrid (n=9): S1 44% high; S3 89% low.
  — [PHILTER Table 4, §6.1](https://www.usenix.org/system/files/usenixsecurity26-alam.pdf)
- By input (Table 5):
  - URL-only (n=16): best privacy (S3 69% high) but "roughly 62–88% low" on F2, F3, S1 and S2.
  - URL plus external metadata only (n=4): "all three [security] metrics (S1, S2, S3) at 100% low".
  - Adding page content raises F2, F3, S1 and S2, but privacy drops (S3 67–90% low).
  — [PHILTER §6.2.1, Table 5](https://www.usenix.org/system/files/usenixsecurity26-alam.pdf)
- By deployment (Table 6):
  - Client-side (n=23): 61% high on privacy, against 12% for server-side (n=32).
  - Server-side shows "comparatively stronger fulfillment" on F2, F3, S1 and S2.
  - Real-time detectors (under 1 s end-to-end, n=24) reach 54% high privacy, against 16% for non-real-time detectors.
  — [PHILTER §6.2.2–6.2.3, Tables 6–7](https://www.usenix.org/system/files/usenixsecurity26-alam.pdf)
- Accuracy does not predict fulfilment. The 99–100% accuracy band (n=12) is still 67% low on F2 and 58% low on S2 (Table 8). "Methods that address security concerns often report reduced accuracy." — [PHILTER Table 8, §1](https://www.usenix.org/system/files/usenixsecurity26-alam.pdf)
- Key findings and recommendations (Table 1), paraphrased:
  1. No study reports tactic-labelled evaluation.
  2. Most lack evaluation on diverse benign pages, "risking elevated false alarms". Remedy: controlled inclusion of "benign pages with legitimate brand elements and low-reputation sites".
  3. Drift handling is missing. Remedy: "time-aware evaluation".
  4. Active-attack evaluation is missing (obfuscation, delayed content, redirects, manipulated visuals).
  5. Most designs transmit sensitive data externally. Remedy: client-side detection, federated learning, anonymised features.
  6. Combining methods with complementary strengths is "underexplored".
  — [PHILTER Table 1](https://www.usenix.org/system/files/usenixsecurity26-alam.pdf)

**Das et al.: the earlier SoK (IEEE COMST)**
- Das, Baki, El Aassal, Verma, Dunbar, "SoK: A Comprehensive Reexamination of Phishing Research from the Security Perspective", IEEE Communications Surveys & Tutorials 22(1), 2020 (arXiv 1911.00953; COMST DOI 10.1109/COMST.2019.2957750, from my own knowledge and not checked against IEEE Xplore). It names four persistent challenges: real-time detection, active attackers, dataset quality, and the base-rate fallacy. — [arXiv 1911.00953](https://arxiv.org/pdf/1911.00953)
- Survey statistics:
  - 64% of the phishing-website detection papers used URL features.
  - 50% of the URL-feature papers also used WHOIS properties.
  - Only about 23% of papers used large datasets (≥ 100,000s of URLs).
  - About 55% did not report when their data was collected.
  - 10 of 61 papers did not report the evaluation metric.
  - "A majority of the papers studied report evaluation results only on balanced datasets."
  — [Das et al. §VI](https://arxiv.org/pdf/1911.00953)
- Popular-only negatives, measured: in an Alexa-category crawl, the top 50 domains made up 75% of the legitimate URLs. Capping at 12 URLs per domain cut this to 2.3% of 21,788 URLs. The same top-50 share was 24% for OpenPhish, 12.6% for PhishTank and 18% for APWG. — [Das et al. §VI-B](https://arxiv.org/pdf/1911.00953)

**Divakaran & Oest: the review written from deployment experience**
- Divakaran (Trustwave) and Oest (PayPal), "Phishing Detection Leveraging Machine Learning and Deep Learning: A Review", IEEE Security & Privacy magazine, 2022 (arXiv 2205.07411).
  - Trade-offs by input: URL models are fast but carry "limited information in URLs". HTML is rich, but needs a fetch and expensive feature extraction, and is evadable. Screenshot/reference methods need only a reference list but take about 2 s and are open to adversarial ML. Network/reputation features need extra latency or large up-to-date databases.
  - Browsers expect pages "within a few hundred milliseconds", so URL-based detection fits there.
  - "An FPR of 10^-3 is usually expected for adoption in industry."
  - Google retrains its content classifier daily, and industry retrains at least weekly.
  — [ar5iv 2205.07411](https://ar5iv.labs.arxiv.org/html/2205.07411)

**Other surveys (abstract-level only)**
- Safi & Singh, "A systematic literature review on phishing website detection techniques", Journal of King Saud University – Computer and Information Sciences, 2023. Of 80 papers, 57 were ML-based. Phishing data came from PhishTank in 53 studies, and legitimate data from Alexa in 29. Random Forest was the most used classifier (31 studies). The top reported accuracy was 99.98% (CNN). Abstract-level only; DOI not checked. — [CUP repository record](https://kr.cup.edu.in/handle/32116/3912)
- "Phishing Webpage Detection: Unveiling the Threat Landscape and Investigating Detection Techniques", IEEE COMST 27(2), pp. 974–1007. Taxonomy: URL-based, content-based, third-party-based, visual. Only the listing was seen; the full text was not read. — [ResearchGate listing](https://www.researchgate.net/publication/383067201_Phishing_Webpage_Detection_Unveiling_the_Threat_Landscape_and_Investigating_Detection_Techniques)
- Li et al., "A State-of-the-Art Review on Phishing Website Detection Techniques", IEEE Access, Dec 2024. Adds graph-based, LLM-based and phishing-kit-based detection to the taxonomy. — [UTS repository](https://opus.lib.uts.edu.au/handle/10453/184498)

### Inferences
- Across SoKs, the decisive family is the identity check: which brand the page claims to be, and whether this host is one of that brand's domains. It is the only family whose decision explains itself, and the only one that does not rely on attacker-controlled statistics (URL shape, domain age, hosting) that drift. Its known weaknesses are privacy cost, reference-list upkeep and brand-rich benign pages. Each of these can be engineered around: an on-device brand table, and the CRP gate covered in `brand_impersonation_methods.md`.
- URL, domain, hosting and reputation features are supportive. They are cheap, private and good for ranking or gating, but they rate worst on drift and evasion. PHILTER's "U, M only" group scores 100% low on all security metrics.
- Shoo's split matches PHILTER's own client/server trade-off. On-device detection is where privacy is high; server-side is where drift adaptation and benign diversity are better. The SoK names a combination of the two as the open opportunity.

### Gaps
- PHILTER rates papers, not running systems, and an LLM produced the first-pass ratings (with expert validation; 89% agreement before correction). It does not rank individual features.
- No 2021–2026 ACM Computing Surveys paper specific to phishing websites was found in this pass. The 2024 COMST survey and the Safi & Singh SLR were not read in full.

## Q2. Evaluation pitfalls (leakage, base rate, temporal drift, popular-only negatives): who documents them, with what numbers, and what protocol they recommend

### Takeaway
The pitfalls are well quantified:
- Sampling bias is at least partly present in 90% of top-venue ML-security papers, and data snooping in 73% (Arp et al.).
- At a 1:100 class ratio, "99% TPR at 1% FPR" means 100 false alarms for every 99 hits.
- Google's own phishing pipeline needed FPR ≤ 0.1% to reach 90% precision at a 1% phishing rate.
- PhreshPhish [preprint] shows average precision dropping from 0.98 (24% base rate) to 0.88 (1%) and 0.61 (0.05%) for its best model.
- Models trained on legitimate homepages give many false positives on legitimate login pages (Sánchez-Paniagua et al.).

The recommended protocol: a temporally disjoint (future) test set, near-duplicate removal, realistic base rates of 1% or lower, benign sets that include login pages, low-reputation sites and pages with brand widgets, and precision/recall at FPR ≤ 10^-3.

### Cited Findings
**Arp et al.: prevalence of ML pitfalls**
- Arp, Quiring, Pendlebury, Warnecke, Pierazzi, Wressnegger, Cavallaro, Rieck, "Dos and Don'ts of Machine Learning in Computer Security", USENIX Security 2022. Prevalence across 30 top-venue papers, counted as "present":
  - P1 sampling bias 60%
  - P2 label inaccuracy 10%
  - P3 data snooping 57%
  - P4 spurious correlations 20%
  - P5 biased parameter selection 10%
  - P6 inappropriate baseline 20%
  - P7 inappropriate performance measures 33%
  - P8 base-rate fallacy 10%
  - P9 lab-only evaluation 47%
  - P10 inappropriate threat model 17%

  Sampling bias and data snooping "are at least partly present in 90% and 73%" of papers. — [arXiv 2010.09470](https://arxiv.org/pdf/2010.09470)
- Base-rate example: "99% true positives are possible at 1% false positives. Yet, if we consider the class ratio of 1:100, this actually corresponds to 100 false positives for every 99 true positives". Recommendations: precision-recall curves, MCC when prevalence is inflated, and ROC "only up to tractable false-positive rates" (bounded AUC). — [Arp et al. §2 P8](https://arxiv.org/pdf/2010.09470)

**Base rates in a production pipeline**
- Google's in-production numbers: "Since our datasets contain roughly one percent phishing web pages, our classifier must demonstrate a false positive rate of 0.1% to achieve precision of 90%". Measured results:
  - Cross-validation: TPR 0.9497, precision 0.9754, FPR 0.0003 (98,467 TP, 2,479 FP, 9,282,232 TN).
  - One month later on August data: TPR 0.9185, precision 0.9895.

  Whittaker, Ryner, Nazif, "Large-Scale Automatic Classification of Phishing Pages", NDSS 2010. **[pre-2020, foundational]** — [NDSS PDF](https://www.ndss-symposium.org/wp-content/uploads/2017/09/whit.pdf)
- Das et al. illustrate the base-rate fallacy: with 10% incidence and a 90%-accurate classifier, a flagged item is an attack only 50% of the time. — [Das et al. §IV](https://arxiv.org/pdf/1911.00953)

**PhreshPhish: leakage and base-rate measurements [preprint]**
- Dalton et al., "PhreshPhish: A Real-World, High-Quality, Large-Scale Phishing Website Dataset and Benchmark", arXiv 2507.10854 (v2 Feb 2026), Webroot/OpenText authors.
  - Data: 250,002 phishing and 366,991 benign pages, collected July 2024 to December 2025. Phishing came from PhishTank, the APWG eCX and Netcraft. Benign pages came from browsing telemetry of more than 6 million Webroot users, plus search results for heavily targeted brands.
  - Applying the same cleaning to prior datasets rejected 49.1% of Aljofey et al. (65.5% of its phishing samples) and 28.5% of Crawling2024, against 0.52% of PhreshPhish.
  - The test set is temporally disjoint (future) and near-duplicates are removed with LSH.
  - Benchmarks are built at base rates of 0.05%, 0.1%, 0.5%, 1% and 5%.
  - Best model (GTE embedding) average precision: 0.9779 at 24%, 0.9382 at 5%, 0.8762 at 1%, 0.6050 at 0.05%.
  - Linear model: AP 0.6841 and precision@recall 0.9 of 0.2191 at 1%. An LLM baseline: AP 0.6252 at 1%.
  - "The performance of all models degrades as the base rate decreases."
  — [arXiv HTML v2](https://arxiv.org/html/2507.10854v2)

**Login pages as negatives (Sánchez-Paniagua et al.)**
- Sánchez-Paniagua, Fidalgo, Alegre, Al-Nabki, González-Castro, "Phishing URL Detection: A Real-Case Scenario Through Login URLs", IEEE Access 10 (2022), pp. 42949–42960, DOI 10.1109/ACCESS.2022.3168681.
  - Prior work used homepages as the legitimate class. Existing techniques obtained "a high false-positive rate when tested with URLs from legitimate login pages."
  - Models trained on older data lost accuracy on recent URLs.
  - New dataset PILU-90K: 60K legitimate URLs (index and login pages) and 30K phishing URLs. LR + TF-IDF reached 96.50%.

  Abstract-level only; the exact FPR is not seen. — [Semantic Scholar record](https://api.semanticscholar.org/graph/v1/paper/DOI:10.1109/ACCESS.2022.3168681?fields=title,abstract,venue,year,authors,openAccessPdf); [Univ. León portal](https://portalcientifico.unileon.es/documentos/628009853333e458234bb6bc?lang=ca)
- Companion paper: Sánchez-Paniagua, Fidalgo, Alegre, Alaiz-Rodríguez, "Phishing websites detection using a novel multipurpose dataset and web technologies features", Expert Systems with Applications 207 (2022) 118010, DOI 10.1016/j.eswa.2022.118010. PILWD has 134K verified samples of login websites (Aug 2019 to Sep 2020). LightGBM with 54 URL, HTML and web-technology features reached 97.95% accuracy. — [Univ. León portal](https://portalcientifico.unileon.es/documentos/63c3915ab0644813d9027263)

**Benign diversity and drift**
- PHILTER defines what a realistic benign set must include:
  - (i) "low-reputation or long-tail domains (e.g., Alexa/Tranco low-rank sites, personal domains, recently registered domains, or regional businesses)";
  - (ii) "legitimate brand element usage (e.g., PayPal/OAuth login widgets, social media buttons, embedded logos)".

  "Without such diversity, evaluations risk underestimating false positive rates." 49% of studies score low on drift: no adaptive mechanism and no temporally split test. — [PHILTER §4.1.2, §7](https://www.usenix.org/system/files/usenixsecurity26-alam.pdf)
- Drift size: Scientific Reports (2023), "Life-long phishing attack detection using continual learning". With 2018–2020 data in six temporal datasets, a vanilla NN lost more than 20.65% accuracy over time and transfer learning about 8%. Continual learning held the loss to 2.45%. Abstract-level only. — [PMC10352299](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10352299/)
- Divakaran & Oest: offline random splits hide "biases, errors, obsolete links". Report recall at FPR ≤ 10^-3; an FPR of 10^-1 is "clearly unacceptable". Run longitudinal in-the-wild studies. — [ar5iv 2205.07411](https://ar5iv.labs.arxiv.org/html/2205.07411)

### Inferences
- Shoo's evaluation protocol, synthesised from the papers above:
  - Train/tune on data up to date T, and test on pages first seen after T.
  - Drop near-duplicates and same-kit clones across the split.
  - Report precision and FPR at a 1% or lower phishing prevalence.
  - Include three hard benign subsets: (a) real login pages of Indonesian banks, e-wallets, SaaS and campus SSO; (b) pages embedding "Sign in with Microsoft/Google" or brand logos; (c) long-tail and newly registered Indonesian SME sites.
  - Target FPR around 10^-3 per page view for an interruptive block (industry norm in Divakaran & Oest). Use a softer warning tier above that.
- Back-of-envelope (my arithmetic, not a measurement): a user loads about 100 pages a day. At FPR 10^-3 that is about 1 false block every 10 days. At 10^-2 it is about 1 per day, which drives users to disable the extension.

### Gaps
- The exact FPR of homepage-trained models on login URLs (PILU-90K) was not readable: IEEE Xplore blocked the PDF. DOI listed for MyLoft.
- No peer-reviewed phishing-website study gives the share of legitimate page views that are login pages (see Q4).

## Q3. How deployed systems decide: blocklists, reputation, brand checks and verification

### Takeaway
Every documented production pipeline is a cascade that is conservative about false positives:
- Candidates come only from suspicious sources: spam, user reports, feeds.
- A hand-built allowlist of popular sites is removed before scoring.
- An ML score on URL, hosting and content follows.
- Popular or high-reputation hits go to human review before listing.
- Lists are pushed to clients, which check locally first.

Blocklists are accurate but slow and uneven, especially on mobile. PhishTime measured mobile Chrome/Safari (GSB) at 57.8% coverage with a 17.5 h median, against 92.9% at 57 min on desktop GSB. Detection must therefore also work on the page itself, in the user's browser.

### Cited Findings
**Google's published architecture (Whittaker et al., NDSS 2010) [pre-2020, still the only full published description]**
- Pipeline stages:
  1. Candidates come only from "submitted as a potential phishing page or collected from a spam email".
  2. A URL Feature Extractor drops malformed URLs and a manually compiled allowlist of 2,778 high-traffic sites that "not host arbitrary user-generated content". This removed "approximately half" of the candidates.
  3. Headless browsers render the page for content features.
  4. A logistic-regression score marks phishing above 0.5.
  5. "Before the classifier automatically blacklists the page, it checks to make sure that the page does not have a high PageRank… Popular pages require a final manual review."
  6. User-submitted pages and reported errors are also reviewed manually, to break feedback loops.
- Output: the classifier evaluated "hundreds of millions of pages" in H1 2009 and auto-blacklisted 165,382. PhishTank confirmed 47,203 of 139,340 candidates in the same period. Target: better than 90% precision and 90% recall. FPR "well below 0.1%".
- Feature evidence:
  - IP-address hosting was several times more common on phishing pages.
  - Some residential-ISP ASNs had very high phishing ratios.
  - Phishing pages lived "approximately three days" on average, most less than a day.
  — [Whittaker et al. §3–4](https://www.ndss-symposium.org/wp-content/uploads/2017/09/whit.pdf)

**PhishTime: blocklist performance measured from outside (Oest et al., USENIX Security 2020)**
- 2,862 test phishing sites across nine months (May 2019 to Jan 2020). — [authors' copy](https://adamdoupe.com/publications/phishtime_usenix_2020.md); [USENIX page](https://www.usenix.org/conference/usenixsecurity20/presentation/oest-phishtime)
- Baseline coverage and median listing time (Table 4):

  | Blocklist | Coverage | Median time to list |
  |---|---|---|
  | GSB desktop | 92.9% | 00:57 |
  | SmartScreen | 93.2% | 02:48 (the body text says 3 h 47 m) |
  | Opera | 60.5% | 00:55 |
  | Mobile Chrome/Safari (GSB) | 57.8% | 17:30 |
  | Mobile Firefox | 92.9% | — |
  | Mobile Opera | 3.7% | — |

- Evasions:
  - With redirection lures, mobile Chrome/Safari coverage fell to 9.3–25.9%, and listing was 8–40 h slower than desktop.
  - With domain reuse, mobile coverage fell to 3.7–4.3%.
  - Behaviour-based JS cloaking (CAPTCHA, mouse movement, notification prompt) got 0% GSB coverage.
- Reporting channel matters:
  - Standard URL reports to GSB reached 20.4% coverage.
  - Evidence-based reports (Chrome Suspicious Site Reporter) reached 90.7%.
  - Reports to APWG alone led to 98.1% GSB coverage; reports to PayPal alone led to 16.2%.
  — [PhishTime](https://adamdoupe.com/publications/phishtime_usenix_2020.md)

**Cascades in practice (Divakaran & Oest)**
- Recommended deployment: a URL model gates a content model, which gates a screenshot model. A threshold θ sets how many pages get fetched. ML is combined with rules and scores, because models are "probabilistic and not perfect". — [ar5iv 2205.07411](https://ar5iv.labs.arxiv.org/html/2205.07411)

**Netcraft [vendor]**
- Netcraft describes a mix of rules, pattern recognition and AI: headless-browser analysis, redirect-chain tracking, automated screenshot analysis, and fetches from residential and mobile proxies chosen per attack to defeat geo-cloaking. It claims more than a third of global phishing takedowns, and removal "within an average of 33 minutes". Unverified marketing figures. — [Netcraft phishing detection page](https://netcraft.com/solutions/use-cases/phishing-detection); [Netcraft platform page](https://www.netcraft.com/cybercrime/fraud-detection/)
- An Imperial College industry talk (2018–19) says Netcraft's "Automated Victim" classifier runs in production. **[older]** — [Imperial ACI listing](https://imperial.ac.uk/computing/industry/aci/2018-19/netcraft)

### Inferences
- The Google pipeline shows how production keeps FP low without a "password = phishing" rule. It never scores the general web, only suspicious candidates. It removes popular sites first. It sends any popular-site hit to a human. Shoo cannot use human review on-device. The equivalents are:
  - an on-device allowlist of the brand's own login domains and top Indonesian sites;
  - "warn, don't block" for medium scores;
  - server-side escalation for the uncertain middle band.
- PhishTime's mobile numbers are the strongest published case for Shoo's in-page detection on iPhone. Mobile Safari relies on GSB, which in 2019–2020 was both slower and less complete on mobile.
- Microsoft SmartScreen and Cloudflare have no published architecture with numbers (see Gaps). Treat any statement about how they decide as unverified.

### Gaps
- No peer-reviewed or official architecture paper with numbers for Microsoft SmartScreen, Cloudflare (Radar URL Scanner, Email Security) or Netcraft was found. Whittaker et al. (2010) is old; GSB has since added real-time lookups (covered in `safari_ios_deployment.md`).
- Phishing-simulation vendors: no study measures how blocklists treat simulation domains. Practitioner material shows that mail and network filters routinely flag simulations unless admins allowlist them (e.g. [Microsoft Defender guidance as summarised by WPS](https://www.wps.com/office-quick-solution/security-issues/how-to-stop-microsoft-defender-from-marking-phishing-simulations-as-threats/); [Check Point community thread](https://community.checkpoint.com/t5/General-Topics/Best-way-to-whitelist-KnowBe4-Phishing-domains/m-p/65030)). Low-authority sources.

## Q4. Credential-requiring-page (CRP) detection as a gate: accuracy, how it is used, and how common CRPs are on legitimate sites

### Takeaway
The CRP classifier and its 86.5% false-positive reduction are already documented in `brand_impersonation_methods.md`. The new evidence here is about the benign side. Every SoK that looks at benign data says legitimate login pages and pages with brand login widgets are exactly where detectors fail:
- PHILTER names "PayPal/OAuth login widgets" as a required benign subset.
- Sánchez-Paniagua et al. report high FPR on legitimate login URLs.
- Google's pipeline sends popular-site hits to human review.

A password field therefore marks the page as the kind of page a phisher builds. It is a precondition for harm, not evidence of fraud. Only the brand-to-domain mismatch turns it into a verdict.

### Cited Findings
- PHILTER requires benign sets to include "legitimate brand element usage (e.g., PayPal/OAuth login widgets…)". Similarity and identity detectors show "high false positives on brand-rich benign pages" (citing Ji et al.). — [PHILTER §2, §4.1.2](https://www.usenix.org/system/files/usenixsecurity26-alam.pdf)
- Existing URL techniques obtain "a high false-positive rate when tested with URLs from legitimate login pages". PILU-90K was built because homepage-only negatives hide this. — [Sánchez-Paniagua et al., IEEE Access 2022](https://api.semanticscholar.org/graph/v1/paper/DOI:10.1109/ACCESS.2022.3168681?fields=title,abstract,venue,year,authors,openAccessPdf)
- AiTM reverse-proxy kits relay the real brand login page "mirror[ing] live content". On such pages every content signal is the genuine one: real CRP, real logo, real DOM. Network-level features (TLS and timing) classified these proxies with 99.9% accuracy. — [Kondracki, Azad, Starov, Nikiforakis, "Catching Transparent Phish", ACM CCS 2021, DOI 10.1145/3460120.3484765 (summary via search; abstract via Unpaywall record)](https://unpaywall.org/10.1145%2F3460120.3484765)
- Divakaran & Oest: phishing pages imitate login interfaces, so form and input-tag features are useful. The review gives no stand-alone CRP accuracy. — [ar5iv 2205.07411](https://ar5iv.labs.arxiv.org/html/2205.07411)

### Inferences
- Why "asks for a password" is not a verdict:
  - (a) Base rate. Legitimate login pages vastly outnumber phishing pages in any user's browsing; every bank, e-wallet, campus SSO and SaaS app has one. A CRP-only rule therefore has a precision near the phishing share among CRP views, far below 50%.
  - (b) Signal value. Phishers copy the real form exactly, down to field ids in Shoo's test case and the live page in AiTM kits, so CRP features cannot separate real from fake.
  - (c) The deciding fact is outside the form: it is whether this host may ask for these credentials. That is the identity check.
- The CRP flag is still valuable as a gate. It is cheap on-device, and it cuts the brand check's false positives on SSO buttons, ads and partner pages. It also sets severity: a brand mismatch plus OTP, PIN or card fields is worse than a mismatch on a page without inputs.

### Gaps
- **No peer-reviewed measurement of the share of legitimate pages, or page views, that are CRPs was found** (searched login-form prevalence and Tranco crawl studies). Shoo should measure it in its own telemetry: the count of sensitive-form page views per user per day, stored on-device and aggregated.
- The exact FPR numbers in the PILU-90K and PILWD papers were not readable (paywall or blocked). DOIs are listed below for MyLoft.

## Q5. Phishing-ecosystem measurements 2020–2026: which signals stay stable

### Takeaway
Infrastructure signals are being neutralised:
- Phishing moves onto reputable shared platforms: Cloudflare Pages/Workers, Vercel, GitHub Pages, Netlify, free website builders, IPFS.
- It uses valid TLS.
- It relays genuine pages through AiTM proxies, and blocklists list only 43.7% of AiTM domains and 18.9% of their IPs.

Domain reputation, age, hosting ASN and certificates therefore carry less weight each year. What stays stable across every kit and platform is the business requirement of the attack: the page must look like brand X and must collect brand-X credentials on a host that is not brand X's. That is the identity + CRP + domain-mismatch rule.

### Cited Findings
**AiTM proxy kits (Kondracki et al., ACM CCS 2021)**
- 1,220 MITM (reverse-proxy) phishing sites were tracked over a year. Only 43.7% of their domains and 18.9% of their IPs appeared on blocklists. A network-level classifier reached 99.9% accuracy; the authors' poster says 98.9%, a conflict to check in the paper. Code and data: catching-transparent-phish.github.io. Summary from abstract and secondary coverage. — [Unpaywall record](https://unpaywall.org/10.1145%2F3460120.3484765); [Malwarebytes coverage](https://www.malwarebytes.com/blog/news/2022/01/intercepting-2fa-over-1200-man-in-the-middle-phishing-toolkits-detected)

**Phishing-as-a-Service [vendor]**
- Sekoia: Tycoon 2FA used more than 1,100 domains between late Oct 2023 and late Feb 2024. — [Sekoia](https://blog.sekoia.io/tycoon-2fa-an-in-depth-analysis-of-the-latest-version-of-the-aitm-phishing-kit/)
- Barracuda: Tycoon 2FA was 89% of PhaaS incidents in Jan 2025, EvilProxy 8%, Sneaky 2FA 3%. EvilProxy uses random URLs. — [Barracuda, Mar 2025](https://blog.barracuda.com/2025/03/19/threat-spotlight-phishing-as-a-service-fast-evolving-threat)
- Barracuda: after a Europol-coordinated disruption of Tycoon 2FA in March 2026, Mamba 2FA, EvilProxy, Sneaky 2FA and Whisper 2FA picked up activity. — [Barracuda, Apr 2026](https://blog.barracuda.com/2026/04/16/threat-spotlight-tycoon-2fa-scattered-everywhere)

**Free website builders (Saha Roy, Karanjit, Nilizadeh, "Phishing in the Free Waters", ACM, Oct 2023)**
- FreePhish found more than 31.4K phishing URLs on 17 free website-builder services, shared on Twitter and Facebook over six months. Blocklists and browser protections had "much lower coverage and slower detection" for these than for self-hosted phishing. Builders and platforms removed them unevenly. The venue is believed to be IMC 2023 but was not verified. — [UTA repository](https://mavmatrix.uta.edu/cse_facpubs/9/); [arXiv 2212.02563](https://arxiv.org/html/2212.02563v2)

**Cloud and developer platforms [vendor]**
- Kaspersky/Securelist, 12 months (Aug 2025 to Jul 2026): 224,984 unique third-level domains blocked on cloud and decentralised platforms, and more than 390,000 phishing pages. Shares of phishing links:

  | Domain | Share |
  |---|---|
  | pages.dev | 24.9% |
  | vercel.app | 13.8% |
  | github.io | 13.7% |
  | netlify.app | 10.0% |
  | dweb.link | 7.8% |
  | ipfs.io | 5.3% |
  | workers.dev | 2.5% |
  | azurewebsites.net | 1.0% |

  Why detection is hard: shared parent domains with positive reputation, programmatic subdomains, CDN-hidden origins, and valid HTTPS. The report also documents an AiTM campaign on workers.dev that uses the Ultraviolet proxy plus browser-in-the-browser spoofing against Microsoft login. — [Securelist, 4 Aug 2026](https://securelist.com/cloud-platforms-in-phishing/120832/)
- Fortra: Cloudflare Pages phishing incidents rose from 460 (2023) to 1,370 (to mid-Oct 2024); Workers from 2,447 to 4,999. — [Fortra blog](https://www.fortra.com/blog/cloudflare-pages-workers-domains-increasingly-abused-for-phishing)
- No measurement found specifically for S3, GCS, Azure Blob or Firebase static hosting (see Gaps).

**Short lifetimes and blocklist latency**
- Google's 2010 pipeline was designed around phishing pages living "approximately three days" on average, most under a day. — [Whittaker et al.](https://www.ndss-symposium.org/wp-content/uploads/2017/09/whit.pdf)
- Behaviour-based cloaking defeated GSB completely in PhishTime (0% coverage). — [PhishTime](https://adamdoupe.com/publications/phishtime_usenix_2020.md)

### Inferences
**Stable vs. eroding signals for Shoo**
- Stable:
  - The brand identity shown: favicon, logo, title, text, brand-specific field ids.
  - Credential intent (CRP).
  - The host not being in the brand's domain set.
  - Assets hot-linked from known kit or simulation hosts (stable per campaign, not across campaigns).
- Eroding:
  - Domain age: aged or compromised domains are common.
  - TLS presence or issuer.
  - Hosting reputation: shared platforms.
  - Redirect presence: many attacks have none.
  - Blocklist presence: slow on mobile, with low AiTM coverage.

**Shoo test case (helpnets.info, registered 2018; Microsoft clone on S3 behind Cloudflare; 30-day auto-delete header; byte-identical Microsoft favicon; real Microsoft field ids; assets from a phishing-simulation vendor host; no redirect)**
- Silent or misleading: domain age (8 years old), TLS (valid via Cloudflare), hosting ASN or IP (Cloudflare edge), redirect chain (none), lexical URL (no brand token, ordinary .info), and probably blocklists in the first hours (PhishTime).
- Firing:
  - Brand identity is Microsoft: favicon hash, field ids, title and text.
  - A CRP is present.
  - The host is not in the Microsoft login-domain set. This alone decides the case.
  - Assets come from a third-party host that is neither Microsoft's CDN nor the page's own origin. Supportive.
  - The short-retention header is a weak, supportive signal: it shows disposable infrastructure, but legitimate temporary content uses it too.
- This case matches the ecosystem trend above. Only the identity rule catches it with high confidence.
- The simulation-vendor asset host suggests this may be a corporate phishing-awareness test. Shoo should still warn: the user cannot tell, and a real kit could hot-link the same assets. A simulation-vendor host list could be used for labelling, not for suppressing warnings.

### Gaps
- No peer-reviewed 2023–2026 measurement of PhaaS/AiTM kits (Tycoon 2FA, EvilProxy) was found. The numbers are vendor-only.
- No measurement of phishing served from S3, GCS, Azure Blob or Firebase static hosting, or of the "30-day lifecycle" header pattern, was found.
- No peer-reviewed study of phishing-simulation vendor infrastructure being reused by real phishers, or of simulations being flagged by blocklists.

## Q6. Mobile / in-browser (extension) detection, and non-English (Indonesian / Southeast Asian) phishing

### Takeaway
Mobile users get the least protection from blocklists: in PhishTime, GSB covered 57.8% of sites on mobile Chrome/Safari, with a 17.5 h median listing time, and much less under redirection. PHILTER shows that client-side, real-time designs are the privacy-preserving ones, but they are evaluated more weakly on benign diversity and drift. That argues for Shoo's on-device identity check plus a server for drift-prone, updatable knowledge. For Indonesia there is still no peer-reviewed phishing-website measurement or dataset. The closest is an arXiv study of gambling defacements on Indonesian government and education sites, and these compromised trusted domains defeat reputation allowlists.

### Cited Findings
- Mobile gap: see the PhishTime table in Q3. The authors recommend "stronger protections on mobile devices" and evidence-based reporting. Google acknowledged the mobile gap after disclosure. — [PhishTime](https://adamdoupe.com/publications/phishtime_usenix_2020.md)
- PHILTER (Tables 6–7):
  - Client-side detectors (n=23) reach 61% high privacy, against 12% for server-side.
  - Real-time (<1 s) detectors reach 54% high privacy, against 16% for non-real-time.
  - Both groups are weaker on F2, S1 and S2. "Client-side systems trade stronger privacy for weaker fulfillment of most other requirements."
  — [PHILTER §6.2](https://www.usenix.org/system/files/usenixsecurity26-alam.pdf)
- Browser latency budget is "a few hundred milliseconds". Screenshot methods take about 2 s. — [Divakaran & Oest](https://ar5iv.labs.arxiv.org/html/2205.07411)
- Indonesia: "Just Dork and Crawl: Measuring Illegal Online Gambling Defacement in Indonesian Websites" (ITB and Radboud). 453 defaced pages were found in one month, and site owners reacted after 75.3 h on average. Government and education sites are increasingly targeted. **[preprint]** — [arXiv 2508.19368](https://arxiv.org/html/2508.19368v1)
- SOCRadar: 59.62% of phishing sites seen in Indonesia use HTTPS, and 4,046 phishing attacks were counted in Indonesia (2024 report). **[vendor]** — [SOCRadar Indonesia 2025](https://socradar.io/wp-content/uploads/2025/08/Indonesia-Threat-Landscape-Report-2025.pdf); [SOCRadar Indonesia 2024](https://socradar.io/wp-content/uploads/2024/08/SOCRadar-Indonesia-Threat-Landscape-Report-2024.pdf)
- An Indonesian e-commerce study found 22 of 31 platforms "can be easily replicated" with SET for phishing. Peer-reviewed, local journal. — [IJAAS](https://ijaas.iaescore.com/index.php/IJAAS/article/view/21819)

### Inferences
- PHILTER's taxonomy places Shoo's design in a near-empty cell: a client-side, real-time identity check. The brand table and favicon hashes live on the device. The server supplies only signed updates of brand-to-domain data and receives at most a hostname for escalation.
- Indonesian compromised `.go.id` and `.ac.id` hosts mean a "trusted TLD or old domain" allowlist must not suppress an identity mismatch. A bank login form on a defaced campus site is still a mismatch.
- Non-English pages hurt text-based brand extraction more than favicon or field-id matching, which are language-independent. This favours the hash and DOM-identity signals for Indonesian brands. The Indonesian brand table (BCA, BRI, Mandiri, BNI, DANA, OVO, GoPay, ShopeePay, J&T, JNE and similar) must be built by the team; no academic reference list exists.

### Gaps
- No peer-reviewed Indonesian or Southeast Asian phishing-website measurement or labelled dataset was found (the earlier note `visual_llm.md` Q5 reached the same conclusion).
- No iOS-specific evaluation of any in-browser phishing detector after PhishTime was found. Safari's own Fraudulent Website Warning has no published mobile coverage figures after 2020.

---

**DOIs and links for MyLoft (paywalled or blocked in this pass)**
- Das et al., IEEE COMST 22(1) 2020 — DOI 10.1109/COMST.2019.2957750 (from memory; check). Open copy: arXiv 1911.00953.
- Divakaran & Oest, IEEE Security & Privacy 2022 — DOI not confirmed in this pass; open copy arXiv 2205.07411.
- Sánchez-Paniagua et al., IEEE Access 2022 — 10.1109/ACCESS.2022.3168681 (open access on IEEE, but blocked to the crawler).
- Sánchez-Paniagua et al., Expert Systems with Applications 207 (2022) 118010 — 10.1016/j.eswa.2022.118010.
- Kondracki et al., ACM CCS 2021 — 10.1145/3460120.3484765.
- Saha Roy et al., "Phishing in the Free Waters" (ACM, 2023) — DOI not confirmed; open copy arXiv 2212.02563.
- Safi & Singh, J. King Saud Univ. CIS (2023) — DOI not confirmed.
- "Phishing Webpage Detection: Unveiling the Threat Landscape…", IEEE COMST 27(2) — DOI not confirmed.
- Open access: PHILTER (USENIX Sec 2026), Arp et al. (USENIX Sec 2022), PhishTime (USENIX Sec 2020), Whittaker et al. (NDSS 2010).
