# Fase 0 — Hasil Spike Audio

Dijalankan 19 Nov 2026. Semua angka di bawah adalah keluaran alat, bukan perkiraan.

## Lingkungan

| Item | Nilai |
|---|---|
| macOS | 27.2 (build 26B5091g) |
| Toolchain | Swift 6.4, Command Line Tools saja — **Xcode tidak terpasang** |
| Perangkat | BlackHole 2ch (`BlackHole2ch_UID`, 2 out/2 in), MacBook Pro Speakers (2 out), MacBook Pro Microphone (1 in) |
| Default output | **BlackHole 2ch** |
| Default input | MacBook Pro Microphone |

## Terbukti

| Uji | Metode | Hasil |
|---|---|---|
| Tap global menangkap audio | `nail-spike tap 6` sambil `afplay Ping.aiff` | 663 callback, 2 channel, 4096 byte/buffer, peak RMS 0.032 |
| Tap per proses mengisolasi | `afplay nail-a` (3,5 dtk) mulai t=0; `afplay nail-b` (4,7 dtk) mulai t=4,5; tap hanya PID `nail-a` | Sinyal t=0,3–3,0 dtk; **nol** t=3,5–9,1 dtk meski `nail-b` berbunyi |
| PID harus diterjemahkan | Mengirim PID mentah ke `CATapDescription` | Gagal `!obj` (560947818). Wajib lewat `kAudioHardwarePropertyTranslatePIDToProcessObject` |

Artefak: `spike/Sources/nail-spike/main.swift`, perintah `nail-spike devices` dan `nail-spike tap [detik] [--pid PID[,PID]]`.

## Kebocoran speaker dan AEC

Diukur di MacBook Pro internal speaker dan mic internal, volume sistem apa adanya.

| Kondisi | Baseline (diam) | Saat speaker berbunyi | Rasio |
|---|---|---|---|
| Tanpa AEC, volume 29 | 0.0027–0.0041 | puncak **0.03021** | ~10× baseline |
| AEC, volume 29 | 0.00140 | puncak **0.00196** | ~1,4× baseline |
| Tanpa AEC, volume 100 | 0.00258 | puncak **0.10547** | ~40× baseline |
| AEC, volume 100 | 0.00170 | puncak **0.00199** | ~1,2× baseline |

Pada volume 100 dengan AEC, level bertahan datar sepanjang pemutaran (0.00132 / 0.00119 / 0.00143 / 0.00115), bukan hanya turun di awal.

Sumber suara adalah proses lain (`afplay`), bukan proses spike. Artinya referensi AEC bekerja di level perangkat, bukan hanya audio milik aplikasi sendiri. Kondisi ini sama dengan Peserta yang berbicara di Meet: pemutaran dilakukan proses lain.

Konsekuensi desain: headset **tidak** perlu diwajibkan pada speaker internal, bahkan di volume maksimum, selama AEC aktif. Syarat headset tetap disimpan untuk speaker eksternal dan headset Bluetooth, yang belum diukur karena tidak ada perangkat terpasang saat uji.

## Isolasi tab di Arc (Chromium)

Musik dan Google Meet dibuka di Arc. `nail-spike processes` menunjukkan hanya satu proses audio aktif: `pid 1744` (`company.thebrowser.browser.helper`), `running=1 output=1`. Tap pada PID itu menangkap audio (peak RMS 0.352).

Tidak ada PID kedua meski dua tab memutar audio. Chromium mengarahkan audio semua tab ke satu proses, jadi tap per proses = **per aplikasi**, bukan per tab. Musik dan Meet tidak bisa dipisahkan selama keduanya ada di aplikasi yang sama.

Konsekuensi: pisahkan aplikasi, bukan tab. Meet di satu aplikasi (misalnya Safari), audio lain di aplikasi berbeda, atau tidak memutar audio lain selama Sesi.

## Jalur AI untuk prototipe saat ini

Gunakan langganan ChatGPT Plus saja, tanpa model lokal dan tanpa API berbayar terpisah. Uji transkripsi dan notulen secara manual lewat [ChatGPT Record](https://help.openai.com/en/articles/11487532-chatgpt-record) di aplikasi macOS; uji percakapan suara lewat ChatGPT Voice di klien yang mendukung. Untuk notulen dari teks, prototipe sudah membuktikan bahwa Codex CLI bisa menjawab lewat login ChatGPT tanpa API key tambahan.

Record dan Voice bukan endpoint yang bisa dipanggil Nail. Integrasi audio otomatis dan pemutaran suara ke Peserta Meet belum terbukti lewat Plus. Uji dengan materi nonrahasia atau dengan izin Peserta karena pemrosesan berlangsung di cloud.

**Uji suara tanpa tab browser lulus.** `codex app-server` melaporkan `authMethod=chatgpt` tanpa variabel API key. WebRTC lewat Chromium headless menerima klip sintetis “Berapa dua tambah dua?”; Codex mengembalikan transkrip “Dua tambah dua sama dengan empat.” Penerima mendekode 459.360 sampel audio dengan `totalAudioEnergy=0.09042`. Tidak ada mic fisik, akun browser, atau rapat yang dipakai.

WebSocket meminta API key. Klien WebRTC Python mencapai ICE `completed` tanpa RTP; uji yang lulus memakai Chromium headless. Protokol Codex ini eksperimental. Pemutaran fisik, latensi ke suara pertama, dan routing BlackHole ke Meet belum diuji.

## Google AI Pro tanpa API key

`agy --print` (Antigravity CLI, sudah terpasang) menjawab lewat akun Google, tanpa `GEMINI_API_KEY`. Uji: pertanyaan Bahasa Indonesia dijawab dalam 7,6 detik; notulen tiga bagian dari transkrip pendek dihasilkan dalam 11,3 detik dan lolos pemeriksaan isi.

Batasnya: Antigravity tidak menyediakan jalur audio langganan. Suara tetap hanya tersedia lewat Codex Live Voice (kuota langganan, reset 13:10) atau Gemini API berbayar. Jadi otak teks bisa pindah ke Google tanpa biaya tambahan; mulut Nail belum bisa.

## 9router sebagai endpoint lokal

`http://localhost:20128/v1` hidup dengan 56 model (`cx/*` = Codex, `ag/*` = Antigravity/Gemini) dan API key tersimpan di `~/.9router/db/data.sqlite`.

| Uji | Hasil |
|---|---|
| `cx/gpt-6.1-sol` | `429 usage limit`, kuota ChatGPT yang sama |
| `ag/gemini-3.8-flash`, streaming | “Empat.”, ~47 detik |
| Audio masuk (`input_audio`, klip 3 detik) | Transkrip benar: “Bima akan mengirim laporan sebelum hari Jum'at”, **55–59 detik** |
| Audio keluar | Tidak ada. Semua 56 model melaporkan `audioOutput: false` |

Kesimpulan: 9router bisa menjadi telinga dan otak Nail lewat langganan Google tanpa API key berbayar, tetapi tidak bisa menjadi mulut. Latensi 55 detik untuk klip 3 detik berarti batch setelah rapat, bukan percakapan langsung.

Varian `low` tidak memperbaiki latensi: `ag/gemini-3.8-flash-low` 55,4 detik dengan transkrip benar; `ag/gemini-3.6-flash-low` 56,9 detik dengan balasan kosong.

## DeepSeek: telinga, otak, dan mulut

Key disimpan di Keychain (`nail.deepseek`). Diukur langsung dari Mac uji:

| Uji | Hasil |
|---|---|
| ASR klip 3,3 detik | transkrip benar, **1,04–1,27 detik** |
| TTS kalimat 2 buah (6,04 detik audio) | byte pertama **1,12 detik**, selesai 1,78 detik |
| TTS → ASR | teks kembali identik: “dua tambah dua sama dengan empat. Bima akan mengirim laporan sebelum hari Jumat.” |

Semua tiga tahap berjalan lebih cepat daripada realtime, dengan Bahasa Indonesia didukung di ASR dan TTS. Biaya: ASR $0.058/jam, TTS $0.225/10k karakter, `deepseek-flash` $0.15/M input. Satu jam rapat ≈ $0.06.

Batas: ASR maksimal 120 detik per request dan tanpa streaming; TTS tanpa kontrol kecepatan.

## Kanal Pemilik (mic fisik)

Untuk bicara langsung dan mendengar jawaban di headset, jalankan `python3 spike/nail-loop.py --mic --chunk 8`. Mode mic memakai masukan dan keluaran yang dipilih di Pengaturan Sistem → Suara, tanpa beralih ke BlackHole. `--no-speak` menampilkan jawaban sebagai teks saja.

Uji langsung: pengguna berbicara lewat `External Microphone` dan mengonfirmasi jawaban Nail terdengar di `External Headphones`. Uji ini tidak memvalidasi audio yang diterima peserta di Meet.

`nail-spike record --mic` merekam mic ke WAV; `nail-loop.py --mic` memakainya sebagai masukan. Uji lewat speaker pada volume 100 (bukan bicara langsung): transkrip muncul, total 2,64 detik (ASR 1,38 / LLM 1,27).

Akurasi pada uji itu buruk — “Nail, Bima” menjadi “Nayu Lima”, “Jumat” menjadi “jumpa” — karena audio dua kali dikonversi lewat udara. Uji ini membuktikan jalur, bukan kualitas; bicara langsung ke mic tidak melewati speaker.

Pada volume 29, level mic hanya RMS 185 dan ASR mengembalikan teks kosong. Mic internal Mac butuh suara dekat atau volume lebih tinggi.

## Pipeline satu perintah

`python3 spike/nail-loop.py --self-test` menjalankan seluruh rantai: rekam audio proses → ASR → `deepseek-flash` → TTS → BlackHole → kembalikan default output.

| Tahap | Detik |
|---|---|
| ASR | 1,71 |
| LLM | 1,49 |
| TTS | 1,04 |
| **Total (akhir potongan → suara siap)** | **4,25** |

Transkrip: “Akan mengirim laporan sebelum hari Jumaat. Kapan Bima mengirim laporan?” Jawaban: “Bima akan mengirim laporan sebelum hari Jumat.” Kata pertama terpotong karena rekaman mulai 0,4 detik setelah pemutaran; pada Sesi nyata rekaman sudah berjalan lebih dulu.

Untuk rapat sungguhan, pakai PID audio aplikasi rapat: `python3 spike/nail-loop.py --pid <pid> --chunk 30 --turns 3`.

## HUD dan menu bar

`app/NailSpike` dibangun dengan SwiftPM lalu dibungkus menjadi `NailSpike.app` (ad-hoc signing, `LSUIElement`). Tidak perlu `.xcodeproj` untuk spike ini.

Terukur saat dijalankan: jendela `NailSpike` ada di daftar on-screen dengan `layer=25` (level `.statusBar`) dan ukuran 360×248 di posisi (40,40). Laporan runtime dari dalam aplikasi (`--print-window`): `level=25`, `collectionBehavior=273`, `canJoinAllSpaces=true`, `fullScreenAuxiliary=true`, `isVisible=true`, frame 360×248.

Panel bertahan di atas aplikasi fullscreen: pengguna membuka Arc fullscreen dan mengonfirmasi panel tetap terlihat. Tombol Approve mengubah status menjadi “Disetujui” tanpa menutup panel.

Catatan: panel sempat “hilang” saat pengujian karena saya menjalankan aplikasi dengan `--print-window`, yang memang memanggil `NSApp.terminate`. Bukan bug panel.

## Integrasi HUD dan pipeline

Aplikasi `NailSpike` menjalankan `spike/nail-loop.py` dari tombol **Dengar 8 detik** dan menampilkan transkrip serta jawaban di panel. Diuji headless lewat `--run-turn --pid <pid>` (jalur kode yang sama dengan tombol):

| Uji | Hasil |
|---|---|
| Audio dengan jeda 0,7 detik | hanya kalimat terakhir tertangkap |
| Audio dengan jeda 2 detik | transkrip lengkap: “Bima akan mengirim laporan sebelum hari Jumat. Rina menyiapkan transkrip.”; ASR 1,38 dtk, LLM 1,26 dtk, TTS 2,07 dtk |

Penyebab truncation adalah proses Python yang butuh ~1 detik sebelum merekam, bukan ASR. Aplikasi sekarang merekam dengan biner Swift lebih dulu, lalu menyerahkan WAV ke Python lewat `--from-wav`. Jalur file itu diuji dan lulus (transkrip lengkap, ASR 1,19 dtk).

Perbaikan truncation pada jalur mic belum terbukti secara terkontrol. Pada uji itu pengguna menyanyi, dan mic menangkap suaranya dengan benar: ASR menuliskan lirik bahasa Inggrisnya (“You didn't know how to make me cry when you gave me those sad eyes. I'm scared.”) dalam 1,35 detik. Itu membuktikan capture dan ASR pada suara langsung, bukan pembuktian kata pertama.

## Frasa pemicu

`nail-loop.py --require Nail` menolak menjawab bila transkrip tidak memuat kata pemicu. Diuji dengan dua klip sintetis:

| Klip | Hasil |
|---|---|
| “rapat kita mulai jam sembilan besok pagi” | `skipped`, alasan `tanpa frasa pemicu 'Nail'` |
| “Nail, jam berapa rapat kita mulai besok?” | dijawab, ASR 1,21 dtk, LLM 2,35 dtk |

Ini gerbang teks, bukan deteksi suara lokal. Nail tetap mengirim seluruh potongan audio ke ASR sebelum menolak, dan Porcupine belum dipakai.

## Notulen Markdown

Setiap putaran yang dijawab menulis ke `~/NAIL/Notulen/YYYY-MM-DD.md` (bisa diganti dengan `--notulen`, dimatikan dengan `--no-notulen`). Format: heading waktu, `**Dengar:**`, `**Nail:**`.

Diuji dengan dua putaran ke file sementara: putaran yang dijawab menambah entri; putaran yang ditolak frasa pemicu tidak menulis apa pun. Jumlah entri akhir 1. Dikonfirmasi juga dari aplikasi: pengguna menjalankan satu putaran dan entri benar-benar tertulis di `~/NAIL/Notulen/`.

## Dengar terus

**Dengar terus** memproses potongan 8 detik secara berurutan. Audio berikutnya baru direkam setelah pemrosesan potongan sebelumnya selesai, jadi ini belum perekaman tanpa jeda. HUD mempertahankan transkrip terakhir saat potongan berikutnya kosong. **Berhenti** mencegah potongan berikutnya; perekaman atau pemrosesan yang sedang berjalan diselesaikan sebelum tombol mulai aktif lagi. Potongan yang masih direkam saat berhenti tidak dikirim ke ASR.

Diagnosis: log macOS menolak `kTCCServiceAudioCapture` untuk `dev.nail.spike` karena bundle lama tidak memiliki `NSAudioCaptureUsageDescription`. Empat potongan terakhir yang diperiksa berdurasi sekitar 8 detik dan seluruh sampelnya nol. Bundle baru menyertakan deskripsi agar macOS bisa meminta izin. Potongan tanpa sinyal dilewati tanpa panggilan ASR, dan HUD menunjukkan petunjuk sumber atau izin alih-alih kembali ke status “Merekam…”.

Verifikasi: `python3 spike/test_nail_loop.py` lulus untuk potongan nol. `--run-turn --pid` pada klip sintetis menghasilkan “Bima akan mengirim laporan sebelum hari Jumat.” tanpa kata pemicu. Uji ini memakai proses `afplay` dan peluncuran CLI, bukan persetujuan izin di GUI atau rapat. Bundle ditandatangani ulang, diluncurkan melalui LaunchServices, dan panel terlihat di layer 25.

## Dengar sekali (tanpa frasa pemicu)

Tombol **Dengar sekali** memproses satu potongan tanpa gerbang “Nail”, untuk perintah yang sengaja ditekan. Diuji headless (`--run-turn --no-gate`) dengan klip tanpa kata pemicu: “Jam berapa rapat kita mulai besok?” dijawab, ASR 1,24 dtk, LLM 1,32 dtk, TTS 2,22 dtk.

Alasannya tercatat di bagian frasa pemicu: ASR kadang menjatuhkan kata “Nail”, sehingga perintah sah bisa ditolak. Jalur tekan-sengaja menghindari kegagalan itu.

## Berhenti saat diam (belum dipakai aplikasi)

`nail-spike record <maks> --mic --until-silence` berhenti setelah 0,9 detik tanpa suara di atas ambang, atau saat batas waktu tercapai. Belum diaktifkan di aplikasi.

Dua percobaan verifikasi lewat speaker gagal sebagai bukti: percobaan pertama berhenti di 2,40 detik karena sinyal speaker bocor ke mic terputus-putus; setelah ambang diturunkan, rekaman berjalan penuh 12 detik karena derau speaker terus di atas ambang. Keduanya mengukur jalur udara, bukan suara langsung. Ambang dikembalikan ke nilai awal (0,01 RMS, jeda 0,9 detik), dan fitur menunggu satu uji dengan suara langsung.

Menu bar menyediakan **Buka notulen hari ini**; jika file belum ada, Finder dibuka di folder notulen. Path diverifikasi lewat `--print-notulen`: `~/NAIL/Notulen/2026-11-20.md`, `exists=true`.

## Sumber audio aplikasi

Toggle **Dengar audio aplikasi (Meet/Zoom)** memilih satu PID dengan `output=1` di awal sesi (mis. helper Arc). Mulai saat sumber sedang berbunyi. Jika tidak ada PID, HUD melaporkannya dan tidak beralih ke mikrofon. Tap pada Arc tidak membedakan tab Meet dari tab lain.

## Injeksi suara ke BlackHole

Audio yang diputar ke BlackHole 2ch terekam sebagai perangkat masukan: 3,6 detik, RMS 2444, tanpa model dan tanpa API. Ini membuktikan kaki keluaran — suara Nail bisa menjadi mic aplikasi rapat. Default output dikembalikan ke MacBook Pro Speakers setelah uji.

Pada uji lanjutan, Codex menolak karena kuota langganan habis (pesan: *usage limit*, coba lagi 13:10), bukan karena kode atau auth. Latensi ke suara pertama masih belum terukur.

Temuan Whisper di bawah hanya arsip pembanding, bukan jalur yang dipakai prototipe.

## Transkripsi Indonesia tanpa API key

Pemeriksaan pada Mac uji: `SFSpeechRecognizer` mengenali locale `id-ID`, tetapi melaporkan `supportsOnDeviceRecognition=false`; `SpeechTranscriber` tidak menawarkan locale tersebut. Sebagai alternatif lokal, `faster-whisper` Base (CPU, int8) mentranskrip klip sintetis Damayanti berdurasi 5,99 detik dengan benar untuk waktu rapat, nama, tugas, dan tenggat. Muat model 0,69 detik; inferensi 0,47 detik. Pengujian berjalan offline setelah bobot tersedia.

Jalankan `uv run spike/transcribe-local.py rekaman.m4a` dari root repo. Prototipe ini membutuhkan `uv` dan `ffmpeg`; pemakaian pertama dapat mengunduh dependensi dan bobot. Belum diuji pada audio rapat nyata, campuran ID–EN, atau streaming. Codex untuk rangkuman tetap menggunakan cloud, meski tanpa API key tambahan.

Pada klip sintetis 45,38 detik yang sama, Whisper Base salah membaca “Kamis sore” sebagai “kami sorry” (inferensi 2,16 detik). Whisper Small membaca tenggat itu dengan benar. Uji ulang offline dengan bobot tersedia: muat model 0,90 detik, inferensi 5,84 detik. Small masih salah menulis “menyiapkan”, jadi notulen tetap perlu diperiksa. Small sekarang default untuk spike; `--model base` masih bisa dipakai sebagai pembanding.

## Belum terbukti

1. **Dua perangkat di Meet/Zoom.** Butuh perangkat kedua dan tangan manusia.
2. **Latensi dan kualitas suara.** Round trip sintetis Codex Live Voice lulus; latensi ke suara pertama dan kualitas pada rapat nyata belum diukur.
3. **NSPanel di Space fullscreen.** Belum diuji; SDK Xcode belum bisa digunakan sebelum lisensi disetujui.
4. **Speaker eksternal dan headset Bluetooth.** Belum ada perangkat saat uji.

## Blocker

1. **Lisensi Xcode belum disetujui.** Xcode 27.2 sudah terpasang. `xcodebuild -showsdks` keluar dengan status 69. Buka Xcode untuk meninjau lisensi dan menyelesaikan setup awal sebelum membangun spike MenuBarExtra dan NSPanel.
2. **Routing Meet dan Zoom belum diuji dengan Peserta.** Pemilik tetap memakai speaker atau headset sebagai keluaran macOS. Aplikasi rapat memakai BlackHole sebagai masukan untuk menerima campuran mic Pemilik dan suara Nail.

## Perintah

```bash
cd spike
swift build
./.build/debug/nail-spike devices
./.build/debug/nail-spike tap 6            # global tap, cetak RMS
./.build/debug/nail-spike tap 9 --pid 1234 # hanya proses 1234
./.build/debug/nail-spike mic 5            # RMS mic
./.build/debug/nail-spike leak 6 /tmp/nail-b.aiff --aec  # kebocoran speaker, AEC aktif
```

## Langkah berikutnya

1. Selesaikan setup awal Xcode, lalu uji `MenuBarExtra` + `NSPanel` pada layar biasa dan Space fullscreen.
2. Pertahankan speaker atau headset sebagai keluaran, lalu uji routing dua perangkat di Meet dan Zoom.
3. Ukur kebocoran speaker sebelum dan sesudah AEC.

## Gabung Google Meet dari HUD

Tempel link `https://meet.google.com/xxx-xxxx-xxx` di HUD dan tekan **Gabung Meet**. Bila Meet meminta persetujuan, host tetap harus mengizinkan Nail. Tekan **Keluar Meet** untuk menutup sesi Nail. Chromium tersembunyi dan tidak punya akses ke mic atau kamera fisik, berbagi layar, maupun pemutaran ke speaker.

Menu **Login Google untuk Nail** membuka Chromium tertanam dengan profil persisten di `~/Library/Application Support/Nail/Meet Chromium`; tutup panel setelah login. Bundle lokal memerlukan Electron di `Contents/Frameworks/Electron.app` serta `Support/meet.cjs`, `Support/meet-media.cjs` dan `Support/codex-voice.cjs` di `Contents/Resources/`.

Aktifkan **Dengar dan jawab di Meet**, lalu pilih **Codex Live Voice** (default, login ChatGPT tanpa API key), **DeepSeek** (API key di Keychain), atau **Antigravity (Google AI Pro)** (`spike/agy-voice.py`). Pilihan tersimpan dan dikunci selama sesi; beri tahu peserta tentang penyedia yang dipilih.

Klip tanpa sinyal audio yang cukup dilewati sebelum dikirim ke penyedia. HUD membedakan koneksi Codex, konfirmasi transkrip, dan pengiriman ke mic virtual. Putaran Codex dibatalkan setelah 50 detik jika belum selesai.

### Temuan dan Perbaikan Audio Google Meet di Electron (20–21 Nov 2026)

1. **Passthrough `RTCRtpReceiver.createEncodedStreams()` (`Support/meet-media.cjs`)**:
   - Diagnosis pada rapat nyata (`prm-igjg-eki`): WebRTC menerima ratusan paket RTP audio pada `mid: "3"` (`ssrc: 6666`, `payloadType: 111`, `audio/opus`), namun `totalSamplesReceived: 0` dan `jitterBufferEmittedCount: 0`.
   - Penyebab: halaman Google Meet memanggil `receiver.createEncodedStreams()` pada ketiga receiver audio, membaca seluruh frame dari `readable` (`inC: 283–1295`), tetapi Worker halaman Meet di Electron tidak menulis satu pun frame kembali ke `writable` (`outC: 0`). Pemeriksaan byte frame (`0x78 ...`, 55–70 byte) dan dekode ulang lewat `ffmpeg` membuktikan payload adalah Opus polos yang valid (bukan terenkripsi).
   - Perbaikan: membungkus `createEncodedStreams()` untuk menggandakan `RTCEncodedAudioFrame` dan menulis frame langsung ke `streams.writable` selama Worker Meet belum mengirim frame balik (`outC === 0`).

2. **Deteksi Mic Virtual Setelah Pemrosesan `AudioContext` Meet (`Support/meet-media.cjs`)**:
   - `navigator.permissions.query({name: 'microphone'})` di-override menjadi `'granted'` di main world (izin hardware Chromium di `meet.cjs` tetap `false`) agar Meet tidak memblokir tombol mikrofon.
   - Meet memproses track mic virtual melalui `AudioContext` internalnya sebelum dipasang ke `RTCRtpSender`, sehingga track pengirim berganti referensi dengan label `MediaStreamAudioDestinationNode`. Pengecekan `sending()` diperbarui untuk mengenali track tersebut saat `micCalls > 0`.

3. **Jalur Antigravity (Google AI Pro) & Daemon Hangat (`spike/agy-voice.py`)**:
   - Rantai suara tanpa kuota Codex/DeepSeek:
     - **Telinga (STT):** `faster-whisper` model **`small`** lokal (CPU `int8`, `language="id"`, `initial_prompt` + `hotwords="Nail, Halo Nail, Hei Nail"`).
     - **Otak (LLM):** `agy` (`gemini-3.8-flash-low`) dalam mode persisten `--input-format stream-json --output-format stream-json`.
     - **Mulut (TTS):** macOS `say -v Damayanti --data-format=LEI16@16000` langsung menghasilkan WAV 16 kHz mono tanpa proses `ffmpeg` tambahan.
   - Saat Nail masuk ke Meet, `meet.cjs` menyalakan `agy-voice.py --daemon` di latar belakang untuk memuat `faster-whisper` ke RAM dan melakukan *warmup* sesi `agy`. Waktu proses per putaran turun dari **9,83–11,09 detik** (cold) menjadi **~4,1–6,74 detik** (warm).

4. **Mode Panggil `"Nail"` Otomatis & Pre-Roll 450 ms (`Support/meet-media.cjs`, `Support/meet.cjs`, `MeetSession.swift`)**:
   - Setelah masuk rapat dengan penyedia `antigravity` atau `deepseek`, Nail otomatis menyimak tanpa perlu menekan tombol **Dengar & jawab di Meet**.
   - Audio peserta dialirkan melalui `DelayNode` **450 ms** (`preRoll`) ke `MediaRecorder` (`64 kbps`), sedangkan `AnalyserNode` memantau onset suara secara langsung. Rekaman baru dimulai saat suara terdeteksi (menyertakan 450 ms sebelum suku kata pertama agar konsonan awal seperti `"H-"` pada `"Halo Nail"` tidak terpotong) dan otomatis berhenti setelah **~1,1 detik** hening.
   - Selama kata pemicu `"Nail"` belum disebut, HUD tetap diam di status **`Siaga di Meet — menunggu panggilan 'Nail'…`**, tidak menampilkan transkrip obrolan peserta, dan tidak memanggil LLM. Jika `"Nail"` dipanggil di tengah kalimat, semua kata sebelum `"Nail"` dibuang sebelum dikirim ke LLM.
