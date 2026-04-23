# qpdf

[![pub package](https://img.shields.io/pub/v/qpdf.svg)](https://pub.dev/packages/qpdf)

Dart FFI wrapper for the [qpdf](https://github.com/qpdf/qpdf) C library. PDF
encryption, decryption, linearization, page manipulation, metadata editing,
and low-level PDF object access.

Works in pure Dart, Flutter, and server-side Dart.

## Features

- **Full qpdf C API wrapped** — every function in qpdf's C API is accessible
  via idiomatic, type-safe Dart
- **High-level Dart API** — `QpdfDocument`, `QpdfObject`, `QpdfPage` with
  builder-style options and sealed exception types
- **Async API** — `QpdfAsync` runs every operation in an isolate, safe to
  call from Flutter UI code or server event loops
- **Encryption** — AES-256 (R6), AES-128 (R5/R4), RC4 (R2/R3); Unicode
  passwords; owner + user password support; per-action permissions
- **Automatic native asset bundling** — prebuilt qpdf binaries are downloaded
  at build time for supported desktop platforms, with a system-install fallback

## Installation

```yaml
dependencies:
  qpdf: ^0.1.0
```

### Native library

This package needs the qpdf 12.x shared library at runtime. It is obtained
automatically through a Dart native asset [build hook](hook/build.dart):

| Platform | Arch  | Behavior                                              |
| -------- | ----- | ----------------------------------------------------- |
| Linux    | x64   | Prebuilt downloaded from this package's GitHub releases |
| Linux    | arm64 | Prebuilt downloaded from this package's GitHub releases |
| macOS    | x64   | Prebuilt downloaded from this package's GitHub releases |
| macOS    | arm64 | Prebuilt downloaded from this package's GitHub releases |
| Windows  | x64   | Prebuilt downloaded from this package's GitHub releases |
| Windows  | arm64 | Prebuilt downloaded from this package's GitHub releases |
| Android  | any   | System install required (mobile prebuilts planned)    |
| iOS      | any   | System install required (mobile prebuilts planned)    |

The prebuilt `libqpdf` has `zlib`, `libjpeg-turbo`, and `OpenSSL` statically
linked — nothing else to install.

**Fallback.** If the prebuilt download fails (offline build, firewalled CI,
unsupported platform), the hook falls back to a system-installed qpdf:

| Platform              | Install command                  |
| --------------------- | -------------------------------- |
| macOS                 | `brew install qpdf`              |
| Debian / Ubuntu       | `sudo apt install libqpdf-dev`   |
| Fedora / RHEL         | `sudo dnf install qpdf-libs`     |
| Windows               | [qpdf releases](https://github.com/qpdf/qpdf/releases) (add `bin` to PATH) |

Watch the build log for lines prefixed `[qpdf]` to see which path is taken.

## Usage

### Sync API

```dart
import 'package:qpdf/qpdf.dart';

void main() {
  final doc = QpdfDocument.open('input.pdf');
  try {
    print('Pages: ${doc.pageCount}');
    print('Version: ${doc.pdfVersion}');
    print('Encrypted: ${doc.isEncrypted}');

    doc.title = 'Updated Title';
    doc.author = 'Dart qpdf';

    doc.writeToFile(
      'output.pdf',
      options: const WriteOptions(linearize: true),
    );
  } finally {
    doc.dispose();
  }
}
```

### Async API (Flutter & servers)

Every operation runs in a fresh isolate. Safe from Flutter UI threads and
high-throughput servers.

```dart
import 'package:qpdf/qpdf.dart';

Future<void> main() async {
  const qpdf = QpdfAsync();

  // Inspect a PDF
  final info = await qpdf.getInfo('input.pdf');
  print('Pages: ${info.pageCount}');

  // Decrypt a password-protected PDF
  await qpdf.decrypt(
    'encrypted.pdf',
    'decrypted.pdf',
    password: 'secret',
  );

  // Encrypt with AES-256
  await qpdf.encrypt(
    'input.pdf',
    'encrypted.pdf',
    const R6EncryptionParams(
      userPassword: 'user',
      ownerPassword: 'owner',
      print: R3PrintPermission.low,
      allowExtract: false,
    ),
  );

  // Merge, linearize, check
  await qpdf.merge(['a.pdf', 'b.pdf'], 'merged.pdf');
  await qpdf.linearize('input.pdf', 'web.pdf');
  final warnings = await qpdf.check('input.pdf');
}
```

### Error handling

All failures raise a typed subclass of the sealed `QpdfException`:

```dart
try {
  final doc = QpdfDocument.open('encrypted.pdf', password: 'wrong');
} on QpdfPasswordException {
  // Incorrect password
} on QpdfDamagedPdfException {
  // Malformed / corrupt PDF
} on QpdfSystemException {
  // I/O error (file not found, permission denied, etc.)
} on QpdfException catch (e) {
  // Any other qpdf error
  print('${e.code}: ${e.message}');
}
```

### Low-level PDF object access

For advanced use cases, traverse and mutate PDF objects directly:

```dart
final doc = QpdfDocument.open('input.pdf');
try {
  final root = doc.root;                // Catalog
  final pages = root.getKey('/Pages');
  final count = pages.getKey('/Count').intValue;

  for (final key in root.dictKeys) {
    print('$key: ${root.getKey(key).typeName}');
  }

  // Mutate
  final info = doc.trailer.getKey('/Info');
  info.replaceKey('/Title', doc.newUnicodeString('New Title'));
} finally {
  doc.dispose();
}
```

## Resource management

`QpdfDocument` holds native resources. Prefer explicit disposal:

```dart
final doc = QpdfDocument.open('input.pdf');
try {
  /* use doc */
} finally {
  doc.dispose();
}
```

A `NativeFinalizer` is also attached — if a `QpdfDocument` becomes
unreachable without `dispose()` being called, the underlying `qpdf_data`
is reclaimed by the garbage collector. Explicit disposal is still
recommended because finalizer timing is non-deterministic.

The async API disposes automatically — each operation spawns a fresh
isolate that owns and releases its own document.

## Thread / Isolate safety

`qpdf_data` handles are not thread-safe:

- A `QpdfDocument` must only be used on the isolate that created it
- Never pass a `QpdfDocument` across isolate boundaries
- `QpdfAsync` enforces this by creating each document inside its
  worker isolate and returning only plain Dart values

## Architecture

```
lib/src/
  bindings/qpdf_bindings.g.dart  # ffigen-generated FFI bindings (do not edit)
  native/                        # Library loading, error mapping, string utils
  models/                        # Pure Dart types: exceptions, enums, options
  qpdf_document.dart             # Main high-level class
  qpdf_object.dart               # PDF object wrapper (qpdf_oh)
  qpdf_page.dart                 # Page abstraction
  qpdf_async.dart                # Isolate-based async facade
hook/build.dart                  # Native asset download + system fallback
tool/                            # Maintainer scripts for building prebuilts
```

## Versioning

- **This package** follows semver from `0.1.0` onward
- **qpdf** is pinned per release — the current prebuilts track
  **qpdf 12.3.2**

## License

```
BSD 3-Clause License

Copyright (c) 2026, Birju Vachhani

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

```

### Third-party notices

This package includes qpdf C API headers in
[`third_party/include/qpdf/`](third_party/include/qpdf/), which are
Copyright © 2005-2021 Jay Berkenbilt and © 2022-2026 Jay Berkenbilt and
Manfred Holger, distributed under the Apache License 2.0. See
<https://github.com/qpdf/qpdf> for the upstream source.

The prebuilt `libqpdf` shared libraries distributed via this package's
GitHub Releases statically link [zlib](https://zlib.net/),
[libjpeg-turbo](https://libjpeg-turbo.org/), and
[OpenSSL](https://www.openssl.org/), each under its respective license.