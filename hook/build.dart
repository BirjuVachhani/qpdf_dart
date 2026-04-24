import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

// -----------------------------------------------------------------------------
// Version & release configuration
// -----------------------------------------------------------------------------

/// qpdf C library version that the prebuilts are built against.
///
/// Must match:
///   - headers in `third_party/include/qpdf/`
///   - generated bindings in `lib/src/bindings/qpdf_bindings.g.dart`
///   - `QPDF_VERSION` in `.github/workflows/build-prebuilts.yml`
///   - the `prebuilts-<version>` release tag on GitHub
const _qpdfVersion = '12.3.2';

/// Repository that hosts the prebuilt binaries. Must be the repository of
/// **this package**, not qpdf upstream.
const _prebuiltsRepo = 'BirjuVachhani/qpdf_dart';

/// GitHub release tag used for prebuilt downloads. Derived from the qpdf
/// version so the package is always pinned to a specific prebuilt release.
/// See `.github/workflows/build-prebuilts.yml`.
const _prebuiltsTag = 'prebuilts-$_qpdfVersion';

const _packageName = 'qpdf';
const _assetId = 'package:qpdf/src/native/libqpdf';

// -----------------------------------------------------------------------------
// Artifact naming convention — KEEP IN SYNC WITH `tool/build_qpdf.sh`
// -----------------------------------------------------------------------------
//
// Each prebuilt release asset is a gzipped tarball named:
//
//     libqpdf-<os>-<arch>.tar.gz
//
// where:
//     <os>    ∈ { "linux", "macos", "windows" }
//     <arch>  ∈ { "x64", "arm64" }
//
// The tarball contains the primary library at the top level:
//
//     Linux   → libqpdf.so       (shared object)
//     macOS   → libqpdf.dylib    (shared library)
//     Windows → qpdf29.dll       (dynamic link library)
//
// Source-built prebuilts statically link native dependencies into a single
// library file. The windows-x64 prebuilt is repackaged from the matching
// upstream qpdf release for the same qpdf version and may include additional
// top-level DLLs from that upstream bundle.
//
// Full download URL:
//     https://github.com/<repo>/releases/download/<tag>/libqpdf-<os>-<arch>.tar.gz
//
// If either the CI build script or this hook changes the naming, update both.

/// Platforms for which we publish prebuilt binaries via our own CI.
/// Other platforms fall back to the system-installed qpdf library.
const _prebuiltPlatforms = <(OS, Architecture)>{
  (OS.linux, Architecture.x64),
  (OS.linux, Architecture.arm64),
  (OS.macOS, Architecture.x64),
  (OS.macOS, Architecture.arm64),
  (OS.windows, Architecture.x64),
  (OS.windows, Architecture.arm64),
};

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

/// Prints a hook log line to stderr with a consistent prefix.
/// All build-hook diagnostics go through this so users can filter logs by
/// the `[qpdf]` tag when debugging pub get / flutter pub get failures.
void _log(String message) {
  stderr.writeln('[qpdf] $message');
}

/// Prints an indented detail line (used for nested diagnostics).
void _logDetail(String message) {
  stderr.writeln('[qpdf]   $message');
}

// -----------------------------------------------------------------------------
// Entry point
// -----------------------------------------------------------------------------

void main(List<String> args) async {
  await build(args, _buildHook);
}

Future<void> _buildHook(BuildInput input, BuildOutputBuilder output) async {
  if (!input.config.buildCodeAssets) {
    return;
  }

  final targetOS = input.config.code.targetOS;
  final targetArch = input.config.code.targetArchitecture;
  final outDir = input.outputDirectoryShared;

  _log(
    'Resolving qpdf $_qpdfVersion for ${_osSuffix(targetOS)}-'
    '${_archSuffix(targetArch)}',
  );

  final libraryFile = await _resolveLibrary(
    os: targetOS,
    arch: targetArch,
    outDir: outDir,
  );

  _log('Using library: ${libraryFile.path}');

  output.assets.code.add(
    CodeAsset(
      package: _packageName,
      name: _assetId,
      linkMode: DynamicLoadingBundled(),
      file: libraryFile.uri,
    ),
  );
  output.dependencies.add(libraryFile.uri);
}

// -----------------------------------------------------------------------------
// Library resolution pipeline
// -----------------------------------------------------------------------------

/// Resolves the qpdf native library using this priority order:
///
///   1. **Cache** — if we already downloaded/extracted it previously, use it.
///   2. **Prebuilt download** — for supported platforms, download the release
///      artifact from our GitHub releases.
///   3. **System library** — search well-known OS paths for a qpdf install.
///
/// Throws [StateError] only after all three strategies fail.
Future<File> _resolveLibrary({
  required OS os,
  required Architecture arch,
  required Uri outDir,
}) async {
  // ---- Strategy 1: Cache -------------------------------------------------
  final cached = File.fromUri(outDir.resolve(_libraryFilename(os)));
  if (cached.existsSync()) {
    _log('Cache hit: ${cached.path}');
    return cached;
  }
  _log('Cache miss: ${cached.path}');

  // ---- Strategy 2: Prebuilt download ------------------------------------
  if (_prebuiltPlatforms.contains((os, arch))) {
    try {
      final downloaded = await _downloadPrebuilt(
        os: os,
        arch: arch,
        outDir: outDir,
      );
      _log('Prebuilt downloaded successfully');
      return downloaded;
    } on Exception catch (e) {
      _log('Prebuilt download failed: $e');
      _log('Falling back to system-installed qpdf…');
    }
  } else {
    _log(
      'No prebuilt published for ${_osSuffix(os)}-${_archSuffix(arch)}; '
      'checking system-installed qpdf…',
    );
  }

  // ---- Strategy 3: System install ---------------------------------------
  return _findSystemLibrary(os);
}

// -----------------------------------------------------------------------------
// Strategy 2: Prebuilt download
// -----------------------------------------------------------------------------

Future<File> _downloadPrebuilt({
  required OS os,
  required Architecture arch,
  required Uri outDir,
}) async {
  final assetName = _artifactName(os, arch);
  final url = Uri.parse(
    'https://github.com/$_prebuiltsRepo/releases/download/$_prebuiltsTag/$assetName',
  );

  _log('Attempting prebuilt download');
  _logDetail('asset: $assetName');
  _logDetail('url:   $url');

  final outDirPath = outDir.toFilePath();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  try {
    final response = await _getFollowingRedirects(client, url);
    final contentLength = response.contentLength;
    if (contentLength > 0) {
      _logDetail('size:  ${_formatBytes(contentLength)}');
    }

    final archiveFile = File('$outDirPath/qpdf_prebuilt.tar.gz');
    await response.pipe(archiveFile.openWrite());
    _logDetail('downloaded → ${archiveFile.path}');

    await _extractTarGz(archiveFile, Directory(outDirPath));
    archiveFile.deleteSync();

    final libName = _libraryFilename(os);
    final lib = File('$outDirPath/$libName');
    if (!lib.existsSync()) {
      throw StateError(
        'Archive $assetName did not contain expected "$libName" at top level',
      );
    }
    _logDetail('extracted → ${lib.path}');
    return lib;
  } finally {
    client.close();
  }
}

/// Performs a GET that follows up to 5 redirects (GitHub releases redirect to
/// S3 object storage). Returns the final response on success.
Future<HttpClientResponse> _getFollowingRedirects(
  HttpClient client,
  Uri url,
) async {
  var currentUrl = url;
  for (var hops = 0; hops <= 5; hops++) {
    final request = await client.getUrl(currentUrl);
    request.followRedirects = false;
    final response = await request.close().timeout(
      const Duration(seconds: 120),
    );

    if (response.isRedirect) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null) {
        throw const HttpException('Redirect without Location header');
      }
      await response.drain<void>();
      currentUrl = Uri.parse(location).isAbsolute
          ? Uri.parse(location)
          : currentUrl.resolve(location);
      _logDetail('redirect → $currentUrl');
      continue;
    }

    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'HTTP ${response.statusCode} ${response.reasonPhrase}',
        uri: currentUrl,
      );
    }
    return response;
  }
  throw HttpException('Too many redirects', uri: url);
}

/// Extracts a .tar.gz archive into [dest]. Requires `tar` on PATH (available
/// by default on macOS, Linux, and Windows 10+).
Future<void> _extractTarGz(File archive, Directory dest) async {
  final result = await Process.run('tar', [
    'xzf',
    archive.path,
    '-C',
    dest.path,
  ]);
  if (result.exitCode != 0) {
    throw ProcessException(
      'tar',
      ['xzf', archive.path, '-C', dest.path],
      'Exit code ${result.exitCode}: ${result.stderr}'.trim(),
      result.exitCode,
    );
  }
}

// -----------------------------------------------------------------------------
// Strategy 3: System-installed library
// -----------------------------------------------------------------------------

File _findSystemLibrary(OS os) {
  final candidates = _systemSearchPaths(os);

  _log('Searching for system-installed qpdf');
  for (final path in candidates) {
    final file = File(path);
    final exists = file.existsSync();
    _logDetail('${exists ? "✓" : "✗"} $path');
    if (exists) {
      return file;
    }
  }

  throw StateError(
    'qpdf native library not found after trying prebuilt download and '
    'system paths. Install qpdf on your system:\n'
    '  macOS:   brew install qpdf\n'
    '  Linux:   sudo apt install libqpdf-dev   (Debian/Ubuntu)\n'
    '           sudo dnf install qpdf-libs     (Fedora/RHEL)\n'
    '  Windows: https://github.com/qpdf/qpdf/releases\n'
    '\n'
    'Or ensure this package can reach github.com to download the prebuilt.',
  );
}

List<String> _systemSearchPaths(OS os) => switch (os) {
  OS.macOS => const [
    '/opt/homebrew/lib/libqpdf.dylib',
    '/opt/homebrew/lib/libqpdf.30.dylib',
    '/opt/homebrew/lib/libqpdf.29.dylib',
    '/usr/local/lib/libqpdf.dylib',
    '/usr/local/lib/libqpdf.30.dylib',
    '/usr/local/lib/libqpdf.29.dylib',
  ],
  OS.linux => const [
    '/usr/lib/x86_64-linux-gnu/libqpdf.so',
    '/usr/lib/x86_64-linux-gnu/libqpdf.so.29',
    '/usr/lib/aarch64-linux-gnu/libqpdf.so',
    '/usr/lib/aarch64-linux-gnu/libqpdf.so.29',
    '/usr/lib/libqpdf.so',
    '/usr/local/lib/libqpdf.so',
  ],
  OS.windows => const [
    r'C:\Program Files\qpdf\bin\qpdf29.dll',
    r'C:\Program Files\qpdf\bin\qpdf30.dll',
  ],
  _ => const <String>[],
};

// -----------------------------------------------------------------------------
// Naming helpers (MUST match the convention documented above)
// -----------------------------------------------------------------------------

/// Returns the asset filename published by CI for the given `(os, arch)`.
///
/// Must stay in sync with `tool/build_qpdf.sh` (which writes the tarball
/// name) and `.github/workflows/build-prebuilts.yml` (which uploads it).
String _artifactName(OS os, Architecture arch) =>
    'libqpdf-${_osSuffix(os)}-${_archSuffix(arch)}.tar.gz';

/// The library filename inside the prebuilt tarball, and the filename at
/// which we cache it in the build output dir.
String _libraryFilename(OS os) => switch (os) {
  OS.macOS => 'libqpdf.dylib',
  OS.linux => 'libqpdf.so',
  OS.windows => 'qpdf29.dll',
  OS.android => 'libqpdf.so',
  OS.iOS => 'libqpdf.dylib',
  _ => throw UnsupportedError('Unsupported OS: $os'),
};

String _osSuffix(OS os) => switch (os) {
  OS.linux => 'linux',
  OS.macOS => 'macos',
  OS.windows => 'windows',
  OS.android => 'android',
  OS.iOS => 'ios',
  _ => throw UnsupportedError('Unsupported OS: $os'),
};

String _archSuffix(Architecture arch) => switch (arch) {
  Architecture.x64 => 'x64',
  Architecture.arm64 => 'arm64',
  Architecture.arm => 'arm',
  Architecture.ia32 => 'ia32',
  Architecture.riscv64 => 'riscv64',
  _ => throw UnsupportedError('Unsupported architecture: $arch'),
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}
