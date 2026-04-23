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
#   QPDF_BUILD_STRATEGY — "source" | "upstream-release" (default: "source")
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
# The tarball contains the primary library at the top level:
#     Linux   → libqpdf.so
#     macOS   → libqpdf.dylib
#     Windows → qpdf29.dll
#
# The windows-x64 upstream-repackaged artifact may also contain additional
# top-level DLLs required by the upstream qpdf distribution.
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
QPDF_BUILD_STRATEGY="${QPDF_BUILD_STRATEGY:-source}"

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

job_count() {
  nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4
}

prepare_windows_toolchain() {
  [ "$TARGET_OS" = "windows" ] || return 0

  # Ensure MSVC tools win PATH resolution inside Git Bash so OpenSSL/nmake
  # don't accidentally pick Git's `link` utility.
  local cl_path=""
  cl_path="$(command -v cl.exe 2>/dev/null || command -v cl 2>/dev/null || true)"
  if [ -n "$cl_path" ]; then
    export PATH="$(dirname "$cl_path"):$PATH"
  fi

  [ "$QPDF_BUILD_STRATEGY" = "source" ] || return 0

  local link_path=""
  local nmake_path=""
  local rc_path=""
  local pkg_config_path=""

  cl_path="$(command -v cl.exe 2>/dev/null || command -v cl 2>/dev/null || true)"
  link_path="$(command -v link.exe 2>/dev/null || command -v link 2>/dev/null || true)"
  nmake_path="$(command -v nmake.exe 2>/dev/null || command -v nmake 2>/dev/null || true)"
  rc_path="$(command -v rc.exe 2>/dev/null || command -v rc 2>/dev/null || true)"
  pkg_config_path="$(command -v pkg-config.exe 2>/dev/null || command -v pkg-config 2>/dev/null || true)"

  echo "==> Windows toolchain diagnostics"
  echo "    cl:    ${cl_path:-<missing>}"
  echo "    link:  ${link_path:-<missing>}"
  echo "    nmake: ${nmake_path:-<missing>}"
  echo "    rc:    ${rc_path:-<missing>}"
  echo "    pkg-config: ${pkg_config_path:-<missing>}"
  echo "    CFLAGS: ${CFLAGS:-<unset>}"
  echo "    CXXFLAGS: ${CXXFLAGS:-<unset>}"

  if [ -z "$cl_path" ] || [ -z "$link_path" ] || [ -z "$nmake_path" ] || [ -z "$rc_path" ]; then
    echo "Missing required Windows build tools on PATH"
    exit 1
  fi

  case "$cl_path" in
    *Microsoft\ Visual\ Studio*|*MSVC*) ;;
    *)
      echo "Resolved cl is not from MSVC: $cl_path"
      exit 1
      ;;
  esac

  case "$link_path" in
    *Microsoft\ Visual\ Studio*|*MSVC*) ;;
    *)
      echo "Resolved link is not from MSVC: $link_path"
      exit 1
      ;;
  esac

  case " ${CFLAGS:-} ${CXXFLAGS:-} " in
    *" -fPIC "*)
      echo "Unix flag -fPIC leaked into Windows build flags"
      exit 1
      ;;
  esac
}

extract_zip() {
  local archive="$1"
  local dest="$2"

  rm -rf "$dest"
  mkdir -p "$dest"

  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$archive" -d "$dest"
  else
    tar -xf "$archive" -C "$dest"
  fi
}

package_staging_dir() {
  local staging="$1"

  case "$TARGET_OS" in
    linux) ldd "$staging"/*.so || true ;;
    macos) otool -L "$staging"/*.dylib || true ;;
    windows) : ;;
  esac

  local tarball="$DIST_DIR/libqpdf-${TARGET_OS}-${TARGET_ARCH}.tar.gz"
  tar -czf "$tarball" -C "$staging" .
  echo "==> Wrote $tarball"
  ls -lh "$tarball"
}

# Shared C flags for native builds. Windows/MSVC must not inherit Unix flags.
if [ "$TARGET_OS" = "windows" ]; then
  export CFLAGS="${CFLAGS:-} /O2"
  export CXXFLAGS="${CXXFLAGS:-} /O2"
else
  # PIC is required so static deps can be linked into the shared libqpdf.
  export CFLAGS="${CFLAGS:-} -fPIC -O2"
  export CXXFLAGS="${CXXFLAGS:-} -fPIC -O2"
fi

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
    make -j"$(job_count)"
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

  if [ "$TARGET_OS" = "windows" ]; then
    local jpeg_lib=""
    for jpeg_lib in \
      "$PREFIX/lib/jpeg-static.lib" \
      "$PREFIX/lib/libjpeg-static.lib" \
      "$PREFIX/lib/jpeg.lib" \
      "$PREFIX/lib/libjpeg.lib"
    do
      if [ -f "$jpeg_lib" ]; then
        if [ ! -f "$PREFIX/lib/jpeg.lib" ]; then
          cp "$jpeg_lib" "$PREFIX/lib/jpeg.lib"
        fi
        if [ ! -f "$PREFIX/lib/libjpeg.lib" ]; then
          cp "$jpeg_lib" "$PREFIX/lib/libjpeg.lib"
        fi
        break
      fi
    done
  fi
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
    make -j"$(job_count)"
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
  local cmake_prefix_path="$PREFIX"
  local pkg_config_exe=""
  local jpeg_library=""
  local zlib_library=""
  if [ "$TARGET_OS" = "macos" ]; then
    # Set rpath so the library is locatable when loaded via DynamicLibrary.open
    extra_cmake_args+=("-DCMAKE_INSTALL_NAME_DIR=@rpath")
  fi

  if [ -n "${CMAKE_PREFIX_PATH:-}" ]; then
    if [ "$TARGET_OS" = "windows" ]; then
      cmake_prefix_path="$PREFIX;${CMAKE_PREFIX_PATH}"
    else
      cmake_prefix_path="$PREFIX:${CMAKE_PREFIX_PATH}"
    fi
  fi

  if [ "$TARGET_OS" = "windows" ]; then
    # On Windows/MSVC, pkg-config commonly reports zlib as `-lz`, which CMake
    # turns into `z.lib`. Force CMake to use the explicit library paths below.
    extra_cmake_args+=("-DCMAKE_DISABLE_FIND_PACKAGE_PkgConfig=ON")
  else
    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    if [ -d "$PREFIX/lib64/pkgconfig" ]; then
      export PKG_CONFIG_PATH="$PREFIX/lib64/pkgconfig:$PKG_CONFIG_PATH"
    fi

    pkg_config_exe="$(command -v pkg-config.exe 2>/dev/null || command -v pkg-config 2>/dev/null || true)"
    if [ -n "$pkg_config_exe" ]; then
      extra_cmake_args+=("-DPKG_CONFIG_EXECUTABLE=$pkg_config_exe")
    fi
  fi

  for jpeg_library in \
    "$PREFIX/lib/jpeg.lib" \
    "$PREFIX/lib/libjpeg.lib" \
    "$PREFIX/lib/jpeg-static.lib" \
    "$PREFIX/lib/libjpeg-static.lib"
  do
    if [ -f "$jpeg_library" ]; then
      extra_cmake_args+=(
        "-DJPEG_INCLUDE_DIR=$PREFIX/include"
        "-DJPEG_LIBRARY=$jpeg_library"
        "-DJPEG_LIBRARY_RELEASE=$jpeg_library"
        "-DJPEG_LIBRARIES=$jpeg_library"
      )
      break
    fi
  done

  for zlib_library in \
    "$PREFIX/lib/zlib.lib" \
    "$PREFIX/lib/zlibstatic.lib"
  do
    if [ -f "$zlib_library" ]; then
      extra_cmake_args+=(
        "-DZLIB_INCLUDE_DIR=$PREFIX/include"
        "-DZLIB_LIBRARY=$zlib_library"
        "-DZLIB_LIBRARY_RELEASE=$zlib_library"
        "-DZLIB_LIBRARIES=$zlib_library"
      )
      break
    fi
  done

  echo "==> qpdf dependency discovery"
  echo "    CMAKE_PREFIX_PATH: $cmake_prefix_path"
  echo "    PKG_CONFIG_PATH: ${PKG_CONFIG_PATH:-<unset>}"
  echo "    PKG_CONFIG_EXECUTABLE: ${pkg_config_exe:-<missing>}"
  echo "    JPEG library: ${jpeg_library:-<missing>}"
  echo "    ZLIB library: ${zlib_library:-<missing>}"

  cmake -B build -S . \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$cmake_prefix_path" \
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
    cmake --build build -j"$(job_count)"
    cmake --install build
  fi
}

reuse_upstream_release() {
  echo "==> Repackaging upstream qpdf release artifact"
  cd "$SRC_DIR"

  local archive=""
  local extracted="$BUILD_ROOT/upstream"
  local staging="$BUILD_ROOT/staging"

  case "${TARGET_OS}-${TARGET_ARCH}" in
    windows-x64)
      archive="qpdf-${QPDF_VERSION}-msvc64.zip"
      ;;
    *)
      echo "Unsupported upstream-release target: ${TARGET_OS}-${TARGET_ARCH}"
      exit 1
      ;;
  esac

  fetch "https://github.com/qpdf/qpdf/releases/download/v${QPDF_VERSION}/${archive}" "$archive"
  extract_zip "$archive" "$extracted"

  rm -rf "$staging"
  mkdir -p "$staging"

  case "${TARGET_OS}-${TARGET_ARCH}" in
    windows-x64)
      mapfile -t dlls < <(find "$extracted" -iname "*.dll" | sort)
      if [ "${#dlls[@]}" -eq 0 ]; then
        echo "Could not find any DLLs in upstream archive"
        exit 1
      fi
      local main_dll=""
      main_dll="$(find "$extracted" -iname "qpdf*.dll" | head -1)"
      if [ -z "$main_dll" ]; then
        echo "Could not find qpdf DLL in upstream archive"
        exit 1
      fi
      local dll
      for dll in "${dlls[@]}"; do
        cp "$dll" "$staging/$(basename "$dll")"
      done
      if [ "$(basename "$main_dll")" != "qpdf29.dll" ]; then
        cp "$main_dll" "$staging/qpdf29.dll"
      fi
      ;;
  esac

  package_staging_dir "$staging"
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

  package_staging_dir "$staging"
}

# ---------- main ----------

prepare_windows_toolchain

case "$QPDF_BUILD_STRATEGY" in
  upstream-release)
    reuse_upstream_release
    ;;
  source)
    build_zlib
    build_jpeg
    build_openssl
    build_qpdf
    package_artifact
    ;;
  *)
    echo "Unknown QPDF_BUILD_STRATEGY: $QPDF_BUILD_STRATEGY"
    exit 1
    ;;
esac

echo "==> Done."
