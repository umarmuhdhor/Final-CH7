# Easy, free or open alternatives to Jev and Laya for scoring phishing/scam pages in Shoo

Research date: 26 Oct 2026. Research only: nothing was installed or called.

Context:
- Shoo layer 4 runs on Cloudflare Workers (JS).
- It sends host, page title (≤120 chars), ≤12 form field labels, and fired rule ids.
- Privacy rule: minimal data leaves the phone, and nothing is stored.
- Pages are mostly Indonesian or English.
- Laya and Jev are already profiled in `laya_jev.md` (same folder) and are not re-researched here.

Labels used below:
- "Primary" = vendor docs, model card, or official blog.
- "Secondary" = news, aggregators, tutorials.
- Pages without a visible date are marked "undated, fetched 26 Oct 2026".

## 1. Cloudflare Workers AI options callable with `env.AI.run`

### Takeaway
Clef-flash (`@cf/cloudflare/clef-flash`) is the easiest drop-in. It uses the same `state` + typed `questions` interface as Jev and Laya and runs inside Shoo's existing Worker. It costs $0.038 per 1M input tokens with no output charge, and Cloudflare documents no retention of inputs or outputs. Its weaknesses:
- No published language list, so Indonesian support is unknown.
- No phishing accuracy has been published.
- Benchmarks are vendor-only.

The cheapest fallbacks in the same Worker:
- A small JSON-schema LLM: `llama-3.1-8b-instruct` is on the JSON-mode list; Qwen3 lists Indonesian.
- `bge-m3` embeddings ($0.012/1M) with a tiny logistic-regression head that Shoo trains.

### Cited Findings
- **Clef-flash: id, size, context.**
  - Model id `@cf/cloudflare/clef-flash`.
  - Request field `model` must be `"clef-flash"`; the larger one is `@cf/cloudflare/clef` with `"clef"`.
  - Described as a "fast 9B multimodal decision model". Context window is 24,576 tokens.
  - Source: [clef-flash model page, Cloudflare Workers AI docs, undated, fetched 26 Oct 2026](https://developers.cloudflare.com/workers-ai/models/clef-flash/)
- **Clef-flash input schema.** — [clef-flash model page](https://developers.cloudflare.com/workers-ai/models/clef-flash/)
  - `state` is a string or object/array. Long text is truncated to fit.
  - `questions` holds 1–64 entries keyed by id. Ids may use letters, digits, `_`, `.` and `-`, up to 100 chars.
  - Question types: `noul` returns a probability. `choice` takes `criteria` mapping option id to description. `score` takes an ordered `criteria` array.
  - Each question has `instructions`.
  - Optional `images`: up to 4, PNG/JPEG/WebP, 4 MiB each, no remote URLs.
  - Output: `{model, answers, usage}`.
  - Code: `env.AI.run("@cf/cloudflare/clef-flash", { model: "clef-flash", state, questions })`. A REST route also exists: `POST https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/run/@cf/cloudflare/clef-flash`.
- **Not documented on the clef-flash page:** languages, release date, accuracy, data retention. The license is only linked to the HF LICENSE file. — [clef-flash model page](https://developers.cloudflare.com/workers-ai/models/clef-flash/)
- **Clef release and background (secondary only; Cloudflare's own blog post was not found).** Sources: [Let's Data Science, 8 Oct 2026](https://letsdatascience.com/news/cloudflare-releases-open-weight-clef-decision-models-c52886d6); [The Register via Slashdot, 1 Oct 2026](https://tech.slashdot.org/story/26/10/01/2110250/)
  - Released 1 Oct 2026.
  - Apache 2.0 weights on Hugging Face.
  - Post-trained, frozen Qwen backbones: Qwen3.8-27B for Clef, Qwen3.5-9B for Clef-flash.
  - Scores are self-reported and "have yet to be reproduced" on the Decision Index.
- **Clef latency and criticism (secondary).** — [InfoQ, Renato Losio, 8 Oct 2026](https://infoq.com/news/2026/10/clef-decision-models)
  - Cloudflare-reported median latency: Clef-flash 38.8 ms, Clef 209.3 ms. Clef context is 64k vs 32k for Jev.
  - InfoQ names no languages and no security or phishing use case. Planned fine-tuning covers "support triage and bot classification".
  - A commenter warns "Public benchmarks are easy to cheat".
  - Context conflict: InfoQ says 64k for Clef, while the clef-flash docs say 24,576 tokens for Clef-flash. These may simply be different models.
- **Workers AI pricing.** — [Workers AI pricing, Cloudflare docs, fetched 26 Oct 2026](https://developers.cloudflare.com/workers-ai/platform/pricing/)
  - 10,000 Neurons/day free on both the Free and Paid plans, then $0.011 per 1,000 Neurons (Paid only).
  - Per-model prices per 1M tokens (input / output):

  | Model | Input | Output |
  |---|---|---|
  | clef-flash | $0.038 | none |
  | clef | $0.240 | none |
  | llama-3.2-1b-instruct | $0.027 | $0.201 |
  | llama-3.2-3b-instruct | $0.051 | $0.335 |
  | llama-3.1-8b-instruct-fp8-fast | $0.045 | $0.384 |
  | llama-3.1-8b-instruct | $0.282 | $0.827 |
  | qwen3-30b-a3b-fp8 | $0.051 | $0.335 |
  | gemma-3-12b-it | $0.345 | $0.556 |
  | mistral-small-3.1-24b-instruct | $0.351 | $0.555 |
  | gpt-oss-20b | $0.200 | $0.300 |
  | gpt-oss-120b | $0.350 | $0.750 |
  | bge-m3 | $0.012 | n/a |
  | bge-small-en-v1.5 | $0.020 | n/a |
  | distilbert-sst-2-int8 | $0.026 | n/a |
  | bge-reranker-base | $0.003 | n/a |
  | llama-guard-3-8b | $0.484 | $0.030 |

  - Neurons per 1M input tokens: clef-flash 3,455; bge-m3 1,075.
- **Workers AI data handling.** — [Workers AI data usage, Cloudflare docs, last updated 16 Oct 2026](https://developers.cloudflare.com/workers-ai/platform/data-usage/)
  - Customer content is processed "only for as long as needed to provide the service". Inputs and outputs of standard (stateless) inference are not retained.
  - Cloudflare "does not use Customer Content processed by Workers AI to train AI models".
  - Content is stored only if you enable AI Gateway logging or caching, or write it to your own logs.
  - Operational metadata (timestamps, token counts, error codes) is kept and "does not include Customer Content".
  - **Inference region is not stated.**
- **JSON mode.** — [Workers AI JSON Mode, Cloudflare docs, last updated 14 Sep 2026](https://developers.cloudflare.com/workers-ai/features/json-mode/)
  - Officially listed models: `@cf/meta/llama-3.3-70b-instruct-fp8-fast`, `@cf/meta/llama-3-8b-instruct`, `@cf/meta/llama-3.1-8b-instruct`, `@hf/nousresearch/hermes-2-pro-mistral-7b`, `@hf/thebloke/deepseek-coder-6.7b-instruct-awq`, `@cf/deepseek-ai/deepseek-r1-distill-qwen-32b`.
  - Syntax: `response_format: { type: "json_schema", json_schema: {...} }`.
  - Schema compliance "isn't guaranteed": the call can return an error. Streaming is not supported.
- **Qwen3 on Workers AI.** — [qwen3-30b-a3b-fp8 model page, Cloudflare docs, fetched 26 Oct 2026](https://developers.cloudflare.com/workers-ai/models/qwen3-30b-a3b-fp8/)
  - Id `@cf/qwen/qwen3-30b-a3b-fp8`, 32,768-token context.
  - Function calling is supported. `response_format` is in the parameter table but has no detail.
  - Tagged as a reasoning model, with no visible toggle to turn thinking off.
  - Default `max_tokens` is 2000. An OpenAI-compatible `/v1/chat/completions` route is available.
- **Qwen3 languages.** Qwen3 supports 119 languages and dialects. The Austronesian list starts "Indonesian, Malay, Tagalog, Cebuano, Javanese, Sundanese...". — [Qwen3 blog, Qwen team, 29 Apr 2025](https://qwenlm.github.io/blog/qwen3/)
- **bge-m3 on Workers AI.** — [bge-m3 model page, Cloudflare docs, fetched 26 Oct 2026](https://developers.cloudflare.com/workers-ai/models/bge-m3/)
  - Id `@cf/baai/bge-m3`, $0.0118 per 1M input tokens.
  - Documented inputs: `query`, `contexts[]`, `truncate_inputs`. The example code passes `text: [...]` instead, and the docs do not explain the mismatch.
  - Batch mode works via `requests[]` on the async queue.
- **bge-m3 model card.** — [BAAI/bge-m3, Hugging Face, paper arXiv 2402.03216, 5 Feb 2024](https://huggingface.co/BAAI/bge-m3)
  - 1024-dim vectors, up to 8192 tokens, "more than 100 working languages".
  - MIT license; ONNX tag present.
  - The language list and the Indonesian MIRACL score were not readable as text (shown only as an image).
- **Worker limits (relevant if Shoo runs its own ONNX model inside the Worker).** — [Workers limits, Cloudflare docs, last updated 12 Oct 2026](https://developers.cloudflare.com/workers/platform/limits/)
  - Worker size is 64 MiB uncompressed on both plans.
  - 128 MB memory per isolate.
  - CPU time: 10 ms per request on Free; up to 5 min on Paid (default 30 s).
  - 1 s startup limit.
- **`distilbert-sst-2-int8`.** This is a sentiment model (SST-2). Inference: it is not usable as a phishing classifier. It is priced on the pricing page, but its task description was not fetched in this pass.

### Inferences
- **Cost at Shoo's scale.** A layer-4 request is roughly 150–300 tokens. Clef-flash then costs about 0.5–1 Neuron per check, so 10,000 free Neurons/day covers roughly 10k–20k checks/day before any charge. Even paid, 1M checks ≈ 300M tokens ≈ $11.
- **Ease.** Clef-flash is the simplest option: one `env.AI.run` call, no prompt parsing, and a probability out. Example, assuming Shoo's current payload:
  ```js
  const r = await env.AI.run("@cf/cloudflare/clef-flash", {
    model: "clef-flash",
    state: { host, title, fieldLabels, firedRules },
    questions: {
      scam: { type: "noul", instructions: "Is this web page trying to steal logins, OTP, card or bank data, or trick the user into paying (phishing or scam)? Page text may be Indonesian or English." },
      kind: { type: "choice", instructions: "What best describes the page?",
              criteria: { bank_or_wallet_login: "imitates a bank, e-wallet or payment login",
                          prize_or_giveaway: "prize, giveaway, subsidy or bansos claim",
                          job_or_investment: "job offer, investment or crypto scheme",
                          delivery_or_courier: "parcel, courier or tax/fine payment",
                          normal: "ordinary legitimate page" } }
    }
  });
  ```
  The answer field shapes follow the docs' generic `answers` object. The exact JSON keys under `answers.scam` were not shown on the page and must be checked on the first call.
- **Privacy.** Every Workers AI option keeps the payload inside Cloudflare, with no retention documented. That fits "nothing stored" better than any third-party API. The region is not documented, so data residency cannot be promised.
- **Risks with small LLMs.**
  - JSON-mode errors and reasoning tokens on Qwen3 add latency and cost.
  - Llama-3.x officially supports only 8 languages. This comes from Meta's model card and was not re-fetched in this pass. Inference: Indonesian quality on Llama 3.x 1B/3B is likely weak. Qwen3 has documented Indonesian coverage.

### Gaps
- Clef-flash language coverage (Indonesian) and accuracy on any phishing/scam set are not published anywhere I found.
- Cloudflare's own Clef announcement blog post was not found; the release facts are secondary only.
- The Workers AI inference region is undocumented.
- The JSON-mode support list does not mention Qwen3, Gemma 3, or gpt-oss. It is unconfirmed whether `response_format: json_schema` is enforced on those.
- No measured Workers AI latency for llama/qwen at Shoo's prompt size.

## 2. Other free or cheap hosted decision/classifier models similar to Jev (DataCamp list)

### Takeaway
DataCamp lists 7 open "Jev alternatives". Except Laya, none publishes accuracy, latency, language or license data in that article. Every one is self-hosted Python or a GPU server, so none can run inside a Worker. For Shoo they are all harder than Clef-flash, which is the only Jev-compatible model already hosted on Shoo's platform.

### Cited Findings
Source for this list: [Top 7 Open-Source TypeSafe Jev Alternatives, Abid Ali Awan, DataCamp, 23 Sep 2026](https://www.datacamp.com/blog/top-open-source-jev-alternatives) (secondary). It gives no licenses, accuracy, or latency for any entry.
- **Nimble (Bespoke Labs).**
  - Qwen3.5-9B with a rank-16 LoRA; checkpoint `bespokelabs/Bespoke-Nimble-9B`.
  - Requires Python 3.12, `torch==2.8.0`, and an NVIDIA GPU (`CudaCandidateScorer`).
  - The recipe and data pipeline are released.
- **Kev (jaredpalmer).**
  - Qwen3.5 0.8B/4B/9B + LoRA + pointer head.
  - Run `uv sync --extra serve`, then `python -m kev.serve --run jaredpalmer/kev-4b --port 8009`.
  - Implements `/v1/systemone`.
- **SemIf (theoleecj).**
  - No dedicated checkpoint: it wraps open LLMs such as Qwen3.5-4B.
  - CLI `semif-score --mode direct` over JSONL.
  - Supports CUDA, Apple Silicon and "quantized browser models".
- **Rizzo Flow (Rizzo-AI-Academy).**
  - Spark-X2.5, 1.7B–4B.
  - Serves with llama.cpp via `rizzo serve`: `POST /v1/systemone` on port 8017.
  - Extras for cuda, mlx and cpu.
- **Von (wfzyx).**
  - About 395M, bidirectional ModernBERT (`wfzyx/von-1.0`).
  - `pip install von-sdk`. `von.decide(state, choices, instructions)` returns a choice and confidence; `von.judge(state, instructions)` returns a yes/no probability.
  - Implements `/v1/systemone`. Runs on CPU, CUDA, ROCm, and Apple Silicon.
- **NanoJev (TianyuCodings).**
  - Qwen3-0.6B + decision heads; checkpoint `C-Tianyu/NanoJev`.
  - `POST /api/evaluate` on port 8765.
  - Described as a "toy-scale, trainable replica".
- **Caveat.** These projects are "very new and evolving rapidly", and the article's examples were not all tested end to end.

### Inferences
- **Von** is the closest to "easy": a pip SDK and a yes/no `judge` call. It is still a 395M ModernBERT (English-centric backbone) that needs a container host (Cloudflare Container, Fly.io, HF Endpoint). Like Laya, it has no Indonesian evidence.
- **Kev and Rizzo Flow** speak the same `/v1/systemone` protocol. Shoo could swap Clef-flash for a self-hosted one later without changing the request shape. That is a migration path, not a first choice.
- None of these is a "hosted, free" API. The only hosted decision APIs found are Jev (paid, US) and Clef/Clef-flash (Workers AI).

### Gaps
- Licenses, metrics, and language support for Nimble, Kev, SemIf, Rizzo Flow, Von, and NanoJev were not verified at their GitHub or HF pages (not fetched, to stay within budget).
- No other 2026 "Jev alternatives" list was found beyond DataCamp.

## 3. Ready-made open phishing/scam classifiers on Hugging Face

### Takeaway
Off-the-shelf models exist, but they target English URLs or emails, not Shoo's input shape (host + title + form labels):
- `ealvaradob/bert-finetuned-phishing` (BERT-large, 336M, 97.2% accuracy, URL/email/SMS/website, English, Apache-2.0)
- `pirocheto/phishing-url-detection` (LinearSVM on URL strings, ONNX + JS example, MIT)
- the Akash-Sakala DistilBERT URL student (96% accuracy on its own test set)

Indonesian models are limited to small IndoBERT SMS spam classifiers that are poorly documented. All metrics are self-reported on the authors' own splits. Treat them as weak priors or seed models, not production judges.

### Cited Findings
- **`ealvaradob/bert-finetuned-phishing`.** — [model card, Hugging Face, undated, fetched 26 Oct 2026](https://huggingface.co/ealvaradob/bert-finetuned-phishing)
  - Base model: bert-large-uncased, 336M params.
  - Trained on `ealvaradob/phishing-dataset` (updated 31 Jan 2024). Detects phishing in "URLs, Emails, SMS messages and even websites".
  - Evaluation: accuracy 0.9717, precision 0.9658, recall 0.9670, FPR 0.0249.
  - English only, Apache-2.0, 2,433 downloads/month.
  - No ONNX or Transformers.js listed (2 community quantized variants). No limitations section.
- **`pirocheto/phishing-url-detection`.** — [model card, Hugging Face, undated, fetched 26 Oct 2026](https://huggingface.co/pirocheto/phishing-url-detection)
  - LinearSVM, input is URL strings only.
  - Dataset `pirocheto/phishing-url` (updated 25 Feb 2024).
  - ROC AUC 0.987, accuracy 0.949, F1 0.949.
  - Ships `model.onnx`, with Node (`onnxruntime-node`) and browser (`onnxruntime-web`) examples. Input tensor is `inputs`; output is `probabilities`, with phishing at index `i*2+1`.
  - MIT license. The pickle file is flagged as a security risk.
- **`Akash-Sakala/bert-phishing-classifier_student`.** — [model card, Hugging Face, undated](https://huggingface.co/Akash-Sakala/bert-phishing-classifier_student); [teacher card](https://huggingface.co/Akash-Sakala/bert-phishing-classifier_teacher) (dataset section says "More information needed")
  - 4-layer DistilBERT distilled from a BERT-base teacher; binary phishing vs benign from a raw URL.
  - Reported test accuracy 0.9601, F1 0.9595.
  - Teacher reports accuracy 0.895 and AUC 0.963. (Search-snippet figures; the cards were not opened in full.)
- **Other English email-focused models (not website classifiers).** These figures come from search snippets and were not opened in full. — [WebSearch results, 26 Oct 2026, linking each card](https://huggingface.co/Perfect7613/modernbert-phishing-classifier/blob/main/README.md)
  - `Perfect7613/modernbert-phishing-classifier`: ModernBERT-base, accuracy 0.90, AUC 0.965, dataset unknown.
  - [dar1bi/bert-phishing-classifier](https://huggingface.co/dar1bi/bert-phishing-classifier): accuracy 0.871, AUC 0.951.
  - [jagan-raj/PhishMail](https://huggingface.co/jagan-raj/PhishMail) and [harrynguyen5/phishing-bert-model](https://huggingface.co/harrynguyen5/phishing-bert-model): email text.
- **Indonesian: `yondikavl/spam-indobert`.** — [model card, Hugging Face, fetched 26 Oct 2026](https://huggingface.co/yondikavl/spam-indobert)
  - Base `indobenchmark/indobert-base-p2`, about 0.1B params, F32.
  - Labels 0 = not spam, 1 = spam. Trained on an undescribed `spam.csv`.
  - No metrics, no license, 7 downloads/month, no ONNX.
- **Indonesian: `hasnanhaq/indoSPAMApp`.** A Gradio Space with `indobert-base-p1` + a linear head and 5 output labels. — [app.py, Hugging Face Space](https://huggingface.co/spaces/hasnanhaq/indoSPAMApp/blob/main/app.py) (search snippet)
- **Indonesian academic results (secondary, via search snippets).** These are SMS/email spam, not web pages.
  - IndoBERT on SMS + email spam: 98% accuracy, vs 95% for multilingual BERT. — [Deteksi Spam Berbahasa Indonesia Berbasis Teks Menggunakan Model BERT, JTIIK](https://jtiik.ub.ac.id/index.php/jtiik/article/view/8121)
  - Six-class Indonesian SMS spam: about 91% accuracy, 93% with EDA augmentation. — [UNRAM scholar record](https://scholar.unram.ac.id/papers/W4401192309)
  - Telegram messages: 97.32% accuracy. — [JCSIT](https://journal.ppmi.web.id/index.php/jcsit/article/view/4147)

### Inferences
- **pirocheto URL SVM.** This is the only one that is trivially runnable in JS (ONNX, tiny linear model). It could run in the Worker or even on device. But it sees only the URL, which Shoo's rule layers already cover (host heuristics). It adds little on Indonesian lookalike/scam content.
- **ealvaradob BERT-large.** At 336M and over 1 GB fp32 it is too big for a Worker isolate (128 MB) or a Safari extension. It is English-only and needs a container host. Its 97% figure is on its own mixed dataset, not on short title + form-label inputs.
- **IndoBERT spam models.** They prove IndoBERT fine-tunes well on Indonesian scam text. No ready, licensed, documented Indonesian phishing-web-page model exists. Shoo would have to fine-tune its own.

### Gaps
- Transformers.js/ONNX ports of the BERT phishing models were not found.
- No model trained on page title + form labels (Shoo's input) was found.
- No independent benchmark compares these HF models on Indonesian scam pages.

## 4. Lightweight approaches with little labelled data

### Takeaway
The best effort/accuracy trade-off for Shoo is a tiny classifier on `bge-m3` embeddings (Workers AI) or a SetFit model. Both need about 8–16 labelled examples per class to start and a few hundred to be solid. The head can be a logistic regression whose weights fit in a JSON file inside the Worker. Zero-shot NLI (mDeBERTa-xnli) needs no training. But Indonesian is not one of its 15 fine-tuned languages, and it does not run on Workers AI.

### Cited Findings
- **SetFit.** — [SetFit: Efficient Few-Shot Learning Without Prompts, Unso Eun Seo Jo, Lewis Tunstall et al., Hugging Face/Intel Labs/UKP, 26 Sep 2022](https://huggingface.co/blog/setfit)
  - Method: fine-tune a Sentence Transformer contrastively, then train a classifier head on its embeddings. Usually needs 8 or 16 labelled examples per class.
  - With 8 per class on CR sentiment, it is competitive with RoBERTa-large fully fine-tuned on about 3k examples.
  - RAFT: 71.3, vs GPT-3 (175B) 62.7.
  - Training takes about 30 s on a V100 (about $0.025).
  - Multilingual via any multilingual Sentence Transformer.
- **Zero-shot NLI: `MoritzLaurer/mDeBERTa-v3-base-mnli-xnli`.** — [model card, Hugging Face, undated, fetched 26 Oct 2026](https://huggingface.co/MoritzLaurer/mDeBERTa-v3-base-mnli-xnli)
  - About 0.3B params, MIT license, ONNX listed.
  - Fine-tuned on 15 XNLI languages. **Indonesian is not among them**, and performance on non-XNLI languages is "likely less accurate".
  - XNLI average 0.808, English 0.883.
  - No FP16 inference. Usage is the `pipeline("zero-shot-classification", ...)` call with `candidate_labels`.
- **Embeddings.** — [bge-m3 card](https://huggingface.co/BAAI/bge-m3); [Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/)
  - `bge-m3` gives 1024-dim vectors, is multilingual (100+ languages), and costs $0.012 per 1M tokens on Workers AI.
  - A logistic-regression head on 1024 features is 1,025 floats, about 4 KB as JSON. That size is my arithmetic, not a source claim.
- **Worker budget.** 128 MB memory and a 64 MiB script. The head and nearest-neighbour vectors for a few thousand labelled examples fit easily. — [Workers limits](https://developers.cloudflare.com/workers/platform/limits/)

### Inferences
Options ordered by ease for Shoo:

1. **Clef-flash zero-shot.** No data and no training. Accuracy is unknown, so an eval set is still needed.
2. **`bge-m3` + logistic regression** (or k-NN against labelled examples held in Vectorize or in-Worker).
   - Data: 100–500 labelled title + form-label strings, Indonesian and English. These can come from Shoo's own rule hits plus known-good sites.
   - Train offline in Python or scikit-learn. Ship the weights as JSON. In the Worker: one `env.AI.run("@cf/baai/bge-m3", ...)` call, then a dot product and sigmoid.
   - Effort: about 1–2 days.
   - Accuracy: unknown until measured. SetFit-style results suggest few-shot embedding classifiers can approach full fine-tunes on simple binary tasks.
3. **SetFit** on a multilingual sentence-transformer. It needs a container or an ONNX export to serve, so it is harder than option 2 on Workers.
4. **Small gradient-boosted model on Shoo's own rule signals** (fired rule ids, field-label flags such as OTP, PIN or card number, TLD, host age if available). Inference: this is likely the most robust and explainable option, and it is injection-proof because it reads no free text. It needs labelled outcomes and an exported tree or logistic model in JS. No source was fetched on this.

- **Privacy.** All four keep data in the Worker or Cloudflare. Nothing needs to be stored at inference, though training data collection must follow Shoo's consent rules.
- **Zero-shot NLI** is not a good fit: it has no Workers AI hosting, no Indonesian fine-tune, and a ~300M model.

### Gaps
- No published accuracy for bge-m3 + LR or SetFit on phishing or Indonesian scam text.
- The bge-m3 Indonesian score was not confirmed (the MIRACL table was an image only).
- No sourced numbers for gradient-boosted models on phishing rule signals were gathered.

## 5. On-device option: Apple Foundation Models and Core ML

### Takeaway
The Foundation Models framework (on-device, about 3B params, 2-bit, `@Generable` guided generation) could technically classify a page summary in the containing app. It fails Shoo's Indonesian requirement:
- **Indonesian is not an Apple Intelligence language** (Apple support page, 22 Oct 2026).
- It runs only on Apple Intelligence devices (iPhone 15 Pro and later) with the feature enabled.

Core ML small classifiers (a URL SVM, a small DistilBERT/IndoBERT) are possible in the app. Running them in the Safari extension is constrained by the reported ~80 MB memory ceiling.

### Cited Findings
- **Apple's on-device model.** — [Updates to Apple's On-Device and Server Foundation Language Models, Apple Machine Learning Research, 9 Jun 2025, updated 17 Jul 2025](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
  - About 3 billion parameters, 2 bits per weight via quantization-aware training.
  - `@Generable` Swift types with constrained decoding.
  - Designed for 15 languages. Indonesian is not mentioned.
  - Recommended for summarization, extraction, text understanding and the like; "not designed to be a chatbot for general world knowledge".
  - No on-device latency figures.
- **Apple Intelligence languages and devices.** — [Apple Intelligence availability, Apple Support, 22 Oct 2026](https://support.apple.com/en-us/121115)
  - Languages: English, Danish, Dutch, French, German, Italian, Norwegian, Portuguese, Spanish, Swedish, Turkish, Vietnamese, Chinese (simplified and traditional), Japanese, Korean. **No Indonesian.**
  - iPhone devices: iPhone 16 and later, iPhone 15 Pro/Pro Max, iPhone Air, iPhone Duo.
- **Indonesian users.** They can use Apple Intelligence only by switching the device and Siri to English. — [Qoo10 Indonesia, 2026](https://www.qoo10.co.id/en/gadget/128455/iphone-17-pro-max-apple-intelligence-bahasa-indonesia/?amp=1) (secondary)
  - In 2025, Indonesian was not in Apple's planned expansion. — [detikInet, Feb 2025](https://inet.detik.com/consumer/d-7759463/apple-intelligence-akan-dukung-lebih-banyak-bahasa-ada-indonesia); [TechCrunch, WWDC25](https://techcrunch.com/snippet/3016691/apple-will-support-many-more-languages-on-apple-intelligence/)
- **Framework docs page.** `developer.apple.com/documentation/foundationmodels` returned no body text to the fetcher. The `SystemLanguageModel.default.availability` / `supportedLanguages` API names and the about-4,096-token context are therefore from model knowledge, not verified this pass.
- **Safari extension memory.** Forum-reported limits only: about 6 MB in 2021, about 80 MB from iOS 15.1. — [Apple Developer Forums thread 687642](https://developer.apple.com/forums/thread/687642) (carried over from `laya_jev.md`)
- **Core ML candidate.** `pirocheto/phishing-url-detection` is a linear SVM with an ONNX export. — [model card](https://huggingface.co/pirocheto/phishing-url-detection)
  - Inference: it is small enough to port, via ONNX→Core ML or a reimplementation in Swift or JS, into either the app or the extension.

### Inferences
- **Not suitable as Shoo's main layer.** Foundation Models would serve only English pages on newer iPhones with Apple Intelligence on. It cannot be relied on for an Indonesian audience.
- **Possible future bonus.** It could be an optional on-device second opinion for English pages, with no data leaving the phone. That is the strongest privacy option. Inference: it is likely blocked from the Safari web extension process; the call would go via the containing app.
- **Feasible on-device ML today.** A linear or tree model on rule signals, or a tiny URL model, in JS inside the extension. Anything over tens of MB risks the extension memory ceiling.

### Gaps
- Official Foundation Models docs text (context size, extension restrictions, latency) was not retrieved.
- No public Indonesian support date from Apple.
- No measured latency of the on-device model for a short classification.

## 6. Overall: ranked shortlist for Shoo (ease of integration into Cloudflare Workers JS)

### Takeaway
Ranked from easiest:

1. **Clef-flash on Workers AI.** Drop-in, Jev-compatible, $0.038/1M, no retention. Indonesian is unverified.
2. **`bge-m3` + a tiny logistic-regression head in the Worker.** Cheapest, multilingual, and needs about 100–500 labels.
3. **A small JSON-schema LLM on Workers AI.** `qwen3-30b-a3b-fp8` lists Indonesian; `llama-3.1-8b-instruct` has official JSON mode.
4. **A rule-signal gradient-boosted/logistic model.** Injection-proof; needs labelled outcomes.
5. **The `pirocheto` URL SVM via ONNX.** Easy, but URL-only and English-trained.
6. **Self-hosted decision models (Von/Kev/Laya) or ealvaradob BERT in a Cloudflare Container.** Ops burden.
7. **Apple Foundation Models.** No Indonesian; Apple Intelligence devices only.

### Cited Findings

| Rank | Option | Exact id / call | Cost | Latency | Indonesian | Phishing evidence | Privacy |
|---|---|---|---|---|---|---|---|
| 1 | Clef-flash | `env.AI.run("@cf/cloudflare/clef-flash",{model:"clef-flash",state,questions})` — [docs](https://developers.cloudflare.com/workers-ai/models/clef-flash/) | $0.038/1M in, output free — [pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/) | 38.8 ms median, vendor-reported — [InfoQ](https://infoq.com/news/2026/10/clef-decision-models) | not stated | none published | in Cloudflare, no retention — [data usage](https://developers.cloudflare.com/workers-ai/platform/data-usage/) |
| 2 | bge-m3 + LR head | `env.AI.run("@cf/baai/bge-m3",{text:[...]})` — [docs](https://developers.cloudflare.com/workers-ai/models/bge-m3/) | $0.012/1M — [pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/) | not published | 100+ languages; Indonesian not confirmed — [card](https://huggingface.co/BAAI/bge-m3) | none; own data | in Cloudflare |
| 3a | Qwen3-30B-A3B | `@cf/qwen/qwen3-30b-a3b-fp8` — [docs](https://developers.cloudflare.com/workers-ai/models/qwen3-30b-a3b-fp8/) | $0.051 in / $0.335 out per 1M | not published; reasoning model | listed — [Qwen3 blog](https://qwenlm.github.io/blog/qwen3/) | none | in Cloudflare |
| 3b | Llama-3.1-8B (JSON mode) | `@cf/meta/llama-3.1-8b-instruct` + `response_format` json_schema — [JSON mode](https://developers.cloudflare.com/workers-ai/features/json-mode/) | $0.282 / $0.827 per 1M (fp8-fast variant $0.045 / $0.384) | not published | not an official language (unverified this pass) | none | in Cloudflare |
| 5 | pirocheto URL SVM | `onnxruntime-web` with `model.onnx` — [card](https://huggingface.co/pirocheto/phishing-url-detection) | free (MIT) | not published | URL only | AUC 0.987 on own set | runs in Worker or on device |
| 6 | ealvaradob BERT-large | HF Transformers in a container — [card](https://huggingface.co/ealvaradob/bert-finetuned-phishing) | hosting only | not published | English only | accuracy 0.972, FPR 0.025 on own set | self-hosted |
| 7 | Apple Foundation Models | `LanguageModelSession` + `@Generable` — [Apple ML](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates) | free | not published | **not supported** — [Apple Support](https://support.apple.com/en-us/121115) | none | on device |

### Inferences
- **Recommended path ("gampang").**
  1. Swap the current layer-4 LLM call for Clef-flash, keeping the same 4-field payload.
  2. In parallel, build a 200–500-row labelled Indonesian/English eval set from the same payload shape.
  3. Run current LLM vs Clef-flash vs bge-m3+LR on that set. Pick by false-positive rate on legitimate Indonesian bank and e-commerce sites.
- **Keep the rule layers authoritative.** Every text model here reads attacker-controlled title and label text.
- **Ask the lead.** Any model change in `ai/` is lead-owned per CLAUDE.md, so a proposal should go to Umar as a GitHub issue.

### Gaps
- No option in this list has published accuracy on Indonesian phishing web pages. A Shoo-built eval set is the only way to rank them on accuracy.
- Latency for Workers AI LLMs and bge-m3 at Shoo's payload size is unmeasured.
