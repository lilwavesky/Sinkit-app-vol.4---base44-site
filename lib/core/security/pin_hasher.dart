import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../utils/persian_utils.dart';

enum PinVerificationStatus {
  unlocked,
  invalidPin,
  storageUnavailable,
  lockedOut,
}

class PinVerificationResult {
  final PinVerificationStatus status;
  final int remainingAttempts;
  final Duration? lockoutRemaining;
  final bool hashMigrated;
  final String messageFa;

  const PinVerificationResult({
    required this.status,
    required this.remainingAttempts,
    this.lockoutRemaining,
    this.hashMigrated = false,
    required this.messageFa,
  });

  bool get isUnlocked => status == PinVerificationStatus.unlocked;
}

enum PinTransactionStatus {
  /// Transaction committed and verified cleanly.
  committed,

  /// PIN deactivation committed and verified (`pinLockEnabled == false`),
  /// but post-commit cleanup of the old encrypted PIN hash or lockout record
  /// failed. The old encrypted hash remains harmless unused data; persisted
  /// state and in-memory state remain completely consistent.
  committedWithCleanupWarning,

  /// Transaction aborted before commit OR rolled back and verified back to
  /// the exact prior persisted PIN hash and security state.
  rolledBack,

  /// A write failed mid-transaction AND restoring the prior PIN hash could not
  /// be verified. The application has entered a locked, recovery-required state
  /// (`pinRecoveryRequired = true`, `isUnlocked = false`).
  recoveryRequired,

  /// Rejected prior to modifying storage (invalid PIN format or app is locked).
  rejected,
}

class PinTransactionResult {
  final PinTransactionStatus status;
  final bool pinLockEnabledAfter;
  final bool cleanupSucceeded;
  final bool recoveryRequired;
  final String messageFa;

  const PinTransactionResult({
    required this.status,
    required this.pinLockEnabledAfter,
    this.cleanupSucceeded = true,
    this.recoveryRequired = false,
    required this.messageFa,
  });

  bool get succeeded =>
      status == PinTransactionStatus.committed ||
      status == PinTransactionStatus.committedWithCleanupWarning;

  bool get hasCleanupWarning =>
      status == PinTransactionStatus.committedWithCleanupWarning;
}

class PinHashCheckResult {
  final bool matched;
  final bool needsMigration;
  final bool isMalformed;
  final String algorithm;
  final String? rejectionReason;

  const PinHashCheckResult({
    required this.matched,
    required this.needsMigration,
    this.isMalformed = false,
    required this.algorithm,
    this.rejectionReason,
  });
}

class PinBenchmarkResult {
  final String algorithm;
  final int iterations;
  final int keyLengthBytes;
  final int elapsedMicroseconds;

  const PinBenchmarkResult({
    required this.algorithm,
    required this.iterations,
    required this.keyLengthBytes,
    required this.elapsedMicroseconds,
  });

  double get elapsedMilliseconds => elapsedMicroseconds / 1000.0;

  /// OWASP mobile UI responsiveness heuristic (< 300ms target on device).
  bool get isResponsiveForMobileUi => elapsedMilliseconds <= 300.0;
}

/// Persisted brute-force protection state stored in encrypted secure storage.
class PinSecurityState {
  final int failedAttempts;
  final DateTime? lockoutUntilUtc;

  /// Durable transaction journal. When true, startup and PIN verification must
  /// remain locked until an explicit, verified recovery wipes sensitive data.
  /// Missing values in older V2.1.1/V2.1.2 records default to false.
  final bool recoveryRequired;

  /// Secure-store mirror of the PIN gate. This is authoritative alongside the
  /// preference flag, so a damaged/stale plaintext preference cannot silently
  /// disable an already configured PIN after this version has committed it.
  final bool pinLockEnabled;

  const PinSecurityState({
    this.failedAttempts = 0,
    this.lockoutUntilUtc,
    this.recoveryRequired = false,
    this.pinLockEnabled = false,
  });

  PinSecurityState copyWith({
    int? failedAttempts,
    DateTime? lockoutUntilUtc,
    bool clearLockout = false,
    bool? recoveryRequired,
    bool? pinLockEnabled,
  }) {
    return PinSecurityState(
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockoutUntilUtc:
          clearLockout ? null : (lockoutUntilUtc ?? this.lockoutUntilUtc),
      recoveryRequired: recoveryRequired ?? this.recoveryRequired,
      pinLockEnabled: pinLockEnabled ?? this.pinLockEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'failedAttempts': failedAttempts,
        'lockoutUntilUtc': lockoutUntilUtc?.toUtc().toIso8601String(),
        'recoveryRequired': recoveryRequired,
        'pinLockEnabled': pinLockEnabled,
      };

  factory PinSecurityState.fromJson(Map<String, dynamic> json) {
    final rawAttempts = json['failedAttempts'];
    if (rawAttempts is! int || rawAttempts < 0) {
      throw const FormatException('Invalid failedAttempts in PinSecurityState');
    }
    final rawLockout = json['lockoutUntilUtc'];
    final rawRecoveryRequired = json['recoveryRequired'];
    final rawPinLockEnabled = json['pinLockEnabled'];
    if (rawRecoveryRequired != null && rawRecoveryRequired is! bool) {
      throw const FormatException('Invalid recoveryRequired in PinSecurityState');
    }
    if (rawPinLockEnabled != null && rawPinLockEnabled is! bool) {
      throw const FormatException('Invalid pinLockEnabled in PinSecurityState');
    }
    DateTime? lockout;
    if (rawLockout != null) {
      if (rawLockout is! String) {
        throw const FormatException('Invalid lockoutUntilUtc type');
      }
      lockout = DateTime.parse(rawLockout).toUtc();
    }
    return PinSecurityState(
      failedAttempts: rawAttempts,
      lockoutUntilUtc: lockout,
      recoveryRequired: rawRecoveryRequired as bool? ?? false,
      pinLockEnabled: rawPinLockEnabled as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PinSecurityState) return false;
    final thisLock = lockoutUntilUtc?.toUtc().millisecondsSinceEpoch;
    final otherLock = other.lockoutUntilUtc?.toUtc().millisecondsSinceEpoch;
    return failedAttempts == other.failedAttempts &&
        thisLock == otherLock &&
        recoveryRequired == other.recoveryRequired &&
        pinLockEnabled == other.pinLockEnabled;
  }

  @override
  int get hashCode => Object.hash(
        failedAttempts,
        lockoutUntilUtc?.toUtc().millisecondsSinceEpoch,
        recoveryRequired,
        pinLockEnabled,
      );
}

enum PinTransactionOperation {
  activate,
  rotate,
  deactivate,
}

/// Persistent write-ahead recovery journal stored in encrypted secure storage.
///
/// Captures the COMPLETE prior valid security snapshot before the first mutation
/// of any PIN transaction (activation, rotation, deactivation). Never contains
/// plaintext PIN values.
///
/// Lifecycle:
/// 1. Written with `committed = false` and read-back verified BEFORE any state mutation.
/// 2. After all target writes (`hash`, `securityState`, `settings`) are read-back verified,
///    updated to `committed = true` and read-back verified.
/// 3. Deleted (and deletion verified) ONLY after step 2 succeeds — or after a verified
///    rollback restores every field of the prior snapshot.
/// 4. If the process restarts while a journal exists on disk:
///    - `committed == false` -> startup deterministically restores the prior snapshot,
///      verifies read-back, and removes the journal (or fails closed if restoration fails).
///    - `committed == true` -> startup verifies the target state is intact and cleans up
///      the journal (or fails closed if target state is inconsistent).
class PinTransactionJournal {
  final int schemaVersion;
  final String transactionId;
  final PinTransactionOperation operation;
  final DateTime startedAtUtc;
  final bool committed;
  final bool rollbackFailed;

  // Complete pre-transaction snapshot
  final String? previousHash;
  final bool previousPinLockEnabled;
  final int previousFailedAttempts;
  final DateTime? previousLockoutUntilUtc;

  // Intended post-transaction target (never contains plaintext PIN)
  final String? targetHash;
  final bool targetPinLockEnabled;

  const PinTransactionJournal({
    this.schemaVersion = 1,
    required this.transactionId,
    required this.operation,
    required this.startedAtUtc,
    this.committed = false,
    this.rollbackFailed = false,
    required this.previousHash,
    required this.previousPinLockEnabled,
    required this.previousFailedAttempts,
    required this.previousLockoutUntilUtc,
    required this.targetHash,
    required this.targetPinLockEnabled,
  });

  PinSecurityState get previousSecurityState => PinSecurityState(
        failedAttempts: previousFailedAttempts,
        lockoutUntilUtc: previousLockoutUntilUtc,
        recoveryRequired: false,
        pinLockEnabled: previousPinLockEnabled,
      );

  PinSecurityState get targetSecurityState => PinSecurityState(
        failedAttempts: 0,
        lockoutUntilUtc: null,
        recoveryRequired: false,
        pinLockEnabled: targetPinLockEnabled,
      );

  PinTransactionJournal markCommitted() => PinTransactionJournal(
        schemaVersion: schemaVersion,
        transactionId: transactionId,
        operation: operation,
        startedAtUtc: startedAtUtc,
        committed: true,
        rollbackFailed: false,
        previousHash: previousHash,
        previousPinLockEnabled: previousPinLockEnabled,
        previousFailedAttempts: previousFailedAttempts,
        previousLockoutUntilUtc: previousLockoutUntilUtc,
        targetHash: targetHash,
        targetPinLockEnabled: targetPinLockEnabled,
      );

  PinTransactionJournal markRollbackFailed() => PinTransactionJournal(
        schemaVersion: schemaVersion,
        transactionId: transactionId,
        operation: operation,
        startedAtUtc: startedAtUtc,
        committed: false,
        rollbackFailed: true,
        previousHash: previousHash,
        previousPinLockEnabled: previousPinLockEnabled,
        previousFailedAttempts: previousFailedAttempts,
        previousLockoutUntilUtc: previousLockoutUntilUtc,
        targetHash: targetHash,
        targetPinLockEnabled: targetPinLockEnabled,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'transactionId': transactionId,
        'operation': operation.name,
        'startedAtUtc': startedAtUtc.toUtc().toIso8601String(),
        'committed': committed,
        'rollbackFailed': rollbackFailed,
        'previousHash': previousHash,
        'previousPinLockEnabled': previousPinLockEnabled,
        'previousFailedAttempts': previousFailedAttempts,
        'previousLockoutUntilUtc':
            previousLockoutUntilUtc?.toUtc().toIso8601String(),
        'targetHash': targetHash,
        'targetPinLockEnabled': targetPinLockEnabled,
      };

  factory PinTransactionJournal.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    final txId = json['transactionId'];
    final rawOp = json['operation'];
    final rawStarted = json['startedAtUtc'];
    final rawCommitted = json['committed'];
    final rawRollbackFailed = json['rollbackFailed'];
    if (rawRollbackFailed != null && rawRollbackFailed is! bool) {
      throw const FormatException('Invalid rollbackFailed in PinTransactionJournal');
    }
    final rawPrevHash = json['previousHash'];
    final rawPrevEnabled = json['previousPinLockEnabled'];
    final rawPrevAttempts = json['previousFailedAttempts'];
    final rawPrevLockout = json['previousLockoutUntilUtc'];
    final rawTargetHash = json['targetHash'];
    final rawTargetEnabled = json['targetPinLockEnabled'];

    if (schemaVersion is! int || schemaVersion != 1) {
      throw const FormatException('Unsupported PinTransactionJournal schemaVersion');
    }
    if (txId is! String || txId.trim().isEmpty) {
      throw const FormatException('Invalid transactionId');
    }
    if (rawOp is! String) {
      throw const FormatException('Invalid operation');
    }
    final op = PinTransactionOperation.values.firstWhere(
      (e) => e.name == rawOp,
      orElse: () => throw const FormatException('Unknown PinTransactionOperation'),
    );
    if (rawStarted is! String) {
      throw const FormatException('Invalid startedAtUtc');
    }
    final startedAt = DateTime.parse(rawStarted).toUtc();
    if (rawCommitted is! bool ||
        rawPrevEnabled is! bool ||
        rawTargetEnabled is! bool) {
      throw const FormatException('Invalid boolean flags in PinTransactionJournal');
    }
    if (rawPrevAttempts is! int || rawPrevAttempts < 0) {
      throw const FormatException('Invalid previousFailedAttempts');
    }
    if (rawPrevHash != null && rawPrevHash is! String) {
      throw const FormatException('Invalid previousHash type');
    }
    if (rawTargetHash != null && rawTargetHash is! String) {
      throw const FormatException('Invalid targetHash type');
    }
    DateTime? prevLockout;
    if (rawPrevLockout != null) {
      if (rawPrevLockout is! String) {
        throw const FormatException('Invalid previousLockoutUntilUtc');
      }
      prevLockout = DateTime.parse(rawPrevLockout).toUtc();
    }

    if (op == PinTransactionOperation.activate &&
        (rawTargetHash == null || rawTargetHash.isEmpty || !rawTargetEnabled)) {
      throw const FormatException('Malformed activate journal');
    }
    if (op == PinTransactionOperation.rotate &&
        (rawPrevHash == null ||
            rawPrevHash.isEmpty ||
            rawTargetHash == null ||
            rawTargetHash.isEmpty ||
            !rawPrevEnabled ||
            !rawTargetEnabled)) {
      throw const FormatException('Malformed rotate journal');
    }
    if (op == PinTransactionOperation.deactivate &&
        (rawTargetEnabled || (rawTargetHash != null && rawTargetHash.isNotEmpty))) {
      throw const FormatException('Malformed deactivate journal');
    }

    return PinTransactionJournal(
      schemaVersion: schemaVersion,
      transactionId: txId,
      operation: op,
      startedAtUtc: startedAt,
      committed: rawCommitted,
      rollbackFailed: rawRollbackFailed as bool? ?? false,
      previousHash: rawPrevHash,
      previousPinLockEnabled: rawPrevEnabled,
      previousFailedAttempts: rawPrevAttempts,
      previousLockoutUntilUtc: prevLockout,
      targetHash: rawTargetHash,
      targetPinLockEnabled: rawTargetEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PinTransactionJournal) return false;
    return schemaVersion == other.schemaVersion &&
        transactionId == other.transactionId &&
        operation == other.operation &&
        startedAtUtc.toUtc().millisecondsSinceEpoch ==
            other.startedAtUtc.toUtc().millisecondsSinceEpoch &&
        committed == other.committed &&
        rollbackFailed == other.rollbackFailed &&
        previousHash == other.previousHash &&
        previousPinLockEnabled == other.previousPinLockEnabled &&
        previousFailedAttempts == other.previousFailedAttempts &&
        previousLockoutUntilUtc?.toUtc().millisecondsSinceEpoch ==
            other.previousLockoutUntilUtc?.toUtc().millisecondsSinceEpoch &&
        targetHash == other.targetHash &&
        targetPinLockEnabled == other.targetPinLockEnabled;
  }

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        transactionId,
        operation,
        startedAtUtc.toUtc().millisecondsSinceEpoch,
        committed,
        rollbackFailed,
        previousHash,
        previousPinLockEnabled,
        previousFailedAttempts,
        previousLockoutUntilUtc?.toUtc().millisecondsSinceEpoch,
        targetHash,
        targetPinLockEnabled,
      );
}

/// Standards-compliant RFC 2898 PBKDF2-HMAC-SHA256 PIN derivation and verification.
///
/// Storage format:
///   `pbkdf2_sha256$<iterations>$<keyLengthBytes>$<saltHex>$<derivedKeyHex>`
///
/// OWASP Password Storage Cheat Sheet Rationale (2025/2026):
/// - OWASP currently prefers Argon2id for general password storage, and lists
///   600,000 PBKDF2-HMAC-SHA256 iterations when PBKDF2 is required for FIPS-140,
///   while advising teams to benchmark on actual target hardware so verification
///   stays responsive (typically ~100–300ms, never exceeding 1 second).
/// - The current 100,000-iteration default is a provisional mobile-performance
///   compromise, not the OWASP 600,000-iteration FIPS-required work factor. Pure-Dart
///   PBKDF2 on low-end ARM Android devices can be several times slower than native
///   C/OpenSSL, so the app pairs this default with Android Keystore encryption and
///   persistent 5-attempt lockout, and permits raising the work factor after
///   benchmarking on target Android hardware
///   via Settings -> PBKDF2 Benchmark. A future native FFI Argon2id upgrade can
///   migrate cleanly using the self-describing `$` record prefix.
class PinHasher {
  static const String algorithmPbkdf2Sha256 = 'pbkdf2_sha256';
  static const String algorithmLegacyV2Sha256 = 'legacy_v2_sha256_1000';

  /// Conservative mobile-safe pure-Dart default pending real-device Android benchmarking.
  static const int defaultIterations = 100000;

  /// OWASP PBKDF2-HMAC-SHA256 reference target (benchmark on target Android before enabling).
  static const int owaspRecommendedPbkdf2Sha256Iterations = 600000;

  /// Records below this threshold trigger automatic upgrade on verified unlock.
  static const int minAcceptableIterations = 100000;

  /// Lowest iteration count accepted when verifying an existing PBKDF2 record.
  static const int minVerificationIterations = 1000;

  /// Hard upper bound protecting the device from CPU DoS via tampered records
  /// while still permitting OWASP 600,000-iteration records.
  static const int maxAcceptableIterations = 600000;

  static const int defaultKeyLengthBytes = 32;
  static const int defaultSaltLengthBytes = 16;

  static final RegExp _fourDigitPin = RegExp(r'^\d{4}$');
  static final RegExp _strictUnsignedInt = RegExp(r'^\d+$');
  static final RegExp _strictHex = RegExp(r'^[0-9a-fA-F]+$');

  static String normalizePin(String raw) =>
      PersianUtils.toEnglishDigits(raw).trim();

  static bool isValidPinFormat(String raw) =>
      _fourDigitPin.hasMatch(normalizePin(raw));

  static bool isValidHex(String value) =>
      value.isNotEmpty && value.length.isEven && _strictHex.hasMatch(value);

  /// Creates a parameterized PBKDF2-HMAC-SHA256 hash record with a unique 16-byte random salt.
  static String createSaltedHash(
    String pin, {
    int iterations = defaultIterations,
    int keyLengthBytes = defaultKeyLengthBytes,
    Random? random,
  }) {
    final normalized = normalizePin(pin);
    if (!isValidPinFormat(normalized)) {
      throw ArgumentError('PIN must be exactly 4 digits.');
    }
    if (iterations < minVerificationIterations ||
        iterations > maxAcceptableIterations) {
      throw RangeError.range(
        iterations,
        minVerificationIterations,
        maxAcceptableIterations,
        'iterations',
      );
    }
    if (keyLengthBytes != defaultKeyLengthBytes) {
      throw ArgumentError(
        'Derived key length must be exactly $defaultKeyLengthBytes bytes.',
      );
    }
    final rng = random ?? Random.secure();
    final saltBytes = Uint8List.fromList(
      List<int>.generate(defaultSaltLengthBytes, (_) => rng.nextInt(256)),
    );
    final dk = derivePbkdf2HmacSha256(
      password: utf8.encode(normalized),
      salt: saltBytes,
      iterations: iterations,
      keyLengthBytes: keyLengthBytes,
    );
    return '$algorithmPbkdf2Sha256\$$iterations\$$keyLengthBytes\$${_toHex(saltBytes)}\$${_toHex(dk)}';
  }

  /// Creates a legacy V2.0 hash record strictly for migration test coverage.
  static String createLegacyV2HashForTesting(String pin, String saltHex) {
    final normalized = normalizePin(pin);
    final digest = _computeLegacyV2Digest(saltHex, normalized);
    return '$saltHex:$digest';
  }

  /// Verifies a PIN against either PBKDF2-HMAC-SHA256 or legacy V2.0 format,
  /// rejecting malformed or excessively expensive records before executing PBKDF2.
  static PinHashCheckResult verifyRecord(
    String candidatePin,
    String storedRecord,
  ) {
    final normalized = normalizePin(candidatePin);
    if (storedRecord.trim().isEmpty) {
      return const PinHashCheckResult(
        matched: false,
        needsMigration: false,
        isMalformed: true,
        algorithm: 'unknown',
        rejectionReason: 'empty_record',
      );
    }

    // 1. Current parameterized PBKDF2-HMAC-SHA256 format
    if (storedRecord.startsWith('$algorithmPbkdf2Sha256\$')) {
      final parts = storedRecord.split('\$');
      if (parts.length != 5) {
        return const PinHashCheckResult(
          matched: false,
          needsMigration: false,
          isMalformed: true,
          algorithm: algorithmPbkdf2Sha256,
          rejectionReason: 'invalid_field_count',
        );
      }

      if (!_strictUnsignedInt.hasMatch(parts[1]) ||
          !_strictUnsignedInt.hasMatch(parts[2])) {
        return const PinHashCheckResult(
          matched: false,
          needsMigration: false,
          isMalformed: true,
          algorithm: algorithmPbkdf2Sha256,
          rejectionReason: 'non_numeric_parameters',
        );
      }

      final iterations = int.tryParse(parts[1]);
      final keyLength = int.tryParse(parts[2]);
      if (iterations == null ||
          iterations < minVerificationIterations ||
          iterations > maxAcceptableIterations) {
        return const PinHashCheckResult(
          matched: false,
          needsMigration: false,
          isMalformed: true,
          algorithm: algorithmPbkdf2Sha256,
          rejectionReason: 'iterations_out_of_bounds',
        );
      }

      if (keyLength != defaultKeyLengthBytes) {
        return const PinHashCheckResult(
          matched: false,
          needsMigration: false,
          isMalformed: true,
          algorithm: algorithmPbkdf2Sha256,
          rejectionReason: 'invalid_key_length',
        );
      }

      final saltHex = parts[3];
      final expectedHex = parts[4];

      // Validate exact salt length (16 bytes == 32 hex chars) and strict hex encoding
      if (!isValidHex(saltHex) ||
          saltHex.length != defaultSaltLengthBytes * 2) {
        return const PinHashCheckResult(
          matched: false,
          needsMigration: false,
          isMalformed: true,
          algorithm: algorithmPbkdf2Sha256,
          rejectionReason: 'invalid_salt_format_or_length',
        );
      }

      // Validate exact derived-key length (32 bytes == 64 hex chars) and strict hex encoding
      if (!isValidHex(expectedHex) ||
          expectedHex.length != defaultKeyLengthBytes * 2) {
        return const PinHashCheckResult(
          matched: false,
          needsMigration: false,
          isMalformed: true,
          algorithm: algorithmPbkdf2Sha256,
          rejectionReason: 'invalid_derived_key_format_or_length',
        );
      }

      if (!isValidPinFormat(normalized)) {
        return const PinHashCheckResult(
          matched: false,
          needsMigration: false,
          isMalformed: false,
          algorithm: algorithmPbkdf2Sha256,
          rejectionReason: 'invalid_candidate_pin',
        );
      }

      final saltBytes = _fromHex(saltHex);
      if (saltBytes == null || saltBytes.length != defaultSaltLengthBytes) {
        return const PinHashCheckResult(
          matched: false,
          needsMigration: false,
          isMalformed: true,
          algorithm: algorithmPbkdf2Sha256,
          rejectionReason: 'salt_decode_failed',
        );
      }

      final derived = derivePbkdf2HmacSha256(
        password: utf8.encode(normalized),
        salt: saltBytes,
        iterations: iterations,
        keyLengthBytes: keyLength!,
      );
      final matched = _constantTimeEquals(
        _toHex(derived),
        expectedHex.toLowerCase(),
      );
      final needsUpgrade = iterations < minAcceptableIterations;
      return PinHashCheckResult(
        matched: matched,
        needsMigration: matched && needsUpgrade,
        isMalformed: false,
        algorithm: algorithmPbkdf2Sha256,
      );
    }

    // 2. Legacy V2.0 format (`<saltHex>:<sha256_1000_hex>`)
    final legacyParts = storedRecord.split(':');
    if (legacyParts.length == 2 &&
        isValidHex(legacyParts[0]) &&
        legacyParts[0].length >= 16 &&
        legacyParts[0].length <= 64 &&
        isValidHex(legacyParts[1]) &&
        legacyParts[1].length == 64) {
      if (!isValidPinFormat(normalized)) {
        return const PinHashCheckResult(
          matched: false,
          needsMigration: false,
          isMalformed: false,
          algorithm: algorithmLegacyV2Sha256,
          rejectionReason: 'invalid_candidate_pin',
        );
      }
      final expected = _computeLegacyV2Digest(legacyParts[0], normalized);
      final matched = _constantTimeEquals(
        expected,
        legacyParts[1].toLowerCase(),
      );
      return PinHashCheckResult(
        matched: matched,
        needsMigration: matched,
        isMalformed: false,
        algorithm: algorithmLegacyV2Sha256,
      );
    }

    return const PinHashCheckResult(
      matched: false,
      needsMigration: false,
      isMalformed: true,
      algorithm: 'unknown',
      rejectionReason: 'unrecognized_hash_format',
    );
  }

  static bool verifySaltedHash(String candidatePin, String storedRecord) {
    return verifyRecord(candidatePin, storedRecord).matched;
  }

  /// Pure RFC 2898 PBKDF2-HMAC-SHA256 implementation verified against standard vectors.
  static Uint8List derivePbkdf2HmacSha256({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int keyLengthBytes,
  }) {
    if (iterations < 1 || iterations > maxAcceptableIterations) {
      throw RangeError.range(
        iterations,
        1,
        maxAcceptableIterations,
        'iterations',
      );
    }
    if (keyLengthBytes < 1 || keyLengthBytes > 128) {
      throw RangeError.range(keyLengthBytes, 1, 128, 'keyLengthBytes');
    }

    const hashLen = 32;
    final blocks = (keyLengthBytes + hashLen - 1) ~/ hashLen;
    final hmac = Hmac(sha256, password);
    final output = Uint8List(blocks * hashLen);
    var offset = 0;

    for (var blockIndex = 1; blockIndex <= blocks; blockIndex++) {
      final blockInput = Uint8List(salt.length + 4)
        ..setRange(0, salt.length, salt);
      blockInput[salt.length] = (blockIndex >> 24) & 0xff;
      blockInput[salt.length + 1] = (blockIndex >> 16) & 0xff;
      blockInput[salt.length + 2] = (blockIndex >> 8) & 0xff;
      blockInput[salt.length + 3] = blockIndex & 0xff;

      var u = hmac.convert(blockInput).bytes;
      final t = Uint8List.fromList(u);

      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < hashLen; j++) {
          t[j] ^= u[j];
        }
      }

      output.setRange(offset, offset + hashLen, t);
      offset += hashLen;
    }

    return Uint8List.sublistView(output, 0, keyLengthBytes);
  }

  /// Measures on-device PBKDF2 derivation latency for Android hardware benchmarking.
  static PinBenchmarkResult benchmarkPbkdf2({
    int iterations = defaultIterations,
    int keyLengthBytes = defaultKeyLengthBytes,
  }) {
    final sw = Stopwatch()..start();
    derivePbkdf2HmacSha256(
      password: utf8.encode('1234'),
      salt: utf8.encode('karen_android_benchmark_salt'),
      iterations: iterations,
      keyLengthBytes: keyLengthBytes,
    );
    sw.stop();
    return PinBenchmarkResult(
      algorithm: algorithmPbkdf2Sha256,
      iterations: iterations,
      keyLengthBytes: keyLengthBytes,
      elapsedMicroseconds: sw.elapsedMicroseconds,
    );
  }

  static String _computeLegacyV2Digest(String saltHex, String pin) {
    // Explicit List<int>: on current Dart SDKs `utf8.encode` is inferred as
    // Uint8List, while `Digest.bytes` is List<int>, so `var` would not compile.
    // The hashed bytes are identical to the previous implementation.
    List<int> bytes = utf8.encode('$saltHex:$pin:karen_v2');
    for (var i = 0; i < 1000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return _toHex(bytes);
  }

  static String _toHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List? _fromHex(String hex) {
    if (!isValidHex(hex)) return null;
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byteVal = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (byteVal == null) return null;
      out[i] = byteVal;
    }
    return out;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
