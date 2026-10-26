# Encoder and decision-style (non-generative) models for phishing and scam detection: academic evidence for Shoo

Research date: 26 Oct 2026. Research only: nothing was installed, trained or called.

Scope and labels:
- This note extends `../Fitur deteksi situs phishing/visual_llm.md`, `laya_jev.md` and `easy_alternatives.md`. It does not repeat their content: ChatPhishDetector, PhishLLM, KnowPhish (including its XLM-R CRP classifier), PhishAgent, Lee et al. eCrime 2024, Goldenits et al. small LMs, the IndoPhis-D URL study, and the Hugging Face model cards (ealvaradob, pirocheto, Akash-Sakala, yondikavl, mDeBERTa-xnli, SetFit blog). Note: the brief said `visual_llm.md` covers PhishLang. It does not; PhishLang is covered here.
- "Preprint" = arXiv or similar with no peer-reviewed venue shown. "Abstract only" = only the abstract page was read. "Snippet only" = the number came from a search-engine summary and the paper was not opened. "Older" = before 2021.
- Paywalled or blocked (HTTP 403) papers have DOIs listed so they can be fetched through MyLoft.
- Shoo layer 4 input: host, title ≤120 chars, ≤12 form-field labels, fired rule ids. It runs on Cloudflare Workers.

## 1. How well do fine-tuned encoders detect phishing (web page, URL, email, SMS), with how much data, and how well do they generalise across datasets and time?

### Takeaway
On in-distribution test splits, fine-tuned encoders (BERT, DistilBERT, RoBERTa, DeBERTa, MobileBERT, IndoBERT) routinely report 94–99% accuracy or F1 for email, SMS, URL and HTML. These numbers are inflated. Public datasets suffer from leakage and unrealistic base rates. Cross-dataset tests show large drops, and almost no study uses a temporal split. The best web-page evidence is PhishLang (NDSS): a 25M-parameter MobileBERT on parsed HTML tags reached F1 0.94–0.96, ran fully client-side in 0.4–0.7 s using about 74–102 MB of RAM, and needed adversarial retraining to resist evasion. No encoder study uses Shoo's sparse input (title + field labels + host).

### Cited Findings
**Web pages (HTML)**
- PhishLang: Sayak Saha Roy, Shirin Nilizadeh (UT Arlington). "PhishLang: A Real-Time, Fully Client-Side Phishing Detection Framework Using MobileBERT". NDSS Symposium listing (the PDF path is `2026-s1037-paper.pdf`); arXiv 2408.05667 v3. — [arXiv v3](https://arxiv.org/html/2408.05667v3); [NDSS page](https://www.ndss-symposium.org/ndss-paper/phishlang-a-real-time-fully-client-side-phishing-detection-framework-using-mobilebert)
  - Input: parsed HTML text from 17 tag types: h1–h3, p, a, ul/ol/li, form, **title**, footer, script, input, button, iframe, meta, a-with-JS, map and area. Empty tags become `<EMPTY>`, and all text is lowercased. `img` and `applet` are excluded.
  - Model comparison (F1, Table 2): Llama 2 7B 0.96, MobileBERT 0.96, DistilBERT 0.94, T5-base 0.88, TinyBERT 0.84, DeBERTa 0.84, Bloom 0.74, GPT-2 0.68, FastText 0.63.
  - Memory (Table 2): MobileBERT about 74 MB of DRAM, DistilBERT 502 MB, Llama 2 7B 4,873 MB. MobileBERT has about 25M parameters.
  - Comparison with other systems (accuracy, Table 3): PhishIntention 0.96 at 10.7 s, **GPT-4 on parsed HTML 0.94**, PhishLang 0.94 at 0.9 s, GPT-4 on full HTML 0.92, VisualPhishNet 0.85, URLNet 0.73.
  - Client-side median latency, excluding fetch: 0.44 s (experimental machine), 0.59 s (mid-range), 0.73 s (low-end). Client memory median: 76–102 MB.
  - Live stream: 25,796 phishing URLs flagged over about 3.5 months (v2), 27,574 after patching, on a 42.7M-domain stream.
  - The two tables report different numbers for what looks like the same model. The paper does not explain this.
- SemanticPhishNet (MDPI Computers 15(6):335) uses a DistilBERT-family encoder on cleaned HTML plus URL text as separate inputs. Snippet only; F1 not seen. — [MDPI](https://www.mdpi.com/2073-431X/15/6/335)

**URLs**
- Trad, Chehab. "Prompt Engineering or Fine-Tuning? A Case Study on Phishing Detection with Large Language Models". *Machine Learning and Knowledge Extraction* 6(1):367–384, 2024. DOI [10.3390/make6010018](https://doi.org/10.3390/make6010018). Snippet only (MDPI blocked).
  - Small fine-tuned models (GPT-2, Bloom, Baby LLaMA, DistilGPT-2) reached F1 97.29% and AUC 99.56% on 1,000 test URLs.
  - These are small decoder models used as classifiers, not BERT encoders.
- A DistilRoBERTa URL model reports F1 92.30% and is described as a good trade-off between accuracy and runtime. ResearchGate preprint; snippet only. — [ResearchGate 404487237](https://www.researchgate.net/publication/404487237_Real-Time_Phishing_URL_Detection_Using_Fine-Tuned_DistilRoBERTa)

**Email**
- In a preprint comparing classical ML and transformers on email, roberta-base reached phishing-class F1 0.9951 and distilbert-base-uncased 0.9911. Snippet only. — [Preprints.org 202410.1467](https://www.preprints.org/manuscript/202410.1467/v1)
- Ahmed, Pourmoafil. arXiv 2607.18429 (Jul/Aug 2026). Preprint. — [arXiv](https://arxiv.org/abs/2607.18429)
  - Corpus: 82,255 emails from six public datasets.
  - Both TF-IDF + logistic regression and fine-tuned DistilBERT scored above 98% on clean data.
- "Phishing Email Detection Using BERT and RoBERTa", MDPI *Computation* 14(2):46. RoBERTa beat BERT, with fewer false negatives. Snippet only. — DOI [10.3390/computation14020046](https://doi.org/10.3390/computation14020046)

**SMS / smishing**
- Timko, Rahman. "Smishing Dataset I: Phishing SMS Dataset from Smishtank.com". ACM CODASPY 2024.
  - 1,062 user-submitted smishing samples. Each has sender, body and brand; messages with a URL add domain and VirusTotal data.
  - Source: [arXiv 2402.18430](https://arxiv.org/html/2402.18430v2)
- One robustness study reports BERT classifying 910 of 913 cleaned Smishtank messages correctly (99.67% recall). Snippet only; the attribution is unclear (it came with the arXiv 2609.01171 result).
- Tanbhir et al. "Hybrid Machine Learning Model for Detecting Bangla Smishing Text Using BERT and Character-Level CNN". ICECE 2024. Three classes: normal, promotional, smishing. Accuracy 98.47%. — [arXiv 2502.01518](https://arxiv.org/abs/2502.01518)
- A fine-tuned RoBERTa variant reached 99.84% on a benchmark SMS spam set. Snippet only, source unverified. — [ECU record](https://ro.ecu.edu.au/ecuworks2022-2026/7087)

**Cross-domain (one model for all channels)**
- Mahendru, Pandit. "SecureNet: A Comparative Study of DeBERTa and Large Language Models for Phishing Detection". IEEE BDAI 2024, pp. 160–169. Data: email, HTML, URL, SMS and synthetic sets. DeBERTa V3 recall was 95.17% on the HuggingFace phishing dataset. Abstract only. — [arXiv 2406.06663](https://arxiv.org/abs/2406.06663)

**Generalisation across datasets and time**
- Dalton et al. (OpenText). "PhreshPhish: A Real-World, High-Quality, Large-Scale Phishing Website Dataset and Benchmark". arXiv 2507.10854, v2 Feb 2026. Preprint, abstract only.
  - Existing datasets "suffer from leakage and unrealistic base rates", which makes reported performance overly optimistic.
  - Source: [arXiv](https://arxiv.org/abs/2507.10854)
- A 2026 MDPI *Computers* systematic review (vol. 15, art. 624) found:
  - Missing timestamps are the biggest problem in existing studies.
  - Temporal or campaign-level evaluation is not consistently reported.
  - Source, snippet only: DOI [10.3390/computers15090624](https://doi.org/10.3390/computers15090624)
- A second systematic review (MDPI *Electronics* 14(18):3744, 2017–2024 literature) says random splits leak future data into training, and that performance drift appears wherever cross-time evaluation was attempted. Snippet only. — [MDPI](https://www.mdpi.com/2079-9292/14/18/3744)
- A "Classical-First Selective Cascades" paper (MDPI *Electronics* 15(14):3051, 2026) reports two numbers. Snippet only (MDPI returned 403). — DOI [10.3390/electronics15143051](https://doi.org/10.3390/electronics15143051)
  - A frozen DistilBERT reached F1 0.950 on its test set.
  - A novelty score separated LLM-style emails from legacy test data with AUROC 0.70.
- Across phishing URL detectors, performance can drop by 10%–32% when the test set comes from a different dataset. TransURL (a multi-layer transformer URL encoder) held AUC 0.9705 on external data. Snippet only; the attribution of the 10–32% figure is unclear. — [TransURL, arXiv 2312.00508](https://arxiv.org/pdf/2312.00508)
- Bobe et al. "Diagnosing Generalization Failures in Fine-Tuned LLMs: A Cross-Architectural Study on Phishing Detection". arXiv 2601.10524, Jan 2026. Preprint, abstract only. It covers decoders, not encoders. — [arXiv](https://arxiv.org/abs/2601.10524)
  - Gemma 2 9B exceeds 91% F1 only when trained on a stylistically diverse dataset.
  - Llama 3.1 8B does well on a narrow domain but drops when given diverse data.
- AURA (Berjawi, Fahs, Khatoun; arXiv 2609.19873, Sep 2026, under review). Macro F1 was 0.9858 in-distribution. On held-out real-world corpora it fell to 0.9502 (NazPhish-Eval) and 0.9436 (GuenterTrap-Eval). Abstract only. — [arXiv](https://arxiv.org/abs/2609.19873)
- A random forest's ROC-AUC fell from 0.999 in-distribution to about 0.53 on an unseen human-written corpus. Leave-one-source-out tests showed FPR up to 0.50. **Low-quality source: a high-school research journal.** — [NHSJS 2026](https://nhsjs.com/2026/cross-dataset-fragility-of-phishing-detectors/)
- Fernando, Komninos. "Evaluating and Combating the Impact of Concept Drift on the Performance of ML-Based Phishing Detection Systems". arXiv 2606.11471, Jun 2026. Its abstract covers spam-email drift and mitigation but gives no numbers. — [arXiv](https://arxiv.org/abs/2606.11471)

**How much labelled data**
- Typical corpus sizes in the studies above:
  - Email: 82k (Ahmed and Pourmoafil).
  - HTML: PhishLang's training set is not restated here. Its 5K labelled set was used for Table 3.
  - SMS: 1–2.3k (Bangla set 2,287 per search snippet; Indonesian 1.1k, see section 4).
- No study found measured a learning curve: accuracy against the number of labelled examples for phishing encoders.

### Inferences
- **Size class.** For a server-side layer, a base-size encoder (DistilBERT, MobileBERT, IndoBERT-base) is the right size class. PhishLang shows a 25M MobileBERT matching a 7B LLM on HTML text, with under 100 MB of RAM.
- **Workers fit.** A 25M MobileBERT in int8 is roughly 25–30 MB of weights (my arithmetic). That would sit within the 64 MiB Worker script and 128 MB isolate limits noted in `easy_alternatives.md`. This is unverified, and ONNX runtime overhead could break it.
- **Claimed 96–99% figures will not carry over.** They come from random splits on English corpora with full text. Shoo's input is short and partly Indonesian. Expect a real drop, and measure it on a time-split, Shoo-shaped eval set at a realistic base rate. PhreshPhish's warning about base rates applies directly.

### Gaps
- No encoder study on Indonesian web pages was found.
- No study reports a learning curve (accuracy against the number of labels) for phishing encoders.
- No encoder study used a strict temporal split on web-page phishing with numbers I could verify. The MDPI cascade and drift papers were blocked or abstract-only.
- I did not read the PhreshPhish baselines (models, precision at low base rate).

## 2. Encoder / decision models vs generative LLMs: accuracy, cost, latency, calibration; does any paper evaluate Laya, Jev or Clef-flash?

### Takeaway
Where both were tested, fine-tuned small models beat prompted LLMs:
- URL: F1 97.29% fine-tuned vs 92.74% prompted.
- Mixed phishing data: DeBERTa recall 95.17% vs GPT-4 91.04%.
- SMS: fine-tuning was the strongest approach; zero-shot prompting was unreliable.

Zero-shot frontier LLMs stay competitive without labels (about 94–95% on balanced email), but their false positives rise sharply outside English. Encoders are 1–3 orders of magnitude cheaper and faster.

On calibration, fine-tuned transformers are overconfident. Standard ECE hides this at high accuracy, and post-hoc temperature scaling breaks under noisy or obfuscated text.

No peer-reviewed or preprint paper evaluates Laya, Jev or Clef-flash on phishing. The only phishing numbers are Cloudflare's vendor-run "PhishNChips" accuracies:

| Model | PhishNChips accuracy |
|---|---|
| Clef | 79.60 |
| Clef-flash | 75.05 |
| Jev | 62.55 |
| Laya | 50.15 (about chance) |

The benchmark itself is undocumented.

### Cited Findings
**Head-to-head: fine-tuned vs prompted**
- Trad, Chehab, MAKE 2024. DOI [10.3390/make6010018](https://doi.org/10.3390/make6010018). Snippet only.
  - Best prompt engineering (GPT-3.5-turbo, Claude 2) reached F1 92.74%.
  - Fine-tuned small models reached F1 97.29%.
  - Per a secondary summary, the gap grows when phishing is rarer than legitimate URLs.
- SecureNet, IEEE BDAI 2024: DeBERTa V3 recall 95.17% vs GPT-4 91.04%. Gemini 1.5 was also tested on other datasets. The abstract does not say whether the LLMs were zero-shot. — [arXiv 2406.06663](https://arxiv.org/abs/2406.06663)
- SpaLLM-Guard (arXiv 2501.04985, Jan 2025, preprint, snippet only):
  - Zero-shot prompting was unreliable for SMS spam. Few-shot helped, but inconsistently.
  - Fine-tuned Mixtral reached 98.6% accuracy with FPR and FNR both under 2%. It did not appear to benchmark BERT.
  - Source: [arXiv](https://arxiv.org/abs/2501.04985)
- Wang et al. (arXiv 2405.10523, May 2024): across sentiment, spam-SMS and multi-label tasks, the fine-tuned model was the top performer on every dataset. Snippet only. — [papers.cool](https://papers.cool/arxiv/2405.10523)
- An IEEE S&P 2025 poster found few-shot beat zero-shot for small LLMs on smishing (Phi-3-mini, Gemma-2B, Qwen-2.5-3B). Snippet only. — [S&P 2025 poster](https://sp2025.ieee-security.org/downloads/posters/sp25posters-final23.pdf)
- PhishLang Table 3 (HTML): GPT-4 on parsed HTML 0.94 accuracy, equal to the 25M MobileBERT (0.94); GPT-4 on full HTML 0.92. — [arXiv 2408.05667v3](https://arxiv.org/html/2408.05667v3)
- Lin et al. (arXiv 2505.00034, 2025): improved methods raised Qwen2.5-1.5B-Instruct from about 0.5 to 0.976 accuracy on SpamAssassin. Small instruct LLMs are near-useless out of the box. Snippet only. — [arXiv](https://arxiv.org/html/2505.00034v2)

**Zero-shot LLM strength and weakness**
- Hasan et al. "Phishing Email Detection Using Large Language Models". arXiv 2512.10104 v2, Dec 2025. Preprint. — [arXiv](https://arxiv.org/html/2512.10104v2)
  - Balanced 2,000-email accuracy with a structured prompt: GPT-4o 95%, Claude Sonnet 4 94%, Grok-3 88%.
  - On an imbalanced set (20 phishing in 200), the best F1 was only 0.864 (GPT-4o zero-shot). Structured prompting averaged 0.657.
  - No cost, latency or calibration numbers. No encoder baseline.
- A benchmark of zero-/few-shot LLMs on phishing URLs reported Grok-3-Beta zero-shot accuracy of 0.976 and recall of 0.938. Running 1,000 URLs took about 94 s with Qwen-7B and 488 s with Llama-3-70B. OpenReview, snippet only. — [OpenReview](https://openreview.net/pdf?id=COmhlLFVk9)

**Cascades / routing (encoder first, expensive model only when unsure)**
- AURA routes only messages the URL classifier is unsure about to a fine-tuned encoder. Macro F1 0.9858 in-distribution, 0.94–0.95 on held-out corpora. — [arXiv 2609.19873](https://arxiv.org/abs/2609.19873)
- Li, Miao, Krishnan, Padman. "JEV-as-a-Judge: Accept When Confident, Escalate When Unsure". arXiv 2609.26550, v5 Oct 2026. Preprint, abstract only; it covers generic judging, not phishing. — [arXiv](https://arxiv.org/abs/2609.26550)
  - Where the verdict can be read from the text, Jev scored within 3 points of GPT-6, at about 0.36% of GPT-6's fee and 0.15 s median latency.
  - A confidence cascade was 0.9 points more accurate than GPT-6 on 1,610 pairs, at 41% of its fee.
  - Routing weakens on style-adversarial pairs.

**Laya / Jev / Clef-flash: explicit search result**
- **No academic paper evaluates any of the three on phishing, scam or spam.** Searches for Laya, Jev and Clef with "phishing" on arXiv turned up only off-topic papers (generic judging, pentesting).
- Cloudflare blog, "Introducing Clef: our open-source decision models, and new RL fine-tuning platform", Michelle Chen, 1 Oct 2026. Vendor, not peer-reviewed. — [Cloudflare blog](https://blog.cloudflare.com/clef-decision-models)
  - PhishNChips accuracy: Clef 79.60, Clef-flash 75.05, Jev 62.55, DiffusionGemma Jev 85.35, Kev-9B 50.75, Laya 50.15.
  - Latency over 43 benchmarks, median / p95 in ms:

  | Model | Median | p95 |
  |---|---|---|
  | Clef | 209.3 | 238.6 |
  | Clef-flash | 38.8 | 122.4 |
  | Jev | 524.1 | 536.0 |
  | DiffusionGemma Jev | 84.4 | 211.2 |
  | Kev-9B | 51.4 | 187.9 |
  | Laya | 5.8 | 222.5 |

  - The blog names no calibration numbers and no language list.
  - **PhishNChips is not described anywhere I could find**: no source, size or language. A web search found no paper or dataset by that name.
  - This **corrects `easy_alternatives.md`**, which says no Clef-flash phishing accuracy is published. A vendor number exists, but it is unverifiable.
- "Calibrated Decision Models for Autonomous Penetration-Testing Harnesses: JEV and Laya as System One Decision Layers". arXiv 2609.28940, 24 Sep 2026. It covers pentest adjudication, not phishing. Per call: Jev 236–276 ms, Laya 33–40 ms. Snippet only. — [arXiv](https://arxiv.org/html/2609.28940v1)
- A blog test of Jev vs Clef vs Laya on 600 business decisions exists. It was not read, and it is not academic. — [softwareinsights.dev](https://www.softwareinsights.dev/posts/jev-vs-clef-vs-laya-decision-models-tested/)

**Calibration**
- Fonseca, Prenassi, Cunha, Rocha, Gonçalves. "When High Accuracy Hides Poor Calibration: Rethinking Confidence Evaluation in Transformer-Based Text Classification with Balanced Brier Score". ACL 2026 (long). PDF read. — [ACL Anthology 2026.acl-long.2128](https://aclanthology.org/2026.acl-long.2128.pdf)
  - Models: fine-tuned RoBERTa and four fine-tuned 7–8B LLMs (Llama-3.1-8B, Gemma-7B, Mistral-7B, Qwen3-8B), against TF-IDF + logistic regression (LR).
  - Datasets: six text-classification sets, not phishing.
  - Transformers "remain markedly overconfident". ECE and Brier "become biased in high-effectiveness regimes", sometimes making a transformer look better calibrated than LR.
  - RoBERTa vs LR, Table 3:

  | Metric | RoBERTa | LR |
  |---|---|---|
  | ECE | 0.04–0.13 | 0.06–0.16 |
  | Balanced Brier Score (lower is better) | 0.89–0.95 | 0.62–0.89 |

  - LR was best or tied on BBS for 4 of 6 datasets, despite much lower Macro-F1.
- Desai, Durrett. "Calibration of Pre-trained Transformers". EMNLP 2020. **Older.** Snippet level. — [arXiv 2003.07892](https://arxiv.org/pdf/2003.07892)
  - BERT and RoBERTa are relatively well calibrated in-domain, and temperature scaling reduces error further.
  - Out of domain, label smoothing helps more. Pre-trained models' out-of-the-box out-of-domain calibration error can be up to 3.5x lower than non-pretrained baselines.
- An AAAI paper on noisy text classification: temperature scaling "performs poorly" when inputs carry slight noise such as character swaps. Snippet only; the year was not verified (article id 26632 suggests AAAI-23). — [AAAI OJS 26632](https://ojs.aaai.org/index.php/AAAI/article/view/26632/26404)
- The Laya card's own calibration (ships over-confident; ECE 0.466 to 0.081 after per-type temperature) is already in `laya_jev.md`.

### Inferences
- **Cost.** An encoder fine-tuned on a few hundred to a few thousand Shoo-shaped examples should beat zero-shot LLMs and zero-shot decision models on Shoo's task, at far lower cost. Every head-to-head points the same way. Zero-shot Laya is at chance on Cloudflare's phishing benchmark and below majority-class on its own benchmark. Clef-flash at 75% (vendor-run, undocumented benchmark) is not a production-grade judge either.
- **A route that fits Shoo.** The cascade/routing pattern (AURA, JEV-as-a-Judge) matches Shoo's design:
  - rules decide clear cases;
  - an encoder or decision model scores the rest;
  - only low-confidence cases escalate to a more expensive LLM, or to "warn, don't block".
- **Calibration practice.** Encoder probabilities should not be used raw as block thresholds.
  - Fit a temperature on an Indonesian held-out set.
  - Check reliability curves, or a balanced metric such as BBS, not just ECE.
  - Re-check after obfuscation tests, because temperature scaling degrades under noise.
- **Benchmark caveat.** Fonseca et al. is not phishing data. Its transfer to phishing is an assumption.

### Gaps
- No controlled head-to-head of a fine-tuned BERT-family encoder against GPT-4-class zero-/few-shot on web-page phishing, with cost per 1K, was found. PhishLang's GPT-4 row is the closest.
- No phishing-specific calibration study (ECE or reliability on phishing encoders) was found.
- PhishNChips has no documentation, so Clef-flash's 75% cannot be interpreted (language, base rate, input type).
- No Indonesian numbers exist for Laya, Jev or Clef.

## 3. Robustness: adversarial text and prompt injection, non-generative classifiers vs LLMs on attacker-controlled text

### Takeaway
- **Encoders are not robust to adversarial rewording.** Fine-tuned DistilBERT and TF-IDF + LR both fell about 35 points under adversarial phishing. PhishLang misclassified up to 20.9% under JS obfuscation until it was adversarially retrained. Adversarial training alone is "insufficient" for SMS.
- **LLM judges are additionally open to prompt injection.** Hidden HTML instructions reached 40–85% attack success on GPT-5, Llama 4, Grok 4 Fast and Gemma 3. Even with defences, Llama 4 stayed at 61.7%.
- **An encoder or decision head cannot be "instructed".** It has no instruction channel or free-text output. Injected text can still shift its score like any other adversarial input.
- No paper directly measures prompt-injection text against a BERT classifier vs an LLM on the same pages.

### Cited Findings
**Adversarial attacks on encoders**
- Ahmed, Pourmoafil, arXiv 2607.18429 (2026, preprint). — [arXiv](https://arxiv.org/abs/2607.18429)
  - On a 275-sample adversarial set: TF-IDF + LR 64.00% (−34.59 points), DistilBERT 63.64% (−35.40 points).
  - The two models agreed on 54.9% of adversarial samples, and their errors are partly complementary.
  - Clean accuracy above 98% "does not predict" robustness.
- PhishLang problem-space attacks (A1–A15). — [arXiv 2408.05667v3](https://arxiv.org/html/2408.05667v3)
  - Before patches, the worst error rate was 20.92% (ObfuscateJS).
  - After adversarial patches, most attacks fell to 0% and the rest to 0.63–1.68%.
  - Behavioural JS-evasion TPR rose to 97.2% after adding 411 augmented samples.
- Salman, Islam, Ikram, Kaafar. "Johnny Still Receives Spam SMS: Assessing the Robustness of SMS Spam Detection". arXiv 2609.01171, Sep 2026. Preprint, abstract only. — [arXiv](https://arxiv.org/abs/2609.01171)
  - It tested commercial apps, anti-spam services and Hugging Face open models, using only perturbations that survive real SMS/RCS delivery.
  - "Adversarial training alone is insufficient". Robustness does not transfer to encoding-level attacks.
  - Best defence: an ensemble of classifiers with different architectures and tokenizers, with minority voting.
- On Indonesian online-gambling ("judol") comments, spammers swap in non-standard Unicode characters that the IndoBERT tokenizer maps to unknown tokens. The proposed fix is a hybrid of IndoBERT [CLS] vectors and character n-gram TF-IDF, fed to LinearSVC. — [Progresif, STMIK Banjarbaru](https://ojs.stmik-banjarbaru.ac.id/index.php/progresif/article/view/3914)

**Prompt injection on LLM detectors**
- Koide, Nakano, Chiba (NTT). "Clouding the Mirror: Stealthy Prompt Injection Attacks Targeting LLM-based Phishing Detection". arXiv 2602.05484, Feb 2026. Preprint, full HTML read. — [arXiv](https://arxiv.org/html/2602.05484v1)
  - Attack success (ASR) for hidden instructions in HTML, standard attack / with InjectDefuser:

  | Model | Standard | With InjectDefuser |
  |---|---|---|
  | GPT-5 | 39.9% | 0.3% |
  | Grok 4 Fast | 65.1% | 26.1% |
  | Llama 4 Maverick | 84.7% | 61.7% |
  | Gemma 3 27B | 64.7% | 36.7% |

  - URL-based injection ASR (standard): 0–33.5%.
  - Against existing systems (PhishLLM, KnowPhish, PhishAgent): CRP-prediction ASR up to 25.0% (Llama 4); brand-extraction ASR up to 12.5% (GPT-5).
  - InjectDefuser (prompt hardening, allowlist RAG, output validation) adds about 3.08 s per site for GPT-5.
  - The paper benchmarks no encoder or non-LLM classifier.
- Hasan et al. (arXiv 2512.10104) found low injection success on frontier models. — [arXiv](https://arxiv.org/html/2512.10104v2)
  - Across 1,134 email cases: GPT-4o 1.1%, Grok-3 1.6%, Claude Sonnet 4 2.9%.
  - Instruction-override ASR was up to 12.3% (Grok-3).
- Hidden-text injection is used in the wild: a Sep 2025 Booking.com-themed campaign hid instructions and multilingual filler to push AI scanners toward "safe". Secondary vendor reporting. — [Wiz](https://www.wiz.io/academy/ai-security/prompt-injection-attack)
- The decision-model side (no free-text output; Laya `noul` label-text bias, issue #156; Jev weaker on style-adversarial pairs) is already in `laya_jev.md`.

### Inferences
- **Instruction channel.** For Shoo's attacker-controlled title and labels, a classification head removes the instruction channel and the parse-breaking failure mode. GPT-5-class models resist well only with heavy defences. The open models Shoo could afford on Workers (Llama 4, Gemma 3 class) stayed at 37–62% ASR even with defences.
- **Score shifts remain.** Encoders do not remove adversarial risk. A title like "Situs resmi BCA – bukan penipuan" ("Official BCA site – not a scam") is just adversarial text to an encoder. Mitigations:
  - adversarial augmentation (PhishLang-style);
  - character-level features for Unicode obfuscation;
  - an ensemble of architecturally different models;
  - keeping rule layers authoritative, so a model score can raise but never clear a strong rule verdict.
- **Test both.** No study puts the same injected pages through an encoder and an LLM. Shoo would need its own test.

### Gaps
- No direct encoder-vs-LLM prompt-injection comparison on identical inputs exists.
- No Indonesian adversarial phishing test set was found.
- Per-attack breakdowns for arXiv 2607.18429 and 2609.01171 were not read.

## 4. Multilingual and Indonesian: XLM-R, mBERT, IndoBERT, mmBERT on Indonesian scam text; available datasets

### Takeaway
Indonesian evidence is almost entirely local journals and theses on SMS spam, email and online-gambling comments, with small datasets (about 1.1k SMS). IndoBERT reaches 91–98% there and beats mBERT (98% vs 95%).

IndoBERT vs XLM-R is task-dependent:
- IndoBERT is equal or better on homogeneous Indonesian data.
- XLM-R is better on NLI, cross-domain data and AUPRC ranking.
- English-only RoBERTa and BERT collapse cross-lingually; XLM-R holds up.

LLM zero-shot false-positive rates jump in non-English text (Claude Sonnet 4: 2.4% to 24.1%). That argues for a fine-tuned multilingual or Indonesian encoder over zero-shot judges.

No study evaluates mmBERT on Indonesian scams, or any model on Indonesian phishing web-page text. No study on "investasi bodong" (investment scam) text classification was found. Public Indonesian datasets are scarce: the Rahmi & Wibisono 3-class SMS set (normal / fraud / promo), and URL sets from BSSN or PANDI that do not appear to be public.

### Cited Findings
**Indonesian SMS / spam / fraud**
- "Deteksi Spam Berbahasa Indonesia Berbasis Teks Menggunakan Model BERT" ("Indonesian text spam detection using BERT"), JTIIK (Universitas Brawijaya; DOAJ-indexed).
  - On Indonesian SMS + email spam, IndoBERT reached 98% accuracy vs 95% for multilingual BERT.
  - Authors and volume not retrieved (403). Snippet only.
  - Source: [JTIIK 8121](https://jtiik.ub.ac.id/index.php/jtiik/en/article/view/8121); [DOAJ](https://doaj.org/article/94921b0ddfbe454d933bcce504efb3aa)
- Latifah, Nugraha, Dwiyansaputra, 2024, *MATRIK*. Six-class Indonesian SMS spam. Abstract-level snippet. — [UNRAM scholar record](https://scholar.unram.ac.id/papers/W4401192309) (page returned 404 at fetch time)
  - IndoBERT: 91% accuracy, rising to 93% with EDA augmentation.
  - Minority-class F1 improved by an average of 12%.
- Rahmi & Wibisono 3-class SMS dataset: 1,143 SMS, labels 0 = normal, 1 = fraud ("penipuan"), 2 = promo. It is reused by several student and journal papers. Snippets only, and the original Rahmi & Wibisono paper was not found.
  - LSTM: 94%. — [JINACS, UNESA](https://ejournal.unesa.ac.id/index.php/jinacs/article/download/57488/45135)
  - ANN: 95.5% on 1,113 SMS (count conflict with 1,143). — [Unsri repository](https://repository.unsri.ac.id/147874/3/RAMA_55201_09021282025099_0008118205_0018048003_01_front_ref.pdf)
  - Two-stage Naive Bayes: 94.12% and 94.56%. — [JATI, ITN](https://ejournal.itn.ac.id/index.php/jati/article/download/9532/5476)
  - Logistic regression: 95%. — [Repositor, UMM](https://ejournal.umm.ac.id/index.php/repositor/article/download/32080/13994/109048)
  - Inference: classical models reach about 94–95% on this set, so IndoBERT's margin on 3-class SMS is small.
- One search summary said a 1,143-record set has 335 fraud messages, attributed to the six-class MATRIK paper. This conflicts with the 3-class description and is unverified.
- "Implementasi Model Transformer IndoBERT ... untuk Deteksi Spam Pesan Teks Berbahasa Indonesia" ("IndoBERT transformer for Indonesian text-message spam detection"), JCSIT. Telegram messages, 97.32% accuracy. Snippet only. — [JCSIT 4147](https://journal.ppmi.web.id/index.php/jcsit/article/view/4147)
- Darmono, Saputro, Barkah. "Klasifikasi Spam Bahasa Indonesia dengan IndoBERT dan XLM-RoBERTa: Evaluasi Pooling, Stride, dan Late-Fusion" ("Indonesian spam classification with IndoBERT and XLM-RoBERTa"). *BITS* 7(2):1456–1466, Sep 2025. DOI [10.47065/bits.v7i2.8034](https://doi.org/10.47065/bits.v7i2.8034)
  - IndoBERT is better and more efficient on binary classification. XLM-R is slightly better on AUPRC, so it suits risk ranking.
  - Production recommendation: IndoBERT with truncation, mean pooling and embedding-only features. Late fusion helps only marginally, perhaps under heavy obfuscation.
  - Limited to short messages. Exact numbers were not on the landing page.
- Nuha, Lin. "Conditional Semi-Supervised Data Augmentation for Spam Message Detection with Low Resource Data". arXiv 2407.04990, Jul 2024. Preprint.
  - Uses an Indonesian SMS set (spam / promo / normal), where spam includes fraud such as unknown bills and "irrational gifts". Balanced accuracy is about 85%.
  - Sources: [arXiv](https://arxiv.org/abs/2407.04990); label details via search snippet.

**Indonesian email**
- Purnamadewi, Zahra. "Enhancing detection of zero-day phishing email attacks in the Indonesian language using deep learning algorithms". *Bulletin of Electrical Engineering and Informatics* 14(1), 2025 (received May 2024). Snippet level. — [BEEI 8759](https://beei.org/index.php/EEI/article/view/8759)
  - Uses email headers only.
  - FastText + CNN gave the best accuracy, precision and F1 (each 98.4375%). FastText + LSTM gave the best recall (98.9583%).
  - IndoBERT feature variants were tested but were not the best.
  - Body text was left for future work.

**Online gambling ("judi online / judol") text**
- "Klasifikasi Komentar Judi Online Menggunakan IndoBERT" ("classifying online-gambling comments with IndoBERT"), Universitas Sriwijaya thesis. IndoBERT reached P/R/F1 98.68% on 20,807 comments. — [Unsri repository](https://repository.unsri.ac.id/195594/1/RAMA_55201_09021282227042.pdf)
- "Analisis Komparatif Algoritma One-Class Untuk Klasifikasi Teks Iklan Judi Online Berbasis Embedding IndoBERT" ("one-class classifiers on IndoBERT embeddings for online-gambling ads"), UNPER *Informatics* journal (2025 per snippet).
  - It trains only on gambling text, using IndoBERT 768-d embeddings.
  - One-Class SVM was best, with F1 91% in the balanced scenario.
  - Source: [UNPER](https://e-journal.unper.ac.id/index.php/informatics/article/view/2309)
- IndoBERT + NER to extract gambling-site names from comments. — [Prosiding SoBAT, USB YPKP](https://jurnal.usbypkp.ac.id/index.php/ProsidingSoBAT/article/download/5256/1378)
- Known failure modes: sarcasm and irony are often misclassified (BITS study), and ordinary comments draw false positives (JATI). Snippet only. — [BITS](https://ejurnal.seminar-id.com/index.php/bits/article/download/8421/4241/); [JATI](https://ejournal.itn.ac.id/jati/article/download/18440/9611)

**Investment scams / illegal online lending ("investasi bodong / pinjol ilegal")**
- No text-classification study was found.
- Context only (news, not research): OJK's Satgas PASTI stopped 796 illegal entities in Oct–Dec 2024, including 543 illegal lending apps ("pinjol ilegal"). Impersonation of licensed entities' names and social accounts is a common method. — [CNBC Indonesia, 24 Jan 2025](https://www.cnbcindonesia.com/market/20250124124205-17-605679/satgas-pasti-setop-796-pinjol-ilegal-dan-investasi-bodong); [Bisnis.com, 18 Apr 2024](https://finansial.bisnis.com/read/20240418/55/1758554/hati-hati-ada-modus-investasi-bodong-catut-nama-dan-sosial-media-entitas-resmi)

**IndoBERT vs XLM-R vs mBERT on Indonesian (general NLU)**
- Wilie et al. "IndoNLU: Benchmark and Resources for Evaluating Indonesian Natural Language Understanding". AACL 2020. **Older.** — [arXiv 2009.05387](https://arxiv.org/pdf/2009.05387)
  - IndoBERT-large and XLM-R-large are the top classification performers.
  - XLM-R-large, IndoBERT-large and XLM-R-base are the top 3 on sequence labelling.
- Mahendra et al. "IndoNLI: A Natural Language Inference Dataset for Indonesian". EMNLP 2021. Snippet level. — [arXiv 2110.14566](https://arxiv.org/pdf/2110.14566)
  - XLM-R beat IndoBERT-large.
  - Suggested reason: XLM-R saw far more Indonesian pretraining text (180 GB vs 23 GB uncompressed).
- UMN thesis (2026), Indonesian emotion classification. — [UMN repository 44259](https://kc.umn.ac.id/id/eprint/44259/)
  - Internal test: IndoBERT 89.09% vs XLM-R 87.30%.
  - External data: XLM-R 86.59% vs IndoBERT 85.40%.
  - Conclusion: IndoBERT is better on homogeneous data, XLM-R more robust across domains.
- A DINUS systematic evaluation found monolingual Indonesian BERTs consistently beat multilingual ones in both accuracy and resource use. Snippet only. — [Techno.COM, DINUS](https://publikasi.dinus.ac.id/technoc/article/view/15843)

**Cross-lingual transfer in phishing**
- Apeke et al., 2026. "Phishing detection by Transformers: Adversarial Robustness and Cross-Lingual Generalization". *Indian Journal of Science and Technology*. Snippet only. — [IJST](https://indjst.org/articles/phishing-detection-by-transformers-adversarial-robustness-and-cross-lingual-generalization)
  - RoBERTa and BERT "collapse" in cross-lingual transfer, while XLM-RoBERTa maintains performance.
  - Transformers struggle on sophisticated phishing emails.
- "Self-Training Approach for Smishing Detection in Multilingual and Low-Resource Settings". ISD 2026 (AISeL). Abstract-level snippet. — [AISeL](https://aisel.aisnet.org/isd2014/proceedings2026/general/16/)
  - XLM-R self-training: zero-shot inference on Bengali and Swahili SMS, keeping high-confidence pseudo-labels.
  - It improved recall and F1 without parallel corpora.
- Hasan et al. (arXiv 2512.10104), FPR for zero-shot LLMs, English → non-English mean (Bangla, Chinese, Hindi). — [arXiv](https://arxiv.org/html/2512.10104v2)

  | Model | English FPR | Non-English mean FPR |
  |---|---|---|
  | GPT-4o | 10.0% | 13.7% |
  | Claude Sonnet 4 | 2.4% | 24.1% |
  | Grok-3 | 24.1% | 43.3% |

**mmBERT**
- No scam, phishing or Indonesian-specific evaluation of mmBERT was found. Its card does not name Indonesian among the languages; see `laya_jev.md`.

**Indonesian datasets**
- SMS: the Rahmi & Wibisono 1,143-SMS 3-class set, via the papers above. The original repository was not located in this pass.
- URL: an IPB University thesis compares RF, XGBoost and LightGBM on URL data collected by BSSN (national cyber agency) for 2021–2024. Public access is not stated. — [IPB repository](https://repository.ipb.ac.id/handle/123456789/178128?show=full)
- An ACIIDS 2026 abstract evaluates 83 lexical, structural and entropy features on .id phishing URLs. — [EasyChair slide](https://easychair.org/smart-slide/slide/lTm7)
- Telkom University's IndoPhis-D (6,112 .id URLs) is already in `visual_llm.md`.
- PANDI (the .id registry) reports 34,622 phishing cases over five years and 7,988 unique attacks in Q3 2022. Secondary, via search summary.

### Inferences
- **Backbone choice.** On short Indonesian scam text, IndoBERT-base is the evidence-backed default. XLM-R-base is the hedge for code-mixed Indonesian/English and cross-domain robustness. Neither has been tested on title + form-label strings.
- **Laya not shown for Indonesian.** Laya-multilingual's mmBERT backbone has no Indonesian evidence. That is a weaker basis than IndoBERT or XLM-R, which have many Indonesian results.
- **Zero-shot LLMs.** The jump in false positives outside English (2.4% to 24.1%) is the strongest published warning against relying on a zero-shot LLM for Indonesian pages, where false alarms on legitimate bank or e-commerce sites are the main product risk.
- **Data.** The lack of Indonesian web-page datasets means Shoo has to build its own labelled set from its exact layer-4 payload shape. Seed classes can borrow from the SMS work (normal / fraud / promo) and the gambling work. Promo vs fraud is the confusable pair, since both use urgency and prizes.

### Gaps
- No Indonesian phishing web-page dataset or model was found.
- No investment-scam ("investasi bodong") classifier study was found.
- Exact metrics for the JTIIK, MATRIK and BITS papers were not read: 403 errors or landing pages only. Ask via MyLoft, or try DOAJ or Garuda directly.
- No mmBERT Indonesian evaluation was found.
- The original Rahmi & Wibisono dataset paper and its download location were not verified.

## 5. Small-input settings: classifiers that see only title + form-field labels + domain (like Shoo layer 4); embedding + lightweight classifier evidence

### Takeaway
No paper evaluates a classifier on only page title + form-field labels + host. The closest evidence:
- PhishLang's encoder uses the title and input/form/button tags among 17 tags, but always together with body text.
- Brand-domain consistency features alone (logo domain, form-action domain, most-common-link domain, certificate CN) reach 99.7–99.8% accuracy with a random forest. That is on a self-collected set without a temporal split.
- Frozen-embedding + LR/one-class heads (IndoBERT embeddings + OCSVM F1 91% on gambling text; frozen BERT + LR matching fine-tuned BERT on binary scam messages) suggest the "embedding + tiny head" route is viable for short texts.
- SetFit (8–16 examples per class) has no phishing application.

### Cited Findings
- Mishra, Varshney. "A Study of Effectiveness of Brand Domain Identification Features for Phishing Detection in 2025". arXiv 2503.06487, Mar 2025. Preprint, abstract only. — [arXiv](https://arxiv.org/abs/2503.06487)
  - Features: certificate CN, logo domain, form-action domain, most-common-link domain, cookie domain.
  - Data: 4,667 legitimate and 4,561 phishing sites.
  - Random forest: 99.7% accuracy at 0.08 s. The best 3-feature sets reached 99.8%.
  - The page title is not a feature, and no FPR is reported.
- PhishLang's inputs include `title`, `form`, `input` and `button` tags, so the title and field-label signals are part of a working encoder. No ablation of title + inputs alone was found in the parts read. — [arXiv 2408.05667v3](https://arxiv.org/html/2408.05667v3)
- Lee et al. (eCrime 2024) use the HTML title as one brand cue for MLLMs. Already in `visual_llm.md`.
- A scam-message study compared KNN, LR and RF on frozen BERT embeddings against full BERT fine-tuning. ResearchGate, snippet only. — [ResearchGate 396838460](https://www.researchgate.net/publication/396838460_Comparing_KNN_Logistic_Regression_Random_Forest_and_BERT_Fine-Tuning_for_Scam_Message_Detection)
  - Fine-tuned BERT was best on multiclass (95.83%).
  - LR on embeddings reached 96.67% binary accuracy, matching fine-tuning.
- IndoBERT 768-d embeddings + One-Class SVM: F1 91% on online-gambling ad text. — [UNPER](https://e-journal.unper.ac.id/index.php/informatics/article/view/2309)
- IndoBERT embedding-only features with mean pooling are the production recommendation for Indonesian spam. — [BITS 7(2), DOI 10.47065/bits.v7i2.8034](https://doi.org/10.47065/bits.v7i2.8034)
- Tunstall et al. "Efficient Few-Shot Learning Without Prompts" (SetFit). arXiv 2209.11055, 2022. — [arXiv](https://arxiv.org/abs/2209.11055)
  - With 8 labels per class it is competitive with RoBERTa-large fine-tuned on about 3k examples (CR dataset).
  - No phishing, smishing or scam application was found in search.
- Microsoft Research's older work (about 2016, **older**) uses lexical and domain features, including a domain-to-brand-name distance, when pages are inaccessible. — [Microsoft Research PDF](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/Phishing_Detection_v1.4.0.pdf)
- AURA's design, a cheap URL-only model that escalates uncertain cases to a text encoder, is a small-input-first cascade. — [arXiv 2609.19873](https://arxiv.org/abs/2609.19873)

### Inferences
- **Shoo's layer-4 payload is a new, untested input shape.** The closest proven signals are:
  - brand-domain mismatch (Mishra & Varshney; and the reference-based literature in `visual_llm.md`);
  - credential intent from form fields (PhishIntention, already in `visual_llm.md`).
  Both are largely in Shoo's rules already. A text model on title + labels mainly adds brand and lure recognition in Indonesian wording.
- **Suggested design to test, in order of evidence and ease** (inference, not measured):
  1. Frozen multilingual embedding (bge-m3 on Workers AI, or IndoBERT mean-pooled), plus an LR head, plus rule-id features.
  2. Fine-tuned IndoBERT-base or XLM-R-base on the exact payload string, served in a container.
  3. A Clef-flash or Laya fine-tune only if 1–2 underperform. They have no Indonesian evidence and weak zero-shot phishing numbers.
- **Evaluation plan.** Build a time-split, Shoo-shaped eval set (Indonesian + English) with a realistic benign:phishing ratio. Report FPR on legitimate Indonesian bank, e-wallet and e-commerce pages. Add adversarial variants: Unicode obfuscation and "official site" injection in the title. This follows PhreshPhish (base rates), Ahmed & Pourmoafil (adversarial) and Fonseca et al. (calibration under high accuracy).

### Gaps
- No study uses title + form labels + host only, in any language.
- No ablation shows how much the title alone contributes in encoder-based web-page detectors.
- No published accuracy exists for embedding + LR on phishing web-page metadata.
- The Mishra & Varshney features rely on page links, cookies and certificates. Shoo's privacy-minimal payload does not send these, though Shoo's on-device rules could compute some of them.
