# Gunakan Swift native untuk NAIL di macOS

**Status**: accepted

NAIL hanya menargetkan macOS ([ADR 0001](0001-macos-only-v1.md)), dan belum ada kode desktop yang perlu dipertahankan. Kami memilih SwiftUI untuk menu bar dan pengaturan, AppKit untuk HUD, serta Core Audio untuk process tap dan mixer. Dibanding Wails dengan Go dan React, stack ini menghilangkan lapisan web dan lintas bahasa tanpa mengubah kebutuhan untuk menguji izin, routing audio, dan HUD di Space fullscreen.

Process tap mengambil audio rapat; BlackHole 2ch hanya berfungsi sebagai mic virtual untuk mengirim campuran mic fisik dan TTS. Fase 0 harus membuktikan routing di Meet dan Zoom sebelum aplikasi menjanjikan dukungan konfigurasi tertentu.

ADR ini menggantikan pilihan bahasa di [ADR 0004](0004-exporters-in-process-go.md): eksportir ditulis dalam Swift dan tetap berjalan di dalam proses aplikasi. Jadikan MCP Swift SDK sebagai klien integrasi pihak ketiga; Policy Gate tetap menegakkan izin di aplikasi.
