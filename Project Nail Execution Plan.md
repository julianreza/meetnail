# Project NAIL: Rencana Eksekusi macOS (Revisi Arsitektur Bot Meet/Teams + Codex Live Voice)

Rencana ini mencakup dua fase awal yang telah selesai (Fase 0 validasi dan Fase 1 fondasi aplikasi) serta tiga fase lanjutan (Fase 2–4) untuk aplikasi macOS **`NAIL.xcodeproj`** (full-native Swift dengan `SQLite3`/`GRDB`, `PDFKit`, dan `MCP Swift SDK` opsional di Fase 4, serta *embedded helper* Chromium Electron untuk bot Google Meet & Microsoft Teams dan worker lokal `faster-whisper` + `agy`).

---

## Keputusan Arsitektur Kunci

1. **Jalur Masuk Rapat:** **Bot Google Meet dan Microsoft Teams (mode tamu) tertanam (Electron)** sebagai jalur utama dengan nol setup BlackHole 2ch serta isolasi penuh dari tab/aplikasi lain. Dukungan **Zoom tetap ditunda**.
2. **Stack AI & Suara Utama:**
   - **Jalur Utama:** **Codex Live Voice** (suara natural ChatGPT WebRTC + panggil otomatis `"Nail"` *hands-free* via Whisper lokal + tombol manual cadangan).
   - **Jalur Cadangan:** **Antigravity (Google AI Pro)** (`gemini-4-neon-low` / `gemini-3.8-flash-low`) dengan `faster-whisper` lokal dan TTS macOS Enhanced.
   - **Opsional:** **DeepSeek** tetap tersedia di pengaturan penyedia HUD.
3. **Privasi & Mode Menyimak di HUD:**
   - **Mode Siaga (default):** hanya memproses dan menjawab saat dipanggil `"Nail"`; tidak mencatat atau menampilkan obrolan sebelum kata pemicu.
   - **Mode Notulen:** mencatat transkrip lokal + label pembicara lokal, dan otomatis dipakai sebagai **memori konteks** saat menjawab pertanyaan tentang pembahasan rapat berjalan maupun rapat sebelumnya (Fase 2).
4. **Struktur Proyek:** **`NAIL.xcodeproj`** full-native Swift (`NAIL/UI`, `NAIL/Audio`, `NAIL/Speech`, `NAIL/Memory`, `NAIL/Brain`, `NAIL/MCP`, `NAIL/Exporter`) dengan *embedded helper* Electron (`meet.cjs`, `meet-media.cjs`, `codex-voice.cjs`, serta dukungan Microsoft Teams mode tamu) dan worker `agy-voice.py` di dalam bundel `NAIL.app`.

---

## Ringkasan Timeline

| Fase | Fokus Utama | Status / Prioritas | Output Utama |
| :--- | :--- | :--- | :--- |
| **Fase 0** | Validasi stack native, bot Google Meet, dan jalur Antigravity | **Selesai** | Spike HUD fullscreen, bot Meet Electron dua arah, jalur Antigravity + Whisper + Damayanti terverifikasi |
| **Fase 1** | Fondasi `NAIL.xcodeproj`, Meet & Teams, Codex Live Voice, Mode Menyimak & Interupsi | **Selesai** | Proyek `NAIL.xcodeproj` aktif; Google Meet + Microsoft Teams (mode tamu), Codex Live Voice (*hands-free* `"Nail"` + manual), Antigravity, DeepSeek, diarization lokal, `Cmd+Shift+M`, jendela lanjutan, TTS Enhanced |
| **Fase 2** | Memori Rapat Cerdas, Dokumen Lokal & Mode Klien | **Berikutnya** | Transkrip SQLite + FTS5, pemulihan sesi terputus, Rangkuman Berjalan tiap 2 menit, memori lintas rapat, notulen terstruktur, pencarian 1 folder kerja (`PDFKit` + `FTS5`) + Kartu Bukti HUD, switch Persona manual cepat |
| **Fase 3** | Distribusi Notulen Tim | **Naik Prioritas** | Markdown lokal + tombol **Copy Ringkasan**, Slack & Discord (konfirmasi), Notion via REST API + Keychain, perintah penutup `"Nail, rapat selesai"` / tombol **Akhiri & Bagikan** (Email formal masuk backlog) |
| **Fase 4** | MCP & *Policy Gate* (4A Read-Only & 4B Opsional Write) | **Bertahap & Opsional** | **4A:** `MCP Swift SDK` Read-Only Filesystem/Git + cuplikan HUD. **4B:** Kanal Pemilik mic fisik, Policy Gate 3 Zona (default DENY), snapshot wajib, diff Approve/Reject 30 dtk, DB staging write, `audit.log` JSONL |

---

## Fase 0: Validasi Stack, Bot Google Meet & Jalur Antigravity (Selesai)

- [x] Spike HUD (`app/NailSpike`): `MenuBarExtra` + `NSPanel` level `.statusBar`, bertahan di atas Arc fullscreen, tombol Approve berfungsi tanpa menutup panel.
- [x] Evaluasi audio OS (`spike/`): Core Audio process tap, BlackHole 2ch, dan pengukuran kebocoran speaker + AEC (tersimpan di `spike/REPORT.md` sebagai referensi jika suatu saat mendukung Zoom).
- [x] Bot Google Meet tertanam (Electron): gabung Meet dengan profil Google persisten, tanpa akses mic/kamera fisik.
- [x] Perbaikan audio masuk & keluar Meet: passthrough `RTCRtpReceiver.createEncodedStreams()` untuk frame Opus polos di Electron, serta deteksi mic virtual pasca-`AudioContext` Meet (`MediaStreamAudioDestinationNode`).
- [x] Jalur **Antigravity (Google AI Pro)** (`spike/agy-voice.py`): `faster-whisper small` (lokal, `initial_prompt` + `hotwords`), daemon hangat `agy` (`stream-json`, `gemini-3.8-flash-low`), dan `say -v Damayanti` langsung ke WAV 16 kHz. Waktu proses turun dari ~10–11 dtk menjadi ~4,1–6,7 dtk.
- [x] Mode panggil `"Nail"` otomatis: `DelayNode` pre-roll **450 ms**, berhenti otomatis saat hening (~1,1 dtk), dan pembuangan semua ucapan sebelum kata `"Nail"`.
- [x] Penyedia cadangan & Live Voice: DeepSeek (`spike/nail-loop.py`) dan Codex Live Voice (`codex-voice.cjs`) terverifikasi di pemilih penyedia HUD.

---

## Fase 1: Fondasi `NAIL.xcodeproj`, Meet/Teams, Codex Live Voice & Kontrol Rapat (Selesai)

### Daftar Tugas
- [x] **Buat proyek `NAIL.xcodeproj` (full-native Swift, macOS 14+):**
  - [x] Susun struktur modul: `NAIL/UI/`, `NAIL/Audio/`, `NAIL/Speech/`, `NAIL/Memory/`, `NAIL/Brain/`, `NAIL/MCP/`, `NAIL/Exporter/`.
  - [x] Pindahkan HUD `NSPanel`, `MenuBarExtra`, `MeetSession`, serta bundel *embedded* `Electron.app` + `meet.cjs` + `meet-media.cjs` + `codex-voice.cjs` + `agy-voice.py` ke build phase `NAIL.app`.
- [x] **Jalur Masuk Rapat Multi-Platform (Nol BlackHole 2ch):**
  - [x] **Google Meet** tertanam (Electron) dengan profil persisten.
  - [x] **Microsoft Teams (mode tamu)** tertanam (Electron) untuk audio dua arah langsung di ruang rapat Teams.
- [x] **Penyedia AI & Suara di HUD (`NAIL/Brain/` & `NAIL/Speech/`):**
  - [x] **Codex Live Voice (Jalur Utama):** suara natural ChatGPT WebRTC + panggil otomatis `"Nail"` *hands-free* via Whisper lokal + tombol manual cadangan.
  - [x] **Antigravity (Cadangan):** dukungan `gemini-4-neon-low` / `gemini-3.8-flash-low` via `agy` + Whisper lokal.
  - [x] **DeepSeek (Opsional):** tersedia sebagai opsi penyedia di pengaturan HUD.
  - [x] Pemilihan model `agy`, model Whisper (`base`/`small`), dan upgrade **TTS Enhanced** (suara macOS Enhanced/Premium yang terpasang) di pengaturan HUD.
- [x] **Dua Mode Menyimak, Diarization Lokal & Konteks Berjalan (`NAIL/UI/` & `NAIL/Speech/`):**
  - [x] **Mode Siaga (default):** abaikan dan buang seluruh audio/teks sebelum kata pemicu `"Nail"`; HUD tetap tenang di status siaga.
  - [x] **Mode Notulen:** catat transkrip lokal via `faster-whisper`, gunakan **diarization pembicara lokal** (`scripts/setup-speaker-labels.sh` dengan `Pembicara N` atau pencocokan caption jika aktif), dan dukung **membaca notulen sesi berjalan** sebagai konteks saat menjawab pertanyaan di rapat.
- [x] **Kontrol Suara, Interupsi & Pengungkapan:**
  - [x] **Push-to-Interrupt (`Cmd+Shift+M`) & Panic Mute di menu bar:** potong pemutaran audio Nail di rapat (< 200 ms) dan batalkan antrean pemrosesan saat itu juga.
  - [x] **Jendela lanjutan 3 detik:** setelah Nail selesai berbicara, terima pertanyaan lanjutan selama 3 detik tanpa perlu mengulang kata `"Nail"`.
  - [x] **Kalimat pengungkapan (*disclosure*) opsional saat masuk rapat** dan pemeriksaan prasyarat pertama kali.

**Target Selesai (DoD — Tercapai):** `NAIL.app` dibangun bersih dari `NAIL.xcodeproj`, masuk ke Google Meet & Microsoft Teams (mode tamu) tanpa setup BlackHole, menjalankan Codex Live Voice (*hands-free* `"Nail"` + tombol manual) serta Antigravity/DeepSeek, mendukung Mode Siaga vs Mode Notulen + diarization lokal + membaca notulen sesi berjalan, dapat diinterupsi via `Cmd+Shift+M` di bawah 200 ms, serta mendukung jendela lanjutan dan TTS Enhanced.

---

## Fase 2: Memori Rapat Cerdas, Dokumen Lokal & Mode Klien

### Daftar Tugas
- [ ] **Penyimpanan Transkrip Berkelanjutan & Pemulihan (`NAIL/Memory/`):**
  - [ ] Tambahkan dependensi **SQLite + FTS5** (`SQLite3` bawaan macOS atau package SPM `GRDB.swift`).
  - [ ] Simpan transkrip sesi (saat **Mode Notulen** aktif) secara berkelanjutan di SQLite + FTS5 agar sesi yang terputus tetap dapat dipulihkan dan ditutup.
  - [ ] Sediakan tombol **Hapus per Sesi** di UI untuk menghapus transkrip dan notulen lokal sesi tertentu.
- [ ] **Rangkuman Berjalan & Memori Lintas Rapat (`NAIL/Memory/` & `NAIL/Brain/`):**
  - [ ] Regenerasi **Rangkuman Berjalan** otomatis tiap **2 menit** dari rangkuman sebelumnya + transkrip baru dengan skema tetap: *topik aktif*, *keputusan sementara*, *poin terbuka*, *action items*, *istilah*, dan *koreksi terakhir*.
  - [ ] Aktifkan **memori lintas rapat** berbasis FTS5: Nail otomatis mencari dan menjawab pertanyaan dari notulen rapat-rapat sebelumnya (bukan hanya sesi berjalan).
- [ ] **Notulen Akhir Terstruktur (`NAIL/Exporter/`):**
  - [ ] Hasilkan notulen akhir terstruktur berisi: **Ringkasan Eksekutif**, **Keputusan Utama**, **Action Items + PIC + Tenggat**, dan **Transkrip rapi**.
  - [ ] Simpan notulen kanonik ke penyimpanan lokal Markdown beserta dukungan menutup sesi terputus.
- [ ] **Pencarian 1 Folder Dokumen Kerja & Kartu Bukti HUD (`NAIL/Memory/` & `NAIL/UI/`):**
  - [ ] Pantau dan indeks **1 folder dokumen kerja** (`.pdf`, `.md`, `.txt`) menggunakan **PDFKit** (ekstraksi teks per halaman) + **SQLite FTS5**.
  - [ ] Tampilkan **Kartu Bukti di HUD** setiap kali jawaban merujuk dokumen atau memori rapat, lengkap dengan **nama file & nomor halaman PDF** atau **potongan notulen** sumbernya.
- [ ] **Switch Persona Manual Cepat di HUD (`NAIL/Brain/` & `NAIL/UI/`):**
  - [ ] Sediakan switch Persona manual cepat di HUD untuk 3 mode: **Santai/Internal**, **Klien Formal**, dan **Brainstorm** (**tanpa auto-switch otomatis 2 menit**).
  - [ ] Saat **Klien Formal** aktif, terapkan **filter kerahasiaan & isolasi memori rapat internal** agar detail rapat internal sebelumnya tidak bocor ke jawaban rapat klien.
  - [ ] Pisahkan **`voice_reply`** (ringkas untuk diucapkan di rapat) dan **`hud_card`** (detail kutipan/bukti di HUD).

**Target Selesai (DoD):** Dalam rapat Mode Notulen dengan 1 folder kerja berisi dokumen `.pdf`/`.md`/`.txt`, transkrip tersimpan berkelanjutan di SQLite + FTS5, Rangkuman Berjalan terbarui tiap 2 menit, pertanyaan tentang rapat sebelumnya maupun isi dokumen dijawab ringkas lewat suara disertai Kartu Bukti (nama file + nomor halaman / potongan notulen) di HUD, switch Persona manual cepat bekerja seketika dengan isolasi penuh pada mode Klien Formal, dan sesi terputus dapat dipulihkan atau dihapus per sesi dari UI.

---

## Fase 3: Distribusi Notulen Tim (Naik Prioritas)

### Daftar Tugas
- [ ] **Markdown Lokal & Copy Ringkasan (`NAIL/Exporter/` & `NAIL/UI/`):**
  - [ ] Ekspor notulen akhir terstruktur ke file Markdown lokal yang rapi.
  - [ ] Sediakan tombol **Copy Ringkasan** di HUD (format ringkas siap tempel ke WhatsApp / chat tim).
- [ ] **Distribusi ke Slack & Discord (`NAIL/Exporter/`):**
  - [ ] Kirim ringkasan **3–5 poin + daftar tugas** ke **Slack** dan **Discord** melalui webhook/bot dengan langkah konfirmasi di HUD sebelum pengiriman.
- [ ] **Integrasi Langsung ke Notion (`NAIL/Exporter/`):**
  - [ ] Buat halaman notulen + tabel *Action Items* langsung via **Notion REST API** dengan kredensial tersimpan aman di **macOS Keychain** (tanpa menunggu Fase MCP).
- [ ] **Perintah Penutup & Aksi Akhiri Rapat (`NAIL/Brain/` & `NAIL/UI/`):**
  - [ ] Hubungkan perintah suara penutup **`"Nail, rapat selesai"`** dan tombol **Akhiri & Bagikan** di HUD untuk memicu pembuatan notulen akhir dan alur distribusi.
- [ ] **Backlog:**
  - [ ] Pengiriman **Email formal** dipindahkan ke *backlog* (di luar cakupan Fase 3).

**Target Selesai (DoD):** Mengucapkan `"Nail, rapat selesai"` atau menekan **Akhiri & Bagikan** menghasilkan notulen Markdown lokal terstruktur, menyediakan **Copy Ringkasan** siap tempel, mengirim ringkasan 3–5 poin + tugas ke Slack/Discord setelah konfirmasi, dan membuat halaman notulen + tabel Action Items di Notion via Notion REST API + Keychain.

---

## Fase 4: MCP & *Policy Gate* (Bertahap & Opsional)

### 4A: *Read-Only* / Zona Hijau
- [ ] **MCP Client Host Read-Only (`NAIL/MCP/`):**
  - [ ] Tambahkan dependensi SPM **`MCP Swift SDK`** untuk transport `stdio` dan Streamable HTTP (`config/mcp_servers.json`).
  - [ ] Sambungkan **MCP Filesystem / Git** (hanya-baca / Zona Hijau) untuk mengecek kode, mencari fungsi, dan membaca riwayat *commit* saat rapat teknis.
  - [ ] Tampilkan **cuplikan kode / hasil Git** di **Kartu Bukti HUD** bersamaan dengan jawaban suara ringkas.

### 4B: Opsional — *Write* & Keamanan Penuh
- [ ] **Kanal Pemilik via Mic Fisik Lokal (`NAIL/Audio/`):**
  - [ ] Tangkap audio dari mic fisik lokal macOS khusus untuk **perintah aksi sensitif** dan **persetujuan suara**, sehingga suara peserta dari Google Meet / Microsoft Teams tidak pernah bisa memicu atau menyetujui aksi *write*.
- [ ] **Policy Gate 3 Zona (`NAIL/Brain/`):**
  - [ ] Terapkan *allowlist* eksplisit per server dan nama operasi dengan **default DENY** untuk operasi tak terdaftar.
  - [ ] **Zona Hijau:** pembacaan yang diizinkan dan arsip lokal — jalan otomatis.
  - [ ] **Zona Kuning:** *write* rutin / notifikasi — konfirmasi suara dari **Kanal Pemilik** dalam 6 detik; diam/ambigu = batal.
  - [ ] **Zona Merah:** ubah file repo atau *write* berisiko — **snapshot wajib** lebih dulu, tampilkan **kartu diff Approve/Reject** di HUD dengan batas waktu **30 detik**.
- [ ] **DB Staging Write & Audit Trail (`NAIL/MCP/` & `NAIL/Memory/`):**
  - [ ] Dukung *write* ke database *staging/sandbox* dengan pratinjau transaksi dan snapshot.
  - [ ] Tulis `audit.log` JSONL *append-only* di Application Support (`{ts, session_id, server, tool, zone, args_digest, intent_span_id, approver, decision, result_digest, latency_ms}`).

**Target Selesai (DoD):**
- **4A:** Pertanyaan teknis tentang fungsi/commit di repo dijawab ringkas lewat suara dan menampilkan cuplikan kode di HUD (Zona Hijau).
- **4B:** Aksi *write* hanya dapat dipicu/disetujui Pemilik melalui Policy Gate 3 Zona (default DENY), snapshot wajib tersimpan sebelum eksekusi, kartu diff Approve/Reject 30 dtk berfungsi di HUD, dan seluruh keputusan tercatat di `audit.log` JSONL.

---

## Matriks Skenario Pengujian End-to-End

| No | Skenario Uji | Fase | Kriteria Lulus |
| :--- | :--- | :--- | :--- |
| **1** | **Hands-Free Codex Live Voice & Cadangan** | Fase 1 | Panggilan `"Nail"` via Whisper lokal memicu Codex Live Voice (*WebRTC*) secara otomatis; tombol manual cadangan berfungsi, dan jalur cadangan Antigravity (`gemini-4-neon-low` / `gemini-3.8-flash-low`) serta opsi DeepSeek merespons normal. |
| **2** | **Stabilitas Bot Google Meet & Microsoft Teams** | Fase 1 | Nail masuk ke Google Meet dan Microsoft Teams (mode tamu) tanpa setup BlackHole 2ch, menerima audio peserta tanpa hening, menjawab lewat mic virtual, dan keluar bersih saat sesi diakhiri. |
| **3** | **Anti-Echo, Interupsi & Jendela Lanjutan** | Fase 1 | Nail tidak memicu dirinya sendiri saat berbicara; `Cmd+Shift+M` memotong audio < 200 ms; pertanyaan lanjutan dalam jendela lanjutan (3 detik) diproses tanpa mengulang kata `"Nail"`. |
| **4** | **Privasi Mode Siaga & Diarization Mode Notulen** | Fase 1 | Pada Mode Siaga, obrolan tanpa `"Nail"` tidak dicatat dan tidak memanggil AI. Pada Mode Notulen, transkrip lokal + label pembicara lokal tercatat dan dapat dibaca untuk konteks sesi berjalan. |
| **5** | **Fullscreen HUD & Prasyarat** | Fase 1 | Kartu HUD tampil di atas aplikasi fullscreen / menu bar tanpa kehilangan status; pemeriksaan prasyarat memberi panduan jelas jika komponen belum siap. |
| **6** | **Memori Notulen, Rangkuman 2 Menit & Lintas Rapat** | Fase 2 | Transkrip tersimpan berkelanjutan di SQLite + FTS5; Rangkuman Berjalan diperbarui tiap 2 menit; pertanyaan tentang keputusan di rapat berjalan maupun rapat-rapat sebelumnya dijawab akurat disertai potongan notulen. |
| **7** | **Pencarian 1 Folder Kerja & Kartu Bukti HUD** | Fase 2 | Pencarian `.pdf`, `.md`, dan `.txt` via `PDFKit` + `FTS5` mengembalikan jawaban ringkas lewat suara dan menampilkan Kartu Bukti di HUD berisi nama file serta nomor halaman PDF. |
| **8** | **Sesi Terputus & Hapus per Sesi** | Fase 2 | Mematikan aplikasi di tengah rapat Mode Notulen tetap menjaga transkrip SQLite; sesi dapat dipulihkan/ditutup, dan tombol **Hapus per Sesi** di UI menghapus transkrip serta notulen sesi tersebut. |
| **9** | **Switch Persona Manual & Isolasi Klien Formal** | Fase 2 | Switch manual cepat di HUD berpindah seketika antara **Santai/Internal**, **Klien Formal**, dan **Brainstorm** (tanpa auto-switch 2 menit); saat **Klien Formal** aktif, filter kerahasiaan aktif dan memori rapat internal terisolasi total. |
| **10** | **Distribusi Notulen (Markdown, Copy, Slack/Discord, Notion)** | Fase 3 | Perintah `"Nail, rapat selesai"` atau tombol **Akhiri & Bagikan** menghasilkan notulen akhir terstruktur, **Copy Ringkasan** siap tempel, pengiriman ringkasan 3–5 poin ke Slack/Discord (dengan konfirmasi), serta halaman + tabel Action Items di Notion via **Notion REST API + Keychain**. |
| **11** | **MCP Read-Only (Zona Hijau)** | Fase 4A | Pertanyaan kode/fungsi/commit melalui `MCP Swift SDK` (Filesystem/Git) dijawab ringkas lewat suara dan menampilkan cuplikan di HUD tanpa izin *write*. |
| **12** | **Policy Gate, Kanal Pemilik & MCP Write** | Fase 4B | Suara peserta rapat ditolak untuk aksi *write*; hanya **Kanal Pemilik** (mic fisik) yang diterima; operasi tak terdaftar terkena **default DENY**; Zona Merah wajib **snapshot** + kartu diff **Approve/Reject** 30 detik; seluruh aksi tercatat di `audit.log` JSONL. |
