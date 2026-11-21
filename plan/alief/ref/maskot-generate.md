# Maskot Shoo — resep generate pose (Tripo, 2D)

Resep ini dipakai untuk membuat pose baru si burung hantu Shoo yang **sama persis** dengan maskot asli. Dibuat 21 Nov 2026. Hasilnya ada di Figma, page High Fidelity, frame **"alief maskot"** (node `2431:12759`).

## Aturan karakter (wajib)

- **Mata** hanya dua celah putih tajam di topeng hitam. Tanpa pupil, iris, titik hitam, mata bulat, atau mata senyum melengkung. Emosi ditunjukkan lewat sudut dan lebar celah, kepala, paruh, dan sayap.
- **Badge kerah** harus logo asli **LOGO FIX** (node `227:3954`). Logo buatan AI selalu sedikit beda, jadi badge selalu **ditimpa** dengan logo asli setelah generate (langkah 4).
- Tubuh putih bulat, dua jambul hitam runcing, paruh abu gelap, jubah gradasi biru ke teal dengan pinggiran biru muda, dan kaki abu gelap pendek. Gaya render 3D lembut ala Pixar.
- Badge tidak boleh tertutup sayap. Kalau tertutup, logo tidak bisa ditimpa rapi, jadi generate ulang.

## Referensi di Figma

| Apa | Node |
|---|---|
| Maskot asli (hero) | `2084:4426` |
| Logo badge (LOGO FIX) | `227:3954`, shield saja: `227:4080` |
| Contoh pose duduk | `2296:35861` |
| Contoh pose terbang | `2296:35810` |
| Contoh dialog dengan maskot | `2296:35961` |
| Hasil semua pose | `2431:12759` ("alief maskot") |

## 1. Siapkan gambar referensi

Gabungkan maskot asli (kiri) dan logo shield (kanan) di kanvas putih 1800x1280. Owl tinggi sekitar 1180 px, logo tinggi sekitar 560 px. Export `2084:4426` dan `227:4080` dari Figma (PNG, scale 2), lalu:

```python
from PIL import Image
owl  = Image.open('owl-hero.png').convert('RGBA')
logo = Image.open('logo-shield.png').convert('RGBA')
c = Image.new('RGB', (1800, 1280), (255, 255, 255))
o = owl.resize((int(owl.width*1180/owl.height), 1180), Image.LANCZOS); c.paste(o, (40, 50), o)
l = logo.resize((int(logo.width*560/logo.height), 560), Image.LANCZOS); c.paste(l, (1180, 360), l)
c.save('owl-ref2.png')
```

## 2. Generate di Tripo Studio (Agentic Canvas)

- Node: **Upload** (isi `owl-ref2.png`) → **Generate Image**. Jangan pakai node 3D apa pun.
- Model: **GPT Image 2.5**. Dibandingkan dengan Nano Banana Pro (= Gemini 3 Pro Image) pada prompt yang sama, GPT Image 2.5 lebih tajam dan badge-nya lebih mirip logo.
- Number of images: 1. Biaya sekitar 200 kredit per gambar.
- Aspect ratio:
  - 3:4 untuk pose berdiri (hasil 1152x1536).
  - 1:1 untuk pose lebar seperti terbang, lari, duduk, atau "ini dia" (hasil 1024x1024).
  - 4:3 untuk ngintip (1536x1152).
- Ambil file asli dari tombol **Preview** di node, bukan thumbnail 600 px di node. URL asli tidak punya parameter `width`. Mengubah parameter URL yang sudah ditandatangani menghasilkan 403.
- Hati-hati: kalau node tidak terpilih, panel kontrolnya hilang dan klik ke tombol aspect ratio gagal. Pilih node dulu, dan cek prompt benar-benar terganti sebelum klik Regenerate.

### Template prompt

Ganti `{POSE}` dengan kalimat pose dari tabel di bawah.

```text
The attached image has two parts. LEFT: the Shoo owl mascot, the exact character to draw. RIGHT: the Shoo app logo (a shield with a blue-to-teal gradient inside and a white owl head with a black mask peeking in from the bottom left).

Redraw the LEFT owl in a new pose, keeping the character 100% identical: round white fluffy owl body, two pointed black ear tufts, small dark grey beak, blue-to-teal gradient cape with a light blue rim, short dark grey feet, same soft 3D Pixar-like render style, same proportions and colors.

EYES - most important: the eyes are ONLY two narrow, sharp, angular white slits cut into the black bandit mask, exactly like the left reference. NO pupils, NO irises, NO black dots, NO round eyes, NO curved smile eyes, nothing inside the slits. Show emotion only through the angle and width of the slits, the head tilt, the beak and the wings.

BADGE: the small badge on the cape collar must be a tiny copy of the RIGHT logo: a light blue shield outline, blue-to-teal gradient inside, white owl head with black mask peeking from the bottom left. Do not invent a different emblem.

New pose: {POSE}

Full body, centered, facing the viewer. Plain solid medium grey background (#808080), no floor shadow, no text, no extra objects, do not draw the logo anywhere else. Studio lighting, ultra sharp, very high detail, clean edges, highest quality.
```

### Kalimat pose yang sudah dipakai

| Pose | Rasio | `{POSE}` |
|---|---|---|
| Mikir | 3:4 | THINKING - one wing raised to the chin, head tilted slightly, mask slits angled to look upward and thoughtful, calm 'hmm, are you sure?' expression. |
| Melambai | 3:4 | WAVING HELLO - right wing raised high above the shoulder waving hello, left wing relaxed at the side, head tilted a little, friendly welcoming 'join us' mood; the mask slits are slightly narrowed and curved at the outer corners like a smile, still only white slits with nothing inside, and a small open happy beak. |
| Kaget | 3:4 | SURPRISED AND CAUTIOUS - both wings raised up near the cheeks in a startled gesture, leaning back slightly, small open beak; the mask slits are opened a bit wider and taller than usual to show surprise, still only white slits with nothing inside, a careful 'wait, are you sure?' reaction, not angry. |
| Duduk tidur | 1:1 | SITTING ASLEEP - sitting on its bottom on the floor with both short dark grey feet stretched forward, round belly, wings resting on the belly, cape draped around it on the floor, head slightly tilted down, eyes closed: the mask slits become thin closed white lines, peaceful sleepy expression, cute and cozy. |
| Duduk (bangun) | 1:1 | SITTING AWAKE, CALMLY WAITING - sitting on its bottom on the floor, relaxed, both short dark grey feet stretched forward, round belly, both wings resting softly on its lap, cape draped around it on the floor, head upright and slightly tilted, looking at the viewer, friendly patient 'nothing here yet, I'm waiting' mood; the mask slits are open and calm, still only white slits with nothing inside, small closed beak. Awake, NOT sleeping. The collar badge must be fully visible and unobstructed. (badge: `[562,481,93,0]`; dipakai untuk empty state "Belum ada aktivitas") |
| Terbang | 1:1 | FLYING - wings fully spread wide like flying toward the viewer, cape fluttering behind in the wind, feet tucked under the body, confident brave hero mood, mask slits determined. |
| Detektif | 3:4 | DETECTIVE - holding a big round magnifying glass in one wing up near the face, inspecting something closely, other wing on the hip, curious focused mood, mask slits narrowed. |
| Jempol | 3:4 | ALL SAFE - giving a confident thumbs-up with one wing toward the viewer, chest puffed out proudly, other wing on the hip, small happy open beak, reassuring 'aman!' mood. |
| Loncat senang | 3:4 | CELEBRATING - jumping up in the air with joy, both wings raised high, feet off the ground, cape flying up, happy open beak, playful energetic mood. |
| Ngintip | 4:3 | PEEKING - only the head, both wing tips and the top of the cape visible as it peeks over a straight horizontal edge at the bottom of the image, wing tips gripping the edge, curious cute mood. The bottom edge of the image cuts the owl off at the chest. |
| Nunjuk | 3:4 | POINTING - one wing stretched out to the side pointing with the wing tip at something next to it, like presenting or saying 'look here!', body turned slightly toward the pointing direction, head looking toward where it points, other wing on the hip, friendly helpful mood, small open beak. |
| Ini dia! | 1:1 | PRESENTING 'HERE!' - standing at the left side of the image, body turned three-quarters toward the right, one wing stretched out wide to the right with the wing tip open like an open palm presenting the empty space next to it, like a TV host saying 'here it is!', other wing on the hip, head turned toward the empty space, cheerful small open beak. The right half of the image is empty grey space. |
| Tap di sini | 3:4 | POINTING DOWN AT A BUTTON - standing at the top of the image, one wing stretched straight down and forward, the wing tip clearly pointing at a spot on the floor in front of its feet like pointing at a button below the character, body leaning forward, head looking down at that spot, other wing raised in an excited 'tap here!' gesture, eager helpful mood, small open beak. Leave empty grey space below the feet where it points. |
| Diam (default) | 3:4 | STANDING IDLE - neutral relaxed standing pose facing the viewer, both wings resting at the sides, calm friendly expression, the default mascot pose. |
| Pahlawan | 3:4 | HERO POSE - standing tall and proud with both wings on the hips, chest puffed out, cape flowing to one side in the wind, confident protective mood, slight smile. |
| Maaf | 3:4 | SORRY / SAD - shoulders dropped, head tilted down, both wing tips pressed together in front of the belly, the mask slits angled down at the outer corners in a sad apologetic look, small frown, 'oops, something went wrong' mood, still cute. |
| Sstt | 3:4 | SHHH, IT'S A SECRET - standing facing the viewer, the RIGHT wing raised so that one single wing tip touches the front of the beak vertically like a finger saying 'shhh', the LEFT wing hidden behind the back, a playful knowing look with one mask slit slightly narrower than the other like a wink. Calm, playful, trustworthy privacy mood. No sweat drops, no fear. The raised wing stays above the collar so the collar badge is fully visible. |
| Marah | 3:4 | ANGRY - stomping one foot, both wings clenched into fists at the sides, feathers on the head slightly ruffled, the mask slits angled sharply down toward the beak in an angry frown, open beak shouting, a tiny puff of steam above the head, cartoon-angry at scammers but still cute. |
| Cemberut | 3:4 | POUTING / SULKING - wings crossed tightly over the chest, head turned slightly away, cheeks puffed, the mask slits flattened and narrowed in a grumpy pout, beak pushed out, 'hmph!' mood, cute. |
| Nangis | 3:4 | CRYING - standing with shoulders shaking, one wing tip wiping a big cartoon tear, streams of big clear tears falling from the bottom of the mask slits, the slits curved down sadly, open wobbly beak, sad but cute. |
| Lari | 1:1 | RUNNING - running fast to the right in a dynamic side three-quarter view, legs mid-stride, wings pumping, cape streaming horizontally behind, small speed lines and dust puff behind the feet, determined mood, mask slits focused forward. |
| Takut | 3:4 | SCARED - trembling, both wings raised up beside the face with wing tips spread in fright, knees together, leaning back, feathers slightly puffed up, the mask slits small and wavy with fear, small open beak, a few cartoon sweat drops, frightened but cute. The wings must NOT cover the chest; the collar badge must be fully visible and unobstructed. |
| Cemas | 3:4 | Hasil tak sengaja dari prompt "sstt" yang pertama (owl gemetar, keringat, sayap di dada). Untuk membuat ulang, pakai pose Takut dengan kedua sayap memegang dada. |

Untuk pose baru: tulis satu kalimat dengan pola **NAMA POSE - posisi sayap, kepala, badan, bentuk celah mata, mood**. Selalu tambahkan "still only white slits with nothing inside" kalau emosinya kuat (senang, kaget, marah).

## 3. Cek hasil

1. Mata: celah putih saja, tanpa pupil. Kalau gagal, ulang.
2. Jambul, jubah, dan proporsi sama dengan referensi.
3. Badge terlihat penuh, tidak tertutup sayap.

## 4. Timpa badge dengan logo asli

Cari kotak badge di gambar resolusi penuh: crop sekitar badge, lalu ukur tepi kiri, tepi kanan, dan tepi atas bingkai badge. Isi `cx` (tengah horizontal), `top` (tepi atas), `width` (lebar bingkai + sekitar 8 px supaya bingkai lama tertutup), dan `rot` (derajat; positif = putar berlawanan jarum jam).

```python
# badge.py  —  python3 -I badge.py logo-shield.png '{"think":[635,625,118,-3]}'
# input: gpt-<pose>.png  →  output: gpt-<pose>-logo.png
import sys, json
from PIL import Image, ImageFilter
logo = Image.open(sys.argv[1]).convert('RGBA'); B = json.loads(sys.argv[2])
for k, (cx, top, w, rot) in B.items():
    im = Image.open(f'gpt-{k}.png').convert('RGBA')
    h = round(w * logo.height / logo.width)
    L = logo.resize((w, h), Image.LANCZOS).rotate(rot, resample=Image.BICUBIC, expand=True)
    x = cx - L.width // 2; y = top - (L.height - h) // 2
    sh = Image.new('RGBA', L.size, (20, 40, 90, 0))
    sh.putalpha(L.split()[3].point(lambda v: int(v * 0.45)))
    sh = sh.filter(ImageFilter.GaussianBlur(max(2, w // 28)))
    im.alpha_composite(sh, (x + 2, y + max(3, w // 22)))   # bayangan halus
    im.alpha_composite(L, (x, y))
    im.convert('RGB').save(f'gpt-{k}-logo.png')
```

Jangan coba "mengembalikan" piksel sayap di atas logo dengan filter warna. Bingkai badge dan sayap sama-sama putih, jadi hasilnya rusak. Lebih baik generate ulang dengan badge terlihat penuh.

## 5. Hapus background (gratis, di Mac)

Pakai Vision subject lift bawaan macOS, bukan node Cutout di Tripo (kena kredit):

```swift
// lift.swift  —  swift lift.swift gpt-<pose>-logo.png final-<pose>.png
import Vision
import CoreImage
import AppKit
let a = CommandLine.arguments
let input = CIImage(contentsOf: URL(fileURLWithPath: a[1]))!
let req = VNGenerateForegroundInstanceMaskRequest()
let h = VNImageRequestHandler(ciImage: input)
try h.perform([req])
guard let obs = req.results?.first else { print("no subject"); exit(1) }
let buf = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: h, croppedToInstancesExtent: true)
let out = CIImage(cvPixelBuffer: buf)
try CIContext().writePNGRepresentation(of: out, to: URL(fileURLWithPath: a[2]), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
print("ok", Int(out.extent.width), Int(out.extent.height))
```

Hasil sudah ter-crop ke tepi owl dan transparan. Cek di latar putih **dan** gelap supaya tidak ada sisa abu-abu.

## 6. Masukkan ke Figma

- Buat rectangle bernama `Maskot Shoo · <pose>` di frame `2431:12759`, isi dengan image fill **FIT** dari `final-<pose>.png`.
- Grid 5 kolom per kelompok (Dialog & status, Gestur, Emosi, Aksi, Lainnya). Kotak owl 700x980, rata bawah, label bold 52 dan keterangan 34 di bawahnya.
- Dialog konfirmasi memakai rect owl 150 tinggi dengan lebar mengikuti rasio gambar, mengintip di atas kartu dialog. Pemetaan: Mikir = tandai aman, ganti kode; Melambai = gabung keluarga; Kaget = putus koneksi, hapus akun.
- Sheet (bottom sheet) memakai pose `peek` yang tangannya memegang tepi atas sheet. Rect owl berada di **depan** sheet (urutan layer di atas sheet), ukurannya 147x104. Taruh di kanan dengan jarak 40 dari tepi layar. Supaya tidak kelihatan seperti stiker, owl dibagi jadi 2 lapis.
  - **Badan:** `peek.png` di dalam frame clip setinggi 96.6 (baris 821 dari 884), dengan `y = sheetTop - 96.6`. Badan terpotong rata tepat di tepi sheet, jadi seolah masuk ke belakang sheet.
  - **Tangan:** `peek-hands.png` (hanya jari, baris 812 ke bawah, dipotong dari `peek.png` lewat kolom 195–420 dan 890–1075) di posisi yang sama, di depan sheet. Pakai drop shadow 0/1.5/3 dengan alpha 0.22, jadi jari terlihat menggantung di tepi sheet.
  - Jarak kanan 56. Untuk sheet yang bagian dari gambar, ukur `sheetTop` dari export PNG: baris putih pertama. Dipakai di sheet Matikan Shoo, Tandai sebagai aman (V5), Data yang dikirim (C6), dan Modus penipuan (V3).

## Catatan

- File kerja (PNG mentah dan final) ada di scratchpad sesi dan bisa hilang. Sumber yang awet adalah Figma: export rect `Maskot Shoo · <pose>` sebagai PNG.
- Nano Banana Pro keluar 896x1200. GPT Image 2.5 keluar 1152x1536 untuk 3:4, dan 1024x1024 untuk 1:1. Tripo tidak punya node upscale.
