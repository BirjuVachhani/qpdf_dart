# Releasing prebuilt qpdf binaries

The Dart `qpdf` package downloads prebuilt qpdf shared libraries from this
repository's GitHub Releases at build time. This document describes how to
produce a new set of prebuilts — e.g., when updating to a new qpdf version.

## Overview

```
tool/build_qpdf.sh          # Cross-platform build script (runs in CI)
.github/workflows/
  build-prebuilts.yml       # GitHub Actions workflow that runs the build
                            # on 6 platform matrices and uploads a release
hook/build.dart             # At install-time: downloads the prebuilt for
                            # the user's target platform
```

## What's produced

Six self-contained shared libraries, one per desktop platform:

| OS      | Arch   | File                  | Downloaded by `hook/build.dart` as |
|---------|--------|-----------------------|------------------------------------|
| Linux   | x64    | `libqpdf.so`          | `libqpdf-linux-x64.tar.gz`         |
| Linux   | arm64  | `libqpdf.so`          | `libqpdf-linux-arm64.tar.gz`       |
| macOS   | arm64  | `libqpdf.dylib`       | `libqpdf-macos-arm64.tar.gz`       |
| macOS   | x64    | `libqpdf.dylib`       | `libqpdf-macos-x64.tar.gz`         |
| Windows | x64    | `qpdf29.dll`          | `libqpdf-windows-x64.tar.gz`       |
| Windows | arm64  | `qpdf29.dll`          | `libqpdf-windows-arm64.tar.gz`     |

Each library has **all dependencies statically linked**: `zlib`,
`libjpeg-turbo`, and `OpenSSL`. The resulting file has no external runtime
dependencies beyond the OS C runtime.

## Releasing a new prebuilt set

### Step 1 — Bump versions in 4 places

All four must match. `grep` makes this easy:

```bash
# The upstream qpdf version
grep -rn "12\.3\.2" third_party/include/qpdf/DLL.h       # upstream header
grep -rn "12\.3\.2" hook/build.dart                      # hook constant
grep -rn "12\.3\.2" .github/workflows/build-prebuilts.yml # workflow env
```

In detail:

1. **`.github/workflows/build-prebuilts.yml`** — update `QPDF_VERSION` env var.
2. **`hook/build.dart`** — update `_qpdfVersion` and (if needed)
   `_prebuiltsRevision`. The `_prebuiltsTag` is derived from these two.
3. **`third_party/include/qpdf/`** — re-fetch headers pinned to the new
   version:
   ```bash
   cd third_party/include/qpdf
   for f in qpdf-c.h Constants.h Types.h DLL.h qpdflogger-c.h; do
     curl -fsSL "https://raw.githubusercontent.com/qpdf/qpdf/v<VERSION>/include/qpdf/$f" -o "$f"
   done
   ```
4. **`lib/src/bindings/qpdf_bindings.g.dart`** — regenerate:
   ```bash
   dart run ffigen --config ffigen.yaml
   ```

### Step 2 — Bump the prebuilts revision if needed

If you're rebuilding the **same** qpdf version (e.g., because of a CI fix):
increment `_prebuiltsRevision` in `hook/build.dart`. Leave it at `1` for a
fresh qpdf version bump.

### Step 3 — Trigger the build

The workflow responds to **three** equivalent triggers. Pick whichever fits:

#### Option A — Push a tag (classic)

```bash
git commit -am "build: qpdf 12.3.3 prebuilts"
git tag prebuilts-v12.3.3-1
git push origin main --tags
```

#### Option B — Manual dispatch from the Actions UI

1. Go to the repo's **Actions** tab → **Build qpdf prebuilts** workflow
2. Click **Run workflow** (top right)
3. Enter the tag name, e.g. `prebuilts-v12.3.3-1`
4. Click **Run workflow**

If no git tag and no release exist for that name yet, the workflow creates
them both (tag will point at the current HEAD of the chosen branch).

#### Option C — Create a GitHub Release in the UI

1. Go to **Releases** → **Draft a new release**
2. Set the tag name (e.g. `prebuilts-v12.3.3-1`)
3. Click **Publish release**

The workflow fires automatically on `release: published` and uploads
artifacts to that release.

---

All three paths run the same six cross-compile jobs in parallel (~15–25 min),
then upload six tarballs to the GitHub Release at that tag. `hook/build.dart`
will start downloading from that tag on the next
`dart pub get` / `flutter pub get`.

### Step 4 — Verify

On each of your available platforms:

```bash
rm -rf .dart_tool/
dart pub get
dart test test/integration_test.dart --tags integration
```

The hook should download the prebuilt (watch stderr) and all integration
tests should pass.

## Manual local run

To test the build script locally on your current platform:

```bash
export QPDF_VERSION=12.3.2 ZLIB_VERSION=1.3.1 JPEG_VERSION=3.0.4 OPENSSL_VERSION=3.3.2
export TARGET_OS=macos TARGET_ARCH=arm64   # adjust for your host
bash tool/build_qpdf.sh
# Output: build/dist/libqpdf-macos-arm64.tar.gz
```

This is useful for debugging CI failures.

## Fallback behavior

If the prebuilt download fails at install time (e.g., the user is offline or
GitHub is unreachable), `hook/build.dart` falls back to a system-installed
qpdf library. The fallback paths are also used on platforms we do not ship
prebuilts for (e.g., Android, iOS).

## Notes on dependencies

- **OpenSSL** is required for AES-256 encryption/decryption. We build it
  from source with `no-shared` so all symbols end up inside `libqpdf.so`.
- **libjpeg-turbo** is required for JPEG stream handling in PDFs.
- **zlib** is required for FlateDecode streams (the most common PDF filter).

The build script versions these deps explicitly so builds are reproducible.
