## Implementation plan

This repository appears to be greenfield, so the downstream agent should treat the work as an MVP bootstrap rather than an incremental feature.

1. Scaffold a minimal `frontend/` and `backend/` structure.
2. Build the backend first: config, SQLite schema, filesystem scanner, index persistence, and search API.
3. Build a small React UI that can configure a root folder, start indexing, observe status, and search the index.
4. Add backend tests before polishing the UI; the scanner and repository are the highest-risk areas.
5. Run a real local indexing pass against a sample folder and fix integration gaps.
6. Finish with accurate README instructions and a short list of known limitations.

## Guardrails for the weaker agent

- Do not add Electron, Docker, Redis, queues, or cloud services.
- Do not implement full-text content search in v1.
- Prefer one backend process and SQLite only.
- Keep API and UI surface small and verifiable.
- If scope pressure appears, cut optional UI polish before cutting backend correctness.