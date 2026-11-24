/// A transport-agnostic error the UI can show. Repositories translate raw
/// source/HTTP failures into this so screens never depend on `dio`.
///
/// Decide on [statusCode] + [code] (the server's `error` field), never on the
/// wording: [message] is the app's own user-facing text, not the server's
/// developer message. See docs/services/01-auth.md "Errors".
class AppException implements Exception {
  const AppException(
    this.message, {
    this.kind = AppErrorKind.unknown,
    this.statusCode,
    this.code,
    this.field,
    this.until,
    this.detail,
  });

  /// User-facing text (already mapped from [code]; safe to show as is).
  final String message;
  final AppErrorKind kind;

  /// HTTP status; null for no network / timeout.
  final int? statusCode;

  /// The server's machine code, e.g. `INVALID_CREDENTIALS` (see [ApiErrorCode]).
  final String? code;

  /// `VALIDATION_ERROR` only: the first bad field (`email`, `password`, …).
  final String? field;

  /// `ACCOUNT_BANNED` with a timed ban: when it ends (UTC).
  final DateTime? until;

  /// The server's developer `message`, never shown to players. Read only
  /// where a hand-off file documents a stable prefix to branch on (e.g. the
  /// rewards 409s: `conflict: completed`, `conflict: blocked: device_dupe`).
  final String? detail;

  bool get isOffline => kind == AppErrorKind.offline;
  bool get isUnauthorized => kind == AppErrorKind.unauthorized;
  bool get isBanned => code == ApiErrorCode.accountBanned;
  bool get isRateLimited => code == ApiErrorCode.rateLimited;
  bool get isValidation => code == ApiErrorCode.validation;
  bool get isKillSwitch => code == ApiErrorCode.killSwitch;

  @override
  String toString() => 'AppException($kind, $statusCode, $code${field == null ? '' : ' $field'})';
}

enum AppErrorKind { offline, timeout, unauthorized, notFound, server, unknown }

/// The gateway's `error` codes the app acts on.
abstract final class ApiErrorCode {
  static const validation = 'VALIDATION_ERROR';
  static const badRequest = 'BAD_REQUEST';
  static const conflict = 'CONFLICT';
  static const rateLimited = 'RATE_LIMITED';
  static const invalidCredentials = 'INVALID_CREDENTIALS';
  static const accountBanned = 'ACCOUNT_BANNED';
  static const geoBlocked = 'GEO_BLOCKED';
  static const unauthorized = 'UNAUTHORIZED';
  static const tokenBlacklisted = 'TOKEN_BLACKLISTED';
  static const tokenExpired = 'TOKEN_EXPIRED';
  static const sessionNotFound = 'SESSION_NOT_FOUND';
  static const fingerprintMismatch = 'FINGERPRINT_MISMATCH';
  static const forbidden = 'FORBIDDEN';
  static const notFound = 'NOT_FOUND';
  static const unavailable = 'UNAVAILABLE';
  static const killSwitch = 'KILL_SWITCH_ENGAGED';
  static const databaseBusy = 'DATABASE_BUSY';
  static const gameNotFound = 'GAME_NOT_FOUND';
  static const insufficientFunds = 'INSUFFICIENT_FUNDS';
  static const giftQuotaExceeded = 'GIFT_QUOTA_EXCEEDED';
  // Tournaments (06-tournaments.md).
  static const tournamentFull = 'TOURNAMENT_FULL';
  // Store (11-store.md).
  static const levelRequired = 'LEVEL_REQUIRED';
  static const duplicateTransaction = 'DUPLICATE_TRANSACTION';
  static const userBlocked = 'USER_BLOCKED';
  static const duplicateFriendRequest = 'DUPLICATE_FRIEND_REQUEST';
  static const databaseError = 'DATABASE_ERROR';
  // Safety (12-safety.md).
  static const matchNotFound = 'MATCH_NOT_FOUND';
}

/// "Your account is suspended until `local date and time`." / "… Contact support."
String banMessage(DateTime? until) {
  if (until == null) return 'Your account is suspended. Contact support.';
  final t = until.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Your account is suspended until ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}.';
}

/// Field-level text for a `VALIDATION_ERROR` (the server names the field).
String validationMessage(String? field) => switch (field) {
      'username' => 'Username must be 3 to 32 characters: letters, numbers and _.',
      'email' => 'Enter a valid email address.',
      'password' || 'new_password' => 'Password must be 8 to 128 characters.',
      'code' => 'Enter the 6-digit code.',
      _ => 'Check the highlighted field and try again.',
    };
