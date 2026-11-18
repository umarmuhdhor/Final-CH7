# RISET-PAPER

## Tahap 1 — Literatur deteksi halaman scam/phishing penyamar brand

Tanggal riset: 2026-11-18. Hanya riset: tidak ada kode diubah, tidak ada commit, tidak ada push.
Belum ada shortlist atau rekomendasi (itu Tahap 2). Tidak ada tebakan soal model yang sedang dipakai.

### 0. Batas yang dipakai sebagai penguji

| Batas | Nilai |
|---|---|
| Input | URL, judul, teks terlihat, daftar field form (nama, tipe, label), umur domain. Tanpa HTML mentah, screenshot, DOM, WHOIS selain umur. |
| Runtime | Cloudflare Worker, JS murni, tanpa GPU, < 50 ms CPU |
| Ukuran model + kode | ≤ 3 MB gzip (target), ≤ 10 MB (maksimum) |
| Bahasa | Indonesia + Inggris |
| Label | Lama dan sebagian salah |
| Prioritas | Recall scam tinggi pada FPR 0,5% dan 2% |

Kolom "lolos batas?" memakai batas di atas. Banyak paper gagal di input (butuh HTML/screenshot), bukan di akurasi.

### 1. Status agent-reach

- Terpasang: v1.6.1, lewat `uv tool install` dari GitHub release resmi (bukan PyPI, sesuai peringatan README), lalu `agent-reach setup`.
- `agent-reach doctor --json` **tidak didukung** di v1.6.1 (`unrecognized arguments: --json`). `agent-reach doctor` sudah mencetak JSON secara default. Itu yang dipakai.
- Channel dari `doctor` (tanpa jaringan): `github`, `youtube`, `bilibili`, `v2ex`, `web` berstatus `unverified` (default, terpasang). Sembilan lainnya `not_added` (twitter, reddit, facebook, instagram, xiaohongshu, linkedin, boss, xueqiu, xiaoyuzhou).
- Uji live (`agent-reach check`):
  - `web`: Exa search lolos, Jina read lolos, Exa read lolos.
  - `youtube`: read, search, subtitle lolos.
  - `github`: pencarian lewat `gh` lolos. Backend `github-api` kena rate limit (60/jam tanpa token); `read` via `gh` melapor `RATE_LIMITED`.
  - `reddit`: gagal (`UPSTREAM_BROKEN`, browser Agent Reach belum terpasang). Tidak ada login yang dilakukan.
- Kendala: 6 query Exa paralel memicu HTTP 429. Reach menjeda channel itu 3599 detik dan melarang ganti backend, jadi limit tidak saya tembus. Sisa pencarian pakai indeks paper Firecrawl, pencarian web Firecrawl, `gh`, dan scrape halaman sumber.
- Efek samping `setup`: membuat salinan skill di `~/.agents/skills/agent-reach`, tautan di `~/.cursor`, `~/.gemini`, `~/.copilot`, memperbarui salinan di `~/.claude/skills/agent-reach`, dan menghapus venv lama `~/.agent-reach-venv`.
- Belum login ke platform apa pun. Reddit butuh login, jadi menunggu persetujuan user.

### 2. Tabel paper

Keluarga: a URL/leksikal · b teks halaman · c berbasis referensi brand · d label kotor/timpang · e distillation · f ensemble/stacking/cascade · g Indonesia/Asia Tenggara.
Angka di kolom metrik diambil dari isi paper. Tanda **(turunan)** berarti saya hitung sendiri dari angka paper, bukan angka paper.

| # | Judul | Tahun | Venue | Link | Kel. | Kombinasi model | Fitur | Dataset | Recall@FPR / AUC | Ukuran / latency | Lolos batas? |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | URLTran | 2021 | arXiv (preprint) | [arXiv 2106.05256](https://arxiv.org/abs/2106.05256) | a | BERT / RoBERTa / transformer 3 layer, fine-tune | URL | Data URL skala produksi (ukuran tidak saya verifikasi) | TPR 86,80% @ FPR 0,01% (URLNet 71,20%, Texception 52,15%); AUC 0,9993 | 0,36 ms/sampel di GPU V100; ukuran tidak dilaporkan | Tidak terbukti: latency diukur di GPU, ukuran tidak ada |
| 2 | Towards Lightweight URL-Based Phishing Detection (Butnaru dkk.) | 2021 | Future Internet (MDPI) | [doi 10.3390/fi13060154](https://www.mdpi.com/1999-5903/13/6/154) | a | Random Forest | 12 fitur URL | 100k URL (PhishTank + sumber benign); uji 380k campuran | Recall 99,06%, akurasi 99,29%; FPR dan AUC angka tidak dilaporkan; akurasi rata-rata ≈94% pada uji temporal tanpa retrain | Latency/ukuran tidak dilaporkan | Ya secara bentuk (RF 12 fitur URL). FPR tidak ada |
| 3 | PMANet | 2023 | arXiv (preprint) | [arXiv 2311.12372](https://arxiv.org/abs/2311.12372) | a | CharBERT post-trained + attention antar-layer + SPP | URL | GramBeddings (seimbang), Mendeley (rasio ≈43:1) | AUC 0,9941 (abstrak). Pada Mendeley timpang: AUC 0,9506, recall 0,5786, precision 0,8944 | 12 layer transformer; ukuran tidak dilaporkan | Tidak: transformer 12 layer |
| 4 | Lightweight Hybrid MLP for Real-Time Phishing URL Detection | 2026 | arXiv (preprint) | [arXiv 2606.00889](https://arxiv.org/abs/2606.00889) | a | Blacklist + MLP | 16 fitur struktural URL | PhiUSIIL, 235.795 URL | AUC 0,9965, recall 99,95% (FPR tidak dilaporkan) | 1,2 ms/URL, 4.200 URL/dtk | Ya secara bentuk. Angka kemungkinan terlalu optimis (lihat #21) |
| 5 | Phishing Detection System: CharCNN + LightGBM | 2025 | arXiv (preprint) | [arXiv 2512.16717](https://arxiv.org/abs/2512.16717) | a, f | Char-CNN (60%) + LightGBM (40%) | URL + 36 fitur leksikal/domain | 19.873 URL uji | AUC 0,99947, recall 99,635%, precision 100% | Ukuran tidak dilaporkan | Tidak terbukti: butuh bukti ukuran; fitur "domain-based" tidak dirinci |
| 6 | Comparative Analysis of TinyBERT, SVM, Char-CNN (Krisanti & Umam, Univ. Dian Nuswantoro) | 2026 | SISTEMASI (jurnal Indonesia) | [doi 10.32520/stmsi.v15i5.6345](https://doi.org/10.32520/stmsi.v15i5.6345) | a, g | TinyBERT (weighted loss), SVM n-gram karakter, RF leksikal, Char-CNN | URL | 49.750 URL multi-kelas dibinerkan; tidak disebut khusus Indonesia | Recall phishing 0,9512, F1 0,9387, akurasi 0,9925; AUC/FPR tidak ditulis | Tidak dilaporkan | Tidak terbukti: transformer, ukuran tidak ada |
| 7 | Mahmud & Wirawan, Deteksi Phishing Website (Univ. Gunadarma) | 2024 | SISTEMASI | [doi 10.32520/stmsi.v13i4.3456](https://sistemasi.ftik.unisi.ac.id/index.php/stmsi/article/view/3456) | a, g | Decision Tree, Random Forest, KNN | Fitur URL | Tidak disebut di halaman; motivasi data PANDI | RF: akurasi 0,834, precision 0,86, recall 0,83; AUC/FPR tidak ada | Kecil (model klasik) | Ya ukuran; akurasi rendah (83%) |
| 8 | An effective detection approach using URL and HTML features (Aljofey dkk.) | 2022 | Scientific Reports | [doi 10.1038/s41598-022-10841-5](https://doi.org/10.1038/s41598-022-10841-5) | b, a | XGBoost | URL + TF-IDF karakter dari teks/HTML + fitur hyperlink | 60.252 halaman (32.972 benign / 27.280 phishing) + benchmark publik | FPR 1,39% (akurasi 96,76%); FPR 2,09% (akurasi 98,48%). Recall ≈94,5% **(turunan**, dari akurasi + FPR) | Tidak dilaporkan | Tidak: fitur HTML dan hyperlink. Versi teks-terlihat saja belum diuji |
| 9 | HTMLPhish | 2020 | IJCNN 2020 | [arXiv 1909.01135](https://arxiv.org/abs/1909.01135) | b | CNN, embedding kata + karakter | Teks dokumen HTML | >50.000 dokumen HTML | Akurasi dan TPR >93%; FPR/AUC tidak dilaporkan | Tidak dilaporkan | Tidak: HTML mentah |
| 10 | WebPhish (Look Before You Leap) | 2024 | Expert Systems with Applications 236 | [arXiv 2011.04412](https://arxiv.org/abs/2011.04412) | b | CNN pada embedding URL + HTML | URL mentah + HTML | Data phishing dunia nyata | Akurasi 98,1%; recall/FPR tidak di abstrak | Tidak dilaporkan | Tidak: HTML mentah |
| 11 | MultiText-LP (Phishing detection through multi-model HTML analysis) | 2024 | arXiv (preprint) | [arXiv 2401.04820](https://arxiv.org/abs/2401.04820) | b | MLP tabular + CANINE (judul) + RoBERTa (isi), fusi + linear | Fitur tabular HTML, judul, teks isi | Dataset baru (dirilis) + CatchPhish | F1 96,80, akurasi 97,18 | Transformer penuh; ukuran tidak dilaporkan | Tidak: transformer besar, fitur HTML |
| 12 | PhishLang (MobileBERT) | 2024 | arXiv (preprint; venue tidak terverifikasi) | [arXiv 2408.05667](https://arxiv.org/abs/2408.05667) | b, f | MobileBERT: model URL + model source, digabung | Source HTML terparse + URL | 5K sampel berlabel manual; 2.000 URL PhishTank | Precision 0,93, recall 0,95, akurasi 0,94 (tabel 3); FPR tidak dilaporkan | Memori MobileBERT 74 MB; prediksi median 0,39 dtk (model), 0,9 dtk (total). Kolom "size 7KB" di paper = ukuran input, bukan model | Tidak: >10 MB, >50 ms, butuh HTML |
| 13 | Phishpedia | 2021 | USENIX Security 2021 | [usenix.org](https://www.usenix.org/conference/usenixsecurity21/presentation/lin) | c | Deteksi logo (detektor objek) + pencocokan logo (Siamese) + cek domain | Screenshot + URL | Daftar referensi 181 brand | Identification rate 99,2%, precision 98,2%, recall 87,1% | 0,19 dtk/halaman | Tidak: screenshot, model visual |
| 14 | PhishIntention | 2022 | USENIX Security 2022 | [usenix.org](https://www.usenix.org/conference/usenixsecurity22/presentation/liu-ruofan) | c | Phishpedia + klasifier halaman-minta-kredensial (CRP) + dinamika | Screenshot + layout UI | ≈50K halaman phishing + benign | Precision 99,8%, recall 90,6%, FPR 5,10% pada set legit menyesatkan; recall 0,9 pada FPR 10⁻³ (klaim paper) | 0,58 dtk rata-rata; akurasi CRP 95,0% | Tidak: screenshot, dinamis |
| 15 | KnowPhish | 2024 | USENIX Security 2024 | [arXiv 2403.02253](https://arxiv.org/abs/2403.02253) | c, g | KB brand ±20k + LLM (GPT-3.5-turbo-instruct) ekstraksi brand dari teks + XLM-R CRP + cek domain sah | Screenshot (logo) + teks HTML + URL | TR-OP 10k (5k/5k); SG-SCAN 10k lalu lintas Singapura | TR-OP: recall 86,90%, precision 97,84%. Studi lapangan Singapura: precision 97,42% (681 dari 699 laporan) | 1,64 dtk; varian KPD 7,83 dtk | Tidak: LLM API, XLM-R, screenshot. Langkah cek domain sah ↔ brand bersifat deterministik |
| 16 | Detecting Phishing Sites Using ChatGPT (ChatPhishDetector) | 2023 | arXiv (preprint; venue tidak terverifikasi) | [arXiv 2306.05816](https://arxiv.org/abs/2306.05816) | c | GPT-4V dengan prompt dari hasil crawl, tanpa training | Teks + screenshot + URL hasil crawler | Dataset sendiri, multibahasa | Precision 98,7%, recall 99,6% (GPT-4V); FPR tidak dilaporkan | Panggilan LLM, tidak dilaporkan | Tidak: LLM, screenshot |
| 17 | PhishAgent | 2025 | AAAI 2025 (Oral) | [arXiv 2408.10738](https://arxiv.org/abs/2408.10738) | c | Agen MLLM + KB brand online/offline + retrieval | Logo + HTML | TR-OP, SG-SCAN-1k, TR-AP | Recall 97,05% (TR-OP), 93,20% (SG-SCAN-1k), 94,70% (TR-AP); precision 95,24 / 93,20 / 95,02% | 2,25 / 2,54 / 2,43 dtk | Tidak: MLLM, logo |
| 18 | How Can We Effectively Use LLMs for Phishing Detection? (Ji & Kim) | 2025 | arXiv (preprint) | [arXiv 2511.09606](https://arxiv.org/abs/2511.09606) | c | 7 LLM vs PhishIntention & Phishpedia | Screenshot, logo, HTML, URL | 19.131 phishing + 243 benign | Identifikasi brand 93–95% (LLM komersial); recall@FPR tidak ada. Model DL lebih baik pada sampel benign | Tidak dilaporkan | Tidak: LLM, screenshot |
| 19 | Brand Domain Identification Features in 2025 (Mishra & Varshney) | 2025 | arXiv (preprint) | [arXiv 2503.06487](https://arxiv.org/abs/2503.06487) | c | RF / DT / SVM / MLP / XGBoost | 5 fitur BDI: CN info, domain logo, domain action form, link domain paling umum, domain cookie | 4.667 legit + 4.561 phishing | Akurasi 99,7–99,8% (RF, 3 fitur); recall/FPR/AUC tidak dilaporkan | RF 0,08 dtk | Tidak: butuh logo, sertifikat, cookie, tautan |
| 20 | PhishDebate | 2025 | IEEE BigData 2025 | [arXiv 2506.15656](https://arxiv.org/abs/2506.15656) | c | 4 agen LLM (URL, HTML, semantik, brand) + moderator + hakim | URL, HTML, teks | Dataset phishing dunia nyata | Recall 98,2%; FPR tidak dilaporkan | Banyak panggilan LLM | Tidak: LLM, HTML |
| 21 | PhreshPhish | 2025 | arXiv (preprint) | [arXiv 2507.10854](https://arxiv.org/abs/2507.10854) | d | Benchmark: Linear, FFN, GTE (kemungkinan model embedding teks), LLM | URL + HTML | Dataset besar baru, benchmark berbagai base rate (0,05%–24%) | Presisi pada recall 90% (P@R0,9) pada base rate 0,1%: GTE 0,156; LLM 0,072; FFN 0,032; Linear 0,030. FPR pada recall 90% **(turunan)**: GTE ≈0,49%, LLM ≈1,2%, FFN ≈2,8%, Linear ≈2,9%. Pada base rate penuh (24%) GTE P@R0,9 = 0,975 | Tidak dilaporkan | Sebagian: pembanding evaluasi, bukan model. Input HTML |
| 22 | Large Scale Study and Classification of VirusTotal Reports (Choo dkk.) | 2022 | arXiv (preprint) | [arXiv 2205.13155](https://arxiv.org/abs/2205.13155) | d | Klasifier tabular di atas keluaran 95 scanner VT + fitur leksikal/hosting/WHOIS | Label scanner + URL + WHOIS | 1,577 miliar URL, 2 tahun | Phishing: recall 96,91%, FPR 2,3%, akurasi 97,47% (voting mayoritas: FPR 25,43%) | Offline | Untuk pembersihan label offline: ya. Bukan untuk Worker. Butuh keluaran VT dan WHOIS lengkap |
| 23 | PhishVN | 2026 | Data in Brief (Elsevier) | [doi 10.1016/j.dib.2026.113195](https://doi.org/10.1016/j.dib.2026.113195) | d, g | LR, RF, HistGB, MLP | 21 fitur leksikal/infrastruktur | 18.997 URL inti, 53.116 total; tier label gold/silver/bronze; split temporal | ROC-AUC 0,918 (HistGB), 0,917 (LR); FPR@90% recall 0,18–0,21; FPR negatif Tranco global-sulit 50,2% | Kecil | Ya ukuran. Hanya URL |
| 24 | PhishSSL | 2025 | arXiv (preprint) | [arXiv 2510.05900](https://arxiv.org/abs/2510.05900) | d | Self-supervised contrastive + attention fitur, tanpa label | Fitur tabular siap pakai | 3 dataset publik | AUC 0,960 / 0,935; recall 0,906 / 0,876 / 0,871; FP 134 / 135 / 293 | Tidak dilaporkan | Tidak terbukti: tidak ada ukuran, fitur tabular dari HTML |
| 25 | Agentic Knowledge Distillation (SMS) | 2026 | arXiv (preprint) | [arXiv 2602.10869](https://arxiv.org/abs/2602.10869) | e | Guru LLM menyetel murid SLM (Qwen2.5-0.5B, SmolLM2-135M) lewat data sintetis | Teks SMS | SMS spam/smishing | Recall 96,25%, akurasi 94,31% (konfigurasi terbaik) | SLM 135M–500M parameter | Tidak: murid ratusan juta parameter. Tugas SMS, bukan halaman web |
| 26 | Towards a Multi-Layered Phishing Detection (Rendall dkk.) | 2020 | Sensors (MDPI) | [doi 10.3390/s20164540](https://doi.org/10.3390/s20164540) | f | Cascade 2 lapis berbasis ambang kepercayaan; MLP/SVM/NB/DT | Lapis 1: fitur domain statis; lapis 2: fitur dinamis (DNS, WHOIS, dll.) | 16.494 benign / 7.053 phishing, uji dengan rasio timpang | MLP 2 lapis: precision 75%, recall 87%, F1 81%, akurasi 86%; MLP 1 lapis semua fitur: akurasi 89%. FPR/AUC tidak dilaporkan | Model kecil; waktu tidak dilaporkan | Lapis 1: ya. Lapis 2 butuh WHOIS/DNS penuh |
| 27 | WHALE (on-device QR phishing, multi-stage) | 2026 | Sensors (MDPI) | [doi 10.3390/s26144412](https://doi.org/10.3390/s26144412) | f | Statik (model ringan) → dinamis (credential decoy) untuk skor tak pasti | 54 fitur URL + HTML + DOM; 59 fitur alur kredensial | Uji independen terpisah-sumber | Statik: recall 94,78%, precision 93,08%. Dinamis: recall 0,946, spesifisitas 0,882 (FPR ≈11,8% **(turunan)**) | Model 0,681 MB; inferensi model 0,088 ms; statik end-to-end 58,75 ms; dinamis 4,17 dtk | Ukuran: ya. Input (HTML/DOM) dan FPR: tidak |
| 28 | ML approaches for phishing detection (Alam dkk.) | 2026 | Frontiers in AI | [doi 10.3389/frai.2026.1875321](https://doi.org/10.3389/frai.2026.1875321) | f | LightGBM → probabilitas out-of-fold → CNN-BiLSTM (stacking) | 87 fitur: leksikal URL, HTML, reputasi eksternal | 11.430 instance seimbang | LightGBM AUC 0,9943, F1 0,9699; CNN-BiLSTM recall 0,9703 | Tidak dilaporkan | Tidak: reputasi eksternal (indeks Google, page rank, traffic), HTML |
| 29 | Explainable AI for phishing URL detection: stacking (Khan dkk.) | 2026 | Frontiers in AI | [doi 10.3389/frai.2026.1854934](https://doi.org/10.3389/frai.2026.1854934) | f | Stacking XGBoost + CatBoost + Extra Trees + RF, meta-learner LR | 41 → 24 fitur struktural/leksikal URL | 247.950 URL | AUC 0,9947, F1 96,74, Brier 0,0246 | Tidak dilaporkan | Ya secara bentuk (fitur URL). Ukuran empat model tree tidak dilaporkan |

Total: 29 paper di tabel utama. Per keluarga (baris bisa masuk lebih dari satu keluarga): a = 7 (#1–7), b = 5 (#8–12), c = 8 (#13–20), d = 4 (#21–24, ditambah tabel 3), e = 1 (#25, ditambah 3 di tabel 3), f = 6 (#5, #12, #26–29, ditambah PhishIntel di tabel 3), g = 4 (#6, #7, #15, #23).

### 3. Dicatat, tetapi angkanya bukan AUC/recall@FPR atau bukan data phishing

Dicatat karena relevan ke keluarga d/e/f. Alasan angka tidak sejajar dengan tabel utama ada di kolom terakhir.

| Judul | Tahun | Venue | Link | Kel. | Angka yang ada | Catatan |
|---|---|---|---|---|---|---|
| Learning Robust Representations for Malicious Content Detection (UCF, PU) | 2025 | arXiv | [arXiv 2512.08969](https://arxiv.org/abs/2512.08969) | d | AUC terbaik 0,729 (Gradient Boosting); 1.000 positif + 14.000 tak berlabel | **Data sintetis buatan LLM**, bukan halaman phishing. Tidak mendukung klaim PU untuk phishing |
| A Novel Perspective for PU Learning via Noisy Labels (Tanaka dkk.) | 2021 | arXiv | [arXiv 2103.04685](https://arxiv.org/abs/2103.04685) | d | Hanya benchmark gambar | Metode umum; tanpa data phishing |
| Training Classifiers Universally Robust to All Label Noise Levels (Xu dkk., PU + distillation) | 2021 | IJCNN 2021 | [arXiv 2105.13892](https://arxiv.org/abs/2105.13892) | d, e | Hanya CIFAR-10 dan Clothing1M (+2,94% akurasi di Clothing1M) | Metode umum; tanpa data phishing. Kode: github.com/Xu-Jingyi/PUDistill |
| Deep Learning Frameworks for Handling Imbalance in DGA, Email, URL (cost-sensitive) | 2020 | arXiv | [arXiv 2004.04812](https://arxiv.org/abs/2004.04812) | d | Angka tidak saya ekstrak; abstrak: cost-sensitive selalu lebih baik dari cost-insensitive | Perlu dibaca jika keluarga d dilanjutkan |
| Life-long phishing attack detection using continual learning | 2023 | Scientific Reports | [doi 10.1038/s41598-023-37552-9](https://doi.org/10.1038/s41598-023-37552-9) | d | Penurunan akurasi 2,45% (continual learning) vs 20,65% (model biasa) dalam 3 tahun | Mengukur drift, bukan recall@FPR. Fitur embedding HTML |
| Web Content Filtering through knowledge distillation of LLMs (Vörös dkk.) | 2023 | arXiv | [arXiv 2305.05027](https://arxiv.org/abs/2305.05027) | e | Murid 175× lebih sedikit parameter dari guru; akurasi +9% vs SOTA | Tugas 30 kategori web dari URL, bukan phishing. Bukti paling dekat untuk distillation berbasis URL |
| Lightweight Defense against Phishing Emails, Distilled Attention-Augmented BiLSTM | 2026 | arXiv | [arXiv 2602.22250](https://arxiv.org/abs/2602.22250) | e | Selisih weighted-F1 1–2,5 poin dari baseline transformer; 4,5 juta parameter; 95–99% lebih kecil | Email, bukan halaman web. 4,5 juta parameter ≈ 18 MB FP32 / ≈ 4,5 MB int8 **(turunan)** |
| PhishIntel (fast-slow, reference-based) | 2024 | WWW 2025 (Demo) | [arXiv 2412.09057](https://arxiv.org/abs/2412.09057) | f | Tidak ada angka akurasi di abstrak | Desain: cache + blacklist cepat, RBPD lambat |
| ClaimMirage: self-claims in domain names change LLM judgments | 2026 | arXiv | [arXiv 2609.29130](https://arxiv.org/abs/2609.29130) | c, e | Kata penyangkal risiko di nama domain menurunkan alert 45,3 poin persentase (satu setting); kata dukungan menaikkan 65,6 poin | Kerentanan penilai berbasis LLM terhadap klaim di nama domain |
| Small Language Models for Phishing Website Detection | 2025 | arXiv | [arXiv 2511.15434](https://arxiv.org/abs/2511.15434) | b, e | 15 SLM, 1–70 miliar parameter, HTML mentah; SLM di bawah LLM propietari | Tidak ada angka di abstrak |

### 4. Ringkasan per keluarga

#### a. Model URL / leksikal
- **Kelebihan:** input sama persis dengan batas (hanya URL). Model klasik kecil sangat murah (RF 12 fitur; MLP 16 fitur 1,2 ms/URL). Transformer URL terbukti kuat di FPR sangat rendah (URLTran TPR 86,8% pada FPR 0,01%).
- **Kelemahan:** angka di dataset seimbang terlalu optimis. PMANet pada rasio 43:1 turun ke recall 0,58 dengan AUC 0,95. PhishVN mencatat FPR 50,2% pada negatif populer asing (Tranco global), dan PhreshPhish mengukur dataset publik populer sebagian besar tidak valid. URL saja tidak melihat niat meminta kredensial.
- **Cocok batas?** Model klasik/MLP/n-gram: ya. Transformer (URLTran, PMANet, TinyBERT): tidak terbukti, ukuran dan latency CPU tidak dilaporkan.

#### b. Model isi teks halaman (termasuk neural kecil/terkuantisasi)
- **Kelebihan:** teks menambah sinyal yang tidak ada di URL; Aljofey mencapai FPR 1,39–2,09% dengan fitur teks + URL.
- **Kelemahan:** hampir semua paper memakai HTML mentah atau fitur hyperlink, di luar batas input. Tidak ada paper yang saya temukan menguji hanya judul + teks terlihat + daftar field form. Model neural di keluarga ini besar: MobileBERT sudah 74 MB memori; RoBERTa/CANINE lebih besar. Tidak ada bukti untuk bahasa Indonesia.
- **Cocok batas?** Fitur dan data: tidak. Model: tidak (neural), ya (XGBoost + TF-IDF) jika fitur diganti ke teks terlihat. Itu celah, bukan hasil terukur.

#### c. Berbasis referensi brand (brand klaim vs domain asli, niat minta kredensial)
- **Kelebihan:** precision tinggi (97–99%). Logika inti (brand terdeteksi, klasifikasi minta-kredensial, bandingkan domain dengan daftar domain sah) bisa dibuat deterministik. KnowPhish menunjukkan ekstraksi brand dari teks mengangkat recall pada halaman tanpa logo (recall 69,96% tanpa ekstraktor teks, 86,90% dengan).
- **Kelemahan:** pipeline asli butuh screenshot atau LLM (1,6–8 dtk). Cakupan brand jadi masalah (Phishpedia 181 brand; KnowPhish ±20k). Recall puncak sekitar 87–90% di paper klasik. ClaimMirage menunjukkan LLM bisa dibujuk klaim di nama domain.
- **Cocok batas?** Pipeline utuh: tidak. Komponen teks + knowledge base brand + cek domain: sesuai input, tetapi belum ada paper yang mengukurnya tanpa LLM/screenshot.

#### d. Label kotor dan data timpang (PU, cost-sensitive, pembersihan label)
- **Kelebihan:** ada bukti kuantitatif masalah label. PhreshPhish: sampel tidak valid 49,1% (dataset Aljofey), 28,5% (Crawling2024), 0,52% (PhreshPhish). Choo dkk.: voting mayoritas scanner VT punya FPR 25,43% vs 2,3% dengan klasifier yang dilatih. PhishVN: hanya sekitar seperlima domain blacklist Vietnam yang masih tampak menyajikan phishing saat diaudit, dan memberi tier kepercayaan label.
- **Kelemahan:** tidak ada paper PU/noisy-label khusus phishing dengan data nyata yang saya temukan. Satu-satunya paper PU berlabel "malicious content" (UCF) memakai data sintetis. Metode PU/noisy umum belum diuji pada phishing.
- **Cocok batas?** Sebagai teknik pelatihan offline: tidak terikat batas Worker. Bukti efeknya pada phishing: tipis.

#### e. Distillation dari LLM/model besar ke model kecil
- **Kelebihan:** ada pola jalan yang berhasil di domain dekat: SMS (recall 96,25% dengan murid 135M–500M parameter), kategori web dari URL (murid 175× lebih kecil), email (BiLSTM 4,5 juta parameter, selisih F1 1–2,5 poin).
- **Kelemahan:** tidak ada paper distillation untuk halaman phishing berbasis URL + teks. Murid yang dilaporkan masih belasan MB sampai ratusan juta parameter. Label guru LLM rentan klaim di nama domain (ClaimMirage).
- **Cocok batas?** Murid ≤ 3–10 MB belum ditunjukkan siapa pun di domain ini.

#### f. Ensemble / stacking / cascade
- **Kelebihan:** cascade menghemat biaya dengan kehilangan kecil (Rendall: 3–5% F1/akurasi untuk memindahkan fitur mahal ke lapis 2). WHALE: model statik 0,681 MB dan 0,088 ms. Stacking tree pada fitur URL mencapai AUC 0,9947.
- **Kelemahan:** FPR jarang dilaporkan di keluarga ini (hanya WHALE yang bisa diturunkan: ≈11,8% di tahap dinamis). Hasil stacking di dataset seimbang; kenaikan dari stacking kecil dan spesifik dataset. Lapis 2 sering butuh WHOIS/DNS/DOM.
- **Cocok batas?** Pola cascade berbasis ambang kepercayaan: ya secara arsitektur. Lapis dengan fitur dinamis/HTML: tidak.

#### g. Konteks Indonesia / Asia Tenggara
- **Kelebihan:** PhishVN (Vietnam) adalah dataset regional paling dekat: split temporal, tier kepercayaan label, label skenario peniruan (bank, pemerintah, pajak, e-commerce, telekomunikasi). KnowPhish punya studi lapangan Singapura (precision 97,42%).
- **Kelemahan:** paper Indonesia yang saya temukan (Mahmud & Wirawan 2024; Krisanti & Umam 2026) memakai ML klasik atau TinyBERT pada fitur URL, tanpa AUC/FPR, dan dataset tidak jelas khusus Indonesia (Krisanti memakai 49.750 URL multi-kelas generik). Tidak ada paper berbahasa Indonesia untuk isi halaman scam Indonesia yang terverifikasi. Data PANDI (34.622 phishing dalam 5 tahun) hanya muncul sebagai motivasi.
- **Cocok batas?** Model-modelnya kecil, tetapi bukti akurasi di konteks Indonesia lemah.

### 5. Kode GitHub dan diskusi praktisi

- `gh search repos`: hasil bermanfaat sedikit.
  - [lindsey98/Phishpedia](https://github.com/lindsey98/Phishpedia): 361★, Python, diperbarui 2026-11-14. Model visual PyTorch. Tidak ada jalur JS.
  - [imethanlee/KnowPhish](https://github.com/imethanlee/KnowPhish): 18★, repositori resmi USENIX 2024. Python + LLM.
  - PhishLang dirilis sebagai ekstensi Chromium (menurut paper). Repo tidak saya verifikasi.
  - Pencarian `phishing detection url`, `scam website detection`: repo 0–2★, tugas kuliah/demo. Tidak ada repo dengan ukuran model terukur dan jalur JS yang saya temukan.
  - Pencarian `onnx`, `tfjs`, `wasm`, `indonesia`: tanpa hasil.
- Exa di Reach sempat menampilkan crate Rust [phishnano](https://docs.rs/phishnano/latest/phishnano/) dan model Hugging Face `saidutta69/PhishScout-v2`. Isinya belum saya baca, jadi ukuran dan kemampuan JS belum diketahui.
- Dataset: [PhreshPhish di Hugging Face](https://huggingface.co/datasets/phreshphish/phreshphish) (benchmark dengan berbagai base rate). Dataset Kaggle yang sering dipakai (mis. 11.430 URL seimbang 50/50, PhiUSIIL) berupa data seimbang; PhreshPhish menilai base rate dataset publik pada umumnya tidak realistis.
- Reddit dan Kaggle: ditemukan, tetapi isinya tidak terbaca. Contoh ditemukan: [r/MachineLearning, Random Forest + fitur buatan tangan](https://www.reddit.com/r/MachineLearning/comments/1nc1mxq/project_phishing_url_detection_with_random/) (≈92% akurasi menurut cuplikan). Firecrawl tidak mendukung scrape Reddit dan channel Reddit di agent-reach butuh login yang belum saya lakukan. Tidak ada diskusi r/netsec yang terbaca.

### 6. Catatan kelengkapan (jujur)

- Selesai: ≥15 paper (29), ≥4 keluarga (7 keluarga, tiap keluarga ≥2 paper), paper yang tidak lolos tetap dicatat dengan alasan.
- Tidak semua baris punya angka recall@FPR atau AUC. Sepuluh baris di tabel 3 punya angka metrik lain atau bukan data phishing, dipisah untuk itu. Di tabel utama, baris tanpa FPR (mis. #2, #8–#12, #16, #20, #25) hanya punya recall atau akurasi; kolom diisi apa adanya.
- Venue: yang terverifikasi di paper: USENIX Security 2021/2022/2024, AAAI 2025, IJCNN 2020, ESWA 2024, WWW 2025 (demo), eCrime 2024, IEEE BigData 2025, Sci Rep, Sensors, Frontiers in AI, Data in Brief, SISTEMASI. Banyak sisanya preprint arXiv. NDSS, ACM CCS, IEEE S&P, WWW (non-demo), ACL belum menghasilkan paper terverifikasi. IEEE Access dan Elsevier baru muncul sebagai sitasi (Yang 2019 IEEE Access; Alsariera 2020 IEEE Access) dan belum dibaca.
- Angka dari abstrak/ekstraksi halaman, bukan dari verifikasi ulang tabel asli, kecuali yang saya kutip tabel langsung (URLTran, PMANet, PhreshPhish, PhishVN, KnowPhish, PhishLang, Choo, PhishSSL, Rendall).
- Dua paper Indonesia lain ditemukan di pencarian (Fauzan 2025, MALCOM; Suwarno 2024, Budi Luhur) dan belum dibaca.

### 7. Daftar sumber

Paper (urutan sesuai tabel):
[URLTran](https://arxiv.org/abs/2106.05256) · [Butnaru 2021](https://www.mdpi.com/1999-5903/13/6/154) · [PMANet](https://arxiv.org/abs/2311.12372) · [Hybrid MLP 2026](https://arxiv.org/abs/2606.00889) · [CharCNN+LightGBM](https://arxiv.org/abs/2512.16717) · [Krisanti & Umam 2026](https://doi.org/10.32520/stmsi.v15i5.6345) · [Mahmud & Wirawan 2024](https://sistemasi.ftik.unisi.ac.id/index.php/stmsi/article/view/3456) · [Aljofey 2022](https://doi.org/10.1038/s41598-022-10841-5) · [HTMLPhish](https://arxiv.org/abs/1909.01135) · [WebPhish](https://arxiv.org/abs/2011.04412) · [MultiText-LP](https://arxiv.org/abs/2401.04820) · [PhishLang](https://arxiv.org/abs/2408.05667) · [Phishpedia](https://www.usenix.org/conference/usenixsecurity21/presentation/lin) · [PhishIntention](https://www.usenix.org/conference/usenixsecurity22/presentation/liu-ruofan) · [KnowPhish](https://arxiv.org/abs/2403.02253) · [ChatPhishDetector](https://arxiv.org/abs/2306.05816) · [PhishAgent](https://arxiv.org/abs/2408.10738) · [Ji & Kim 2025](https://arxiv.org/abs/2511.09606) · [BDI 2025](https://arxiv.org/abs/2503.06487) · [PhishDebate](https://arxiv.org/abs/2506.15656) · [PhreshPhish](https://arxiv.org/abs/2507.10854) · [Choo 2022](https://arxiv.org/abs/2205.13155) · [PhishVN](https://doi.org/10.1016/j.dib.2026.113195) · [PhishSSL](https://arxiv.org/abs/2510.05900) · [Agentic KD](https://arxiv.org/abs/2602.10869) · [Rendall 2020](https://doi.org/10.3390/s20164540) · [WHALE](https://doi.org/10.3390/s26144412) · [Alam 2026](https://doi.org/10.3389/frai.2026.1875321) · [Khan 2026](https://doi.org/10.3389/frai.2026.1854934)

Tabel 3: [UCF](https://arxiv.org/abs/2512.08969) · [Tanaka](https://arxiv.org/abs/2103.04685) · [Xu](https://arxiv.org/abs/2105.13892) · [Simran](https://arxiv.org/abs/2004.04812) · [Continual learning](https://doi.org/10.1038/s41598-023-37552-9) · [Vörös](https://arxiv.org/abs/2305.05027) · [BiLSTM email](https://arxiv.org/abs/2602.22250) · [PhishIntel](https://arxiv.org/abs/2412.09057) · [ClaimMirage](https://arxiv.org/abs/2609.29130) · [SLM phishing](https://arxiv.org/abs/2511.15434)

Alat: [Agent-Reach](https://github.com/Panniantong/Agent-Reach) v1.6.1 (web/Exa, github), indeks paper Firecrawl, `gh search repos`, API arXiv (komentar/jurnal), scrape halaman penerbit.

---

## Tahap 2 — Pemetaan ke model kami, shortlist, desain eksperimen

Tanggal: 2026-11-18. Hanya riset: tidak ada training, tidak ada kode diubah, tidak ada commit.
Angka paper di Tahap 1 **tidak sebanding langsung** dengan angka kami: dataset, input, dan base rate berbeda. Angka paper dipakai sebagai petunjuk arah, bukan sebagai target.

### 2.0 Model kami, diverifikasi dari kode

Sumber: `train2.py`, `train3.py`, `eval_v3.py` (lab) dan `Final-CH7-l3model/ai/src/layer3/model/impersonation.js` (port JS).

| Komponen | Isi sebenarnya |
|---|---|
| Judge kata | Judul + 6.000 karakter teks → TF-IDF kata 1–2 gram + `char_wb` 3–5 (hash FNV di JS) → Logistic Regression (`class_weight=balanced`) |
| Judge alamat | Host + path (120 karakter) → TF-IDF `char` 2–4 → Logistic Regression |
| Fakta (23 fitur) | Jumlah field/form, ada field password, form dikirim ke situs lain, brand di judul/teks/host/logo luar, TLD murah, shared host, bentuk host (panjang, angka, tanda hubung, subdomain, IP, punycode), jumlah kata kunci URL |
| Sinyal aturan lama (9) + bendera Indonesia | `asks_password`, `asks_otp`, `asks_pin`, `asks_ktp`, `asks_cvv`, `asks_card`, `asks_selfie_ktp`, `urgent_language`, `brand_logo_offsite` |
| Combiner | 2 × HistGradientBoosting (300 pohon; satu dengan judge alamat, satu tanpa), skor = rata-rata |
| Tier | safe / gate / warn / block; cut-off dari FP legit dev 15% / 2% / 0,5%, per grup bahasa (Indonesia, lain) |
| Aturan tambahan | host resmi + Tranco top 1.000 = safe; saringan klaim v3g; umur domain < 30 hari minimal warn; brand-in-host; kata umpan Indonesia di host; brand-in-host + minta login = block |
| Pembersihan label | Buang scam "parkir/expired/cek bot" (regex), buang legit judi/porn, buang halaman latih yang skor OOF-nya berlawanan dengan label |
| Cost-sensitive | `class_weight=balanced` + cut-off dari target FP |

Temuan dari kode yang relevan untuk pemetaan:
- `brands.json` (dipakai juga oleh model) berisi **27 brand, 57 alias, 4,4 KB (1,2 KB gzip)**, dan tidak ada Telkomsel. Lab menambal sendiri dengan `EXTRA_BRANDS` (roblox, garena, xfinity, pinterest) setelah cek mata, dan komentar `eval_v3.py` mencatat kata umpan "klaim" dan "pemenang" dipertahankan karena membuangnya menghilangkan 6 scam hadiah Indonesia di feed segar (M-KIOS, Telkomsel, cek tunai).
- Teks field form **tidak** dipakai sebagai fitur sendiri. Model hanya melihat jumlah field, ada password atau tidak, dan sinyal `asks_*` dari aturan lama. Baris data (`rows.jsonl` v7 dan fresh) hanya menyimpan hitungan form/field, bukan nama atau label field. **Koreksi (diagnostik 2.6):** kolom `html` di data latih Alief (`pages.jsonl`) bukan HTML mentah, melainkan ringkasan fitur (`links`, `externalLinkShare`, `formActionOffsite`, `apkLink`, `chatLink`, `iframes`, `hiddenInputs`, `scripts`) tanpa teks field. Teks field hanya ada di snapshot v7 (`sample-input.jsonl`) dan feed segar (`fresh/.hasil/pages.jsonl`).
- Data model di Worker: `impersonation-data.js` = **3,05 MB gzip** dari bundle Worker 3,7 MB. Pemangkasan terbukti tidak bisa (469 tier berubah dari 4.283 halaman). Jadi tiap kandidat yang menambah ukuran harus mengganti sesuatu.
- Embedding semantik (bge-m3) pernah dipakai di model Alief dan dibuang dari model ini. Menurut `HASIL-AKHIR-tanpa-LLM.md`, model ringan ini lebih baik dari model Alief di semua data uji. Itu bukti internal **melawan** kandidat embedding.

### 2.1 Baseline

| Ukuran | Nilai | Sumber |
|---|---|---|
| Scam segar tertangkap | 66,5% → 76,3% (+brand-in-host) → 87,7% (+kata umpan di host, kini di worktree) | Prompt 2, `eval_v3.py` |
| Salah tanda legit Kaggle | 0,25% (44 dari 17.410) | `impersonation.js` komentar |
| AUC split uji lama / sampel v5 (6.623 halaman) | 0,988 / 0,690 | Prompt 2 |
| Bundle Worker | 3,7 MB gzip (batas Free 3 MB) | `HANDOVER-l3model.md` |
| Ditolak | Latih ulang `smallbiz`: scam tertangkap turun ke 49% | `HANDOVER-l3model.md` |

Set evaluasi yang sudah ada (ukuran dari `HASIL-AKHIR-tanpa-LLM.md`): scam segar belum pernah dilihat 856 (140 domain sendiri, 716 hosting gratis); legit Kaggle 1.500 (1 halaman per situs) dan 17.410 unseen; legit Indonesia 487; kalibrasi Indonesia 429 halaman; link aman manual 15; cek mata 50; Kaggle `half B` (tidak pernah dilatih) lewat `eval_v3.py --kaggle-half B`.

Batasan baseline yang sudah dicatat tim: feed segar berasal dari sumber yang sama dengan data latih Alief, jadi recall untuk kit phishing baru bisa lebih rendah; data legit condong ke situs besar.

### 2.2 Pemetaan semua kandidat Tahap 1

Label: **sudah punya** · **menutup** (menutup kelemahan kami) · **tidak relevan**.

| # | Kandidat | Label | Alasan satu kalimat |
|---|---|---|---|
| 1 | URLTran | tidak relevan | Transformer; latency CPU dan ukuran tidak terbukti, sementara peran itu sudah diisi judge alamat. |
| 2 | Butnaru (RF 12 fitur URL) | sudah punya | Fitur leksikal URL sudah ada di 23 fitur + judge alamat + HistGB. |
| 3 | PMANet | tidak relevan | Transformer 12 layer. |
| 4 | Hybrid MLP 16 fitur | sudah punya | 16 fitur struktural URL sudah termasuk di fitur kami. |
| 5 | CharCNN + LightGBM | sudah punya | Model karakter + GBM = judge alamat + combiner HistGB; CNN tidak lolos ukuran. |
| 6 | TinyBERT (Krisanti) | tidak relevan | Transformer, ukuran tidak ada. |
| 7 | Mahmud (RF, DT, KNN) | sudah punya | Model klasik fitur URL, sudah kami lampaui secara konsep. |
| 8 | Aljofey (TF-IDF + URL + XGBoost) | sudah punya | TF-IDF kata/karakter + URL + GBM sudah ada; fitur hyperlink tidak ada di input kami. |
| 9 | HTMLPhish | tidak relevan | Butuh HTML mentah. |
| 10 | WebPhish | tidak relevan | Butuh HTML mentah. |
| 11 | MultiText-LP | tidak relevan | Dua transformer besar; ide "judul dipisah dari isi" kecil dan dicatat di C4. |
| 12 | PhishLang | tidak relevan | MobileBERT 74 MB dan HTML. |
| 13 | Phishpedia | tidak relevan | Visual; ide daftar referensi brand ditangani di #15. |
| 14 | PhishIntention | tidak relevan | Visual; konsep "halaman minta kredensial" sudah ada lewat field password dan `asks_*`. |
| 15 | KnowPhish | **menutup** | Basis brand ±20 ribu dengan alias dan domain sah lawan 27 brand kami; pencocokan alias bisa deterministik tanpa LLM. |
| 16 | ChatPhishDetector | tidak relevan | LLM per halaman tidak jalan di Worker; sebagai guru offline lihat "ditunda". |
| 17 | PhishAgent | tidak relevan | MLLM dan logo. |
| 18 | Ji & Kim | tidak relevan | LLM dan screenshot. |
| 19 | Brand Domain Identification | sudah punya | `formActionOffsite` dan `brandOffsite` sudah memeriksa kecocokan brand ↔ domain; logo/cookie tidak tersedia. |
| 20 | PhishDebate | tidak relevan | Banyak panggilan LLM. |
| 21 | PhreshPhish | **menutup** | Protokol base rate realistis + data bersih (0,52% tidak valid); satu-satunya paper dengan angka FPR pada base rate rendah (embedding GTE jauh di atas Linear). |
| 22 | Choo (VirusTotal) | **menutup** | Pembersihan label dari banyak sinyal (FPR 2,3% vs 25,43% voting mayoritas); kelemahan label basi kami nyata, tetapi butuh akses VirusTotal. |
| 23 | PhishVN | **menutup** | Tier kepercayaan label, split temporal, dan negatif sulit; mengisi celah protokol uji kami. |
| 24 | PhishSSL | tidak relevan | Fitur tabular dari HTML; AUC di bawah model supervised. |
| 25 | Agentic KD (SMS) | tidak relevan | Murid 135M–500M parameter; ide guru LLM offline di "ditunda". |
| 26 | Rendall (cascade) | sudah punya | Tier gate/warn/block + gate dikirim ke layer 4 adalah cascade berbasis kepercayaan. |
| 27 | WHALE | sudah punya | Pola "skor tak pasti diteruskan ke tahap mahal" = gate → layer 4; tahap DOM/dinamis tidak ada. |
| 28 | Alam (LightGBM → CNN-BiLSTM) | sudah punya | Stacking OOF LR → HistGB sudah ada; fitur reputasi eksternal tidak tersedia. |
| 29 | Khan (stacking 4 model tree) | sudah punya | Stacking dengan meta-learner sudah ada. |
| 30 | UCF (PU) | tidak relevan | Diuji pada data sintetis. |
| 31 | Tanaka (PU via noisy labels) | tidak relevan | Noise utama kami ada di label positif (scam berubah isi), bukan scam tersembunyi di set tak berlabel; pembuangan OOF sudah ada. |
| 32 | Xu (PU + distillation) | **menutup** | Guru dilatih pada subset bersih, murid pada semua data; cocok sebagai varian C2, tetapi bukti hanya data gambar. |
| 33 | Simran (cost-sensitive) | sudah punya | `class_weight=balanced` + cut-off dari target FP. |
| 34 | Continual learning | tidak relevan | Fitur embedding HTML; isu drift ditangani lewat protokol temporal (2.4). |
| 35 | Vörös (KD URL) | tidak relevan | Tugas kategori web, bukan phishing. |
| 36 | BiLSTM email | tidak relevan | Email dan 4,5 juta parameter. |
| 37 | PhishIntel | sudah punya | Allowlist/cache cepat + tahap lambat = Tranco top 1.000 + gate → layer 4. |
| 38 | ClaimMirage | tidak relevan | Untuk layer 3 tidak ada LLM; relevan untuk prompt layer 4 (beri brand + domain resmi sebagai pembanding). |
| 39 | SLM phishing | tidak relevan | HTML mentah, model miliaran parameter. |

Hitungan: 12 sudah punya · 5 menutup (#15, #21, #22, #23, #32) · 22 tidak relevan = 39 baris (semua 29 baris tabel utama dan 10 baris tabel 3).

### 2.3 Shortlist (4 kandidat, urut dari paling mungkin menaikkan recall scam segar)

Urutan memakai bukti internal, bukan hanya angka paper.

#### C1. Basis brand besar + alias + domain sah (turunan KnowPhish #15, pembanding #13)
- **Kelemahan yang ditutup:** scam yang lolos karena brand tidak dikenal. Bukti internal: 27 brand, tanpa Telkomsel; `EXTRA_BRANDS` dan aturan klaim ditambal tangan. Bukti paper: pada studi lapangan Singapura, Phishpedia dengan daftar bawaan menghasilkan 54 laporan dengan 17 benar, dengan basis KnowPhish 353 laporan dengan 333 benar (presisi 31,48% → 94,33%).
- **Cara gabung:** **ganti** `brands.json` untuk layer 3 dengan salinan sendiri (alias + domain sah). Fakta `brandsInTitle/Text/InHost/Offsite`, `claim`, `brandHost`, dan `loginBlock` otomatis ikut. Latih ulang hanya combiner (judge tidak berubah). Menurut catatan sesi sebelumnya folder `detector/` tidak boleh diubah, jadi file brand layer 3 harus terpisah.
- **Risiko FP:** alias umum (kata biasa sebagai nama brand), merek lokal yang sah di domain lain, distributor resmi. Mitigasi yang diuji: panjang alias minimum, wajib dua sinyal (judul + host, atau teks + form), daftar pengecualian domain terdaftar.
- **Perkiraan ukuran:** 1,2 KB gzip untuk 27 brand ≈ 44 byte per brand. Linear: 500 brand ≈ 22 KB, 2.000 ≈ 88 KB, 20.000 ≈ 0,9 MB gzip (perkiraan kasar; domain tidak sekompres alias). Subset 500–2.000 brand tidak mengubah status 3,7 MB secara berarti.
- **Lolos batas Worker:** ya, pencocokan string murni; waktu per halaman naik linear terhadap jumlah brand (perlu indeks, bukan regex per brand).
- **Catatan:** lisensi dan isi basis KnowPhish (repo publik) belum saya periksa. Diagnostik murah dulu: berapa persen scam segar yang lolos menyebut brand di luar 27 brand.

#### C2. Pembobotan dan pembersihan label berlapis (turunan Choo #22, PhishVN #23, PhreshPhish #21, Xu #32)
- **Kelemahan yang ditutup:** label scam basi (Kaggle: 0 dari 30 masih scam) dan generalisasi lemah (AUC 0,988 → 0,690 di v5). Bukti paper: PhreshPhish 49,1% sampel dataset populer tidak valid; Choo FPR 2,3% vs 25,43% voting; PhishVN tier gold/silver/bronze.
- **Cara gabung:** tidak menambah komponen. Ganti pembuangan keras (regex + OOF) dengan **bobot sampel** dari kesepakatan sinyal (skor OOF judge, aturan lama, jenis sumber, cek halaman hidup). Varian guru–murid (Xu): guru dilatih pada subset terverifikasi, murid pada semua.
- **Risiko FP:** bobot salah bisa menurunkan recall. Preseden: latih ulang `smallbiz` ditolak (scam tertangkap turun ke 49%), jadi perubahan komposisi data latih harus diukur ketat.
- **Ukuran:** 0 (offline). Algoritma LR dan HistGB mendukung `sample_weight`.
- **Lolos batas Worker:** tidak terpengaruh.
- **Catatan:** ekstensi gaya Choo butuh API VirusTotal (biaya/izin); tidak dimasukkan kecuali Anda setuju.

#### C3. Judge teks field form (turunan PhishIntention #14, ablasi CRP di KnowPhish #15)
- **Kelemahan yang ditutup:** input resmi menyertakan nama, tipe, dan label field, tetapi model tidak memakainya (hanya hitungan dan `asks_*`). Bukti paper: tanpa klasifier CRP, presisi studi lapangan KnowPhish turun dari 97,42% ke 85,11%. CRP lebih banyak menurunkan FP daripada menaikkan recall, tetapi FP yang lebih rendah memungkinkan cut-off lebih rendah pada FP tetap.
- **Cara gabung:** **tambah judge** ketiga (TF-IDF kata dari nama + label + placeholder + tipe, LR kecil), skornya masuk ke kedua combiner.
- **Risiko FP:** halaman login sah di hosting gratis (kasus link aman manual 5 dari 15). Label latih lemah jika diturunkan dari `asks_*` (melingkar); perlu label CRP independen.
- **Perkiraan ukuran:** ≤ 5.000 term × (hash 4 B + koefisien 2 B) ≈ 30 KB mentah (perkiraan).
- **Lolos batas Worker:** ya.
- **Catatan (dikoreksi setelah diagnostik 2.6):** `rows.jsonl` tidak menyimpan teks field, dan data latih Alief juga tidak (kolom `html` hanya ringkasan fitur). Teks field ada di snapshot Kaggle v7 dan feed segar, tetapi scam di Kaggle berlabel basi dan feed segar adalah set evaluasi. Melatih C3 butuh pengambilan ulang halaman scam latih atau feed baru.

#### C4. Judge embedding statis kecil (turunan PhreshPhish #21; eksploratif)
- **Kelemahan yang ditutup:** generalisasi ke kit baru. Bukti paper: pada base rate 0,1%, GTE (kemungkinan model embedding) memberi presisi 0,156 pada recall 90% lawan 0,030 untuk Linear (FPR turunan ≈0,49% vs ≈2,9%). Linear/FFN di sana memakai n-gram karakter dan XPath, kerabat TF-IDF kami.
- **Bukti yang melawan:** bge-m3 pernah dipakai di model Alief dan model ringan kami justru lebih baik; PhreshPhish memakai HTML penuh dan data yang belum tentu berbahasa Indonesia.
- **Cara gabung:** **tambah judge** keempat: tabel embedding token statis hasil distilasi dari model besar (offline), rata-rata vektor + LR. Jika dipertahankan, **ganti** tabel `char_wb` (kandidat tabel terbesar; belum diukur) agar bundle tidak membesar.
- **Risiko FP:** vokabulari multibahasa lemah untuk istilah lokal; skor rata-rata bisa mengaburkan sinyal brand.
- **Perkiraan ukuran:** V × d byte untuk int8: 16.000 × 32 ≈ 0,5 MB; 30.000 × 64 ≈ 1,9 MB (perkiraan, int8 hampir tidak terkompres).
- **Lolos batas Worker:** ya secara hitungan (penjumlahan vektor, < 1 ms), tetapi ukuran harus ditukar.

#### Ditunda (butuh keputusan Anda)
- **Guru LLM offline** untuk menilai ulang label (turunan #16, #25, #35). Perlu mengirim teks halaman ke layanan LLM di luar; aturan handover melarang teks halaman asli disimpan di repo, dan saya tidak akan mengirimnya tanpa izin Anda. Bukti paper hanya SMS/email/kategori web. Catatan #38: pembanding brand + domain resmi di prompt mengurangi bias klaim.
- **Pemangkasan/kuantisasi data model** untuk masuk 3 MB bukan dari literatur Tahap 1; keputusan ukuran (Paid atau kuantisasi) belum diambil di `HANDOVER-l3model.md`. Biaya ukuran tiap kandidat di atas dihitung relatif terhadap 3,05 MB data model.

### 2.4 Desain eksperimen

#### Protokol bersama (semua kandidat)
- **Data dan split:** sama dengan baseline. Split per situs (`site()` bukan PSL); train/dev/test Alief tidak berubah; Kaggle v7 legit dibagi `kaggle_half` A (train/dev) dan B (tidak pernah dilatih); scam segar: 856 halaman belum pernah dilihat; legit Indonesia 429/487; link aman manual 15.
- **Metrik utama:** recall scam segar pada FP Kaggle **0,5%** dan **2%**. Cut-off dipilih pada legit dev (Kaggle half A + dev Alief) lalu dilaporkan FP aktualnya di Kaggle half B; sebagai batas atas, cut-off juga dicari langsung di half B dengan interval bootstrap per situs. Diukur pada dua level: skor model saja, dan pipeline penuh (model + v3g + umur domain + brand-in-host + kata umpan + loginBlock), supaya sebanding dengan 66,5% / 76,3% / 87,7%.
- **Metrik pendamping:** PR-AUC scam segar vs Kaggle half B; AUC pada v5 (6.623 halaman) dan test split lama; FP pada legit Indonesia (429) dan link aman manual (15).
- **Ukuran:** gzip `impersonation-data.js` dan bundle Worker (`wrangler deploy --dry-run`), diperinci per tabel (kata, `char_wb`, alamat, pohon).
- **Waktu JS:** p50 dan p95 `scoreImpersonation` per halaman dengan 500 halaman acak, di luar waktu muat pertama; waktu muat (`decode(BLOB)`) dilaporkan terpisah. Batas 50 ms CPU. Dugaan saya, Workers Free membatasi CPU jauh lebih ketat (sekitar 10 ms per request); belum saya verifikasi di dokumentasi Cloudflare, jadi dicek dulu.
- **Paritas:** `parity_js.mjs` untuk kandidat yang menambah judge atau fitur (selisih skor target 0,00000 seperti baseline).
- **Daya statistik:** dengan n = 856, simpangan baku recall di sekitar 88% ≈ 1,1 poin (CI 95% ≈ ±2,2 poin). Perbedaan di bawah ≈3 poin tidak dianggap nyata. Interval bootstrap per situs wajib.
- **Kriteria sebelum jalan:** satu kandidat dianggap menang bila selisih recall pada FP 0,5% atau 2% punya CI bootstrap yang tidak menyentuh nol, FP aktual di half B tidak lebih tinggi dari target, dan ukuran bundle mengikuti anggaran yang ditentukan. Ambang selisih minimum ditentukan Anda.
- **Protokol tambahan dari paper:** split temporal dan negatif sulit (PhishVN #23), base rate realistis dan P@R pada 0,1%/1% (PhreshPhish #21). Dilaporkan sebagai tabel kedua, tidak menggantikan metrik utama.
- **Hasil dilaporkan per set** agar kenaikan di feed segar tidak menutupi kenaikan FP di legit Indonesia.

#### C1 — basis brand besar
1. **Diagnostik (tanpa training):** dari scam segar yang tidak mencapai warn/block pada baseline, hitung berapa persen yang menyebut brand di luar `brands.json`. Ini batas atas manfaat C1.
2. Bangun salinan brand layer 3 bertahap: 27 → 100 → 500 → 2.000 brand (alias + domain sah, prioritas Indonesia/ASEAN: bank, telko, e-wallet, ecommerce, kurir, pemerintah).
3. Hitung ulang fakta brand pada semua baris (lab `build-rows`), latih ulang **combiner saja**, evaluasi dengan protokol bersama.
4. Tabel tambahan: legit yang baru terkena `brandInHost`/`brandOffsite`, per brand, untuk membuang alias berisiko; kurva recall dan FP terhadap jumlah brand; ukuran gzip tiap tahap.
5. Varian tanpa retrain: hanya aturan `brandHost` dan klaim dengan daftar baru.

#### C2 — pembobotan label
1. Variabel bobot: (a) baseline pembuangan keras (kontrol), (b) bobot dari kesepakatan sinyal, (c) bobot dari tier (verifikasi hidup/mati, sumber), (d) guru dilatih pada subset bersih dan murid pada semua (gaya Xu).
2. Latih judge dan combiner dengan `sample_weight`, split per situs yang sama.
3. Evaluasi dengan protokol bersama; tambahan: recall menurut tier label scam di data uji, supaya terlihat apakah scam berlabel "basi" tetap ditangkap atau hilang.
4. Kontrol regresi: pastikan tidak mengulang kegagalan `smallbiz` (49%); laporkan komposisi data latih sebelum dan sesudah.

#### C3 — judge teks field form
1. **Diagnostik (sudah dijalankan, lihat 2.6):** feed segar dan snapshot Kaggle v7 punya `forms[].fields[]` (nama, id, label, placeholder); data latih Alief tidak. Prasyarat baru: sumber scam latih yang punya teks field dan terpisah dari feed segar.
2. Latih LR TF-IDF kata di atas teks field; label dari `asks_*` (lemah) dan, bila memungkinkan, ±200 halaman diberi label CRP manual sebagai uji kecil.
3. Tambahkan skor sebagai kolom ke kedua combiner, latih ulang combiner, evaluasi.
4. Tabel tambahan: FP di legit login (link aman manual 15, Indonesia 429), AUC judge sendiri pada halaman dengan form saja.

#### C4 — embedding statis kecil
1. Sebelum apa pun: ukur ukuran gzip tiap tabel (kata, `char_wb`, alamat) agar tahu apa yang bisa diganti.
2. Bangun tabel embedding statis dari model besar (offline), V × d dengan int8; jalankan LR di atas rata-rata vektor. Variasi V ∈ {16k, 30k}, d ∈ {32, 64}.
3. Evaluasi tiga skema: tambah judge, ganti `char_wb`, ganti seluruh judge kata. Protokol bersama, dengan perhatian khusus pada AUC v5 (generalisasi).
4. Hentikan lebih awal bila judge baru sendirian di bawah judge kata pada AUC v5; itu mencerminkan bukti internal yang melawan.

### 2.5 Catatan dan batasan

- Tidak ada training dan tidak ada kode diubah pada Tahap 2. Pemeriksaan di bawah.
- Perkiraan ukuran dan waktu bertanda "perkiraan" adalah hitungan saya, belum diukur.
- Bukti untuk C4 bertentangan: satu paper (PhreshPhish) mendukung, hasil internal sebelumnya melawan.
- Diagnostik C1 dan C3 sudah dijalankan (2.6); tiga lainnya butuh training.
- Hal yang belum saya periksa: lisensi basis brand KnowPhish, batas CPU Workers Free.

### 2.6 Hasil diagnostik C1 dan C3 (2026-11-18, baca saja)

Cara: pipeline layer 3 yang ada (`scoreImpersonation` di worktree, tanpa mengubah apa pun) saya jalankan pada 882 baris feed segar (`fresh/.hasil`, 856 scam belum pernah dilihat + 11 scam yang situsnya pernah dilihat + 15 link aman manual), dengan umur domain dari `rdap.jsonl` dan sinyal aturan dari `baseline.signals`. Skrip dan keluaran ada di scratchpad sesi, bukan di repo. Daftar di bawah hanya angka dan nama brand; tidak ada host asli atau teks halaman di file ini.

**Baseline terreproduksi:** 749 dari 856 scam segar tertangkap warn/block = **87,5%** (catatan tim 87,6–87,7%; selisih satu–dua halaman, tidak dikejar). Link aman manual: 0 dari 15 ditandai warn/block. Sampingan: 882 halaman dinilai dalam 1,1 detik di Node (termasuk muat model pertama), rata-rata sekitar 1,3 ms per halaman; ini bukan pengukuran Worker.

#### C1 — berapa banyak scam yang lolos menyebut brand di luar 27 brand

Ada **107** scam segar yang lolos (37 `safe`, 70 `gate`). Saya baca judul, nama host (label yang dipilih pemilik), dan 110 karakter pertama teks tiap halaman. Pengelompokan di bawah adalah penilaian manual saya, **belum diverifikasi manusia**; angkanya perkiraan (≈).

| Kelompok dari 107 yang lolos | Jumlah |
|---|---|
| Menyebut brand yang tidak ada di `brands.json`: Pertamina (3 halaman "undian"), Vodafone, Atome, EasyCash, Permata (simulator ATM), Telkom (halaman tidak ditemukan), Exness, cyon (halaman login hosting), Steam, forum Bank BTN/BRI | ≈12 (≈11%) |
| Brand ada di daftar tapi tetap lolos: BPJS "dana bantuan" ×2, host mirip BCA yang isinya halaman panel hosting ×2, host mirip Google yang isinya halaman bawaan server atau kosong ×2 | ≈6 |
| Halaman kosong, rusak, atau bawaan server (teks hanya CSS tanpa judul ×12; akun ditangguhkan, peringatan PHP, ionCube, blog kosong) | ≈16 |
| Terlihat seperti situs bisnis, portofolio, SaaS, desa, atau templat login biasa tanpa brand dan tanpa umpan | ≈73 (di dalamnya ≈5 berbau umpan: CS kredit digital, pinjaman BPKB, "Verifikasi Akun", penghasil uang, sistem pajak) |

Proksi otomatis sebagai pembanding: token judul/host yang cocok dengan label domain Tranco top 20 ribu, bukan kata kamus, bukan di `brands.json`, nama platform hosting dibuang. Hasilnya 11 dari 107 yang lolos (10,3%), dan 87 dari 749 yang tertangkap (11,6%). Dari 11 itu hanya 4 yang mirip brand (Bongacams, Steam Community, Telkom, Vodafone); sisanya kata umum (sydney, online, surabaya, pajak ×2, trabajo, iheart). Proksi tidak membedakan lolos dan tertangkap, dan melewatkan brand lokal (Pertamina, Atome, EasyCash, Permata tidak ada di 20 ribu teratas), jadi bacaan manual lebih lengkap. Kedua cara sepakat pada kisaran sekitar 10%.

**Kesimpulan C1:** menambah brand paling banyak menjangkau ≈12 dari 856 scam segar, yaitu **batas atas ≈1,4 poin recall** (kurang bila beberapa dari 12 itu sebenarnya jinak, mis. simulator ATM atau halaman mati). Itu di bawah ketidakpastian pengukuran (CI 95% ≈ ±2,2 poin pada n = 856), jadi dampaknya tidak akan terlihat di set ini. Manfaat lain C1 (brand lokal untuk `brandHost`/`loginBlock` di data baru) tidak terukur di sini.

**Temuan yang lebih besar dari C1:** sekitar 90 dari 107 yang lolos (≈85%) tidak membawa sinyal peniruan apa pun di halaman. Dua kemungkinan, tidak bisa dibedakan tanpa pemeriksaan manusia: (a) label di feed segar salah atau basi (halaman kosong, bawaan server, atau situs biasa), atau (b) itu kit scam tanpa klaim di halaman. Bila (a), recall nyata di set ini mendekati ≈98% (749 dari ≈767) dan sisa 1–2% itu bukan lagi masalah brand. Ini mendukung catatan tim bahwa pemeriksaan mata baru dilakukan oleh Claude, belum oleh manusia.

#### C3 — statistik field form pada feed segar

| Kelompok | n | Ada field | Field bertipe password | Kata sensitif di nama/label field* | Kata kredensial luas** |
|---|---|---|---|---|---|
| Scam tertangkap | 749 | 405 (54%) | 50 (6,7%) | 117 (15,6%) | 198 |
| Scam lolos | 107 | 74 (69%) | 12 (11,2%) | 10 (9,3%) | 60 |
| Link aman manual | 15 | 13 (87%) | 8 | 9 | 10 |

\* otp, pin, nik, ktp, cvv, kartu, rekening, password, kata sandi, sandi. \*\* ditambah email, username, telepon, whatsapp, saldo, dan sejenisnya.

- Teks field hampir selalu ada bila ada field: 1.163 dari 1.236 field (tertangkap), 624 dari 658 (lolos). Jadi input yang dijanjikan kontrak memang tersedia.
- Token field paling sering pada yang **lolos**: email, name, honey, message, contact, optional, example. "honey" adalah kolom jebakan bot khas formulir kontak. Pada yang **tertangkap**: username, password, email, phone, verifikasi. Yaitu yang lolos kebanyakan formulir kontak biasa, bukan formulir kredensial.
- Artinya teks field kemungkinan membantu menandai halaman jinak (menurunkan FP), bukan menaikkan recall pada sisa yang lolos. Ini sesuai dengan bukti paper (CRP menjaga presisi).
- **Penghalang data:** kolom `html` di data latih Alief hanya berisi ringkasan fitur (`links`, `externalLinkShare`, `formActionOffsite`, `apkLink`, `chatLink`, `iframes`, `hiddenInputs`, `scripts`), tanpa teks field. Teks field hanya ada di snapshot Kaggle v7 (`sample-input.jsonl`; 2.291 dari 4.000 baris pertama punya field, dengan label legit dan scam basi) dan feed segar. Jadi C3 tidak bisa dilatih dari data latih yang ada tanpa mengambil ulang halaman scam latih atau memakai feed segar yang justru dipakai untuk menguji.

#### Dampak ke shortlist 2.3

- **C1:** batas atas ≈1,4 poin, jauh di bawah yang saya perkirakan di 2.3. Murah, tetapi tidak akan terlihat di set evaluasi ini.
- **C3:** terhalang data (di atas); kemungkinan manfaat di FP, bukan recall.
- **C2 dan kualitas set evaluasi** menjadi pertanyaan utama: jika ≈85% dari yang lolos memang tidak membawa sinyal peniruan, recall 87,5% pada set ini dibatasi oleh label, bukan model. Langkah paling bernilai berikutnya adalah pemeriksaan manusia atas 107 halaman itu (atau sampel ±40), karena hasilnya menentukan apakah recall perlu dinaikkan atau set segar perlu dibersihkan.
- **C4:** tidak berubah.
- Urutan di 2.3 ("paling mungkin menaikkan recall") tidak lagi berlaku apa adanya. Saya tidak mengubah isi 2.3; baca bersama bagian ini.
