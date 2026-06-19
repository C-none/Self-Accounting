# TODO List

## Phase 0: Environment and Skeleton

| Status | Item | Module | Acceptance | Depends on |
| --- | --- | --- | --- | --- |
| Done | Confirm local toolchain | Local Test | Go, Flutter, SQLite, FFmpeg, ADB, Chrome, and `Pixel_9_Pro` AVD are documented in `local-closed-loop-testing.md` | None |
| Done | Build minimal Go server skeleton | Server Architecture | Server starts with `config.dev.json`, exposes `/api/health`, initializes SQLite WAL | Toolchain |
| Done | Build minimal Flutter shell | Flutter Client | Android/Web app opens to pairing UI, no heavy UI dependencies | Toolchain |
| Done | Serve Flutter Web from Go | Server / Web | Release `build/web` is served by Go with `/api/` route separation | Server skeleton, Flutter shell |
| Done | Record size baseline | Performance | Initial Go binary, Web build, and Android APK sizes are recorded in `docs/test-records/phase0-phase1.md` | Skeleton |

## Phase 1: Core Online Ledger

| Status | Item | Module | Acceptance | Depends on |
| --- | --- | --- | --- | --- |
| Done | Define SQLite schema | Server / Data Model | Tables use `amount_cent INTEGER`, `currency DEFAULT 'CNY'`, soft delete fields, device and audit tables | None |
| Done | Build Go API skeleton | Server Architecture | `net/http` server starts on Windows; Ubuntu Linux remains a documented target for the same pure-Go server | Schema |
| Done | Implement pairing | Auth Pairing | `POST /api/pair/start` and `POST /api/pair/confirm` work without passwords; token hash stored | API skeleton |
| Done | Console-only first pairing code request | Auth Pairing | Unpaired clients never receive pairing code in HTTP response; server console prints or reprints current code; paired devices can generate codes inside settings | Implement pairing |
| Done | Implement transaction CRUD | Transaction Server | Android/Web can create, edit, list, and soft delete transactions through same API | Pairing, schema |
| Done | Build Flutter app shell | Flutter Client | Android and Web share routing, theme, API client, auth state | Pairing API |
| Done | Add editable client service address | Flutter Client | Pairing and settings pages can save service IP/host and port locally; compile-time API base remains only the default | Pairing API |
| Done | Build transaction UI | Transaction Client | Android and Web both support manual transaction create/edit/list/filter, including date range and keyword filters | Flutter shell, transaction API |
| Done | Add master data management | Master Data Client / Server | Settings page links to category/member/account management; CRUD APIs support soft delete and reject deletion when referenced by transactions | Bootstrap |
| Done | Group transactions by date | Transaction Client | Transaction list inserts date dividers with collapse buttons for each day | Transaction list |
| Done | Improve date filters | Transaction Client | Date filters default to today and one week before, accept `YYYYMMDD`, and keep date picker access through arrow buttons | Transaction list |
| Done | Add statistics API | Statistics Server | Category and timeline endpoints aggregate `amount_cent` and exclude soft-deleted rows | Transaction API |
| Done | Add statistics UI | Statistics Client | Android/Web show self-drawn pie and line charts from server API | Statistics API |

## Phase 2: Photos, Public Use, and Migration

| Status | Item | Module | Acceptance | Depends on |
| --- | --- | --- | --- | --- |
| Done | Add attachment upload API | Attachment Server | Multipart upload accepted and linked to transaction; image endpoints require bearer token | Transaction API |
| Done | Add FFmpeg compression | Attachment Server | Server outputs detail-preserving compressed JPG and thumbnail; backup and compression share a storage lock | Upload API, FFmpeg config |
| Done | Add photo UI | Photo Client | Android camera/gallery and Web file picker upload photos; client displays authenticated server JPG thumbnails | Attachment API |
| Done | Add attachment delete UI/API | Photo Client / Attachment Server | Uploaded photos can be soft-deleted from transaction detail; list and image endpoints exclude deleted attachments | Photo UI |
| Done | Add HTTPS production config | Auth/Security | `require_https=true` rejects non-HTTPS public base URL; business APIs require bearer token | Pairing |
| Done | Add backup API | Backup Migration | `POST /api/admin/backup` creates zip with app.db, photos, thumbnails, config export, manifest | Schema, attachments |
| Done | Add checkpoint API | Backup Migration | `POST /api/admin/checkpoint` runs SQLite checkpoint before migration | SQLite setup |
| Done | Write restore procedure | Backup Migration | Windows <-> Ubuntu steps documented; backup integrity and relative-path package verified locally; Ubuntu restore not executed because WSL is unavailable | Backup API |

## Phase 3: Android SMS Import

| Status | Item | Module | Acceptance | Depends on |
| --- | --- | --- | --- | --- |
| Done | Add Android SMS platform adapter | SMS Client | Android requests SMS permissions; Web feature flag hides SMS UI | Flutter platform layer |
| Done | Implement background SMS listener | SMS Client | Online Android devices receive SMS broadcasts into an in-memory candidate queue | SMS permissions |
| Done | Implement disconnected behavior | SMS Client | If network is unavailable when SMS arrives, the receiver does not queue or parse it | Background listener |
| Done | Implement manual rescan | SMS Client | User can manually rescan recent SMS after network returns; permission grant does not auto-scan history | SMS adapter |
| Done | Add local SMS parser | SMS Client | Parser extracts amount, direction, counterparty, bank name and card tail when possible; SMS imports use the SMS received time as transaction time | SMS adapter |
| Done | Add confirmation UI | SMS Client | User confirms or edits candidate before submit | Parser, transaction UI |
| Done | Add SMS import API | SMS Server | `POST /api/sms/imports` accepts structured data and rejects SMS raw body | Transaction API |
| Done | Add SMS duplicate detection | SMS Server | `sms_hash` prevents duplicate import | SMS import API |
| Done | Fix Android SMS receiver network-state crash | SMS Client | Receiver declares network-state permission and treats network permission failures as offline instead of crashing | Background listener |
| Done | Stabilize SMS duplicate identity hash | SMS Client / Server | `sms_hash` uses sender, raw received time and normalized body; server stores `sms_received_at_ms` without SMS raw body | SMS duplicate detection |
| Done | Add SMS multi-select import | SMS Client | Android SMS page supports multi-select, select-all/cancel-all and one-click import for selected candidates | SMS confirmation UI |
| Done | Add manual SMS templates and enable filters | SMS Client | Android manually stores multiple local templates per sender/account, extracts brace fields from enabled templates, and ignores SMS that do not match enabled templates | SMS parser |
| Done | Show SMS raw body locally and hide imported candidates | SMS Client | Android import candidates and confirm page show local SMS text for verification; successful or duplicate imports are recorded by hash locally and hidden from later scans | Manual SMS templates |
| Done | Add SMS hidden-record reset | SMS Client | Android SMS import page can clear local imported-hash cache without deleting templates, token, or server transactions | Show SMS raw body locally and hide imported candidates |
| Done | Add SMS scan diagnostics | SMS Client | Android empty scans show local non-sensitive counts for read rows, sender 95588 rows, template matches, candidates and hidden hashes | Manual SMS templates |
| Done | Add Bayesian SMS category suggestions | SMS Client / Server | Android SMS candidates request server category suggestions from structured fields only; service uses historical transactions with fallback to local rules and never accepts SMS raw body | Manual SMS templates |

## Phase 4: Statistics Refinement

| Status | Item | Module | Acceptance | Depends on |
| --- | --- | --- | --- | --- |
| Done | Add statistics filters and weekly timeline bucket | Statistics Client / Server | Statistics page filters by direction, member, category, bank and date range; timeline supports day, week and month buckets | Statistics API |
| Done | Add multi-series comparison | Statistics Client / Server | Statistics page can compare一级分类、二级分类、使用人或银行；饼图按比较属性显示占比，折线图按比较属性绘制多条序列 | Statistics filters |
| Done | Improve charts, transaction rows, category picker and master-data ordering | Flutter Client / Server | Charts use clearer colors and click-to-show line values; transaction rows use three-line details; transaction forms use bottom category picker; settings can reorder categories, members and accounts | Multi-series comparison |
| Done | Refine transaction, statistics, master-data and SMS UI | Flutter Client | Transaction filters use fixed two-column rows and MM-DD-YYYY dates; rows omit account from the detail line; statistics charts use muted Morandi colors and aligned clear-filter buttons; master data uses compact add buttons and drag handles; SMS hidden-record clear action lives in the SMS AppBar | Improve charts, transaction rows, category picker and master-data ordering |

## Cross-Cutting Checks

- Client main route remains Flutter for both Android and Web.
- Flutter Web desktop layout uses a responsive rail plus centered content; Android and narrow Web keep mobile navigation.
- Web supports manual transaction creation but never supports SMS scanning.
- No persistent amount field should use floating point.
- Server-side FFmpeg is the only final photo compression authority.
- Server startup and client settings display the current service URL/IP and port.
- Settings supports current device name editing and admin-only concise audit log lookup.
- No password login should be introduced.
- Web favicon/PWA icons and Android launcher icon use `client/assets/branding/icon.png` as the source image.
- Backup and migration must remain valid for both Windows and Ubuntu Linux.
- Ubuntu release scripts in `scripts/ubuntu/` are stable operational interfaces; future changes should preserve file names, arguments, and environment variables where practical.
- Root `MIGRATION.md` must stay aligned with backup behavior and must require migrating `app.db`, `photos/`, `thumbnails/`, and the server secret when preserving paired devices.
- Same-function choices must prefer smaller packages, smaller Web payloads, faster App startup, and faster page open.
- Do not add decorative assets, custom fonts, heavy chart libraries, UI kits, or animations unless a functional requirement proves they are necessary.
- Each completed slice must include the test record required by `architecture/local-closed-loop-testing.md`.
