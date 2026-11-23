# Google Meet Nail Avatar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Peserta Google Meet melihat wajah Nail dari HUD, dengan ekspresi yang mengikuti sesi dan gerakan mulut yang mengikuti suara keluar.

**Architecture:** SwiftUI merender `NailBotFaceView` di luar layar. Electron menerima frame lewat koneksi lokal per sesi dan mengirimnya sebagai track video canvas ke Meet. Perintah sesi tetap memakai kanal yang sudah ada, dan meter mic virtual menjadi sumber gerakan mulut.

**Tech Stack:** macOS 14+, SwiftUI `ImageRenderer`, Network.framework, Electron, Node `net`, Web Audio, WebRTC, XCTest, `node:test`.

**Spec:** [Desain avatar Nail di Google Meet](../specs/2026-11-23-google-meet-nail-avatar-design.md).

## Global Constraints

- Versi pertama mencakup Google Meet dan memakai wajah penuh dari HUD macOS.
- Avatar aktif otomatis setiap kali Nail berhasil masuk rapat. Pilihan kontrol berlaku untuk rapat yang sedang berjalan dan kembali aktif pada rapat baru.
- Tombol **Avatar di rapat** di aplikasi macOS bisa mematikan atau menyalakan video Nail selama rapat.
- Saat Nail berbicara, gerakan mulut mengikuti keras-pelannya audio keluar. Mulut kembali ke posisi diam saat jeda dan sejak frame berikutnya setelah interupsi diproses.
- Batasi sumber kamera sintetis ke sesi bot di `https://meet.google.com`. Sumbernya hanya piksel yang dihasilkan oleh komponen wajah. Request video tidak diteruskan ke webcam fisik, termasuk ketika avatar gagal.
- Pertahankan audio dan notulen saat video gagal atau dimatikan. Jalur Google login, lobi, dan Microsoft Teams mengikuti alur yang berlaku.

## Review Focus

- Host menolak video atau kontrol kamera hilang. Status menunjukkan avatar tidak tersedia dan audio terus berjalan (Tugas 3).
- Tombol berubah cepat atau respons dari permintaan sebelumnya datang belakangan. Pilihan terakhir menentukan keadaan (Tugas 3).
- Renderer lebih lambat daripada produsen frame atau koneksi lama masih mengirim. Frame usang dibuang tanpa menghambat perintah rapat (Tugas 2).
- Permintaan gabungan audio dan video datang saat avatar tidak tersedia. Permintaan audio berikutnya tetap memakai mic virtual dan kamera fisik tetap tertutup (Tugas 3).
- Pembacaan meter berhenti, atau ada sampel tertunda sesudah interupsi. Mulut tetap diam sampai data dari giliran bicara baru tersedia (Tugas 4).

---

## Peta file

| File | Tanggung jawab |
| --- | --- |
| `NAIL/UI/NailTheme.swift`, `NAIL/UI/HUDView.swift` | Komponen wajah dan aturan ekspresi bersama. Pratinjau tetap hanya di HUD. |
| `NAIL/Speech/MeetAvatar.swift` | Parameter frame, jadwal render, koneksi frame sesi, dan kondisi avatar yang dibaca SwiftUI. |
| `NAIL/Speech/MeetSession.swift` | Menyiapkan kanal saat meluncurkan bot, meneruskan kondisi sesi dan meter, mengirim pilihan pengguna, serta menutup kanal. |
| `NAIL/Resources/meet-avatar.cjs` | Menerima frame lokal, mengatur batas antrean, dan menyelaraskan permintaan dengan kondisi kamera. |
| `NAIL/Resources/meet.cjs`, `NAIL/Resources/meet-media.cjs` | Membaca kontrol kamera Meet, merender frame ke canvas, menyediakan track sintetis, dan membaca tingkat audio keluar. |
| `NAIL/UI/MainWindowView.swift` | Menampilkan kontrol dan status **Avatar di rapat** pada sesi Meet yang sudah masuk. |
| `NAIL.xcodeproj/project.pbxproj`, `NAILTests/MeetAvatarTests.swift`, `NAILTests/meet-avatar.test.cjs` | Keanggotaan target Swift dan bundel resource, serta tes regresi avatar. |

Jalankan perintah dari akar repo. Gunakan `-only-testing:NAILTests/MeetAvatarTests` untuk fokus XCTest dan hilangkan opsi itu untuk regresi penuh. Workspace sekarang belum punya commit awal dan akses direktori `.git` di sesi ini hanya baca. Langkah commit di bawah berlaku setelah tersedia baseline dan akses tulis. Stage hanya file terkait.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project NAIL.xcodeproj -scheme NAIL -destination 'platform=macOS' \
  -derivedDataPath /tmp/nail-avatar-xcode CODE_SIGNING_ALLOWED=NO \
  -only-testing:NAILTests/MeetAvatarTests test
```

### Tugas 1 — Buktikan jalur kamera dengan peserta kedua

**File yang ditelusuri** `NAIL/UI/NailTheme.swift`, `NAIL/Speech/MeetSession.swift`, `NAIL/Resources/meet.cjs`, `NAIL/Resources/meet-media.cjs`. Buat perubahan uji sementara di salinan kerja yang dapat dibuang.

**Antarmuka** Membaca `NailBotFaceView(mood: .standby, form: .fullFace, …)` dari Swift. Menghasilkan bukti bahwa `canvas.captureStream()` bisa mengisi kotak peserta Meet di jalur bot yang sekarang.

- [ ] Render dua frame wajah Nail dari SwiftUI dengan mood `.standby` dan `.processing`, lalu kirim bergantian ke canvas pada alur bot Google Meet. Berikan hanya track sintetis saat Meet meminta video. Biarkan secure context, pemisahan konteks Electron, penolakan kamera hardware, dan jalur mic virtual tetap aktif.
- [ ] Pada sebuah rapat uji dengan peserta kedua, nyalakan video Nail, amati perubahan gambar dari sisi penerima, matikan video hingga avatar bawaan muncul, lalu nyalakan video kembali. Putar jawaban Nail selama pengujian. Catat apakah suara tetap terdengar dan apakah privacy indicator webcam Mac tetap mati.
- [ ] Catat dalam hasil Tugas 1 apakah Meet memerlukan perangkat `videoinput` sintetis dan pemberitahuan `devicechange`, kapan Meet meminta track, dan bagaimana kondisi video diverifikasi. Bila Meet menolak track atau audio terganggu, telusuri negosiasi video sebelum mengerjakan integrasi atau menyatakan jalur siap. Buang perubahan khusus uji setelah mencatat hasilnya.

### Tugas 2 — Render wajah dan kirim frame melalui koneksi lokal

**File** Buat `NAIL/Speech/MeetAvatar.swift`, `NAIL/Resources/meet-avatar.cjs`, `NAILTests/MeetAvatarTests.swift`, `NAILTests/meet-avatar.test.cjs`. Ubah `NAIL/UI/NailTheme.swift`, `NAIL/UI/HUDView.swift`, `NAIL.xcodeproj/project.pbxproj`.

**Antarmuka** `NailBotMood.forSession(_:visualState:isSpeaking:isActivelyListening:hasNotesError:) -> NailBotMood` memakai `SessionPresentation` untuk argumen pertama. `NailBotFaceView` menerima `framePose: NailBotFacePose? = nil` dengan `blinkScaleY: CGFloat` dan `glanceX: CGFloat`. `@MainActor MeetAvatarRenderer.renderPNG(_ frame: MeetAvatarFrame) -> Data?` menerima `mood: NailBotMood`, `phase: Double`, `speakingEnergy: Double`, `listeningEnergy: Double`, dan `pose: NailBotFacePose`. `MeetAvatarTransport.connect(path: String)`, `offer(revision: UInt32, png: Data)`, dan `close()` mengirim frame. `listenForAvatarFrames(path, onFrame)` mengembalikan server dengan `close()`, dan memanggil `onFrame(revision, pngBuffer) -> Promise<boolean>`.

- [ ] Tambahkan tes `testSessionMoodKeepsExistingPriority` yang memeriksa status siaga, menyimak, berpikir, berbicara, interupsi dan gangguan. Tambahkan `testAvatarRenderChangesWithBlinkPose` yang merender dua frame berukuran sama lalu memeriksa dimensi `320 × 320` dan piksel berbeda. Di Node, gunakan koneksi lokal yang memecah header menjadi dua potongan dan menunda jawaban `onFrame`. Verifikasi satu callback aktif, frame terbaru yang menunggu menggantikan frame yang lebih lama, payload melebihi `1 MiB` ditolak, dan penutupan menghentikan pengiriman.
- [ ] Jalankan XCTest fokus dan `node --test NAILTests/meet-avatar.test.cjs`. Harapkan kegagalan karena renderer dan koneksi frame belum tersedia.
- [ ] Ekstrak pemetaan ekspresi dari `HUDView` ke `NailBotMood.forSession`. Pertahankan pemetaan khusus pratinjau di awal logika HUD. Pakai masukan kedipan eksplisit saat merender frame. Tanpa masukan tersebut, `NailBotFaceView` tetap mengelola animasi dengan siklus HUD yang ada.
- [ ] Implementasikan `renderPNG` dengan `ImageRenderer` pada ukuran awal `320 × 320`, wajah `.fullFace` di tengah, ruang aman di sekitar wajah, dan latar `#0A0A0A`. Render hanya saat sesi avatar meminta frame. Hubungkan file Swift dan tes ke target yang sesuai, lalu masukkan resource CJS ke bundle.
- [ ] Implementasikan koneksi Unix per sesi dalam direktori privat mode `0700`. Gunakan path pendek dan buka server dari Electron. Tiap pesan frame berisi revisi `UInt32` big-endian, panjang PNG `UInt32` big-endian, dan payload PNG hingga `1 MiB`. Electron membalas satu byte `1` untuk frame yang digambar atau `0` untuk frame yang dilewati. Swift menyimpan satu frame terbaru sambil menunggu balasan. Saat sesi atau koneksi berhenti, batalkan kiriman dan lepas handle.
- [ ] Jalankan kembali kedua rangkaian tes. Harapkan `** TEST SUCCEEDED **` dan `fail 0`. Commit `feat: render and transport shared Nail avatar frames` jika Git siap.

### Tugas 3 — Hubungkan video, kondisi rapat, dan tombol avatar

**File** Ubah `NAIL/Speech/MeetAvatar.swift`, `NAIL/Speech/MeetSession.swift`, `NAIL/Resources/meet-avatar.cjs`, `NAIL/Resources/meet.cjs`, `NAIL/Resources/meet-media.cjs`, `NAIL/UI/MainWindowView.swift`, dan kedua file tes avatar.

**Antarmuka** `MeetSession.meetingAvatarState: MeetingAvatarState` dan `MeetSession.setMeetingAvatarEnabled(_ enabled: Bool)`. Kondisi adalah `.off`, `.starting`, `.on`, `.stopping`, dan `.unavailable`. Perintah `avatar-set {revision,enabled}` memakai stdin. Worker mengirim `avatar-state {revision,state}` di stdout. `__nailMedia.prepareAvatarCamera(revision)` menyiapkan canvas, `drawAvatarFrame(revision, base64PNG) -> Promise<boolean>` menggambar frame terbaru, dan `stopAvatarCamera(revision)` menghentikan track. `createMeetAvatarController({prepare, setCamera, stop, emitState})` menghasilkan `request({revision, enabled})`, `frameReady(revision)`, dan `close()` untuk logika yang bisa diuji dengan fungsi pengganti.

- [ ] Tambahkan tes Node yang mengirim `request(on, rev 1)`, `request(off, rev 2)` lalu konfirmasi dari rev 1. Pastikan kondisi akhir `.off` dan frame rev 1 ditolak. Tambahkan kasus host menolak kamera dan `getUserMedia({audio: true, video: true})` saat avatar tersedia dan saat belum tersedia. Harapkan track sintetis dan mic virtual saat tersedia, penolakan video tanpa panggilan webcam saat tidak tersedia, dan permintaan audio saja tetap berhasil. Tambahkan XCTest untuk mengabaikan status revisi lama, mereset default ke aktif setelah `joined` di sesi Meet baru, dan mengabaikan Google login serta Teams.
- [ ] Jalankan XCTest fokus dan tes Node avatar. Harapkan kasus baru gagal sampai pengendali tersedia.
- [ ] Di `MeetSession`, buat path koneksi lokal hanya untuk sesi Google Meet dan teruskan dengan `NAIL_AVATAR_SOCKET_PATH`. Worker membuka server sebelum melaporkan kondisi `.starting`. Saat menerima `joined`, minta video aktif dan mulai kirim frame setelah menerima `avatar-state` `.starting` dengan revisi yang sama. Kirim sekitar 20 fps, dengan jam milik sesi. Saat menerima `left`, proses berakhir, atau pengguna meminta keluar, hentikan render dan bersihkan socket dan direktori sesi.
- [ ] Di worker, izinkan pengendali hanya pada halaman `https://meet.google.com` sesi yang sudah masuk. Buat canvas sebelum melaporkan `.starting`. Untuk pengiriman pertama, pakai `webContents.executeJavaScript` yang sudah dipakai worker untuk memanggil `drawAvatarFrame` dengan revisi dan PNG base64. Tunggu hasilnya sebelum membalas pengirim melalui socket. Setelah frame pertama, pakai `inspect` dan `click` untuk mengaktifkan kamera. Laporkan `.on` setelah kondisi kontrol mengonfirmasi kamera aktif. Untuk `.off` dan kegagalan, hentikan track dan nonaktifkan kamera jika diperlukan. Beri batas awal tiga detik untuk konfirmasi perubahan. Serialkan aksi kamera agar penyelesaian lama tidak membatalkan pilihan yang lebih baru.
- [ ] Di `meet-media.cjs`, kembalikan track canvas untuk permintaan video Nail yang valid. Daftarkan `videoinput` sintetis saat avatar siap jika Tugas 1 menunjukkan Meet memerlukannya. Untuk audio dan video yang diminta bersamaan, gabungkan track canvas dan mic virtual. Jika video tidak tersedia, kembalikan penolakan video yang jelas tanpa memanggil implementasi webcam. Pertahankan jalur izin hardware yang sudah ada. Hapus track dan frame terkait saat dimatikan. Jika koneksi atau render gagal, publikasikan `.unavailable` dan pertahankan audio.
- [ ] Di `MainWindowView`, letakkan **Avatar di rapat** dekat kontrol sesi. Tampilkan kondisi sementara saat menunggu konfirmasi, berikan cara untuk membalik pilihan, dan tampilkan **Avatar tidak tersedia** saat gagal dengan aksi coba lagi lewat kontrol yang sama.
- [ ] Jalankan ulang tes fokus Swift dan Node. Ulangi pengujian peserta kedua dari Tugas 1 dengan tombol aplikasi. Periksa cepat on–off–on, pembatasan video host, audio sepanjang pergantian video, pergantian sesi, dan keluar saat video aktif. Commit `feat: publish and control the avatar in Google Meet` jika Git siap.

### Tugas 4 — Sinkronkan gerakan mulut dengan audio keluar

**File** Ubah `NAIL/UI/NailTheme.swift`, `NAIL/Speech/MeetAvatar.swift`, `NAIL/Speech/MeetSession.swift`, `NAIL/Resources/meet-media.cjs`, `NAIL/Resources/meet.cjs`, dan kedua file tes avatar.

**Antarmuka** `__nailMedia.avatarAudioSample() -> {rms, sending}` memakai meter yang sudah terhubung ke `micBus`. Event `avatar-audio {revision,turn,rms,sending}` memakai stdout. `AvatarSpeechEnvelope.ingest(rms: Double, turn: UInt64, at: TimeInterval)`, `stop(throughTurn: UInt64)`, dan `energy(at: TimeInterval) -> Double` memakai waktu monotonik lokal. `NailBotFaceView` menerima `speechLevel: Double? = nil` untuk mengatur bukaan mulut saat `.speaking`.

- [ ] Tulis `testSpeechEnvelopeClosesOnSilenceAndInterrupt` dan `testSpeechEnvelopeDropsStaleSamples`. Uji tingkat rendah menghasilkan bukaan yang lebih kecil dari tingkat tinggi, tingkat nol menutup, setelah `150 ms` tanpa data nilainya nol, dan sampel dari giliran yang sudah diinterupsi diabaikan. Tambahkan tes Node untuk meter hanya berjalan saat avatar dan pemutaran aktif, lalu mengirim nol saat mute, stop, atau interupsi.
- [ ] Jalankan XCTest fokus dan tes Node avatar. Harapkan kegagalan untuk envelope atau event audio yang belum tersedia.
- [ ] Baca `measureMicRms()` di sisi bot setelah gain keluaran. Kirim sampel dengan revisi avatar dan nomor giliran, sekitar 20 kali per detik. Ikuti kondisi mute Meet dan kondisi pemutaran aktual. Pada mute, interupsi, atau akhir pemutaran, segera publikasikan `sending: false` dengan tingkat nol. Hentikan sampling saat avatar nonaktif atau sesi berakhir.
- [ ] Di Swift, tolak revisi dan giliran lama. Ratakan perubahan ringan untuk sampel positif dan nolkan nilai saat hening, akhir pemutaran, mute, interupsi, atau data lewat `150 ms`. Perbarui frame berikutnya saat interupsi dan abaikan hasil render tertunda dari giliran itu. Saat `speechLevel` diberikan ke wajah bersama, skalakan bukaan dan amplitudo bar mulut dengan nilai itu hingga mencapai posisi diam. Pertahankan animasi HUD yang ada bagi pemanggil dengan `speechLevel == nil`.
- [ ] Jalankan XCTest penuh, `node --test NAILTests/*.test.cjs`, `node --check` pada tiga resource CJS yang berubah, dan build aplikasi. Harapkan tes Swift dan Node lulus, pemeriksaan sintaks keluar dengan kode 0, dan build menyediakan bundle `Meet Nail.app` dengan resource avatar.
- [ ] Dalam rapat uji dengan pengamat, periksa perubahan ekspresi saat siaga, menyimak, berpikir, berbicara, dan interupsi. Uji paket suara Codex Live Voice, Antigravity, dan DeepSeek pada volume berbeda dan jeda. Ulangi dengan jendela utama ditutup atau HUD disembunyikan. Cek bahwa toggle video dan notulen tetap berfungsi dan render berhenti saat keluar. Catat hasil per penyedia dan simpan temuan yang belum terbukti sebagai verifikasi tertunda. Commit `feat: time Nail avatar speech to outgoing audio` jika Git siap.

## Referensi API

- Render bitmap SwiftUI. [Apple ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer)
- Jalur socket lokal. [Apple NWEndpoint](https://developer.apple.com/documentation/network/nwendpoint/unix%28path%3A%29) · [Node IPC](https://nodejs.org/api/net.html#ipc-support)
- Pengiriman frame ke renderer Electron dan track canvas. [Electron IPC](https://www.electronjs.org/docs/latest/tutorial/ipc) · [Media Capture from DOM Elements](https://www.w3.org/TR/mediacapture-fromelement/#html-canvas-element-media-capture-extensions)
