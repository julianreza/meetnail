# Avatar Nail di Google Meet

23 November 2026 · Usulan untuk ditinjau

## Tujuan

Peserta Google Meet melihat karakter Nail di kotak pesertanya, di tempat yang saat ini menampilkan inisial **N**. Karakter membantu peserta melihat kapan Nail sedang siaga, menyimak giliran bicara, menyiapkan jawaban, atau berbicara. Versi pertama mencakup Google Meet dan memakai wajah penuh dari HUD macOS.

## Perilaku yang disepakati

- Avatar aktif otomatis setiap kali Nail berhasil masuk rapat. Saat siaga, wajah tetap tampil dan sesekali berkedip.
- Saat Nail menyimak giliran bicara atau menyiapkan jawaban, avatar mengikuti ekspresi HUD. Percakapan umum saat Nail siaga tetap menampilkan ekspresi siaga.
- Saat Nail berbicara, gerakan mulut mengikuti keras-pelannya audio keluar. Mulut kembali ke posisi diam saat jeda dan sejak frame berikutnya setelah interupsi diproses. Sinkronisasi mengikuti volume suara tanpa pemetaan fonem.
- Tombol **Avatar di rapat** di aplikasi macOS bisa mematikan atau menyalakan video Nail selama rapat. Saat video dimatikan, Meet menampilkan avatar bawaan peserta, yang saat ini berupa inisial **N**. Nail tetap bisa menyimak, mencatat, dan berbicara.

## Pendekatan

1. **Gambar ulang wajah di Electron.** Canvas bisa membuat animasi langsung di proses rapat, dengan jalur data yang pendek. Perubahan bentuk wajah, warna, dan ekspresi di SwiftUI akan perlu diselaraskan ke gambar Electron.
2. **Render komponen wajah SwiftUI.** Aplikasi macOS menggambar `NailBotFaceView` yang dipakai HUD dan meneruskan frame ke Electron. Perubahan pada komponen wajah tampil di kedua tempat. Ada tambahan pekerjaan untuk menjaga aliran frame tetap lancar dan selaras dengan audio. Ini pendekatan yang dipilih pengguna.

## Rancangan teknis

### Animasi dan audio

Gunakan `NailBotFaceView` dengan bentuk `.fullFace`. Pusatkan wajah dengan ruang di sekelilingnya agar tetap terlihat ketika Meet memangkas kotak peserta. Latar video gelap polos. HUD dan video memakai logika status wajah yang sama, termasuk prioritas untuk interupsi dan gangguan. Mode pratinjau HUD tetap lokal ke HUD.

Komponen wajah saat ini menyimpan kedipan dan lirikan di `@State` yang digerakkan oleh `.task`. Jadikan nilai visual tersebut bisa diterima sebagai masukan per frame agar render di luar layar bisa memakai bentuk dan ekspresi yang sama. Jam animasi video hidup selama video avatar aktif dan berjalan saat HUD disembunyikan. Coba `ImageRenderer` untuk merender frame SwiftUI dengan fase, kedipan, dan tingkat audio yang diketahui. Jaga beban render tetap terbatas agar kontrol rapat di macOS tetap responsif. [Komponen wajah](../../../NAIL/UI/NailTheme.swift#L1949) · [Status wajah HUD](../../../NAIL/UI/HUDView.swift#L577) · [Apple ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer)

Ambil tingkat audio dari meter `micBus` di Electron, setelah pengaturan volume keluaran. Jalur ini membawa audio Codex Live Voice maupun hasil sintesis suara Antigravity dan DeepSeek. Kirim tingkat audio dan status pemutaran ke macOS. Gerakan mulut memakai tingkat audio yang dibatasi dan diratakan secara ringan. Hening, mute, interupsi, dan akhir pemutaran membersihkan nilai gerakan mulut. Jika data meter terhenti, mulut menutup sampai ada nilai baru. [Meter audio keluar](../../../NAIL/Resources/meet-media.cjs#L519) · [Pemutaran jawaban](../../../NAIL/Resources/meet-media.cjs#L883) · [Keluaran Codex](../../../NAIL/Resources/meet-media.cjs#L941)

### Pengiriman video

Electron menerima frame dari aplikasi macOS melalui jalur lokal dan menyalinnya ke canvas. Canvas menghasilkan satu track video sintetis yang diberikan ke Google Meet sebagai kamera Nail. Batasi kiriman frame ke proses rapat yang aktif. Gunakan antrean yang hanya menyimpan frame terbaru agar renderer lambat tidak menambah jeda. Perintah rapat dan sampel meter tetap bisa diproses saat frame video tertunda. Builder memilih format frame, mekanisme IPC, dan laju frame berdasarkan pengukuran. Target awal untuk pengujian adalah sekitar 20 frame per detik dengan frame berukuran cukup untuk kotak peserta. [Proses Electron yang digunakan Nail](../../../NAIL/Speech/MeetSession.swift#L356) · [IPC Electron](https://www.electronjs.org/docs/latest/tutorial/ipc) · [Spesifikasi video canvas](https://www.w3.org/TR/mediacapture-fromelement/#html-canvas-element-media-capture-extensions)

Batasi sumber kamera sintetis ke sesi bot di `https://meet.google.com`. Sumbernya hanya piksel yang dihasilkan oleh komponen wajah. Request video tidak diteruskan ke webcam fisik, termasuk ketika avatar gagal. Permintaan audio dan video bersamaan memakai mic virtual yang sudah ada dan track avatar ketika tersedia. Selama login, di lobi, dan pada versi Teams saat ini, perilaku media mengikuti alur yang berlaku. Jalur video sintetis ini perlu dibuktikan dari sisi peserta Google Meet. [Izin media bot](../../../NAIL/Resources/meet.cjs#L1715) · [Sumber media bot](../../../NAIL/Resources/meet-media.cjs#L593) · [Kontrol video Google Meet](https://support.google.com/meet/answer/10409699?co=GENIE.Platform%3DDesktop)

### Kontrol dan pemulihan

Tempatkan kontrol avatar bersama kontrol rapat di jendela utama. Tampilkan kondisi yang dikonfirmasi oleh bot. Saat dinyalakan, siapkan frame pertama sebelum meminta Meet mengaktifkan video. Saat dimatikan, nonaktifkan video di Meet dan hentikan sumber frame, track, serta sampling yang khusus untuk avatar. Tindakan terakhir pengguna berlaku ketika tombol diubah berulang kali. Pilihan berlaku untuk rapat yang sedang berjalan dan kembali aktif pada rapat baru. Jika pembatasan host, kegagalan render, atau kegagalan pengiriman menghalangi video, Nail tetap memakai audio dan aplikasi memberi tahu bahwa avatar tidak tersedia. Pengguna bisa mencoba lagi selama rapat. Saat keluar atau proses bot berhenti, lepaskan seluruh sumber daya avatar dan abaikan frame dari sesi lama.

## Cakupan dan kriteria penerimaan

- Verifikasi pertama setelah desain disetujui adalah mengirim frame SwiftUI sintetis ke satu rapat uji dan melihatnya dari akun atau browser peserta kedua. Uji ini harus membuktikan tile video bisa aktif dan kembali ke avatar bawaan ketika dimatikan, sambil mempertahankan audio Nail.
- Dalam rapat uji, wajah Nail terlihat sejak bot masuk. Pengamat dapat membedakan kondisi siaga, menyimak, berpikir, dan berbicara. Berpindah tab, menutup jendela utama, atau menyembunyikan HUD tidak membekukan animasi selama sesi aktif.
- Uji perubahan ekspresi selama jawaban Codex Live Voice dan hasil sintesis suara Antigravity atau DeepSeek. Periksa mulut saat audio lemah dan kuat, pada jeda, serta setelah interupsi. Cek dua jalur sintesis suara sebelum menyatakan ketiga penyedia terverifikasi.
- Matikan, nyalakan kembali, dan ubah kontrol dengan cepat selama rapat. Verifikasi dari sisi peserta bahwa video mengikuti pilihan terakhir, audio tetap berjalan, dan sesi berikutnya kembali memakai avatar otomatis.
- Uji rapat dengan video dibatasi host serta skenario keluar ketika animasi aktif. Cek bahwa kamera fisik tetap tertutup, audio tetap tersedia saat video gagal, dan proses render berhenti setelah sesi berakhir.
- Microsoft Teams, pengubahan foto profil, tangkapan layar atau webcam, dan animasi fonem berada di luar cakupan versi ini.
