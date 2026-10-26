# Laya (Convai Innovations) and Jev (TypeSafe AI): profile for Shoo's LLM layer

Research date: 26 Oct 2026. Research only: nothing was installed or run.

Source notes:
- "Primary" means the vendor's own page: the Hugging Face model card, the GitHub README, PyPI, typesafe.ai, OpenRouter docs, or Cloudflare docs.
- Pages fetched without a visible publish date are marked "undated, fetched 26 Oct 2026".
- Every benchmark number below is vendor-reported unless it is marked INDEPENDENT.

## 1. What exactly is Jev?

### Takeaway
Jev is a closed, hosted "System One" decision model from TypeSafe AI, launched in early access on 15 Sep 2026. It does not generate text. It takes a `state` plus typed `questions` (choice / noul / score, and box for images) and returns typed answers with probabilities. It costs about $0.042 per 1M input tokens, and output is free. Architecture, size, weights and training data are not public. The one solid independent study found Jev close to a frontier LLM on text-readable judgments but weaker where reasoning is needed.

### Cited Findings
- **Maker and positioning.** TypeSafe AI describes itself as building "machine-native intelligence infrastructure for automation". Jev is its "first public System One Model". It returns typed decisions with calibrated probabilities and confidence. The site is marked early access ("Version 0.01"). — [TypeSafe AI homepage, TypeSafe AI, undated, fetched 26 Oct 2026](https://typesafe.ai)
- **Launch, people, funding.** Jev launched in early access on 15 Sep 2026 after about 2 years in stealth. The CEO and co-founder is reported as Diogo Almeida, an ex-OpenAI researcher. Reported funding is a $40M seed round led by DCVC. — [TypeSafe AI Launches Jev for Structured Software Decisions, Let's Data Science, Sep 2026](https://letsdatascience.com/news/typesafe-ai-launches-jev-decision-model-889a38c0); [VKTR, ChatGPT co-creator launches TypeSafe AI with Jev, Sep 2026](https://www.vktr.com/ai-platforms/chatgpt-cocreator-launches-typesafe-ai-with-jev/) (secondary sources)
- **Closed model.** Jev's "full architecture, model weights, training data, and training recipe are not public", so it cannot be inspected, reproduced or adapted. — [Top open-source Jev alternatives, Abid Ali Awan, DataCamp, 23 Sep 2026](https://www.datacamp.com/blog/top-open-source-jev-alternatives) (secondary). Let's Data Science also says architecture, training data and model size are undisclosed (secondary). The TypeSafe site itself says nothing about weights.
- **Question types (primitives).**
  - Choice returns the selected option, a probability per option, and confidence.
  - Noul returns P(condition holds).
  - Score returns a probability-weighted level, plus a probability per level.
  - Box returns `top/bottom/left/right` image fractions plus confidence. Box works only on `typesafe/jev-1.14` and `~typesafe/jev-latest`.
  - Jev "does not produce reasoning traces, explanations, or free-form text".
  - Source: [Jev documentation, OpenRouter, undated, fetched 26 Oct 2026](https://openrouter.ai/docs/guides/community/jev)
- **API (via OpenRouter).**
  - Endpoints: `POST https://openrouter.ai/api/alpha/decisions` and `POST https://openrouter.ai/api/v1/systemone`.
  - Request body: `model`, `state` (text and images) and `questions`. Each response carries `usage.cost` in USD.
  - Versions: `typesafe/jev-1.14` (current) and `jev-1.13` (still available).
  - Context: 262,144 tokens. Requests over about 32,000 bytes of text, and all image requests, run in a "long-context mode" that is slower and less accurate.
  - Source: [OpenRouter Jev docs](https://openrouter.ai/docs/guides/community/jev)
- **Pricing.** TypeSafe lists $42 per billion input tokens ($0.042/1M) and claims "193.6x Faster, 444.6x Cheaper" than LLMs. Its example workflow: Jev 0.114 s and $0.000081, versus LLMs 8.566 s and $0.013880. No methodology is shown on the page. — [typesafe.ai](https://typesafe.ai)
  - OpenRouter lists Jev 1.14 at $0.042/1M input, with output free. — [Jev 1.13 API pricing, OpenRouter, Oct 2026](https://openrouter.ai/typesafe/jev-1.13)
  - Conflict: AI/ML API lists $0.0546 and $0.0577668 per 1M input. — [AI/ML API Jev page](https://aimlapi.com/models/typesafe-jev) (reseller markup or stale page)
- **Why output is free and why it is fast.** Jev does not decode text autoregressively, so it produces no billable output tokens. — [AI/ML API](https://aimlapi.com/models/typesafe-jev) (secondary)
  - TypeSafe reports 70–500 ms end-to-end latency. — [Let's Data Science](https://letsdatascience.com/news/typesafe-ai-launches-jev-decision-model-889a38c0) (secondary, quoting vendor)
- **Limits.**
  - Jev cannot explain its answers.
  - Box has no "not found" answer.
  - Image input and Box may change between releases.
  - Source: [OpenRouter Jev docs](https://openrouter.ai/docs/guides/community/jev)
- **Languages and data handling (secondary only).**
  - English is primary. Other languages are "supported" with varying accuracy.
  - Zero data retention is reportedly enterprise-only.
  - Hosting is in the US, and no EU region is documented.
  - Reportedly no training on customer prompts.
  - Sources: [innfactory.ai Jev profile](https://innfactory.ai/en/ai-models/typesafe-jev/); [NeuralTrust, Jev security, Oct 2026](https://neuraltrust.ai/blog/jev-typesafe-ai-security); [Safeguard listing](https://safeguard.sh/models/typesafe-jev). Safeguard contradicts itself: its table says ZDR is "Not offered" while its text says enterprise-only.
- **INDEPENDENT: "JEV-as-a-Judge" (Li, Miao, Krishnan, Padman).** arXiv 2609.26550, v1 22 Sep 2026, v5 9 Oct 2026. Findings: — [arXiv 2609.26550](https://arxiv.org/abs/2609.26550)
  - Jev was compared with 16 generative and reward-model judges, with blinded human adjudication.
  - Jev comes within 3 points of GPT-6 where "the verdict can be read from the text", at 0.36% of GPT-6's fee.
  - It falls behind on math, code and logic.
  - Median latency is 0.15 s.
  - Accept-confident/escalate cascade: on 1,610 held-out pairs it was +0.9 points over GPT-6 at 41% of GPT-6's fee.
  - Routing weakens on style-adversarial inputs.
- **The "777 judgments" claim is not independent.** Every's test (777 judgments in under 0.7 s) is a speed/cost demonstration, and Every was reportedly a launch partner. — [GoPenAI blog, Oct 2026](https://blog.gopenai.com/jevs-boring-use-cases-are-the-ones-that-actually-work-ba13eb117816) (secondary). I did not find Every's original post.
- **Jev-compatible competitors.**
  - Cloudflare's **Clef / Clef-flash** decision models (1 Oct 2026) are API-compatible with Jev and are hosted on Workers AI. — [Cloudflare Workers AI models catalog](https://developers.cloudflare.com/workers-ai/models/); [Let's Data Science, 8 Oct 2026](https://letsdatascience.com/news/cloudflare-releases-open-weight-clef-decision-models-c52886d6)
  - OpenAI reportedly announced a Decisions API in limited preview on 29 Sep 2026 (seen only in a search-result summary; not verified).

### Inferences
- Jev is paid and closed for commercial reasons. The moat is the training recipe and the hosted service, and there is a VC seed round to repay. No source states the reason directly.
- Every Shoo request to Jev would leave Cloudflare for a US third party with no default zero retention. That conflicts with Shoo's "minimal data off the phone, nothing stored" rule unless Shoo has an enterprise ZDR agreement.

### Gaps
- No primary TypeSafe pricing page, privacy policy text or language list was read. The figures come from the homepage plus resellers.
- No published Jev accuracy on phishing, scam or Indonesian text was found.
- Jev's parameter count and architecture are unknown.

## 2. What exactly is Laya?

### Takeaway
Laya is an Apache-2.0, self-hosted Python package (`pip install laya`) with three encoder checkpoints, published around 19 Sep 2026:
- English, on ModernBERT-large, 421M params
- multilingual, on mmBERT-base, 322M params
- typed-decisions, a 421M fine-tune

It copies Jev's state + typed-questions interface and returns calibrated probabilities in one forward pass. The critical caveat: **the base checkpoints are near random zero-shot**. Good numbers come only after fine-tuning on your own labels, and the checkpoints ship over-confident.

### Cited Findings
- **Identity.** Laya is a "multilingual, non-autoregressive System 1 decision model". Input is a state (text, an email-style dict, or JSON) plus typed questions. Output is typed answers with calibrated probabilities from one forward pass, with no text generation. Developer: Convai Innovations. GitHub: NandhaKishorM/laya. Docs: nandhakishorm.github.io/laya. Demo Space: convaiinnovations/laya-demo. — [convaiinnovations/laya model card, Hugging Face, undated, fetched 26 Oct 2026](https://huggingface.co/convaiinnovations/laya)
- **Checkpoints.** — [HF model card](https://huggingface.co/convaiinnovations/laya)

  | Checkpoint | Backbone | Params | Context | Download size |
  |---|---|---|---|---|
  | `convaiinnovations/laya` (root) | ModernBERT-large | 421M | 512 | ~808 MB |
  | `laya-multilingual` | mmBERT-base | 322M | 1,024 default, up to 8,192 via `max_len=8192` | ~647 MB |
  | `laya-typed-decisions` | ModernBERT-large | 421M | 1,024 | not stated |

  - Formats: safetensors, F32/F16.
  - The HF model tree lists 85 community quantizations, 205 finetunes and 26 adapters. No official GGUF, Core ML or int8 file is named.
  - All three checkpoints together take about 2.3 GB on disk. — [GitHub README](https://github.com/NandhaKishorM/laya)
- **Method.**
  - Each option gets its own [MASK] slot, and all options are scored in one pass. — [Runware blog, Jev, Laya and decision models, Oct 2026](https://runware.ai/blog/jev-laya-and-the-emerging-role-of-decision-models) (secondary, search snippet)
  - Training uses RLCD ("Reinforcement Learning for Calibrated Decisions"). Rewards are strictly proper scoring rules (log, spherical, RPS), updated with REINFORCE and a group-mean baseline. — [HF model card](https://huggingface.co/convaiinnovations/laya)
  - Choice options share a fixed budget of 256 tokens, so keep each question to about 20 options. — [Hora de Codar tutorial, Matheus Battisti, 24 Sep 2026](https://horadecodar.com.br/?p=46018) (secondary)
- **Input and output format.** — [HF model card](https://huggingface.co/convaiinnovations/laya)
  - Each question has `type` ∈ {`choice`, `score`, `noul`}, `instructions`, and optional `criteria`: a dict for choice, a list for score.
  - The output has `answers[...]` (choice + per-option probabilities, score, or noul probability) plus `routing` metadata (model, repo, reason).
- **Install and minimal example.** `pip install laya`, Python ≥3.10. Extras: `laya[serve]`, `[mcp]`, `[langchain]`, `[onnx]`, `[fast]`; PyPI also lists `llamaindex`, `crewai` and `structured`. — [HF model card](https://huggingface.co/convaiinnovations/laya); [PyPI laya](https://pypi.org/project/laya/)
  ```python
  from laya import Router
  router = Router()
  questions = {"department": {"type": "choice", "instructions": "Which department should handle this?",
                              "criteria": {"billing": "invoices, payments, refunds", "technical": "bugs, outages, system errors", "other": "everything else"}},
               "churn_risk": {"type": "noul", "instructions": "Does the user threaten to cancel or leave?"}}
  result = router.predict("We were billed twice. Refund it or we cancel.", questions)
  ```
  The Hora de Codar tutorial gives this phishing question (Portuguese in the original): `"is_phishing": {"type": "noul", "instructions": "<does this message try to trick the recipient into giving credentials, bank data or account access?>"}`, used with `laya.load("convaiinnovations/laya")`. — [Hora de Codar, 24 Sep 2026](https://horadecodar.com.br/?p=46018)
- **Languages and routing.**
  - The multilingual checkpoint claims "100+ languages". 45 of 51 languages are "usable" (>3x random) on it, versus 23 of 51 on the English checkpoint.
  - MASSIVE intent across 13 non-English languages: 0.451 multilingual vs 0.306 English. XNLI across 14 languages: 0.731 vs 0.521.
  - The Router detects script and language in under 0.5 ms and sends non-English text to multilingual. Long, mostly-English text needs `model="multilingual"` explicitly.
  - **Indonesian is not named anywhere on the card.**
  - Source: [HF model card](https://huggingface.co/convaiinnovations/laya)
  - The multilingual 51-language MASSIVE macro-average is only 0.227. — [AI Weekly, 19 Sep 2026](https://aiweekly.co/alerts/convai-ships-laya-a-421m-modernbert-decision-model-apache-20) (secondary, citing the card)
  - The English checkpoint fails confidently on non-Latin scripts (Khmer 0.000). — [GitHub README](https://github.com/NandhaKishorM/laya)
  - Low-resource languages are weak: Swahili 0.210, Tamil 0.250, Amharic 0.110. — [Hora de Codar](https://horadecodar.com.br/?p=46018) (secondary)
- **Base model background (mmBERT).**
  - mmBERT-base: 307M params (110M non-embedding), 8,192 max sequence length, Gemma 2 tokenizer, MIT license.
  - Trained on "over 1800 languages" (1,833 in the decay phase). Training starts with 60 high-resource languages, but the card does not list them. Indonesian is not explicitly named.
  - Sources: [jhu-clsp/mmBERT-base, Hugging Face, JHU CLSP](https://huggingface.co/jhu-clsp/mmBERT-base); [mmBERT paper, Marone, Weller et al., arXiv 2509.06888, 8 Sep 2025](https://arxiv.org/abs/2509.06888)
  - The ModernBERT paper (Warner et al., arXiv 2412.13663) was not fetched in this pass.
- **Latency.** — [HF model card](https://huggingface.co/convaiinnovations/laya)
  - Tesla T4, 1 question: 32.8 ms (multilingual), 39.5 ms (English). 10 questions batched: 72.3 / 158.6 ms. Throughput: 103–332 questions/s.
  - CPU, preloaded: 193–464 ms per request.
  - Apple GPU, 4,000-token input: about 1.7 s.
  - Model reload: 7.4 s on CPU, 10.3 s on T4.
  - 56-core Intel Mac Pro, CPU, 4 questions per call: 453 ms (English), 192 ms (multilingual), 441 ms (typed-decisions). Fastest at about 16 threads. — [PyPI laya](https://pypi.org/project/laya/)
- **RAM.** No RAM or VRAM figure is published anywhere.
  - `Router()` keeps up to 2 checkpoints resident; `max_loaded=1` lowers memory.
  - Precision: CPU and MPS run fp32; bf16 is the CUDA default.
  - Sources: [PyPI](https://pypi.org/project/laya/); [HF model card](https://huggingface.co/convaiinnovations/laya)
- **Accuracy: zero-shot vs fine-tuned.** Benchmark: typed-decisions, 2,000 decisions over 4 workflows. — [HF model card](https://huggingface.co/convaiinnovations/laya)

  | Model | Accuracy | Brier | ECE |
  |---|---|---|---|
  | `laya-typed-decisions` (fine-tuned) | 0.766 | 0.062 | 0.213 |
  | `laya` English base | 0.362 | 0.316 | 0.175 |
  | `laya-multilingual` base | 0.342 | 0.439 | 0.285 |
  | Random baseline | 0.318 | | |
  | Majority-class baseline | 0.461 | | |

  - The card calls Laya "a fast base to specialise, not a zero-shot decision engine". The 0.766 comes from fine-tuning on the benchmark's own training split.
  - Source for the quote and the caveat: [AI Weekly, 19 Sep 2026](https://aiweekly.co/alerts/convai-ships-laya-a-421m-modernbert-decision-model-apache-20)
  - Note: the zero-shot base models score below the majority-class baseline.
- **Calibration.**
  - The checkpoints "ship over-confident", so refit per-type temperatures on your own data. — [HF model card](https://huggingface.co/convaiinnovations/laya)
  - Mean ECE is 0.466 out of the box, and 0.081 after one temperature per question type. — [AI Weekly](https://aiweekly.co/alerts/convai-ships-laya-a-421m-modernbert-decision-model-apache-20)
  - The multilingual checkpoint has no fitted temperatures. — [GitHub README](https://github.com/NandhaKishorM/laya)
- **Phishing, spam and injection evidence.**
  - The README's email-triage preset covers spam and phishing; its example input is an account-lock "verify now" message. The guard preset covers jailbreak and prompt injection. No accuracy is given for either preset. — [GitHub README](https://github.com/NandhaKishorM/laya)
  - Only one relevant number is published: prompt-injection detection, held out, n=116. English 0.698, multilingual 0.578. — [GitHub README](https://github.com/NandhaKishorM/laya)
  - **Secondary only:** "98% phishing" (no dataset named) and "99.3% spam on Enron, calibration error 0.013", both after fine-tuning. — [Hora de Codar, 24 Sep 2026](https://horadecodar.com.br/?p=46018). **These numbers are not on the HF card or in the GitHub README I read. Treat them as unverified.**
- **Fine-tuning.**
  - A Kaggle notebook (2x T4) runs the full loop: build dataset, train with RLCD, fit temperatures, evaluate, push to the Hub.
  - An Apple Silicon (MPS/CPU) script covers the same steps.
  - Fine-tuning reportedly fits on a 16 GB MacBook or a single 16 GB GPU.
  - Sources: [HF model card](https://huggingface.co/convaiinnovations/laya); [GitHub README](https://github.com/NandhaKishorM/laya)
- **Known issues.** — [HF model card](https://huggingface.co/convaiinnovations/laya); [GitHub README](https://github.com/NandhaKishorM/laya)
  - Choice accuracy drops above about 20 options.
  - `score` is the weakest type (SST-5 0.372).
  - `noul` can follow the `false:`/`true:` option labels instead of the state (issue #156).
  - `action.act_probability` has no usable signal yet (issue #185).
  - Threshold drift (issue #394) and option-position bias (issue #131).
  - Accuracy varies on inputs over about 4k tokens.
  - Intel Macs need a pinned torch 2.2.2 stack.

### Inferences
- Laya out of the box would be a weak phishing judge. A `noul` "is this phishing?" question on the base checkpoint is near chance on Laya's own benchmark. Shoo would need a labelled Indonesian/English scam dataset, a fine-tune, and temperature refitting before Laya is trustworthy.
- Shoo's layer-4 input is only host, title ≤120 chars, ≤12 field labels and rule IDs. That is short, which suits Laya's 512/1,024-token windows. But it is also very low-signal. The fine-tune data would need to match exactly that input shape.

### Gaps
- No primary release date. The earliest dated coverage is 19 Sep 2026 (AI Weekly).
- No per-language accuracy for Indonesian. No RAM figures.
- No official Core ML or int8 export. ONNX export file sizes are not listed.
- The 98% phishing and 99.3% Enron figures were not found at a primary source.

## 3. How Laya compares with Jev and generic LLMs

### Takeaway
On Laya's own card, Laya beats Jev 1.13 on 4-way and 6-way classification and is about 7x faster on a T4. It loses badly on many-label tasks (Banking77 0.425 vs 0.870). All Laya-vs-Jev numbers are vendor-only: Convai measured Laya and took Jev's numbers from third-party publications. The only independent decision-model evaluation I found covers Jev vs LLMs, not Laya.

### Cited Findings
- **Laya card table: Laya routed vs TypeSafe Jev 1.13.0.** Jev figures are "third-party published", not measured by Convai. — [HF model card](https://huggingface.co/convaiinnovations/laya)

  | Benchmark | Jev 1.13.0 | Laya (routed) |
  |---|---|---|
  | typed-decisions | 0.727 | 0.766 (fine-tuned on this benchmark's train split) |
  | AG News | 0.910 | 0.950 |
  | DAIR Emotion | 0.480 | 0.595 |
  | Banking77 | 0.870 | 0.425 |
  | ECE after temperature | 0.246 | 0.081 |
  | p50 latency, 1 question | 236–276 ms | 32.8 ms |

  The card concedes that Jev leads on label sets over 20 options.
- **Clef (Cloudflare) vendor benchmark.** Median latency over 43 runs: Clef 209.3 ms, Clef-flash 38.8 ms, Jev 524.1 ms. Clef is reportedly best on 7 of 10 decision benchmarks (BFCL, BANKING77, CLINC150+OOS, and others). There is no LLM comparison and no Laya comparison. — [Let's Data Science, 8 Oct 2026](https://letsdatascience.com/news/cloudflare-releases-open-weight-clef-decision-models-c52886d6)
- **Jev vs LLMs, INDEPENDENT.** Within 3 points of GPT-6 on text-readable judgments, at 0.36% of the cost and 0.15 s median latency. Behind on derived reasoning. — [arXiv 2609.26550](https://arxiv.org/abs/2609.26550)
  - A second paper title says Jev is "cheaper, faster, and wrong in the same places" as LLM rubric judges. — [Emergent Mind summary of arXiv 2609.29769](https://www.emergentmind.com/papers/2609.29769) (not read beyond the title)
- **TypeSafe claims vs LLMs.** 193.6x faster and 444.6x cheaper; 238x lower input price than "Claude Fable 5.1". Vendor-only. — [typesafe.ai](https://typesafe.ai)
  - "No independent lab has reproduced the central result." — [OrcaRouter, Jev: what we know](https://www.orcarouter.ai/blog/jev-typesafe-system-one-what-we-know) (secondary, search snippet)
- **Cost.**
  - Laya: hosting cost only, no per-token fee (Apache 2.0, self-hosted). — [HF model card](https://huggingface.co/convaiinnovations/laya)
  - Jev: $0.042/1M input. — [typesafe.ai](https://typesafe.ai)
  - Clef-flash on Workers AI: $0.038/1M input, output free. — [Cloudflare clef-flash docs](https://developers.cloudflare.com/workers-ai/models/clef-flash/)

### Inferences
- At Shoo's request size (roughly 100–300 tokens), Jev and Clef-flash cost fractions of a cent per 1,000 checks. Cost is not the deciding factor. Privacy, latency, accuracy on Indonesian scams, and ops burden are.
- No source compares Laya with GPT, Claude or Gemini directly on phishing. Shoo would need its own eval set (the current layer-4 LLM vs fine-tuned Laya vs Clef-flash) to decide.

### Gaps
- No independent Laya evaluation exists.
- There are no phishing or scam benchmarks for any decision model.
- I could not open the "Jev after eight days of independent tests" article (HTTP 403).

## 4. Deployment fit for Shoo (Cloudflare Workers, containers, on-device iPhone; prompt injection)

### Takeaway
- **Laya cannot run inside a Cloudflare Worker or on Workers AI.** It is not in the catalog, and Workers AI only offers LoRA adapters on a few LLMs.
- It can run in a Cloudflare Container (standard-1, 4 GiB or larger, CPU), on Fly.io, or on an HF Endpoint. CPU latency is about 200–450 ms, and there is a `laya-serve` HTTP server with Docker files.
- On-device in the Safari extension is unrealistic: 650–800 MB of fp32 weights against reported extension memory ceilings of about 80 MB. A 4-bit Core ML ModernBERT exists from the community, so the containing app is a theoretical path only.
- The closest drop-in for Shoo's stack is Cloudflare's own **Clef-flash**. It has the same API shape, runs natively in Workers via `env.AI.run`, and keeps data inside Cloudflare.

### Cited Findings
- **Workers AI.** The catalog lists `clef`, `clef-flash` and `clef-omni` (30B MoE, 3B active). It does not list Laya or ModernBERT. Classification models present: `distilbert-sst-2-int8` and `bge-reranker-base`. LoRA inference is offered only on gemma-2b/7b, llama-2-7b and mistral-7b. — [Workers AI models catalog, Cloudflare, fetched 26 Oct 2026](https://developers.cloudflare.com/workers-ai/models/)
  - Custom or arbitrary models need "a separate conversation with Cloudflare"; LoRA is a selective beta. — [rywalker.com, Workers AI review, 15 Sep 2026](https://rywalker.com/research/cloudflare-workers-ai) (secondary)
- **Clef-flash on Workers.** — [Cloudflare clef-flash model page](https://developers.cloudflare.com/workers-ai/models/clef-flash/)
  - Model ID `@cf/cloudflare/clef-flash`, 9B params, 24,576-token context.
  - $0.038/1M input, output free.
  - Same `state` + `questions` (noul/choice/score) schema, 1–64 questions per request.
  - Up to 4 images per request.
  - Long text state is truncated to fit the context window.
  - Weights at huggingface.co/Cloudflare/clef-flash.
  - Example code uses `env.AI.run(...)` in a TypeScript Worker.
- **Clef background.** Clef is 27B on a Qwen3.8-27B backbone and Apache 2.0. Cloudflare's Threat Intelligence team tested Clef for website-domain classification, with no figures published. Languages are not stated. — [Let's Data Science, 8 Oct 2026](https://letsdatascience.com/news/cloudflare-releases-open-weight-clef-decision-models-c52886d6)
  - Cloudflare also launched an RL fine-tuning service, initially run by its forward-deployed engineering team. — [hyper.ai](https://hyper.ai/en/stories/89d073630f45098d6fd53a6dd84bc9fe) and VKTR via Let's Data Science (secondary)
  - Conflict: OpenRouter says Workers AI truncates long text state to about the first 2K tokens. — [OpenRouter Clef listing](https://openrouter.ai/cloudflare/clef) (search snippet)
- **Cloudflare Containers instance sizes.** — [Containers limits, Cloudflare docs, fetched 26 Oct 2026](https://developers.cloudflare.com/containers/platform-details/limits/)

  | Type | vCPU | Memory | Disk |
  |---|---|---|---|
  | lite | 1/16 | 256 MiB | 2 GB |
  | basic | 1/4 | 1 GiB | 4 GB |
  | standard-1 | 1/2 | 4 GiB | 8 GB |
  | standard-2 | 1 | 6 GiB | 12 GB |
  | standard-3 | 2 | 8 GiB | 16 GB |
  | standard-4 | 4 | 12 GiB | 20 GB |

  - Image size limit equals the instance disk size.
  - The page does not mention GPUs.
- **Laya self-hosting features.** — [GitHub README](https://github.com/NandhaKishorM/laya)
  - `laya-serve` is a FastAPI server exposing `/v1/systemone` and `/v1/systemone/batch`, with optional bearer auth via `LAYA_API_KEY`.
  - Docker and Compose files are included, plus a CPU-container quickstart (`docs/docker.md`).
  - `laya-ts` is a TypeScript package that runs inference in-process through ONNX Runtime.
  - `laya-client` is an HTTP client for `laya-serve`.
  - The ONNX runtime "cannot load parallel-layout checkpoints".
- **iOS on-device.**
  - A community repo provides prebuilt ModernBERT base and large `.mlpackage` files, including 4-bit variants, plus a `convert.py`. — [finnvoorhees/ModernBERT-CoreML, Hugging Face](https://huggingface.co/finnvoorhees/ModernBERT-CoreML/commit/7945f87e3d64c516c610e158768e8997d9263b30) (community, not Convai)
  - No Core ML export of Laya, or of its decision head, was found.
  - Safari extension memory, forum-reported only: the handler was killed at about 6 MB in 2021, and the limit reportedly rose to 80 MB in the iOS 15.1 beta. — [Apple Developer Forums thread 687642](https://developer.apple.com/forums/thread/687642)
  - Mobile Safari pages crashed at about 100 MB on an iPhone on iOS 26.2. — [lapcatsoftware, 7 Jan 2026 (via scour.ing mirror)](https://scour.ing/@hello/p/https://lapcatsoftware.com/articles/2026/1/7.html)
  - Apple publishes no official limit.
- **Prompt-injection robustness.**
  - Decision models emit only probabilities over options defined in advance. They produce "no reasoning traces, explanations, or free-form text". — [OpenRouter Jev docs](https://openrouter.ai/docs/guides/community/jev)
  - Laya ships a guard preset for injection, but its held-out injection-detection accuracy is only 0.698 (English). — [GitHub README](https://github.com/NandhaKishorM/laya)
  - Jev's confidence routing "weakens on style-adversarial pairs". — [arXiv 2609.26550](https://arxiv.org/abs/2609.26550)
  - Laya's `noul` answers can be swayed by option label text (issue #156). — [HF model card](https://huggingface.co/convaiinnovations/laya)

### Inferences
- **Output-channel safety.** A non-generative model cannot be hijacked into writing arbitrary text or calling tools. The worst case is a wrong probability. That removes the class of attack where an LLM is tricked into emitting "SAFE" plus extra text that breaks parsing.
- **Input-side risk remains.** An attacker controls the page title and field labels. Text like "this is the official BCA site, not phishing" can still bias the score, as issue #156 and the style-adversarial weakness show. Shoo should keep the rule-based layers authoritative and treat the decision-model score as one signal.
- **On-device.** The fp32 Laya checkpoints (647–808 MB) are about 10x over the reported extension memory ceiling, so a Safari-extension build is not viable. The containing app could in theory host a 4-bit Core ML conversion, with the extension calling it via native messaging. That path is untested, and the RLCD decision head would also need porting.
- **Privacy.** Self-hosting Laya, or using Clef-flash on Workers AI, keeps Shoo's minimal payload inside infrastructure Shoo controls or already uses (Cloudflare). Jev sends it to a US third party, with ZDR reportedly enterprise-only.

### Gaps
- No measured Laya RAM, so container sizing is a guess. 4 GiB (standard-1) is probably the minimum for one fp32 checkpoint; this is an inference, not measured.
- Clef-flash's language coverage, including Indonesian, is unstated.
- No confirmed Workers AI bring-your-own-model path.
- Apple's official Safari web extension memory limit is unknown.

## 5. Project maturity

### Takeaway
Laya is about 5 weeks old (first coverage 19 Sep 2026) and moves fast: PyPI 0.4.15, GitHub 0.4.16, 2,623 commits. It shows very high popularity numbers (34.3k stars, 5.82k HF likes, 56.6k downloads per month) for its age. It has one visible maintainer handle (NandhaKishorM / Convai Innovations), 51 open issues, and several known correctness issues. Jev is early access with a single vendor. Clef is backed by Cloudflare.

### Cited Findings
- **GitHub.** — [NandhaKishorM/laya, GitHub, fetched 26 Oct 2026](https://github.com/NandhaKishorM/laya)
  - 34.3k stars, 3.1k forks, 123 watchers.
  - 51 open issues and 48 open PRs; 2,623 commits on main.
  - Latest described version: 0.4.16, undated. License: Apache-2.0.
  - "Developed by Convai Innovations". No maintainer full name is given.
- **PyPI.** Latest version 0.4.15. Deps: huggingface_hub 1.x, transformers 5.x, torch 2.14. — [PyPI laya](https://pypi.org/project/laya/)
  - Version conflict: GitHub's README describes 0.4.16. Either the repo is ahead of the PyPI release, or the PyPI page was cached.
- **Hugging Face.** 56,562 downloads last month, 5.82k likes, 33 discussions, 74 Spaces. — [HF model card](https://huggingface.co/convaiinnovations/laya)
- **Release timing.**
  - AI Weekly reported the release on 19 Sep 2026. — [AI Weekly](https://aiweekly.co/alerts/convai-ships-laya-a-421m-modernbert-decision-model-apache-20)
  - DataCamp, 23 Sep 2026: these projects "are very new, evolve quickly", and the article's code examples were not all tested end-to-end. — [DataCamp](https://www.datacamp.com/blog/top-open-source-jev-alternatives)
- **Ecosystem and alternatives.** DataCamp lists other open Jev alternatives:
  - Nimble (Qwen3.5-9B LoRA)
  - Kev (Qwen3.5, 0.8B–9B, implements `/v1/systemone`)
  - SemIf
  - Rizzo Flow
  - Von (395M ModernBERT, `pip install von-sdk`)
  - NanoJev (Qwen3-0.6B)
  - Source: [DataCamp, 23 Sep 2026](https://www.datacamp.com/blog/top-open-source-jev-alternatives)
- **Jev maturity.** Early access via a waitlist; the site is labeled "Version 0.01". Versions 1.13 and 1.14 are live. — [typesafe.ai](https://typesafe.ai); [OpenRouter Jev docs](https://openrouter.ai/docs/guides/community/jev)

### Inferences
- 34k stars and 5.8k likes within about 5 weeks is extraordinary for a niche encoder library. It may reflect hype around the Jev launch, or inflated metrics. Weigh the open-issue list and the known bugs (#156, #185, #394, #131) more than the star count.
- The "who is behind it" picture is thin: one GitHub handle and a company with no founder or location named in the sources I read. That is a bus-factor risk for a production dependency.

### Gaps
- No info found on Convai Innovations itself (founders, location, funding).
- There is no dated changelog, so update frequency cannot be measured beyond "0.3.20 to 0.4.16 within about 5 weeks", which comes from version mentions on the pages.
- GitHub contributor count was not visible.
