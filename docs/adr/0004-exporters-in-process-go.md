# Ekspor Notulen dijalankan di dalam proses Go, bukan sebagai MCP server sendiri

**Status**: superseded by [ADR 0006](0006-native-macos-stack.md). Keputusan in-process tetap berlaku; bahasa implementasi berubah ke Swift.

Blueprint menempatkan Notifier (MD lokal, Discord, Slack, email) sebagai MCP server Node terpisah. MCP membeli plug-and-play untuk server pihak ketiga, tetapi untuk kode yang kami tulis sendiri ia hanya menambah runtime Node, satu proses tambahan, satu jalur IPC, dan satu permukaan serangan baru. Ekspor karena itu ditulis langsung di `internal/exporter` dan dipanggil lewat Policy Gate yang sama; MCP tetap dipakai untuk Notion dan sumber data pihak ketiga.
