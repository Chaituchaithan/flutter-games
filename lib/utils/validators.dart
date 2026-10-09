/// Form-field validators for the auth screens. Each returns `null` when the
/// value is valid, or a short human-readable message to show under the field.
///
/// Kept deliberately lenient on the server's behalf — the API is the source of
/// truth for credentials; these just catch obvious client-side mistakes before
/// a round-trip.
class Validators {
  Validators._();

  // Pragmatic email shape: something@something.tld — not RFC-exhaustive.
  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  /// Display/username. Register sends this as `username`.
  static String? name(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Please enter your name';
    if (v.length < 2) return 'Name is too short';
    return null;
  }

  /// Register username: letters, digits, and underscores; 3–20 chars, no spaces.
  static String? username(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Please choose a username';
    if (v.length < 3) return 'At least 3 characters';
    if (v.length > 20) return 'At most 20 characters';
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(v)) return 'Letters, numbers, and _ only';
    return null;
  }

  static String? email(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Please enter your email';
    if (!_email.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// Login identifier: accepts a username OR an email (the server decides which
  /// it is). Used on the sign-in screen so accounts like `auratester01` work.
  static String? loginIdentifier(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Please enter your username or email';
    if (v.length < 3) return 'Too short';
    return null;
  }

  /// Login password: presence only — the server decides if it's correct.
  static String? password(String value) {
    if (value.isEmpty) return 'Please enter your password';
    return null;
  }

  /// Register password: enforce a minimum strength before creating an account.
  static String? newPassword(String value) {
    if (value.isEmpty) return 'Please create a password';
    if (value.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
      return 'Mix letters and numbers';
    }
    return null;
  }
}
