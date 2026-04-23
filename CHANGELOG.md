## 0.1.0

Initial release. Dart FFI wrapper for the qpdf C library (v12.3.2).

**API**

- High-level `QpdfDocument`, `QpdfObject`, `QpdfPage` with full access to
  the qpdf C API (~150 functions).
- `QpdfAsync` facade that runs every operation in an isolate — safe for
  Flutter UI and server event loops.
- Sealed `QpdfException` hierarchy: `QpdfPasswordException`,
  `QpdfDamagedPdfException`, `QpdfSystemException`, `QpdfPagesException`,
  `QpdfObjectException`, `QpdfJsonException`,
  `QpdfLinearizationException`, `QpdfUnsupportedException`,
  `QpdfInternalException`.
- Sealed `EncryptionParams` hierarchy: `R2`, `R3`, `R4`, `R5`, `R6`
  encryption with full permission control.
- Idiomatic Dart enums for every qpdf enum (object types, stream modes,
  permission flags, etc.).

**Resource management**

- Explicit `dispose()` for deterministic cleanup.
- `NativeFinalizer` attached to every `QpdfDocument` — native resources
  are reclaimed automatically on GC if `dispose` is forgotten.

**Native library**

- Prebuilt qpdf binaries downloaded at build time for Linux (x64, arm64),
  macOS (x64, arm64), and Windows (x64, arm64).
- Prebuilts are self-contained: zlib, libjpeg-turbo, and OpenSSL are all
  statically linked into `libqpdf`.
- Transparent fallback to system-installed qpdf when the prebuilt
  download is unavailable or the platform isn't supported.
- Structured `[qpdf]`-prefixed build-time logging for debugging.

**Tested against**

- macOS arm64 with qpdf 12.3.2 and OpenSSL-backed AES-256 (R6) encryption.
- 47 tests covering unit behavior, document lifecycle, async isolate
  round-trips, and end-to-end encryption / decryption across all five
  encryption revisions.
