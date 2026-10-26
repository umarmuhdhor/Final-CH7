# URL-level and infrastructure-level features for phishing / scam website detection

Scope: URL lexical features, domain age / WHOIS / RDAP, DNS (A/MX/NS, TTL, fast-flux), hosting / IP / ASN reputation, TLS certificate features and Certificate Transparency (CT), typosquatting / homoglyph / combosquatting. Deployment lens: Shoo (iOS Safari Web Extension, MV3) + Cloudflare Workers server that may only receive the registrable domain (eTLD+1) unless the user reports the page. Existing system: blocklist match, on-device lookalike / brand+keyword / cheap-TLD rules, server-side RDAP domain age.

Notation used in Inferences: **[D]** = computable on-device from URL/page; **[S]** = needs a server (network lookups, third-party data, or big reference sets); **[S-domain]** = server can do it from the registrable domain only, so it fits the privacy rule; **[S-URL]** = needs full URL/path, so only allowed after a user report.

Source-quality note: arXiv preprints are flagged "(preprint)". Snippet-only findings (not verified against full text) are flagged "(snippet-level)". Pre-2019 findings are flagged "(older)".

---

## Q1. Which URL lexical and domain features rank highest in feature-importance studies? How do URL-only models compare with content-based models?

### Takeaway
URL-only models report 91–99% accuracy on curated datasets, but the rankings do not hold up across datasets. In the one controlled benchmark found, "external" domain-reputation features (search-index presence, PageRank, domain age, WHOIS) beat pure URL-string features, and URL-string features beat HTML content features. Combining URL and external features gave almost all of the gain. No study shows a stable "top feature". Cross-dataset SHAP work finds importances are dataset-dependent. Realistic, cheap evasion costs 3–10% detection, and multi-space evasion can drive detection to 0.

### Cited Findings
**Headline accuracies (URL-only and hybrid)**
- (older, 2009) Lexical plus host-based URL features (WHOIS, IP/ASN, DNS properties) gave classifiers with 95–99% accuracy and "only modest false positives". The authors frame URL classification as a complement to blacklists, which cannot judge unseen URLs. — [Ma, Saul, Savage, Voelker, "Beyond Blacklists: Learning to Detect Malicious Web Sites from Suspicious URLs", ACM KDD 2009, pp. 1245–1254, doi:10.1145/1557019.1557153](https://cseweb.ucsd.edu/~jtma/papers/beyondbl-kdd2009.pdf)
- Random Forest with only NLP-based URL features reached 97.98% accuracy. The same group's earlier UBMK 2017 version reached 89.9%. — [Sahingoz, Buber, Demir, Diri, "Machine learning based phishing detection from URLs", Expert Systems with Applications 117 (2019), doi:10.1016/j.eswa.2018.09.029](https://openaccess.marmara.edu.tr/entities/publication/5530ff7a-6420-4b75-9dbc-52cd2af7dfe7/full); [Buber, Diri, Sahingoz, UBMK 2017](https://archive.cps-vo.org/node/42652)

**Controlled comparison: URL vs content vs external features (the most useful study for this question)**
- Setup: 11,430 balanced URLs, 87 features in three classes: URL-based (56), content-based (24), external-service (7: WHOIS-registered, registration length, domain age, web traffic, DNS record, Google index, PageRank). Random Forest results: **external-only 94.09%**, **URL-only 91.03%**, **content-only 89.87%**. **URL+external 96.60%**. All 87 features: 96.61% (same macro-F1 of 96.60%). Filter-based feature selection: 96.83%. The authors conclude no single class is enough on its own. — [Hannousse & Yahiouche, "Towards benchmark datasets for machine learning based website phishing detection: An experimental study", arXiv:2010.12847 (journal version: Engineering Applications of Artificial Intelligence, 2021)](https://arxiv.org/abs/2010.12847)
- In the same study, `google_index` (is the URL indexed by Google) ranked #1 under all four filter methods (chi-square, Pearson, information gain, Relief). Seven features appeared in every filter's top 25. They include google_index, page_rank, the 'www' token count, the digit ratio in the URL, domain-in-title, the ratio of internal hyperlinks, and one external WHOIS-derived feature (f83, which by the dataset's column order is domain_age; this mapping is my reading of the column order). Those 7 features alone gave 94.67%. Statistical URL features (counts and ratios) were the best-represented class in the top 25 (20–60%). "Abnormal content" features were the worst (8–12%). — [Hannousse & Yahiouche, arXiv:2010.12847](https://arxiv.org/abs/2010.12847)
- Replicating Choo et al. (only 3 external features) on the same data gave 86.42%. Logistic regression on content features gave 77.11% vs 86.46% for RF. The authors read this as evidence that earlier results are dataset-dependent. — [Hannousse & Yahiouche, arXiv:2010.12847](https://arxiv.org/abs/2010.12847)

**Feature-importance instability (SHAP / XAI)**
- Models trained on one public phishing-URL dataset and tested on another (more than 108K unique URLs in total) showed that SHAP-identified features "can often be dataset-dependent and thus may not be trusted across different datasets even though they share same set of feature behaviors". — [Mia, Derakhshan, Pritom, "Can Features for Phishing URL Detection Be Trusted Across Diverse Datasets? A Case Study with Explainable AI", NSysS 2024, arXiv:2411.09813](https://arxiv.org/abs/2411.09813)
- (snippet-level) SHAP magnitudes on the UCI dataset were about ±0.35–0.40, versus about ±0.003 on a GenAI-phishing dataset. Top XGBoost features differed by dataset: `URL_of_anchor` and `SSLfinal_State` in one, URL length in another. — [arXiv:2411.06860, "Enhancing Phishing Detection through Feature Importance Analysis and Explainable AI: A Comparative Study of CatBoost, XGBoost, and EBM Models" (preprint)](https://arxiv.org/pdf/2411.06860)
- (snippet-level, patent, not peer-reviewed) In one industry phishing-domain classifier, lexical features ranked lowest in importance. The authors attribute this to squatting being only a small share of phishing domains. — [US Patent 11,546,377, "Phishing domain detection systems and methods"](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11546377)
- (snippet-level) A hybrid lexical + metadata study reports that the two feature groups are "orthogonal". Lexical features do the initial discrimination; metadata stabilizes ambiguous URLs. — [“Lightweight Phishing URL Detection Using Hybrid Lexical–Metadata Features” (ResearchGate)](https://www.researchgate.net/publication/398633219_Lightweight_Phishing_URL_Detection_Using_Hybrid_Lexical-Metadata_Features_A_Machine_Learning_Approach)
- (snippet-level) Domain age and domain registration length ranked among the top SHAP features in an email-URL study. Separately, an RF study listed URL structure, domain age and login forms as key contributors. — [Scientific Reports 2025, "Explainable phishing website detection for secure and sustainable cyber infrastructure"](https://www.nature.com/articles/s41598-025-27984-w)

**Evasion and drift (cross-cutting weaknesses)**
- 18 ML phishing-website detectors were tested against 12 realistic evasion attacks. Cheap "problem-space" perturbations (for example, URL edits and shorteners) caused a statistically significant 3–10% drop in detection (p<0.05). Some detectors were immune to the most realistic attacks (p=0.22). Perturbations in several evasion spaces at once dropped the detection rate **from 0.95 to 0**. — [Yuan, Apruzzese, Conti, "Multi-SpacePhish: Extending the Evasion-space of Adversarial Attacks against Phishing Website Detectors using Machine Learning", arXiv:2210.13660 (journal extension of SpacePhish, ACSAC 2022)](https://arxiv.org/abs/2210.13660)
- (snippet-level) Most phishing-URL models are evaluated "under clean conditions". They do not test homoglyph substitution or subdomain reordering. — [“Adversarial-resilient lightweight phishing URL detection: Evaluating lexical & metadata features under evasion techniques”, PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC13507141/)
- (snippet-level) One concept-drift study evaluated on a 13-month URL stream of 2.4 million samples sorted by time, the kind of temporal split that random train/test splits hide. — [Becker, Hartmann, Schneider, "Handling Concept Drift in Phishing Detection: An Online Ensemble with Drift-Aware Reweighting", SSRN](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6089348)

### Inferences
- The 97–99% accuracies are on random splits of static, often leaky datasets (see Q6). Expect much lower real-world precision at a usable false-positive rate. Shoo should judge features by precision at a fixed low FPR on a time-split test, not by accuracy.
- The Hannousse result says the best cheap boost over URL lexical features is **domain reputation and popularity** (search-index presence, rank lists, domain age). In Shoo terms, that is a **[S-domain]** lookup: Tranco/CrUX-style popularity rank plus RDAP age. Shoo already has age. A **popularity / top-list allowlist** is the most obvious missing piece. It cuts FPs on legitimate sites and is a strong benign signal. Google-index queries are not practical (ToS, rate limits).
- Lexical features: **[D]**. Length, digit ratio, hyphens, subdomain depth, IP-as-host, `@`, many dots, entropy, suspicious keywords, TLD. They are cheap and private but easy to evade, and their rank shifts between datasets. Use them as weak signals that feed a score, not as hard blockers.
- Full-path lexical features (path length, query tokens, `login`/`verify` in the path) are only usable **[D]**. Sending the path to the server breaks the privacy rule unless the user reports the page.

### Gaps
- No peer-reviewed SHAP ranking found that holds across 3+ independent datasets with a temporal split. The XAI numbers above are mostly snippet-level.
- URLNet (Le et al., 2018, char/word CNN) and ISCX-URL2016 (Mamun et al., 2016) results were not verified in this pass.
- No study found that measures URL-only vs URL+content accuracy on a mobile/SMS-scam population (the Shoo threat model), as opposed to email/PhishTank URLs.

---

## Q2. How useful is domain age / WHOIS / RDAP today (post-GDPR)? Effective thresholds?

### Takeaway
Domain age is still among the most informative single signals, because most phishing domains are now registered by the criminals themselves and used within days to weeks. 77% of 2024–25 phishing domains were maliciously registered. The median time from registration to blocklist detection is 16.3 days. But GDPR redaction and RDAP gaps mean registration dates are missing for a large share of domains: WHOIS+RDAP alone covered only 62.4% in one large study. Age also cannot catch compromised legitimate sites or abuse on free subdomain platforms (13% of attacks), and it flags legitimate new sites. No peer-reviewed paper gives an optimal day threshold. The evidence supports a "very new" window of about 30 days or less, plus a weaker band up to about 1 year.

### Cited Findings
**How fast phishing domains are used**
- In a study of 690,502 phishing domains over 39 months, 66.1% were maliciously registered (not compromised). The **median time from registration to detection was 16.3 days** for maliciously registered domains, versus 86 days for compromised ones. Domains stayed reachable an average of 11.5 days after detection. Attackers favored cheap TLDs such as .top and .tk. — [Lim, Sommese, Jonker, Mok, claffy, Kim, "Registration, Detection, and Deregistration: Analyzing DNS Abuse for Phishing Attacks", arXiv:2502.09549, 2025 (preprint)](https://arxiv.org/abs/2502.09549)
- In the same study, registration timestamps from **WHOIS and RDAP alone covered only 62.4% (431,011) of domains**. Adding zone files, passive DNS and CT logs raised coverage a lot. The authors had to estimate timestamps for redacted or missing domains. — [Lim et al., arXiv:2502.09549](https://arxiv.org/abs/2502.09549)
- Detection lag varies by blocklist. Measured after APWG's own detection, PhishTank had a median lag of 4.4 days and OpenPhish 4.1 days. Phishunt.io had a median of 930.8 days. APWG-listed domains had a median detection time of 42.4 days. Well-known brands were detected faster (USPS median 1.4 days, OZON 1.3 days). — [Lim et al., arXiv:2502.09549](https://arxiv.org/abs/2502.09549)
- (preprint) In a 2026 dataset, 21.0% of phishing domains were 0–7 days old, while 91.5% of benign domains were older than five years. — [PhiShark2026, arXiv:2608.23199 (preprint)](https://arxiv.org/pdf/2608.23199)

**Malicious registration share, bulk registration, TLDs (industry measurement, May 2024 – Apr 2025)**
- 77% of phishing domains were maliciously registered, a 36% year-on-year rise in malicious registrations. Nearly 9 in 10 phishing domains in new gTLDs were maliciously registered. 37% of phishing domains were registered in bulk, up from 27%. Subdomain-provider abuse fell 44%. — [Interisle Consulting Group, "Phishing Landscape 2025"](https://static1.squarespace.com/static/63dbf2b9075aa2535887e365/t/68dfd315512a675a8fd94ee8/1759499029838/phishinglandscape2025.pdf); [press release](https://interisle.net/press/pl2025-press-release)
- New gTLDs held 11% of the domain market but 51% of reported phishing domains, up from 9% / 21% in 2021. .COM/.NET's share of phishing domains fell to 32%, from 37% the year before and 54% in 2020. ccTLDs fell to 11%. By maliciously registered share: new gTLDs 87%, .COM/.NET 67%, legacy gTLDs 79%, ccTLDs 60%. — [Interisle, Phishing Landscape 2025](https://static1.squarespace.com/static/63dbf2b9075aa2535887e365/t/68dfd315512a675a8fd94ee8/1759499029838/phishinglandscape2025.pdf)
- The top-5 TLDs by phishing score (phishing domains per registered domains) were .xin, .bond, .help, .win and .cfd. — [Domain Name Wire, 11 Sep 2025, reporting Interisle PL2025](https://domainnamewire.com/2025/09/11/report-names-commonly-used-tlds-for-phishing-attacks/)
- In 37,000 "Unpaid Toll" SMS scam attacks, 65% were registered at a single registrar, 49% in a single TLD, and 33% at a single hosting company. — [Interisle, Phishing Landscape 2025](https://static1.squarespace.com/static/63dbf2b9075aa2535887e365/t/68dfd315512a675a8fd94ee8/1759499029838/phishinglandscape2025.pdf)

**Where domain age fails**
- 13% of attacks (256,026, on 701 second-level domains) used subdomain providers, where the registrable domain is old and reputable. 89% of these were on just 10 providers. Hostinger, Webflow, Weebly, DuckDNS and gitbook.io appear in the 5-year rankings. — [Interisle, Phishing Landscape 2025](https://static1.squarespace.com/static/63dbf2b9075aa2535887e365/t/68dfd315512a675a8fd94ee8/1759499029838/phishinglandscape2025.pdf)
- Almost 60% of abusive combosquatting domains stayed active for more than 1,000 days, so old age does not mean benign. — [Kintis et al., "Hiding in Plain Sight: A Longitudinal Study of Combosquatting Abuse", ACM CCS 2017, doi:10.1145/3133956.3134002](https://arxiv.org/abs/1708.08519)
- Compromised domains (33.9% in Lim et al.) are aged legitimate domains. An older estimate cited in a CT paper put 62–73% of phishing sites on compromised infrastructure. — [Lim et al., arXiv:2502.09549](https://arxiv.org/abs/2502.09549); [Drichel et al., arXiv:2106.12343](https://arxiv.org/abs/2106.12343)

**Post-GDPR WHOIS / RDAP data quality**
- A study of 1.2 billion WHOIS records found that more than 85% of large WHOIS providers redact EEA records at scale, and more than 60% also redact non-EEA records. The authors call the impact on security applications "prominent". — [Lu, Liu, et al., "From WHOIS to WHOWAS: A Large-Scale Measurement Study of Domain Registration Privacy under the GDPR", NDSS 2021](https://www.ndss-symposium.org/wp-content/uploads/ndss2021_2A-2_23134_paper.pdf)
- Most fields that could hold personal data are redacted by default. Creation dates sometimes differ between WHOIS and RDAP, partly because different entities define "Creation Date" differently. — ["WHOIS Right? An Analysis of WHOIS and RDAP Consistency", PAM 2024](https://pam2024.cs.northwestern.edu/pdfs/paper-89.pdf)
- RDAP use for phishing investigations is still hindered by low RDAP adoption among ccTLD registries, strict rate limiting, inconsistent data representation, and privacy-driven unavailability. — ["Investigating Phishing Attacks using the Registration Data Access Protocol", CEUR-WS Vol-3631](https://ceur-ws.org/Vol-3631/paper6.pdf)

**Registration-time reputation (beyond age)**
- PREDATOR uses only features available at registration time (registrar, timing, bulk/batch patterns, name profile). It reached a **70% detection rate at a 0.35% false-positive rate** on five months of .com/.net registrations, often days or weeks before blacklists. — [Hao, Kantchelian, Miller, Paxson, Feamster, "PREDATOR: Proactive Recognition and Elimination of Domain Abuse at Time-Of-Registration", ACM CCS 2016](https://www2.cs.uh.edu/~gnawali/courses/cosc6377-s19/papers/Hao16.pdf) (older)

### Inferences
- Domain age is **[S-domain]**: the RDAP lookup needs only eTLD+1, which matches Shoo's privacy rule. Keep it.
- Suggested bands, based on the median 16.3-day detection lag, bulk registration, and 21% of phishing domains aged 0–7 days. These are an inference, not a validated threshold:
  - **≤7 days**: strong risk.
  - **8–30 days**: moderate risk.
  - **31–365 days**: weak risk.
  - **>1 year**: neutral.
  Combine age with TLD and lookalike signals instead of blocking on age alone, because new legitimate shops and campaign sites also fall in the ≤30-day band.
- RDAP gaps: some ccTLDs have no RDAP, and creation dates may be missing. Treat "unknown age" as missing, not as risky. Use a fallback source for first-seen dates: the earliest CT-log certificate for the domain (crt.sh-style query, **[S-domain]**). This is the same fallback Lim et al. used to raise coverage.
- Shoo's on-device cheap-TLD list should be data-driven. Interisle's per-TLD phishing scores give a public basis (.xin, .bond, .help, .win, .cfd, .top, and others) and should be refreshed yearly.
- Age gives no signal for subdomain-platform abuse (for example `*.webflow.io`, `*.weebly.com`, `*.duckdns.org`). For these, **[D]** logic should treat the *full hostname under a known free-hosting / dynamic-DNS suffix* as the unit of reputation, since eTLD+1 age is meaningless there. The Public Suffix List "private" section covers many of these platforms. Sending the full hostname (not the path) for these platforms could be argued to fit the privacy rule. That needs a team decision (CLAUDE.md rule 7: issue to lead).

### Gaps
- No peer-reviewed study found that sweeps domain-age thresholds (for example 7/30/90/365 days) and reports precision/recall at each.
- No study found that isolates how GDPR redaction reduces the accuracy of age-based classifiers.
- Lim et al. is a preprint. Its exact registration-to-*first-use* distribution (as opposed to registration-to-detection) was not extracted.

---

## Q3. How useful are TLS certificate features and CT logs now that most phishing uses HTTPS? Is "no HTTPS" still meaningful?

### Takeaway
HTTPS is no longer a trust signal. HTTPS use on phishing sites rose from 25% (Q3 2017) to about 83% (Q1 2021). Free CAs (Let's Encrypt, Google Trust Services) dominate both phishing and ordinary small legitimate sites. Certificate fields alone (issuer, 90-day validity, SAN count) separate phishing from *popular* sites but not from *unpopular* legitimate sites, which is the comparison that matters for false positives. CT logs are useful as an **early-warning feed of newly certified lookalike domain names**. Nearly all the discriminative power there comes from the domain-name string (brand keywords, Levenshtein distance, TLD), not from certificate fields. Even then, false positives at CT scale are large.

### Cited Findings
**HTTPS adoption by phishers**
- 25% of phishing sites used HTTPS in Q3 2017, 35% in Q2 2018, and 49% in Q3 2018. — [PhishLabs data cited in Fasllija, Enişer, Prünster, "Phish-Hook: Detecting Phishing Certificates Using Certificate Transparency Logs" (SecureComm 2019)](https://tugraz.elsevierpure.com/ws/portalfiles/portal/25394076/156259641564590.pdf)
- 68% in Q3 2019 and 74% by end of 2019. — [PhishLabs, "APWG: two-thirds of phishing sites use SSL/HTTPS"](https://www.phishlabs.com/blog/apwg-two-thirds-phishing-sites-ssl-https); [PhishLabs, "Top phishing trends 2019"](https://www.phishlabs.com/blog/top-phishing-trends-2019)
- About 83% in Q1 2021, flat for two quarters. — [Security Affairs reporting the APWG Q1 2021 Phishing Activity Trends Report](https://securityaffairs.com/118908/cyber-crime/apwg-phishing-record-q1-2021.html)
- APWG's 2025 quarterly reports give volumes (Q1 2025: 1,003,924 attacks; Q2: 1,130,393; Q3: 892,494; Q4: 853,244). No HTTPS share was found in them. — [APWG Q1 2025](https://docs.apwg.org/reports/apwg_trends_report_q1_2025.pdf); [Q2 2025](https://docs.apwg.org/reports/apwg_trends_report_q2_2025.pdf); [Q3 2025](https://docs.apwg.org/reports/apwg_trends_report_q3_2025.pdf); [Q4 2025](https://docs.apwg.org/reports/apwg_trends_report_q4_2025.pdf)

**Certificate-field features vs. the right baseline**
- In the Danish .dk namespace (762 phishing, 1,260 popular, 2,000 unpopular domains): Let's Encrypt + Google Trust Services issued **87.4% of phishing certificates and 74.6% of popular** ones. Let's Encrypt alone issued **87.6% of unpopular** (legitimate) ones. Median and mode validity were the same about-90-day value for all three groups. Mean SAN count was 0.80 (phishing), 3.01 (popular), 0.99 (unpopular). SAN similarity differed significantly between phishing and popular sites but not between phishing and unpopular sites. Conclusion: "no single analyzed feature provides a strong standalone indication of phishing activity". About 20% of phishing domains had one hyphen, versus about 5% of popular domains. Limitation: only 35.4% of phishing domains had certificate data. — [Pelekoudas, Bolis, Lindner, Kyriakidis, Davidsen, Hansen, Reichkendler, Homayoun, "TLS Certificate and Domain Feature Analysis of Phishing Domains in the Danish .dk Namespace", arXiv:2603.21652, 2026 (preprint)](https://arxiv.org/abs/2603.21652)
- In a CT-log sample, Let's Encrypt issued more than 52% of all certificates, across 176 distinct CAs. — [Ostertág, "Anomaly Detection in Certificate Transparency Logs", arXiv:2405.05206, 2024 (preprint)](https://arxiv.org/abs/2405.05206)
- 691,182 certificates were issued to 107,572 combosquatting FQDNs (2013 onward), 41.5% of them by Let's Encrypt. Only 3,011 were issued to typosquatting domains. — [Kintis et al., CCS 2017](https://arxiv.org/abs/1708.08519) (older)
- (older) A deep-learning model on 30+ certificate features detected malware certificates at 94.8% accuracy and phishing certificates at 88.6%. A later CT-pipeline study could not reproduce their ~90% precision. — [Torroledo et al. as cited in Phish-Hook](https://tugraz.elsevierpure.com/ws/portalfiles/portal/25394076/156259641564590.pdf); [Drichel et al., arXiv:2106.12343](https://arxiv.org/abs/2106.12343)

**CT-log monitoring for phishing**
- Phish-Hook classifies CT-log entries near real time with 8 features. Seven are domain-name features: Levenshtein distance to brand keywords, deeply nested subdomains, suspicious TLD, inner TLD inside the subdomain, suspicious keywords, Shannon entropy, and hyphens in the subdomain. One is a certificate feature: issued by a free CA. It reports accuracy, precision, recall and F1 all above 90%, with SVC best. It was evaluated on the UCI dataset, not live CT data. — [Fasllija, Enişer, Prünster, Phish-Hook, SecureComm 2019](https://tugraz.elsevierpure.com/ws/portalfiles/portal/25394076/156259641564590.pdf)
- On *real* CT data (one week of Google Xenon logs), a fixed FPR of 10⁻³ meant **22,510 false positives per week**. 10⁻⁴ meant 2,251. The rule-based "Phishing Catcher" (keyword, suspicious TLD and Let's Encrypt-issuer rules) beat RF and RNN models at 10⁻³. A regex classifier (Sakurai et al.) did best at 10⁻⁴. ML models suffered from noisy labels: certificates of phishing pages on compromised hosts are benign certificates. — [Drichel, Drury, von Brandt, Meyer, "Finding Phish in a Haystack: A Pipeline for Phishing Classification on Certificate Transparency Logs", arXiv:2106.12343, 2021](https://arxiv.org/abs/2106.12343)
- Certificates carry less information than URLs: no path, and sometimes wildcard SANs hide subdomains. — [Drichel et al., arXiv:2106.12343](https://arxiv.org/abs/2106.12343)
- Attackers may move to providers like Cloudflare for free TLS. — [Lim et al., arXiv:2502.09549](https://arxiv.org/abs/2502.09549)

### Inferences
- "No HTTPS" is now a weak risk signal (most phishing has HTTPS, and Safari already warns on HTTP pages). It is not a trust signal. "Has HTTPS" or "Let's Encrypt issuer" alone should carry ~zero weight, since free CAs are the norm for small legitimate sites.
- Certificate inspection in the browser: Safari Web Extension APIs do not expose the page's certificate chain (no `webRequest.getSecurityInfo` as in Firefox). So cert fields would be **[S-domain]**: the Worker opens a TLS connection or queries CT for eTLD+1. This is my reading of the platform, not verified in this pass.
- Highest-value CT use for Shoo: a **[S-domain] first-seen date** (earliest certificate for the domain in CT) as an age fallback when RDAP has no date. Second: an offline/batch **CT stream watcher** that pre-lists newly certified domains matching Indonesian brand + keyword patterns, feeding the blocklist proactively. This is a backend job (Cloudflare Worker cron or an external service). Budget for heavy FP review: Drichel shows thousands of FPs per week even at 10⁻⁴.
- Low SAN count, 90-day validity and a free CA are "unpopular site" traits, not "phishing" traits. Using them would raise FPs on small Indonesian UMKM shops.

### Gaps
- No APWG/Interisle 2024–2026 HTTPS-share number found. The latest verified figure is ~83% (Q1 2021).
- No peer-reviewed study found that measures the gap from certificate issuance (CT) to phishing launch for a modern dataset.
- Phish-Hook's venue (SecureComm 2019) is from my knowledge. The PDF text checked did not show it.

---

## Q4. DNS / hosting / ASN features: effectiveness and cost

### Takeaway
DNS and hosting features are informative in aggregate. Phishing uses short TTLs more often, clusters in specific networks and registrars, and changes records. But few recent papers isolate their accuracy gain for phishing websites. Each needs resolver or passive-DNS / IP-to-ASN data, so they are server-side only. Their main practical value for Shoo is cheap **[S-domain]** reputation (ASN/hosting concentration, NS/registrar patterns). Fast-flux is now a minor share.

### Cited Findings
- Among maliciously registered phishing domains: 21.4% changed DNS records (mean interval 79.4 days, median 125.2). 2.1% used TTL < 60 s and 25.8% used TTL < 1 h. Median TTL was 3,994 s and mean 60,827 s. Only 2.9% set TTL > 12 h. No evidence was found of geo-dependent DNS answers (localization was done client-side). Short TTLs "can facilitate" fast-flux. — [Lim et al., arXiv:2502.09549](https://arxiv.org/abs/2502.09549)
- Malicious combosquatting domains concentrate in hosting: almost 58% were in a single CIDR/AS, versus 38% of all combosquatting domains. — [Kintis et al., CCS 2017](https://arxiv.org/abs/1708.08519) (older)
- More than half of phishing attacks worldwide were hosted with US-based companies, for 5 years in a row. Campaign infrastructure clusters: 33% of Unpaid Toll scam sites were at one hosting company. — [Interisle, Phishing Landscape 2025](https://static1.squarespace.com/static/63dbf2b9075aa2535887e365/t/68dfd315512a675a8fd94ee8/1759499029838/phishinglandscape2025.pdf)
- External DNS features help in a controlled benchmark. The 7 external features (including `dns_record`, `web_traffic`, WHOIS-registered, domain age) beat URL-only features: 94.09% vs 91.03%. — [Hannousse & Yahiouche, arXiv:2010.12847](https://arxiv.org/abs/2010.12847)
- (older) Host-based features (IP/ASN, WHOIS, DNS TTL, geolocation) added to lexical features gave the 95–99% result. — [Ma et al., KDD 2009](https://cseweb.ucsd.edu/~jtma/papers/beyondbl-kdd2009.pdf)
- (older) Registration-time features (registrar, NS, batch registration) gave 70% TPR at 0.35% FPR. — [Hao et al., PREDATOR, CCS 2016](https://www2.cs.uh.edu/~gnawali/courses/cosc6377-s19/papers/Hao16.pdf)
- Active-DNS data (OpenINTEL, about 65% of the namespace snapshotted daily) can flag suspicious IDN homograph domains from the name plus DNS records, finding about 2.97× more homographs than existing confusable tables. — [Yazdani, van der Toorn, Sperotto, "A Case of Identity: Detection of Suspicious IDN Homograph Domains Using Active DNS Measurements", IEEE EuroS&PW 2020](https://oliviervandertoorn.nl/papers/eurospw2020.pdf)

### Inferences
- Cost / placement:
  - A/AAAA/NS/MX lookups via DNS-over-HTTPS from a Worker, **[S-domain]**: cheap (one or more DoH queries, cacheable).
  - IP-to-ASN mapping, **[S-domain]**: needs a free or commercial ASN DB in KV or R2.
  - Passive DNS history, **[S-domain]**: needs a paid feed. Probably not worth it for Shoo's MVP.
  - The extension cannot do raw DNS on iOS **[D-not possible]**.
- The best value per cost is probably:
  - "No MX + new domain + brand-like name" combined (heuristic, not validated in the literature found).
  - An ASN / hosting-provider risk prior learned from Shoo's own confirmed reports.
  - An allowlist for big platforms (Cloudflare, Google, AWS), so the ASN feature does not punish everyone using them.
- Treat Cloudflare-fronted IPs as no-information: many phishing and legitimate sites share them.

### Gaps
- No 2019–2026 peer-reviewed ablation found that quantifies the accuracy gained by DNS/ASN features alone for phishing *websites*. Most DNS-reputation literature (EXPOSURE, Notos) targets malware/botnet domains and is older.
- No current measurement found of fast-flux share among phishing domains. Only the TTL distribution above.
- MANTIS ([arXiv:2502.09788](https://arxiv.org/pdf/2502.09788), low-reputation hosting infrastructure for zero-day malicious domains) was found but its results were not verified.

---

## Q5. Typosquatting / homoglyph / punycode / combosquatting detection methods and effectiveness

### Takeaway
**Combosquatting (brand + keyword) is by far the dominant lookalike form**: about 100× more prevalent than typosquatting, long-lived, and slow to be blacklisted. Edit-distance typo detection alone misses it. IDN homograph detection depends on the confusable table: Unicode's confusables list finds about 8× fewer homographs than an extended visual-similarity table. Most lookalike checks are cheap on-device string operations. Their main weaknesses are FPs from legitimate brand-related domains and evasion through new keywords and characters.

### Cited Findings
**Combosquatting**
- From 468 billion DNS records over about 6 years: 2.7 million combosquatting domains targeting 268 popular US trademarks, **100× more prevalent than typosquatting**. Almost 60% of abusive combosquatting domains lived more than 1,000 days. 20% appeared on a public blacklist only about 100 days after first DNS resolution (30% for those seen in malware feeds). Queries to combosquatting domains grew year over year, unlike typosquatting. 50% add at most 8 characters to the trademark, and 90% have at most three words. — [Kintis, Miramirkhani, Lever, Chen, Romero-Gómez, Pitropakis, Nikiforakis, Antonakakis, "Hiding in Plain Sight: A Longitudinal Study of Combosquatting Abuse", ACM CCS 2017, doi:10.1145/3133956.3134002](https://arxiv.org/abs/1708.08519) (older)
- Standard typosquat detection (edit-distance-1 mutations) misses appended words, so it does not catch combosquats. — [PhishHunter, Computers & Security (Elsevier)](https://www.sciencedirect.com/science/article/abs/pii/S0167404823005783) (snippet-level)

**IDN homographs / punycode**
- ShamFinder (.com, 955K registered IDNs): Unicode Confusables (UC) alone found **436 homographs**. The authors' SimChar visual-similarity table found **3,110+**. Combined found **3,280 (about 8× UC)**. Top targets: myetherwallet.com (170), google.com (114), amazon.com (75), facebook.com (72), allstate.com (68). Data and code: github.com/shamfinder. — [Suzuki, Chiba, Yoneya, Mori, Goto, "ShamFinder: An Automated Framework for Detecting IDN Homographs", ACM IMC 2019, arXiv:1909.07539](https://arxiv.org/abs/1909.07539)
- OCR-based similarity on 3.19 million registered IDNs and 10,000 malicious IDNs found homographs the conventional method missed. — [Sawabe et al., Journal of Information Processing 27 (2019)](https://www.jstage.jst.go.jp/article/ipsjjip/27/0/27_536/_article) (older)
- PhishMatch pipeline: punycode to Unicode, NFKD normalization, Unicode confusables mapping to ASCII, then brand matching. The confusables map alone misses accented-character substitutions. — [PhishMatch: A Layered Approach for Effective Detection of Phishing URLs, arXiv:2112.02226](https://arxiv.org/abs/2112.02226)
- PhishHunter (Siamese neural network on rendered domain images) reports higher accuracy and lower FPR for homographs, and also identifies typosquatting. The authors note that SSIM-based visual methods have a high FPR because they "always mistake typosquatting domain names as homograph ones". — [PhishHunter: Detecting camouflaged IDN-based phishing attacks via Siamese neural network, Computers & Security](https://www.sciencedirect.com/science/article/abs/pii/S0167404823005783) (snippet-level; exact numbers not verified)
- Active-DNS-assisted homograph detection found about 2.97× more homographs than existing tables. — [Yazdani et al., EuroS&PW 2020](https://oliviervandertoorn.nl/papers/eurospw2020.pdf)

**Typosquatting / generated squats**
- PhishReplicant uses a language model to detect *generated* squatting domain names (variants of names already seen). — ["PhishReplicant: A Language Model-based Approach to Detect Generated Squatting Domain Names", arXiv:2310.11763](https://arxiv.org/abs/2310.11763) (author list and results not verified)
- Phish-Hook's top lexical features for brand impersonation: Levenshtein distance to brand keywords under a threshold, suspicious keywords, inner TLD in the subdomain (for example `paypal.com.secure-login.xyz`), hyphens, nested subdomains. — [Phish-Hook](https://tugraz.elsevierpure.com/ws/portalfiles/portal/25394076/156259641564590.pdf)
- In .dk phishing, targets were mostly local businesses (140), retail/e-commerce (113) and IT services (111), not only global brands. — [Pelekoudas et al., arXiv:2603.21652](https://arxiv.org/abs/2603.21652)

### Inferences
- All of these are **[D]**: punycode decoding (`URL` API gives `xn--`; decode with a small punycode library), NFKD plus a confusables or SimChar map, edit distance to a brand list, brand-token + keyword detection, and brand-in-subdomain with a different eTLD+1. They match Shoo's existing on-device lookalike rules.
- Upgrades backed by the evidence:
  1. Use an **extended confusables table**, not UC alone. ShamFinder showed about 8× recall.
  2. Prioritize **brand-token + keyword (combosquat)** over pure typo distance.
  3. Add **brand in subdomain / inner TLD** detection.
  4. Localize the brand list (Indonesian banks, e-wallets, marketplaces, couriers, government services). The .dk study shows local targets dominate.
- FP control: whitelist each brand's official domains, and check that eTLD+1 ≠ brand domain before flagging. Combosquat rules otherwise fire on legitimate partner, fan or news domains. Lookalike plus young age (RDAP) is a much stronger combination than either alone. Inferred from Kintis (long-lived combosquats exist, so age alone misses them) and Lim (new malicious registrations).

### Gaps
- No peer-reviewed precision/recall found for combosquat detection *as a classifier* on a modern dataset. Kintis is a measurement study, and its classifier numbers were not extracted.
- Liu et al., "A Reexamination of Internationalized Domain Names: The Good, the Bad and the Ugly" (DSN 2018) was not found in this pass.
- PhishHunter and PhishReplicant headline numbers were not verified.

---

## Q6. Which public datasets and benchmarks are used, and how trustworthy are they?

### Takeaway
Common benchmarks include PhiUSIIL (UCI), the Mendeley/Hannousse 11,430-URL set, the UCI "Phishing Websites" 11,055×30 set, ISCX-URL2016, and PhishTank/OpenPhish feeds plus Tranco/Alexa for benign URLs. They are small or static, and some leak the label. This explains the inflated 99%+ accuracies. Feeds also lag: maliciously registered domains take a median 16.3 days to detection. Feed labels mix compromised legitimate sites with malicious registrations, which contaminates certificate and domain features.

### Cited Findings
- **PhiUSIIL**: 134,850 legitimate and 100,945 phishing URLs (235,795 total). Published framework accuracy: 99.24% fully incremental and 99.79% pre-trained (figures from secondary sources). — [Prasad & Chandra, "PhiUSIIL: A diverse security profile empowered phishing URL detection framework based on similarity index and incremental learning", Computers & Security 136 (2024) 103545, doi:10.1016/j.cose.2023.103545](https://doi.org/10.1016/j.cose.2023.103545); [UCI ML Repository #967](https://archive.ics.uci.edu/dataset/967/phiusiil+phishing+url+dataset)
- **PhiUSIIL leakage**: an independent (non-peer-reviewed) audit found `URLSimilarityIndex` = 100 for every legitimate URL. The single rule "is it 100?" catches 99.2% of phishing with no false alarms, and all features together give 100%. — [ollivianguy/phishing-url-detection (GitHub audit)](https://github.com/ollivianguy/phishing-url-detection)
- **Hannousse/Mendeley**: 11,430 URLs, balanced 50/50, 87 features. Raw URLs are released so features can be recomputed. The paper also notes that short-lived and dead phishing URLs cannot be used for content features. — [Hannousse & Yahiouche, arXiv:2010.12847](https://arxiv.org/abs/2010.12847)
- **UCI "Phishing Websites"**: 11,055 records, 30 ternary features (several cert- and site-derived). Phish-Hook used it as a proxy. — [Phish-Hook](https://tugraz.elsevierpure.com/ws/portalfiles/portal/25394076/156259641564590.pdf)
- **Cross-dataset**: features trained on one public set did not reliably transfer to another (more than 108K URLs). — [Mia et al., NSysS 2024](https://arxiv.org/abs/2411.09813)
- **Feed lag and coverage**: PhishTank median 4.4 days and OpenPhish median 4.1 days after APWG detection. Maliciously registered domains have a median of 16.3 days from registration to detection. — [Lim et al., arXiv:2502.09549](https://arxiv.org/abs/2502.09549)
- **Label noise**: phishing on compromised hosting means certificates (and age) from feed URLs are often benign. This degraded the ML CT classifiers below rule-based ones. — [Drichel et al., arXiv:2106.12343](https://arxiv.org/abs/2106.12343)
- **CT ground truth**: no complete labeled set of benign or malicious certificates exists. — [Drichel et al., arXiv:2106.12343](https://arxiv.org/abs/2106.12343)
- (preprint) **PhiShark2026**: a multi-layer active-web raw-evidence dataset that includes domain-age distributions. — [arXiv:2608.23199](https://arxiv.org/pdf/2608.23199)

### Inferences
- For Shoo evaluation:
  - Build a **time-split** test set from Indonesian scam reports (Shoo's own user reports, plus PhishTank/OpenPhish entries filtered to .id or Indonesian brands).
  - Use **Tranco top-N plus random "unpopular" .id/.com domains** as negatives. The .dk study shows that popular-only negatives overstate how well features separate the classes.
  - Report precision at a fixed FPR (for example ≤0.1%).
- Do not adopt PhiUSIIL's `URLSimilarityIndex`-style features or its headline accuracy as a target.

### Gaps
- ISCX-URL2016 (UNB CIC) and Vrbančič et al. (2020) Mendeley dataset details were not verified in this pass.
- No public Indonesian- or SEA-specific phishing URL benchmark was found.
- No benchmark found with SMS/WhatsApp-delivered scam URLs, which is closer to Shoo's population than email-sourced PhishTank.
