# DeepSeek untuk telinga, otak, dan mulut

**Status**: accepted

Setelah Deepgram/Cartesia/Gemini diuji, DeepSeek ternyata menutup ketiga peran dengan satu API key yang sudah dimiliki Pemilik. Diukur dari Mac uji: ASR klip 3,3 detik selesai dalam 1,04–1,27 detik dengan transkrip benar; TTS 6,04 detik audio mengirim byte pertama pada 1,12 detik dan selesai 1,78 detik; TTS→ASR mengembalikan teks yang identik. Bahasa Indonesia didukung di ASR maupun TTS.

Konsekuensi yang diterima: ASR tidak streaming dan dibatasi 120 detik per request, jadi transkrip muncul per potongan dan tidak ada transkrip interim. Premis spekulasi di [ADR 0005](0005-latency-target-and-speculative-start.md) dicabut; target latensi harus diukur ulang di Fase 1, bukan diwarisi dari pipeline streaming. TTS tidak punya kontrol kecepatan.

Biaya: ASR $0.058/jam, TTS $0.225/10k karakter, `deepseek-flash` $0.15/M input. Satu jam rapat kira-kira $0.06, dibandingkan sekitar $0.50 untuk Deepgram + Cartesia. Konsekuensi lain: tiga peran bergantung pada satu vendor, dan audio serta teks tetap keluar dari mesin.
