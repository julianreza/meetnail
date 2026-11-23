# Otorisasi Write: asal kanal Pemilik, bukan diarization

**Status**: accepted

Perintah hanya diterima dari Kanal Pemilik, dan diarization tidak pernah menjadi dasar otorisasi. Asal kanal adalah syarat perlu, bukan bukti identitas: siapa pun yang duduk di depan mesin selama Sesi berjalan dapat memberi Perintah, dan itu dinyatakan sebagai asumsi, bukan disamarkan dengan kata "identitas".

Kanal Pemilik dapat terkontaminasi suara Peserta lewat speaker. Nail menjalankan acoustic echo cancellation pada cabang STT dan wake word dengan sinyal tap sebagai referensi, sementara audio mentah yang dikirim ke rapat tidak diproses. Bila uji Fase 0 menunjukkan sisa kebocoran di atas ambang, Zona Kuning dan Merah dinonaktifkan sampai headset dipasang.

Ucapan Peserta, dokumen, dan keluaran tool adalah Konten. Konten boleh memberi konteks atau mengisi argumen dalam ruang lingkup Perintah, tetapi tidak boleh memulai aksi, memberi Persetujuan, atau mengubah aturan di system prompt.
