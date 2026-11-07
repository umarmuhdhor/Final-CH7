# Domain lists: seed vs old lists

Golden: 1111 hosts from origin/main ce137f9 (7 Nov 2026). Seed: 276 rows. Differences: 380, all categorized (K12).

| Reader (category) | Cases | Reason | Examples |
|---|---|---|---|
| backend (a) | 192 | backend now protects L1, L2 apex, brands and suffix rows it did not list | `a.b.acrobat.adobe.com` false→true, `a.b.adobe.com` false→true, `a.b.airbnb.com` false→true, `a.b.alodokter.com` false→true, `a.b.antaranews.com` false→true, `a.b.anteraja.id` false→true |
| backend (c) | 8 | ac.id/sch.id/mil.id/desa.id are apex: names under them can be queued (D-dash-22 #3) | `a.b.ac.id` true→false, `a.b.desa.id` true→false, `a.b.mil.id` true→false, `a.b.sch.id` true→false, `x.ac.id` true→false, `x.desa.id` true→false |
| backend (g) | 4 | multi-tenant host row is protected as apex (D-dash-22 #7) | `1drv.ms` false→true, `cloud.microsoft` false→true, `firebasestorage.googleapis.com` false→true, `storage.googleapis.com` false→true |
| blockMemory (blockMemory-10c) | 90 | Safari block-memory key mode differs (L6 is narrower than L2/L4); decided and tested in 10c | `1drv.ms` registrable→host_path, `a.b.1drv.ms` registrable→host, `a.b.akamaihd.net` registrable→host, `a.b.appspot.com` registrable→host, `a.b.cloud.microsoft` registrable→host, `a.b.duckdns.org` registrable→host |
| build (b) | 60 | L4-only domain: protect only (trusted = false) until X10 | `a.b.bankjago.com` false→true, `a.b.bankmega.com` false→true, `a.b.blubybcadigital.id` false→true, `a.b.btpn.com` false→true, `a.b.doku.com` false→true, `a.b.indihome.co.id` false→true |
| build (d) | 6 | L1 ∩ L2 are apex: tenants under them can be published after 10c (D-dash-22 #2) | `a.b.googleapis.com` true→false, `a.b.s3.amazonaws.com` true→false, `www.googleapis.com` true→false, `www.s3.amazonaws.com` true→false, `x.googleapis.com` true→false, `x.s3.amazonaws.com` true→false |
| build (e) | 8 | platform apex only the backend listed (shared roots) is now protected in the ai/ build (after 10c) | `a.b.page.link` false→true, `a.b.s.id` false→true, `page.link` false→true, `s.id` false→true, `www.page.link` false→true, `www.s.id` false→true |
| build (g) | 12 | multi-tenant host row is protected as apex (D-dash-22 #7) | `1drv.ms` false→true, `a.b.1drv.ms` false→true, `a.b.cloud.microsoft` false→true, `a.b.forms.cloud.microsoft` false→true, `cloud.microsoft` false→true, `forms.cloud.microsoft` false→true |

Old lists: L1 122, L2 72, L4 98 + 61 shared roots.
