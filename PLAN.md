# Local File Finder Implementation Handoff

## 1. Product Summary
Build a native iPhone app that gives users content search across files they manage in the iOS Files ecosystem. The MVP should let a user authorize folders or files from Files, index those documents locally, run full-text keyword search, and view result previews that include file location and matched snippets. The app must support embedded PDF text plus on-device OCR for images and scanned PDFs.

This is a local-first utility app, not a cloud product. Do not introduce a server, external OCR API, or web stack.

## 2. Critical Product Reality: iOS Sandbox Boundaries
The prompt says "all iPhone files," but the implementation must respect how iOS actually works.

What is feasible:
- The app can search files and folders the user explicitly grants through the document picker / Files integration.
- The app can persist access to those locations using security-scoped bookmarks.
- The app can maintain its own local index of extracted text and metadata.

What is not feasible for MVP:
- Crawling the entire device file system without user consent.
- Reading arbitrary files from other apps' sandboxes.
- Assuming continuous filesystem monitoring across every provider.

Product wording in the app should be honest: "Search inside the folders you add from Files." Do not promise unrestricted device-wide crawling.

## 3. MVP Scope
Must-have features:
- Add one or more folders/files from Files.
- Persist access across launches.
- Index supported files locally.
- Extract text from text files and text-based PDFs.
- Run OCR on images and scanned PDFs on device.
- Search by keyword.
- Show result rows with filename, source folder, and content snippet.
- Show indexing status and allow manual reindex.

Explicit MVP exclusions:
- Semantic/vector search.
- Cross-device sync.
- macOS/iPad multitarget support.
- Collaborative libraries.
- Third-party search engine integration.
- Full document editing.

## 4. Recommended Tech Stack
Use Apple-native frameworks only unless a very specific blocker appears.

- Language: Swift
- UI: SwiftUI
- Persistence: SwiftData
- PDF text extraction: PDFKit
- OCR: Vision text recognition
- File access: UIDocumentPickerViewController or SwiftUI file importer
- Type detection: UniformTypeIdentifiers
- Background refresh: BackgroundTasks
- Preview/thumbnails: QuickLookThumbnailing and system document open flows

If a lower-level persistence issue appears with SwiftData query performance, it is acceptable to keep SwiftData models but add a small custom SQLite FTS layer later. Do not start there. Start with SwiftData plus normalized token fields and only escalate if real profiling proves it necessary.

## 5. Proposed Project Structure
Create a clean Xcode structure like this:

```text
LocalFileFinder/
  App/
    LocalFileFinderApp.swift
    AppContainer.swift
    RootView.swift
  Models/
    IndexedSource.swift
    IndexedFile.swift
    ExtractedContent.swift
    IndexingJob.swift
    SearchResultItem.swift
  Services/
    Bookmarks/
      SecurityScopedBookmarkManager.swift
      SourceAccessSession.swift
    Files/
      DocumentPickerCoordinator.swift
      FileEnumerationService.swift
      FileMetadataHasher.swift
    Extraction/
      ContentExtractionService.swift
      PlainTextExtractor.swift
      PDFTextExtractor.swift
      ImageOCRExtractor.swift
      PDFOCRExtractor.swift
    Search/
      SearchRepository.swift
      SearchRanker.swift
      SnippetBuilder.swift
    Indexing/
      IndexingCoordinator.swift
      BackgroundIndexScheduler.swift
      IndexingProgressStore.swift
    Preview/
      ThumbnailService.swift
      DocumentOpenCoordinator.swift
  Features/
    Onboarding/
      OnboardingView.swift
      SourcePickerViewModel.swift
    Search/
      SearchView.swift
      SearchViewModel.swift
      SearchResultRow.swift
    Library/
      SourceLibraryView.swift
      SourceLibraryViewModel.swift
    Detail/
      DocumentDetailView.swift
      DocumentDetailViewModel.swift
    Settings/
      SettingsView.swift
  Utilities/
    Logger.swift
    UTType+SupportedTypes.swift
    String+Normalization.swift
  Tests/
    Unit/
    UI/
    Fixtures/
```

Keep service code separate from SwiftUI view models. A weaker coding agent is likely to mix UI and file logic unless told not to.

## 6. Architecture Overview
High-level flow:
1. User adds folders/files from Files.
2. The app stores security-scoped bookmarks for those locations.
3. The indexing coordinator restores source access and enumerates supported files.
4. For each file, the extraction pipeline chooses one strategy:
   - plain text extraction
   - PDF embedded text extraction
   - OCR for image files
   - OCR for scanned PDFs when embedded text is missing
5. Extracted text and metadata are saved to the local store.
6. Search queries run entirely against the local index and return ranked results with snippets.

Core components and responsibilities:

### 6.1 Source Access
`SecurityScopedBookmarkManager`
- Creates and resolves bookmark data for user-approved URLs.
- Detects stale bookmarks and requests re-authorization.
- Wrap access with `startAccessingSecurityScopedResource()` / stop-access calls.

`DocumentPickerCoordinator`
- Presents folder/file selection.
- Converts chosen URLs into saved source records.
- Restrict initial MVP to iCloud Drive plus other providers that work through standard picker flows.

### 6.2 Enumeration and Change Detection
`FileEnumerationService`
- Recursively enumerates files inside each authorized source.
- Filters to supported UTTypes.
- Collects file metadata: name, path display string, byte size, modification date.

`FileMetadataHasher`
- Optional helper that computes a lightweight content hash when metadata alone is not enough.
- Use hash only when needed because large file hashing can be expensive.

Incremental indexing rule:
- If source bookmark is unchanged and file modification date/size match the stored record, skip reprocessing.
- If metadata changed or file is new, enqueue extraction.
- If a file disappeared, mark it missing and hide from default results.

### 6.3 Extraction Pipeline
`ContentExtractionService`
- Central strategy selector.
- Accepts file URL plus type info.
- Returns normalized text, per-page snippet anchors when relevant, OCR provenance, and extraction diagnostics.

`PlainTextExtractor`
- Handles `.txt`, `.md`, maybe simple structured text formats when trivial.
- Normalize whitespace and trim excessive repeated gaps.

`PDFTextExtractor`
- Uses PDFKit to extract page-by-page text for text-based PDFs.
- If page text is empty or nearly empty, flag the document/page for OCR fallback.

`ImageOCRExtractor`
- Uses Vision text recognition on image formats.
- Normalize result lines into searchable text.

`PDFOCRExtractor`
- Rasterize pages that lack embedded text, then send images through Vision OCR.
- Add page caps for MVP to control runtime.

Normalization rules:
- Lowercase for search indexing.
- Preserve original snippets for display where possible.
- Collapse repeated whitespace.
- Tokenize on non-alphanumeric boundaries for basic search.

### 6.4 Local Search
`SearchRepository`
- Owns query execution over persisted indexed content.
- Supports simple multi-token AND search for MVP.
- Returns `SearchResultItem` objects with file metadata, score, snippet, and match source.

`SearchRanker`
Suggested first-pass scoring:
- Exact filename match: very high weight.
- Filename contains token: high weight.
- Content contains all tokens: medium weight.
- More token hits in snippet: small boost.
- More recent modification date: optional small boost.

`SnippetBuilder`
- Finds the first or best local occurrence of the matched terms.
- Produces a short window of text around the hit.
- Avoid expensive highlighting logic in the storage layer.

### 6.5 Background and Operations
`IndexingCoordinator`
- Single entry point for full scan, source-specific reindex, and incremental reindex.
- Runs work with structured concurrency and a bounded task group.
- Stores progress so the UI can survive app foreground/background transitions.

`BackgroundIndexScheduler`
- Registers a background refresh task.
- Schedules opportunistic refreshes for previously authorized sources.
- Must degrade gracefully because BackgroundTasks timing is not guaranteed.

## 7. Data Model Notes
Use SwiftData models roughly like this.

### `IndexedSource`
Fields:
- `id: UUID`
- `displayName: String`
- `bookmarkData: Data`
- `sourceType: String` (`folder`, `file`)
- `providerIdentifier: String?`
- `dateAdded: Date`
- `lastAuthorizedAt: Date?`
- `lastIndexedAt: Date?`
- `isAccessible: Bool`
- `lastError: String?`

### `IndexedFile`
Fields:
- `id: UUID`
- `sourceID`
- `fileURLBookmarkData: Data?` only if file-level persistence is needed
- `fileName: String`
- `relativePath: String`
- `displayPath: String`
- `uti: String`
- `byteSize: Int64`
- `modificationDate: Date?`
- `contentHash: String?`
- `lastIndexedAt: Date?`
- `isMissing: Bool`
- `extractionState: String`
- `usedOCR: Bool`
- `thumbnailPath: String?`

### `ExtractedContent`
Fields:
- `id: UUID`
- `fileID`
- `fullTextNormalized: String`
- `fullTextPreview: String`
- `pageNumber: Int?` for page-scoped records if needed
- `snippetSeedText: String?`
- `tokenCount: Int`
- `languageCode: String?`

### `IndexingJob`
Fields:
- `id: UUID`
- `scopeDescription: String`
- `startedAt: Date`
- `finishedAt: Date?`
- `status: String`
- `processedCount: Int`
- `successCount: Int`
- `failureCount: Int`
- `currentFileName: String?`

Implementation note: if SwiftData becomes awkward for storing a single giant normalized text blob per file, split large content into chunks or pages. Do not over-engineer this before measuring.

## 8. UI Plan
### 8.1 Onboarding
The first run should explain the access model in plain language:
- Add folders from Files.
- The app indexes only what you add.
- Search stays on device.

Primary CTA: `Add Folder from Files`
Secondary CTA: `Add Individual Files`

### 8.2 Search Home
Default landing screen after onboarding.
Contains:
- Search field at top.
- Indexing status summary.
- Recent or all indexed result list when query is active.
- Empty states for no sources, no indexed files, no matches.

### 8.3 Source Library
List authorized folders/files.
Each row shows:
- source name
- file count
- last indexed timestamp
- accessibility warning if bookmark failed
Actions:
- reindex
- re-authorize
- remove source

### 8.4 Result Row
Each result should show:
- file name
- type badge (`PDF`, `IMG`, `TXT`)
- breadcrumb/location
- snippet preview
- optional indicator when the text came from OCR

### 8.5 Detail View
Show:
- file metadata
- larger snippet or page references
- open/preview action
- source folder reference
- reindex this file/source action if relevant

## 9. Implementation Phases
### Phase 1: App skeleton and persistence
Deliverables:
- SwiftUI app shell
- SwiftData container
- model definitions
- placeholder tabs or navigation destinations

### Phase 2: Source authorization
Deliverables:
- document picker integration
- bookmark persistence and restore
- source library UI
- failure and re-authorize states

### Phase 3: Enumeration and text extraction
Deliverables:
- recursive file scanning
- supported-type filtering
- plain text extraction
- embedded PDF extraction
- incremental indexing metadata

### Phase 4: OCR and search
Deliverables:
- Vision OCR for images
- scanned PDF OCR fallback
- query engine
- snippet building
- ranked result list

### Phase 5: Product hardening
Deliverables:
- background refresh
- thumbnails and better previews
- settings and index management
- tests and performance pass

## 10. File-Type Support Guidance
Start with a narrow, reliable support matrix.

Support in MVP:
- `.txt`
- `.md`
- `.pdf`
- common images: `.png`, `.jpg`, `.jpeg`, `.heic`

Optional later:
- `.rtf`
- Office docs via document text extraction if a reliable Apple-native path exists

Important: do not promise full Word/Pages extraction in v1 unless you confirm a robust implementation path. The prompt mentions docs broadly, but the MVP can ship with PDFs, text, and image OCR first as long as product messaging is precise.

## 11. Testing Strategy
Create fixture files inside `Tests/Fixtures/`:
- text-only PDF
- scanned/image-only PDF
- screenshot with clear OCR text
- plain text note
- unsupported binary file
- large PDF for performance measurement

Required unit tests:
- bookmark creation and restoration
- stale bookmark handling
- enumeration skips unsupported files
- incremental indexing ignores unchanged files
- PDF extractor returns page text
- OCR fallback triggers when PDF page text is empty
- search ranking prefers filename hits over body hits
- snippet builder returns surrounding text correctly

Required UI tests:
- onboarding shows source-add flow
- adding a source transitions to searchable state
- entering a query shows at least one result with snippet

Manual device checks:
- iCloud Drive folder with mixed files
- third-party provider if available
- background refresh behavior after app relaunch
- memory/performance when indexing image-heavy folders

## 12. Acceptance Criteria
The implementation is acceptable when all of the following are true:
- A user can add folders/files from Files and the app remembers them across launches.
- The app indexes text-based files and PDFs locally.
- The app performs on-device OCR for images and scanned PDFs.
- Search returns relevant matches by keyword with filename, location, and snippet.
- The app makes clear which files are searchable and why some files may fail.
- The app can reindex sources without duplicating unchanged work.
- No file content leaves the device.
- Basic service and UI tests exist and pass.

## 13. Risk Mitigations
### Sandbox limitations
Mitigation:
- Build around user-granted sources.
- Make scope explicit in onboarding and marketing copy.
- Store bookmarks robustly and surface repair flows.

### OCR cost and latency
Mitigation:
- Process in batches.
- Cap OCR for extremely large PDFs in MVP.
- Allow cancellation.
- Save extracted results so OCR is not repeated unnecessarily.

### Provider inconsistency
Mitigation:
- Prefer file coordination and defensive error handling.
- Test first on iCloud Drive.
- Track provider identifier in source metadata for diagnostics.

### Native competition risk
Mitigation:
- Differentiate through immediate value: snippets, source management, reindex control, OCR visibility, and local privacy messaging.

## 14. Suggested Execution Order for the Downstream Agent
Implement in this order and do not skip ahead:
1. Project skeleton and persistence models.
2. Document picker plus bookmark persistence.
3. Source library and restored access on launch.
4. Enumeration and incremental indexing state.
5. Plain text and PDF embedded text extraction.
6. OCR for images and scanned PDFs.
7. Search repository, ranking, and snippets.
8. Search/results/detail UI.
9. Background reindex and settings.
10. Tests, fixtures, and performance validation.

## 15. Notes for the Weaker Implementation Agent
- Do not add any backend service.
- Do not use a web wrapper or cross-platform abstraction.
- Do not promise unrestricted device-wide file access.
- Keep the indexing pipeline behind protocols so it is testable.
- Prefer shipping a smaller but honest support matrix over claiming broad document support that is unreliable.
- If you hit SwiftData search limitations, document them before replacing persistence. Only escalate after a measured problem appears.
- Keep file handling resilient: one bad file must not break the overall indexing job.