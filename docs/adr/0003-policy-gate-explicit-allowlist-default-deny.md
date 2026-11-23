# Policy Gate memakai allowlist eksplisit, default DENY

**Status**: accepted

Pola `write_*` dan `delete_*` tidak mencakup operasi filesystem seperti `edit_file` dan `move_file`. Daftarkan operasi secara eksplisit per server atau integrasi. Tool tak terdaftar ditolak sebelum meminta Persetujuan; Merah berlaku hanya untuk operasi yang sudah terdaftar. Jalankan server filesystem dengan `--read-only` kecuali akses tulis dibutuhkan untuk direktori kerja yang disetujui.

Anotasi MCP (`readOnlyHint`, `destructiveHint`) tidak dipakai sebagai pengaman karena spec menyatakannya sebagai hint yang tidak tepercaya — server bisa berbohong. Anotasi hanya boleh memengaruhi tampilan, bukan keputusan eksekusi.
