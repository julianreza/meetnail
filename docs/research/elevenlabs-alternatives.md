# Alternatif ElevenLabs untuk TTS NAIL

23 November 2026. Harga dalam USD berdasarkan dokumentasi penyedia. Kualitas aksen dan latensi di Meet atau Teams belum diukur.

## Pilihan untuk NAIL

**Azure Speech** adalah pilihan dengan perubahan terkecil untuk jalur Antigravity. Azure menyediakan `id-ID-GadisNeural` dan `id-ID-ArdiNeural`, dua suara yang bisa dipilih NAIL sekarang melalui `edge-tts`. REST Azure dapat langsung mengembalikan WAV PCM mono 24 kHz. Pemutar NAIL mendekode WAV melalui `decodeAudioData`, sehingga jalur ini dapat memakai respons Azure dan melewati konversi MP3 lewat FFmpeg. Paket F0 mencakup 500.000 karakter Neural per bulan. Harga berbayar mengikuti wilayah Azure. [Daftar suara](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts) · [REST TTS](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech) · [Harga Azure](https://azure.microsoft.com/en-us/pricing/details/speech/)

**Inworld Realtime TTS-2 Flash** adalah kandidat pertama untuk uji streaming. WebSocket menerima teks bertahap dan mengirim audio ketika sintesis berjalan. `cancelContext` menghentikan sintesis yang masih berjalan, dan klien harus langsung menghentikan pemutaran serta membuang potongan audio terlambat. Model Flash dan TTS-2 mendukung `id-ID` di Tier 2. Inworld menyebut hasil Tier 2 lebih bervariasi menurut bahasa dan suara. Harga On-Demand $15 per juta karakter untuk Flash dan $25 untuk TTS-2. [Bahasa](https://docs.inworld.ai/tts/capabilities/multilingual) · [WebSocket](https://docs.inworld.ai/tts/synthesize-speech-websocket) · [Harga Inworld](https://inworld.ai/pricing)

| Penyedia | Bahasa Indonesia dan streaming | Harga publik |
| --- | --- | --- |
| Google Cloud Chirp 3: HD | `id-ID`, pilihan suara berlabel Indonesia, dan streaming teks/audio dua arah dengan PCM. Region `asia-southeast1` tersedia. [Suara dan format](https://docs.cloud.google.com/text-to-speech/docs/chirp3-hd) · [Panduan streaming](https://docs.cloud.google.com/text-to-speech/docs/create-audio-text-streaming) | 1 juta karakter per bulan gratis, lalu $30 per juta. [Harga Google](https://cloud.google.com/text-to-speech/pricing) |
| Cartesia Sonic 3.6 | `id`, WebSocket dengan teks bertahap, keluaran PCM, dan pembatalan berdasarkan konteks. [Model](https://docs.cartesia.ai/build-with-cartesia/tts-models/latest) · [WebSocket](https://docs.cartesia.ai/api-reference/tts/websocket) | 20.000 kredit per bulan di Free dan 100.000 kredit per bulan di Pro seharga $5. TTS memakai sekitar satu kredit per karakter. [Paket Cartesia](https://www.cartesia.ai/pricing) · [Penggunaan kredit](https://docs.cartesia.ai/pricing) |
| ElevenLabs v4 Turbo | `id` dan WebSocket Text to Dialogue. [Model](https://elevenlabs.io/docs/overview/models/) | $0,04 per 1.000 karakter atau $40 per juta pada harga yang tercantum. [Harga ElevenLabs](https://elevenlabs.io/pricing/api) |

## Dampak pada jalur suara NAIL

Antigravity menunggu teks jawaban selesai dan menghasilkan file WAV sebelum mengirim seluruh audio ke pemutar Meet atau Teams. Mengganti penyedia bisa mengubah suara dan waktu sintesis. Agar peserta mendengar jawaban lebih awal, jalur ini perlu meneruskan potongan teks ke penyedia dan memainkan potongan audio saat tiba. Jalur Codex Live Voice memakai WebRTC tersendiri. macOS `say` dengan Damayanti sudah tersedia sebagai cadangan lokal. [Sintesis Antigravity](../../NAIL/Resources/agy-voice.py#L501) · [Pengiriman audio](../../NAIL/Resources/meet.cjs#L1607) · [Dekoder](../../NAIL/Resources/meet-media.cjs#L891) · [Rencana NAIL](../../Project%20Nail%20Execution%20Plan.md#L11)

Untuk memilih suara, bandingkan Azure Gadis/Ardi, Inworld Flash, dan Google Chirp dengan jawaban formal dan santai yang sama. Sertakan nama orang, singkatan, angka rupiah, dan kalimat campur Inggris. Untuk streaming, ukur waktu dari akhir ucapan sampai audio pertama terdengar di perangkat peserta lain, serta waktu sampai audio berhenti setelah interupsi.
