# Project NAIL

Asisten rapat yang menyimak percakapan, menjawab lewat suara, dan membantu Pemilik mencatat atau menjalankan aksi.

## Bahasa

**Nail**:
Nama produk sekaligus persona asisten yang berjalan di komputer Pemilik.
_Avoid_: bot, assistant, agent

**Sesi**:
Satu rentang waktu ketika Nail menyimak, dari mulai menyimak sampai Notulen diekspor.
_Avoid_: meeting, run, call

**Rapat**:
Percakapan manusia yang disimak Nail di dalam sebuah Sesi.
_Avoid_: meeting, call

**Pemilik**:
Orang yang memulai Sesi di mesin itu dan diasumsikan hadir selama Sesi berjalan. Asal kanal tidak membuktikan identitasnya.
_Avoid_: user, host, operator, admin

**Peserta**:
Semua orang di Rapat selain Pemilik.
_Avoid_: guest, attendee, other speaker

**Perintah**:
Ucapan Pemilik di Kanal Pemilik yang meminta Nail melakukan sesuatu. Hanya Perintah yang boleh memicu aksi.
_Avoid_: request, instruction, prompt

**Frasa Pemicu**:
Kata atau frasa yang membuka Perintah. Hanya didengarkan di Kanal Pemilik.
_Avoid_: wake word, hotword

**Konten**:
Materi tak tepercaya yang dibaca Nail: ucapan Peserta, isi dokumen, dan keluaran tool. Konten tidak pernah memicu aksi.
_Avoid_: input, context, data, prompt

**Kanal Pemilik**:
Jalur audio masukan yang membawa suara Pemilik. Asal kanal adalah sinyal provenance, bukan bukti identitas.
_Avoid_: mic channel, owner stream

**Kanal Rapat**:
Jalur audio masukan yang memuat suara Peserta.
_Avoid_: meeting stream, system audio

**Persona**:
Gaya bicara Nail yang sedang aktif.
_Avoid_: mode, vibe, bunglon

**Suasana**:
Kategori situasi Rapat yang disimpulkan Nail dan menjadi dasar pemilihan Persona.
_Avoid_: vibe, mood, context

**Zona**:
Tingkat bahaya sebuah aksi tool, yang menentukan mekanisme Persetujuan yang berlaku.
_Avoid_: level, tier, risk class

**Persetujuan**:
Keputusan eksplisit Pemilik untuk menjalankan aksi Zona Kuning atau Zona Merah.
_Avoid_: approval, konfirmasi, izin

**Panic Mute**:
Tindakan Pemilik untuk menghentikan TTS dan membatalkan antrean aksi, tanpa memutus jalur suara Pemilik ke Rapat.
_Avoid_: mute all, kill switch

**Rangkuman Berjalan**:
Ringkasan Sesi yang diperbarui berkala selama Rapat berlangsung.
_Avoid_: rolling summary, ringkasan

**Notulen**:
Artefak yang dihasilkan setelah Sesi berakhir, dengan isi dan format berbeda per tujuan distribusi.
_Avoid_: minutes, laporan, summary

**HUD**:
Permukaan visual di layar Pemilik yang menampilkan detail yang sengaja tidak diucapkan.
_Avoid_: overlay, panel, popup
