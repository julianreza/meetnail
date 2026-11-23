# Target latensi diukur dari akhir ucapan ke byte audio pertama

**Status**: accepted; premis spekulasi dicabut oleh [ADR 0007](0007-deepseek-for-speech-and-brain.md). Definisi pengukuran tetap berlaku.

Untuk Perintah tanpa tool, targetkan p50 ≤ 1,3 detik dan p90 ≤ 2,0 detik dari akhir ucapan Pemilik ke byte audio pertama yang bukan filler. Catat waktu sampai suara pertama terdengar di perangkat Peserta secara terpisah.

Mulai dengan endpointing 500 ms agar jeda deteksi tidak memakan sebagian besar target. LLM boleh menyiapkan respons dari transkrip interim setelah frasa pemicu; jangan jalankan tool atau perdengarkan hasil spekulatif sebelum Perintah final.
