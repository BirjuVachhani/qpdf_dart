import 'encryption_params.dart';
import 'enums.dart';

/// Configuration for PDF write operations.
final class WriteOptions {
  /// Enable PDF linearization (web optimization).
  final bool linearize;

  /// Enable QDF mode (for debugging).
  final bool qdfMode;

  /// Use a deterministic /ID based on content.
  final bool deterministicId;

  /// Preserve original encryption settings.
  final bool preserveEncryption;

  /// Compress stream data.
  final bool compressStreams;

  /// Normalize content streams.
  final bool contentNormalization;

  /// How to handle stream data compression.
  final StreamDataMode streamDataMode;

  /// How to handle object streams.
  final ObjectStreamMode objectStreamMode;

  /// How deep to decode streams.
  final StreamDecodeLevel decodeLevel;

  /// Preserve objects not referenced from the page tree.
  final bool preserveUnreferencedObjects;

  /// Insert newline before endstream keyword.
  final bool newlineBeforeEndstream;

  /// Suppress original object IDs.
  final bool suppressOriginalObjectIds;

  /// Minimum PDF version for output.
  final String? minimumPdfVersion;

  /// Minimum PDF version extension level.
  final int? minimumPdfVersionExtension;

  /// Force output to a specific PDF version.
  final String? forcePdfVersion;

  /// Force PDF version extension level.
  final int? forcePdfVersionExtension;

  /// Encryption parameters. If null, no encryption changes are made.
  final EncryptionParams? encryption;

  const WriteOptions({
    this.linearize = false,
    this.qdfMode = false,
    this.deterministicId = false,
    this.preserveEncryption = true,
    this.compressStreams = true,
    this.contentNormalization = false,
    this.streamDataMode = StreamDataMode.preserve,
    this.objectStreamMode = ObjectStreamMode.preserve,
    this.decodeLevel = StreamDecodeLevel.generalized,
    this.preserveUnreferencedObjects = false,
    this.newlineBeforeEndstream = false,
    this.suppressOriginalObjectIds = false,
    this.minimumPdfVersion,
    this.minimumPdfVersionExtension,
    this.forcePdfVersion,
    this.forcePdfVersionExtension,
    this.encryption,
  });
}
