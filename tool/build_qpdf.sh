#!/usr/bin/env bash
# Builds qpdf as a self-contained shared library with statically-linked
# dependencies (zlib, libjpeg-turbo, OpenSSL).
#
# Expects these environment variables (set by the CI workflow):
#   QPDF_VERSION     — e.g. "12.3.2"
#   ZLIB_VERSION     — e.g. "1.3.1"
#   JPEG_VERSION     — e.g. "3.0.4" (libjpeg-turbo)
#   OPENSSL_VERSION  — e.g. "3.3.2"
#   TARGET_OS        — "linux" | "macos" | "windows"
#   TARGET_ARCH      — "x64" | "arm64"
#
# -----------------------------------------------------------------------------
# Artifact naming convention — KEEP IN SYNC WITH `hook/build.dart`
# -----------------------------------------------------------------------------
#
# Output tarball:
#     build/dist/libqpdf-<os>-<arch>.tar.gz
#
# where <os> ∈ { linux, macos, windows }
#       <arch> ∈ { x64, arm64 }
#
# The tarball contains exactly ONE file at the top level:
#     Linux   → libqpdf.so
#     macOS   → libqpdf.dylib
#     Windows → qpdf29.dll
#
# The hook (`hook/build.dart`) constructs the same filename when downloading
# from GitHub releases. If you change the name here, update the hook too.

set -euo pipefail

: "${QPDF_VERSION:?QPDF_VERSION is required}"
: "${ZLIB_VERSION:?ZLIB_VERSION is required}"
: "${JPEG_VERSION:?JPEG_VERSION is required}"
: "${OPENSSL_VERSION:?OPENSSL_VERSION is required}"
: "${TARGET_OS:?TARGET_OS is required}"
: "${TARGET_ARCH:?TARGET_ARCH is required}"

BUILD_ROOT="$(pwd)/build"
SRC_DIR="$BUILD_ROOT/src"
PREFIX="$BUILD_ROOT/prefix"
DIST_DIR="$BUILD_ROOT/dist"

mkdir -p "$SRC_DIR" "$PREFIX/lib" "$PREFIX/include" "$DIST_DIR"

# ---------- helpers ----------

fetch() {
  local url="$1"
  local out="$2"
  echo "==> Fetching $url"
  curl -fsSL --retry 3 -o "$out" "$url"
}

# Shared C flags for static deps (PIC required so they can be linked into libqpdf.so)
export CFLAGS="${CFLAGS:-} -fPIC -O2"
export CXXFLAGS="${CXXFLAGS:-} -fPIC -O2"

# MacOS deployment target is already set in the workflow env
if [ "$TARGET_OS" = "macos" ]; then
  export CFLAGS="$CFLAGS -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET:-10.15}"
  export CXXFLAGS="$CXXFLAGS -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET:-10.15}"
fi

# ---------- zlib (static) ----------

build_zlib() {
  echo "==> Building zlib $ZLIB_VERSION"
  cd "$SRC_DIR"
  fetch "https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz" zlib.tar.gz
  rm -rf "zlib-${ZLIB_VERSION}"
  tar xzf zlib.tar.gz
  cd "zlib-${ZLIB_VERSION}"

  if [ "$TARGET_OS" = "windows" ]; then
    # Use CMake on Windows
    cmake -B build -S . \
      -DCMAKE_INSTALL_PREFIX="$PREFIX" \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DZLIB_BUILD_EXAMPLES=OFF
    cmake --build build --config Release -j
    cmake --install build --config Release
    # zlib on Windows installs as zlibstatic.lib; normalize to zlib.lib
    if [ -f "$PREFIX/lib/zlibstatic.lib" ] && [ ! -f "$PREFIX/lib/zlib.lib" ]; then
      cp "$PREFIX/lib/zlibstatic.lib" "$PREFIX/lib/zlib.lib"
    fi
  else
    ./configure --prefix="$PREFIX" --static
    make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)
    make install
  fi
}

# ---------- libjpeg-turbo (static) ----------

build_jpeg() {
  echo "==> Building libjpeg-turbo $JPEG_VERSION"
  cd "$SRC_DIR"
  fetch "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/${JPEG_VERSION}/libjpeg-turbo-${JPEG_VERSION}.tar.gz" jpeg.tar.gz
  rm -rf "libjpeg-turbo-${JPEG_VERSION}"
  tar xzf jpeg.tar.gz
  cd "libjpeg-turbo-${JPEG_VERSION}"

  cmake -B build -S . \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_SHARED=OFF \
    -DENABLE_STATIC=ON \
    -DWITH_TURBOJPEG=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  cmake --build build --config Release -j
  cmake --install build --config Release
}

# ---------- OpenSSL (static, provides crypto for AES-256) ----------

build_openssl() {
  echo "==> Building OpenSSL $OPENSSL_VERSION"
  cd "$SRC_DIR"
  fetch "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" openssl.tar.gz
  rm -rf "openssl-${OPENSSL_VERSION}"
  tar xzf openssl.tar.gz
  cd "openssl-${OPENSSL_VERSION}"

  # Map our (os,arch) to an OpenSSL Configure target
  local ssl_target=""
  case "${TARGET_OS}-${TARGET_ARCH}" in
    linux-x64)     ssl_target="linux-x86_64" ;;
    linux-arm64)   ssl_target="linux-aarch64" ;;
    macos-x64)     ssl_target="darwin64-x86_64-cc" ;;
    macos-arm64)   ssl_target="darwin64-arm64-cc" ;;
    windows-x64)   ssl_target="VC-WIN64A" ;;
    windows-arm64) ssl_target="VC-WIN64-ARM" ;;
    *) echo "Unknown target: $TARGET_OS-$TARGET_ARCH"; exit 1 ;;
  esac

  perl ./Configure "$ssl_target" \
    --prefix="$PREFIX" \
    --openssldir="$PREFIX/ssl" \
    no-shared \
    no-tests \
    no-docs

  if [ "$TARGET_OS" = "windows" ]; then
    nmake
    nmake install_sw
  else
    make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)
    make install_sw
  fi
}

# ---------- qpdf (shared) ----------

build_qpdf() {
  echo "==> Building qpdf $QPDF_VERSION"
  cd "$SRC_DIR"
  fetch "https://github.com/qpdf/qpdf/releases/download/v${QPDF_VERSION}/qpdf-${QPDF_VERSION}.tar.gz" qpdf.tar.gz
  rm -rf "qpdf-${QPDF_VERSION}"
  tar xzf qpdf.tar.gz
  cd "qpdf-${QPDF_VERSION}"

  local extra_cmake_args=()
  if [ "$TARGET_OS" = "macos" ]; then
    # Set rpath so the library is locatable when loaded via DynamicLibrary.open
    extra_cmake_args+=("-DCMAKE_INSTALL_NAME_DIR=@rpath")
  fi

  cmake -B build -S . \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_STATIC_LIBS=OFF \
    -DBUILD_DOC=OFF \
    -DBUILD_DOC_HTML=OFF \
    -DBUILD_DOC_PDF=OFF \
    -DOSS_FUZZ=OFF \
    -DREQUIRE_CRYPTO_OPENSSL=ON \
    -DUSE_IMPLICIT_CRYPTO=OFF \
    -DZLIB_USE_STATIC_LIBS=ON \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DOPENSSL_ROOT_DIR="$PREFIX" \
    "${extra_cmake_args[@]}"

  if [ "$TARGET_OS" = "windows" ]; then
    cmake --build build --config Release -j
    cmake --install build --config Release
  else
    cmake --build build -j
    cmake --install build
  fi
}

# ---------- package ----------

package_artifact() {
  echo "==> Packaging artifact"
  local staging="$BUILD_ROOT/staging"
  rm -rf "$staging"
  mkdir -p "$staging"

  # Locate and stage the shared library
  case "$TARGET_OS" in
    linux)
      # Prefer the SONAME-less symlink if present; otherwise the versioned one.
      if [ -f "$PREFIX/lib/libqpdf.so" ]; then
        cp -L "$PREFIX/lib/libqpdf.so" "$staging/libqpdf.so"
      else
        local first
        first=$(ls "$PREFIX/lib/"libqpdf.so.* 2>/dev/null | head -1)
        cp -L "$first" "$staging/libqpdf.so"
      fi
      ;;
    macos)
      # Fully resolve symlinks and normalize name
      local src
      if [ -f "$PREFIX/lib/libqpdf.dylib" ]; then
        src="$PREFIX/lib/libqpdf.dylib"
      else
        src=$(ls "$PREFIX/lib/"libqpdf.*.dylib 2>/dev/null | head -1)
      fi
      cp -L "$src" "$staging/libqpdf.dylib"
      # Ensure install name is @rpath-relative for portability
      install_name_tool -id "@rpath/libqpdf.dylib" "$staging/libqpdf.dylib" || true
      ;;
    windows)
      # qpdf installs the DLL under bin/, import lib under lib/
      local dll
      dll=$(find "$PREFIX/bin" -iname "qpdf*.dll" | head -1)
      if [ -z "$dll" ]; then
        dll=$(find "$PREFIX" -iname "qpdf*.dll" | head -1)
      fi
      cp "$dll" "$staging/qpdf29.dll"
      ;;
  esac

  # Verify the library has no unexpected dynamic deps (best-effort)
  case "$TARGET_OS" in
    linux) ldd "$staging"/*.so || true ;;
    macos) otool -L "$staging"/*.dylib || true ;;
    windows) : ;;  # dumpbin not always available on bash
  esac

  local tarball="$DIST_DIR/libqpdf-${TARGET_OS}-${TARGET_ARCH}.tar.gz"
  tar -czf "$tarball" -C "$staging" .
  echo "==> Wrote $tarball"
  ls -lh "$tarball"
}

# ---------- main ----------

build_zlib
build_jpeg
build_openssl
build_qpdf
package_artifact

echo "==> Done."
