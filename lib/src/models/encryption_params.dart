import 'enums.dart';

/// Base class for encryption parameters.
sealed class EncryptionParams {
  final String userPassword;
  final String ownerPassword;

  const EncryptionParams({
    required this.userPassword,
    required this.ownerPassword,
  });
}

/// 40-bit RC4 encryption (R2). Insecure - for legacy compatibility only.
final class R2EncryptionParams extends EncryptionParams {
  final bool allowPrint;
  final bool allowModify;
  final bool allowExtract;
  final bool allowAnnotate;

  const R2EncryptionParams({
    required super.userPassword,
    required super.ownerPassword,
    this.allowPrint = true,
    this.allowModify = true,
    this.allowExtract = true,
    this.allowAnnotate = true,
  });
}

/// 128-bit RC4 encryption (R3). Insecure - for legacy compatibility only.
final class R3EncryptionParams extends EncryptionParams {
  final bool allowAccessibility;
  final bool allowExtract;
  final bool allowAssemble;
  final bool allowAnnotateAndForm;
  final bool allowFormFilling;
  final bool allowModifyOther;
  final R3PrintPermission print;

  const R3EncryptionParams({
    required super.userPassword,
    required super.ownerPassword,
    this.allowAccessibility = true,
    this.allowExtract = true,
    this.allowAssemble = true,
    this.allowAnnotateAndForm = true,
    this.allowFormFilling = true,
    this.allowModifyOther = true,
    this.print = R3PrintPermission.full,
  });
}

/// 128-bit RC4/AES encryption (R4). Insecure - for legacy compatibility only.
final class R4EncryptionParams extends EncryptionParams {
  final bool allowAccessibility;
  final bool allowExtract;
  final bool allowAssemble;
  final bool allowAnnotateAndForm;
  final bool allowFormFilling;
  final bool allowModifyOther;
  final R3PrintPermission print;
  final bool encryptMetadata;
  final bool useAes;

  const R4EncryptionParams({
    required super.userPassword,
    required super.ownerPassword,
    this.allowAccessibility = true,
    this.allowExtract = true,
    this.allowAssemble = true,
    this.allowAnnotateAndForm = true,
    this.allowFormFilling = true,
    this.allowModifyOther = true,
    this.print = R3PrintPermission.full,
    this.encryptMetadata = true,
    this.useAes = true,
  });
}

/// 256-bit AES encryption (R5). Deprecated intermediate version.
final class R5EncryptionParams extends EncryptionParams {
  final bool allowAccessibility;
  final bool allowExtract;
  final bool allowAssemble;
  final bool allowAnnotateAndForm;
  final bool allowFormFilling;
  final bool allowModifyOther;
  final R3PrintPermission print;
  final bool encryptMetadata;

  const R5EncryptionParams({
    required super.userPassword,
    required super.ownerPassword,
    this.allowAccessibility = true,
    this.allowExtract = true,
    this.allowAssemble = true,
    this.allowAnnotateAndForm = true,
    this.allowFormFilling = true,
    this.allowModifyOther = true,
    this.print = R3PrintPermission.full,
    this.encryptMetadata = true,
  });
}

/// 256-bit AES encryption (R6). Recommended for new files.
final class R6EncryptionParams extends EncryptionParams {
  final bool allowAccessibility;
  final bool allowExtract;
  final bool allowAssemble;
  final bool allowAnnotateAndForm;
  final bool allowFormFilling;
  final bool allowModifyOther;
  final R3PrintPermission print;
  final bool encryptMetadata;

  const R6EncryptionParams({
    required super.userPassword,
    required super.ownerPassword,
    this.allowAccessibility = true,
    this.allowExtract = true,
    this.allowAssemble = true,
    this.allowAnnotateAndForm = true,
    this.allowFormFilling = true,
    this.allowModifyOther = true,
    this.print = R3PrintPermission.full,
    this.encryptMetadata = true,
  });
}
