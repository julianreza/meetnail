import Foundation
import XCTest
@testable import NAIL

final class NotulenSummaryAndBackendTests: XCTestCase {
    private var tempDirectories: [URL] = []
    private var testSuites: [String] = []

    override func tearDown() {
        MockBackendURLProtocol.reset()
        let fm = FileManager.default
        for dir in tempDirectories {
            try? fm.removeItem(at: dir)
        }
        tempDirectories.removeAll()

        for suiteName in testSuites {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        testSuites.removeAll()
        super.tearDown()
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NAILSummaryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirectories.append(dir)
        return dir
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "com.nail.tests.\(UUID().uuidString)"
        testSuites.append(suiteName)
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        return suite
    }

    private func makeSampleSummary(
        title: String = "Sprint Sync",
        executiveSummary: String = "Tim menyepakati jadwal rilis fitur notulen.",
        modelUsed: String = "gemini-3.8-flash-low"
    ) -> NotulenSummary {
        NotulenSummary(
            title: title,
            meetingDate: "2026-11-23",
            meetingLink: "https://meet.google.com/abc-defg-hij",
            executiveSummary: executiveSummary,
            keyPoints: ["Integrasi ringkasan selesai", "Backend endpoint disiapkan"],
            decisions: ["Gunakan POST JSON snake_case"],
            actionItems: [
                NotulenActionItem(id: "ai-1", task: "Deploy endpoint staging", owner: "Reza", dueDate: "Besok")
            ],
            participants: ["Reza", "Nail"],
            generatedAt: Date(timeIntervalSince1970: 1_763_890_000),
            modelUsed: modelUsed,
            sourceFileName: "2026-11-23_10-00_sprint-sync.md"
        )
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockBackendURLProtocol.setHandler(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBackendURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - parseSummaryJSON

    func testParseSummaryJSONAcceptsRawJSON() throws {
        let raw = """
        {
          "executive_summary": "Rapat membahas target Q4 dan kesiapan backend.",
          "key_points": ["Target rilis Jumat", "Integrasi API aman"],
          "decisions": ["Gunakan Bearer token di Keychain"],
          "action_items": [
            {"id": "item-42", "task": "Kirim spesifikasi API", "owner": "Budi", "due_date": "2026-11-25"}
          ],
          "participants": ["Budi", "Sari", "Budi"]
        }
        """
        let fixedDate = Date(timeIntervalSince1970: 1_763_890_200)
        let summary = try NotulenSummaryService.parseSummaryJSON(
            raw,
            title: "Sync Q4",
            meetingDate: "2026-11-23",
            meetingLink: "https://meet.google.com/abc-defg-hij",
            sourceFileName: "sync-q4.md",
            modelUsed: "gemini-3.8-flash-low",
            generatedAt: fixedDate
        )

        XCTAssertEqual(summary.title, "Sync Q4")
        XCTAssertEqual(summary.meetingDate, "2026-11-23")
        XCTAssertEqual(summary.meetingLink, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(summary.executiveSummary, "Rapat membahas target Q4 dan kesiapan backend.")
        XCTAssertEqual(summary.keyPoints, ["Target rilis Jumat", "Integrasi API aman"])
        XCTAssertEqual(summary.decisions, ["Gunakan Bearer token di Keychain"])
        XCTAssertEqual(summary.actionItems.count, 1)
        XCTAssertEqual(summary.actionItems.first?.id, "item-42")
        XCTAssertEqual(summary.actionItems.first?.task, "Kirim spesifikasi API")
        XCTAssertEqual(summary.actionItems.first?.owner, "Budi")
        XCTAssertEqual(summary.actionItems.first?.dueDate, "2026-11-25")
        XCTAssertEqual(summary.participants, ["Budi", "Sari"])
        XCTAssertEqual(summary.modelUsed, "gemini-3.8-flash-low")
        XCTAssertEqual(summary.sourceFileName, "sync-q4.md")
        XCTAssertEqual(summary.generatedAt, fixedDate)
    }

    func testParseSummaryJSONStripsMarkdownCodeFences() throws {
        let fenced = """
        ```json
        {
          "executive_summary": "Ringkasan dalam blok kode.",
          "key_points": ["Poin A"],
          "decisions": [],
          "action_items": [],
          "participants": ["Andi"]
        }
        ```
        """

        let summary = try NotulenSummaryService.parseSummaryJSON(
            fenced,
            title: "Weekly",
            meetingDate: nil,
            meetingLink: nil,
            sourceFileName: "weekly.md",
            modelUsed: "gemini-4-neon-low"
        )

        XCTAssertEqual(summary.executiveSummary, "Ringkasan dalam blok kode.")
        XCTAssertEqual(summary.keyPoints, ["Poin A"])
        XCTAssertEqual(summary.participants, ["Andi"])
    }

    func testParseSummaryJSONExtractsObjectFromProseWrapper() throws {
        let wrapped = """
        Berikut adalah hasil ringkasan rapat yang diminta:
        {
          "executive_summary": "Diskusi tentang {skema} dan migrasi server.",
          "key_points": ["Migrasi akhir pekan"],
          "decisions": ["Pakai database utama"],
          "action_items": [],
          "participants": ["Dina"]
        }
        Semoga membantu!
        """

        let summary = try NotulenSummaryService.parseSummaryJSON(
            wrapped,
            title: "Infra",
            meetingDate: nil,
            meetingLink: nil,
            sourceFileName: "infra.md",
            modelUsed: "gemini-3.8-flash-low"
        )

        XCTAssertEqual(summary.executiveSummary, "Diskusi tentang {skema} dan migrasi server.")
        XCTAssertEqual(summary.decisions, ["Pakai database utama"])
    }

    func testParseSummaryJSONHandlesMissingOptionalFieldsAndFallbackSummary() throws {
        let minimal = """
        {
          "key_points": ["Endpoint masih menunggu tim backend", "UI reader sudah siap"],
          "action_items": [
            {"task": "Follow up token API"}
          ]
        }
        """

        let summary = try NotulenSummaryService.parseSummaryJSON(
            minimal,
            title: "Standup",
            meetingDate: nil,
            meetingLink: nil,
            sourceFileName: "standup.md",
            modelUsed: "gemini-3.8-flash-low"
        )

        XCTAssertEqual(summary.executiveSummary, "Endpoint masih menunggu tim backend UI reader sudah siap")
        XCTAssertEqual(summary.decisions, [])
        XCTAssertEqual(summary.participants, [])
        XCTAssertEqual(summary.actionItems.count, 1)
        let item = try XCTUnwrap(summary.actionItems.first)
        XCTAssertFalse(item.id.isEmpty)
        XCTAssertNotNil(UUID(uuidString: item.id))
        XCTAssertEqual(item.task, "Follow up token API")
        XCTAssertNil(item.owner)
        XCTAssertNil(item.dueDate)
    }

    func testParseSummaryJSONThrowsOnMalformedOrEmptyResponse() {
        XCTAssertThrowsError(
            try NotulenSummaryService.parseSummaryJSON(
                "Tidak ada JSON di sini",
                title: "Test",
                meetingDate: nil,
                meetingLink: nil,
                sourceFileName: "test.md",
                modelUsed: "gemini"
            )
        ) { error in
            guard case NotulenSummaryError.invalidSummaryResponse = error else {
                return XCTFail("Expected invalidSummaryResponse, got \(error)")
            }
        }

        XCTAssertThrowsError(
            try NotulenSummaryService.parseSummaryJSON(
                "{ \"executive_summary\": [123] }",
                title: "Test",
                meetingDate: nil,
                meetingLink: nil,
                sourceFileName: "test.md",
                modelUsed: "gemini"
            )
        ) { error in
            guard case NotulenSummaryError.invalidSummaryResponse = error else {
                return XCTFail("Expected invalidSummaryResponse, got \(error)")
            }
        }

        XCTAssertThrowsError(
            try NotulenSummaryService.parseSummaryJSON(
                "{ \"executive_summary\": \"   \", \"key_points\": [], \"decisions\": [] }",
                title: "Test",
                meetingDate: nil,
                meetingLink: nil,
                sourceFileName: "test.md",
                modelUsed: "gemini"
            )
        ) { error in
            guard case NotulenSummaryError.invalidSummaryResponse = error else {
                return XCTFail("Expected invalidSummaryResponse, got \(error)")
            }
        }
    }

    // MARK: - extractiveFallback & summarize

    func testExtractiveFallbackExtractsMetadataSpeakersDecisionsAndActions() {
        let markdown = """
        # Rapat Produk Mobile

        - **Tanggal:** 2026-11-23
        - **Mulai:** 10:00:00
        - **Link Meet:** https://meet.google.com/xyz-abcd-efg
        - **Status:** Selesai (10:45:00)

        ## Transkrip & Tanya Jawab

        - [10:01:00] **Rina:** Kita sepakat merilis versi beta minggu ini.
        - [10:05:12] **Doni:** Tolong siapkan build release besok pagi.
        **Dengar (10:10:00):** Nail, rangkum poin penting dong.
        **Nail (10:10:03 · 1.2 dtk):** Siap, fokus utama adalah rilis beta dan build testing.
        """

        let summary = NotulenSummaryService.extractiveFallback(
            title: "Fallback Title",
            markdown: markdown,
            sourceFileName: "2026-11-23_10-00_rapat-produk.md",
            generatedAt: Date(timeIntervalSince1970: 1_763_890_000)
        )

        XCTAssertEqual(summary.title, "Rapat Produk Mobile")
        XCTAssertEqual(summary.meetingDate, "2026-11-23")
        XCTAssertEqual(summary.meetingLink, "https://meet.google.com/xyz-abcd-efg")
        XCTAssertEqual(summary.modelUsed, "ringkasan-lokal")
        XCTAssertEqual(summary.participants, ["Rina", "Doni", "Nail"])
        XCTAssertTrue(summary.decisions.contains { $0.contains("sepakat merilis versi beta") })
        XCTAssertTrue(summary.actionItems.contains {
            $0.owner == "Doni" && $0.dueDate == "Besok" && $0.task.contains("siapkan build release")
        })
        XCTAssertFalse(summary.keyPoints.isEmpty)

        let rendered = summary.renderedMarkdown()
        XCTAssertTrue(rendered.hasPrefix("## Ringkasan Rapat"))
        XCTAssertTrue(rendered.contains("### Poin Utama"))
        XCTAssertTrue(rendered.contains("### Keputusan"))
        XCTAssertTrue(rendered.contains("### Tindak Lanjut"))
        XCTAssertTrue(rendered.contains("### Peserta"))
    }

    func testSummarizeWithInjectedRunnerUsesStrippedMarkdownAndParsesJSON() async throws {
        let dir = try makeTempDirectory()
        let fileURL = dir.appendingPathComponent("2026-11-23_11-00_demo.md")
        let file = NotulenFile(url: fileURL, name: "2026-11-23_11-00_demo", modifiedAt: Date())

        let markdown = """
        # Demo Integrasi

        <!-- NAIL_SUMMARY_START -->
        ## Ringkasan Rapat

        Ringkasan lama yang tidak boleh dikirim ulang ke prompt.
        <!-- NAIL_SUMMARY_END -->

        ## Transkrip & Tanya Jawab

        - [11:01:00] **Ayu:** Endpoint API sudah kita siapkan untuk uji coba.
        """

        actor CaptureBox {
            var capturedPrompt: String?
            var capturedModel: String?
            func set(prompt: String, model: String) {
                capturedPrompt = prompt
                capturedModel = model
            }
        }
        let box = CaptureBox()

        let summary = try await NotulenSummaryService.summarize(
            file: file,
            markdown: markdown,
            model: "gemini-3.8-flash-medium"
        ) { prompt, model in
            await box.set(prompt: prompt, model: model)
            return """
            {
              "executive_summary": "Tim mendemokan integrasi endpoint API.",
              "key_points": ["Endpoint API siap diuji"],
              "decisions": ["Lanjut ke tahap QA"],
              "action_items": [{"task": "Jalankan unit test", "owner": "Ayu", "due_date": "Hari ini"}],
              "participants": ["Ayu"]
            }
            """
        }

        let capturedPrompt = await box.capturedPrompt
        let capturedModel = await box.capturedModel
        XCTAssertEqual(capturedModel, "gemini-3.8-flash-medium")
        XCTAssertTrue(capturedPrompt?.contains("Demo Integrasi") == true)
        XCTAssertTrue(capturedPrompt?.contains("Endpoint API sudah kita siapkan") == true)
        XCTAssertFalse(capturedPrompt?.contains("Ringkasan lama yang tidak boleh dikirim ulang") == true)

        XCTAssertEqual(summary.title, "Demo Integrasi")
        XCTAssertEqual(summary.modelUsed, "gemini-3.8-flash-medium")
        XCTAssertEqual(summary.sourceFileName, "2026-11-23_11-00_demo.md")
        XCTAssertEqual(summary.decisions, ["Lanjut ke tahap QA"])
    }

    func testSummarizeThrowsEmptyTranscriptWhenNoTranscriptContent() async throws {
        let dir = try makeTempDirectory()
        let fileURL = dir.appendingPathComponent("empty.md")
        let file = NotulenFile(url: fileURL, name: "empty", modifiedAt: Date())

        do {
            _ = try await NotulenSummaryService.summarize(
                file: file,
                markdown: "   \n\n ",
                model: "gemini-3.8-flash-low",
                runner: { _, _ in "{}" }
            )
            XCTFail("Expected emptyTranscript error")
        } catch let error as NotulenSummaryError {
            XCTAssertEqual(error, .emptyTranscript)
        }

        let metadataOnlyMarkdown = """
        # Rapat Kosong

        - **Tanggal:** 2026-11-23
        - **Mulai:** 09:00:00
        - **Status:** Selesai (09:01:00)

        <!-- NAIL_SUMMARY_START -->
        ## Ringkasan Rapat

        Ringkasan lama
        <!-- NAIL_SUMMARY_END -->

        ## Transkrip & Tanya Jawab

        """
        do {
            _ = try await NotulenSummaryService.summarize(
                file: file,
                markdown: metadataOnlyMarkdown,
                model: "gemini-3.8-flash-low",
                runner: { _, _ in "{}" }
            )
            XCTFail("Expected emptyTranscript error for metadata-only markdown")
        } catch let error as NotulenSummaryError {
            XCTAssertEqual(error, .emptyTranscript)
        }
    }

    // MARK: - Sidecar Persistence

    func testSidecarPersistenceRoundTripsAndIsExcludedFromListFiles() throws {
        let dir = try makeTempDirectory()
        let notulenURL = dir.appendingPathComponent("2026-11-23_10-00_sprint-sync.md")
        try "# Sprint Sync\n\n- [10:00:00] **Reza:** Mulai rapat.\n".write(
            to: notulenURL,
            atomically: true,
            encoding: .utf8
        )

        let summary = makeSampleSummary()
        try NotulenSummaryService.saveCachedSummary(summary, for: notulenURL)
        let loadedSummary = NotulenSummaryService.loadCachedSummary(for: notulenURL)
        XCTAssertEqual(loadedSummary, summary)

        let summaryURL = NotulenSummaryService.summarySidecarURL(for: notulenURL)
        XCTAssertTrue(summaryURL.path.contains("/.summaries/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: summaryURL.path))

        let record = NotulenSubmissionRecord(
            statusCode: 201,
            remoteId: "sum_999",
            message: "Created",
            endpointURL: "https://api.example.com/v1/notulen/summary",
            submittedAt: Date(timeIntervalSince1970: 1_763_890_500),
            responseBodyPreview: "{\"id\":\"sum_999\"}"
        )
        try NotulenSummaryService.saveSubmissionRecord(record, for: notulenURL)
        let loadedRecord = NotulenSummaryService.loadSubmissionRecord(for: notulenURL)
        XCTAssertEqual(loadedRecord, record)

        let recordURL = NotulenSummaryService.submissionRecordURL(for: notulenURL)
        XCTAssertTrue(recordURL.path.contains("/.summaries/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordURL.path))

        let listed = NotulenExporter.listFiles(baseDir: dir)
        XCTAssertEqual(listed.map { $0.url.resolvingSymlinksInPath() }, [notulenURL.resolvingSymlinksInPath()])
        XCTAssertEqual(listed.map(\.name), ["2026-11-23_10-00_sprint-sync"])
        XCTAssertFalse(listed.contains { $0.url.path.contains(".summaries") })
    }

    // MARK: - upsertSummarySection

    func testUpsertSummarySectionInsertsCleanlyAndUpdatesIdempotently() throws {
        let dir = try makeTempDirectory()
        let notulenURL = dir.appendingPathComponent("2026-11-23_12-00_arsitektur.md")
        let initialContent = """
        # Rapat Arsitektur

        - **Tanggal:** 2026-11-23
        - **Mulai:** 12:00:00
        - **Status:** Selesai (12:30:00)

        ## Transkrip & Tanya Jawab

        - [12:01:00] **Reza:** Kita pisahkan client API dari UI.
        - [12:03:00] **Budi:** Setuju, pakai Keychain untuk token.
        """
        try initialContent.write(to: notulenURL, atomically: true, encoding: .utf8)

        let firstSummary = makeSampleSummary(
            title: "Rapat Arsitektur",
            executiveSummary: "Ringkasan pertama: pisahkan client API."
        )
        try NotulenSummaryService.upsertSummarySection(in: notulenURL, summary: firstSummary)

        let afterFirst = try String(contentsOf: notulenURL, encoding: .utf8)
        XCTAssertTrue(afterFirst.contains("<!-- NAIL_SUMMARY_START -->"))
        XCTAssertTrue(afterFirst.contains("<!-- NAIL_SUMMARY_END -->"))
        XCTAssertTrue(afterFirst.contains("Ringkasan pertama: pisahkan client API."))
        XCTAssertTrue(afterFirst.contains("- [12:01:00] **Reza:** Kita pisahkan client API dari UI."))
        XCTAssertTrue(afterFirst.contains("- [12:03:00] **Budi:** Setuju, pakai Keychain untuk token."))

        let summaryRange = try XCTUnwrap(afterFirst.range(of: "<!-- NAIL_SUMMARY_START -->"))
        let transcriptRange = try XCTUnwrap(afterFirst.range(of: "## Transkrip & Tanya Jawab"))
        XCTAssertLessThan(summaryRange.lowerBound, transcriptRange.lowerBound)

        let secondSummary = makeSampleSummary(
            title: "Rapat Arsitektur",
            executiveSummary: "Ringkasan kedua yang diperbarui."
        )
        try NotulenSummaryService.upsertSummarySection(in: notulenURL, summary: secondSummary)

        let afterSecond = try String(contentsOf: notulenURL, encoding: .utf8)
        XCTAssertEqual(afterSecond.components(separatedBy: "<!-- NAIL_SUMMARY_START -->").count - 1, 1)
        XCTAssertEqual(afterSecond.components(separatedBy: "<!-- NAIL_SUMMARY_END -->").count - 1, 1)
        XCTAssertEqual(afterSecond.components(separatedBy: "## Ringkasan Rapat").count - 1, 1)
        XCTAssertFalse(afterSecond.contains("Ringkasan pertama: pisahkan client API."))
        XCTAssertTrue(afterSecond.contains("Ringkasan kedua yang diperbarui."))
        XCTAssertTrue(afterSecond.contains("- [12:01:00] **Reza:** Kita pisahkan client API dari UI."))
        XCTAssertTrue(afterSecond.contains("- [12:03:00] **Budi:** Setuju, pakai Keychain untuk token."))
    }

    // MARK: - NotulenBackendClient.buildRequest

    func testBuildRequestValidationErrors() {
        let payload = NotulenSummarySubmissionPayload(summary: makeSampleSummary(), rawMarkdown: "# Raw")

        XCTAssertThrowsError(
            try NotulenBackendClient.buildRequest(
                payload: payload,
                config: NotulenBackendConfig(endpointURLString: "   ", authScheme: .none),
                credential: nil
            )
        ) { error in
            XCTAssertEqual(error as? NotulenBackendError, .endpointNotConfigured)
        }

        for badEndpoint in ["ftp://example.com/hook", "file:///tmp/out.json", "not a valid url", "https://"] {
            XCTAssertThrowsError(
                try NotulenBackendClient.buildRequest(
                    payload: payload,
                    config: NotulenBackendConfig(endpointURLString: badEndpoint, authScheme: .none),
                    credential: nil
                )
            ) { error in
                guard case .invalidEndpointURL = error as? NotulenBackendError else {
                    return XCTFail("Expected invalidEndpointURL for \(badEndpoint), got \(error)")
                }
            }
        }

        for scheme in [BackendAuthScheme.bearer, .apiKeyHeader, .basic] {
            for emptyCred in [nil, "", "   \n "] as [String?] {
                XCTAssertThrowsError(
                    try NotulenBackendClient.buildRequest(
                        payload: payload,
                        config: NotulenBackendConfig(
                            endpointURLString: "https://api.example.com/v1/notulen/summary",
                            authScheme: scheme
                        ),
                        credential: emptyCred
                    )
                ) { error in
                    XCTAssertEqual(error as? NotulenBackendError, .missingCredential(scheme))
                }
            }
        }
    }

    func testBuildRequestAuthSchemesHeadersAndSnakeCasePayload() throws {
        let summary = makeSampleSummary()
        let rawMarkdown = "# Sprint Sync\n\n- [10:00:00] **Reza:** Halo tim."
        let fixedSubmittedAt = Date(timeIntervalSince1970: 1_763_890_600)
        let payload = NotulenSummarySubmissionPayload(
            summary: summary,
            rawMarkdown: rawMarkdown,
            submittedAt: fixedSubmittedAt
        )
        let endpoint = "https://api.example.com/v1/notulen/summary"

        // .bearer
        let bearerReq = try NotulenBackendClient.buildRequest(
            payload: payload,
            config: NotulenBackendConfig(endpointURLString: endpoint, authScheme: .bearer),
            credential: "tok_abc_123"
        )
        XCTAssertEqual(bearerReq.httpMethod, "POST")
        XCTAssertTrue(bearerReq.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true)
        XCTAssertEqual(bearerReq.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(bearerReq.value(forHTTPHeaderField: "Authorization"), "Bearer tok_abc_123")

        // .apiKeyHeader
        let apiKeyReq = try NotulenBackendClient.buildRequest(
            payload: payload,
            config: NotulenBackendConfig(
                endpointURLString: endpoint,
                authScheme: .apiKeyHeader,
                customAuthHeaderName: "X-API-Key"
            ),
            credential: "secret_key_999"
        )
        XCTAssertEqual(apiKeyReq.value(forHTTPHeaderField: "X-API-Key"), "secret_key_999")
        XCTAssertNil(apiKeyReq.value(forHTTPHeaderField: "Authorization"))

        // .basic (username:password -> base64)
        let basicReq = try NotulenBackendClient.buildRequest(
            payload: payload,
            config: NotulenBackendConfig(endpointURLString: endpoint, authScheme: .basic),
            credential: "nail:s3cr3t"
        )
        let expectedBasic = Data("nail:s3cr3t".utf8).base64EncodedString()
        XCTAssertEqual(basicReq.value(forHTTPHeaderField: "Authorization"), "Basic \(expectedBasic)")

        // .none
        let noneReq = try NotulenBackendClient.buildRequest(
            payload: payload,
            config: NotulenBackendConfig(endpointURLString: endpoint, authScheme: .none),
            credential: nil
        )
        XCTAssertNil(noneReq.value(forHTTPHeaderField: "Authorization"))

        // Verify JSON body matches relay webhook contract
        let bodyData = try XCTUnwrap(noneReq.httpBody)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(jsonObject["text"] as? String, summary.renderedMarkdown())
        XCTAssertEqual(jsonObject["title"] as? String, "Sprint Sync")
        XCTAssertEqual(jsonObject["source"] as? String, "google-meet")
        XCTAssertEqual(jsonObject.count, 3)

        XCTAssertEqual(NotulenSummarySubmissionPayload.inferSource(from: "https://us02web.zoom.us/j/123456"), "zoom")
        XCTAssertEqual(NotulenSummarySubmissionPayload.inferSource(from: "https://teams.microsoft.com/l/meetup-join/123"), "teams")
        XCTAssertEqual(NotulenSummarySubmissionPayload.inferSource(from: nil), "nail")
    }

    // MARK: - NotulenBackendClient.submit

    func testSubmitParsesSuccess200And201Responses() async throws {
        let summary = makeSampleSummary()
        let config = NotulenBackendConfig(
            endpointURLString: "https://api.example.com/v1/notulen/summary",
            authScheme: .bearer
        )

        for statusCode in [200, 201] {
            let session = makeMockSession { request in
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
                let url = try XCTUnwrap(request.url)
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                let body = Data("{\"id\": \"sum_123\", \"message\": \"ok\"}".utf8)
                return (response, body)
            }

            let record = try await NotulenBackendClient.submit(
                summary: summary,
                rawMarkdown: "# Raw",
                config: config,
                credential: "token-123",
                session: session
            )

            XCTAssertEqual(record.statusCode, statusCode)
            XCTAssertEqual(record.remoteId, "sum_123")
            XCTAssertEqual(record.message, "ok")
            XCTAssertEqual(record.endpointURL, "https://api.example.com/v1/notulen/summary")
        }
    }

    func testSubmitThrowsHTTPErrorOn401And500() async throws {
        let summary = makeSampleSummary()
        let config = NotulenBackendConfig(
            endpointURLString: "https://api.example.com/v1/notulen/summary",
            authScheme: .bearer
        )

        let session401 = makeMockSession { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data("{\"error\": \"Invalid token\"}".utf8)
            return (response, body)
        }

        do {
            _ = try await NotulenBackendClient.submit(
                summary: summary,
                rawMarkdown: "# Raw",
                config: config,
                credential: "bad-token",
                session: session401
            )
            XCTFail("Expected httpError 401")
        } catch let error as NotulenBackendError {
            XCTAssertEqual(error, .httpError(statusCode: 401, message: "Invalid token"))
        }

        let session500 = makeMockSession { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data("{\"detail\": \"Database unavailable\"}".utf8)
            return (response, body)
        }

        do {
            _ = try await NotulenBackendClient.submit(
                summary: summary,
                rawMarkdown: "# Raw",
                config: config,
                credential: "token-123",
                session: session500
            )
            XCTFail("Expected httpError 500")
        } catch let error as NotulenBackendError {
            XCTAssertEqual(error, .httpError(statusCode: 500, message: "Database unavailable"))
        }
    }

    // MARK: - VoiceSettings Persistence

    @MainActor
    func testVoiceSettingsPersistsBackendConfiguration() throws {
        let defaults = try makeIsolatedDefaults()
        let settings = VoiceSettings(defaults: defaults)

        XCTAssertEqual(settings.backendSummaryEndpoint, VoiceSettings.defaultBackendSummaryEndpoint)
        XCTAssertEqual(settings.backendAuthScheme, .none)
        XCTAssertEqual(settings.backendAuthHeaderName, "X-API-Key")

        settings.backendSummaryEndpoint = "https://backend.meetnail.id/api/summaries"
        settings.backendAuthScheme = .apiKeyHeader
        settings.backendAuthHeaderName = "X-MeetNail-Key"

        let reloaded = VoiceSettings(defaults: defaults)
        XCTAssertEqual(reloaded.backendSummaryEndpoint, "https://backend.meetnail.id/api/summaries")
        XCTAssertEqual(reloaded.backendAuthScheme, .apiKeyHeader)
        XCTAssertEqual(reloaded.backendAuthHeaderName, "X-MeetNail-Key")

        let config = reloaded.notulenBackendConfig()
        XCTAssertEqual(config.endpointURLString, "https://backend.meetnail.id/api/summaries")
        XCTAssertEqual(config.authScheme, .apiKeyHeader)
        XCTAssertEqual(config.customAuthHeaderName, "X-MeetNail-Key")
        XCTAssertTrue(config.isConfigured)
    }
}

private final class MockBackendURLProtocol: URLProtocol, @unchecked Sendable {
    private final class HandlerState: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

        func set(_ newHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?) {
            lock.lock()
            handler = newHandler
            lock.unlock()
        }

        func get() -> (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
            lock.lock()
            defer { lock.unlock() }
            return handler
        }
    }

    private static let state = HandlerState()

    static func setHandler(_ newHandler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        state.set(newHandler)
    }

    static func reset() {
        state.set(nil)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.state.get() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
