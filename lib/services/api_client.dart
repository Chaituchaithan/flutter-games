import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import 'app_exception.dart';
import 'server_clock.dart';

/// REST base — resolved by [AppConfig.apiBaseUrl] (`API_BASE_URL` override →
/// dev proxy → environment server). See lib/configs.
final _baseUrl = AppConfig.apiBaseUrl;

/// Thin wrapper over Dio: attaches the bearer token, keeps it fresh, and maps
/// raw `DioException`s into [AppException] so repositories stay
/// transport-agnostic.
///
/// Session rules (docs/services/01-auth.md "Keeping the user signed in"):
/// * public auth calls (login, register, refresh, forgot/reset password) never
///   carry the token and never trigger a refresh;
/// * a token that expires within 60 s is refreshed BEFORE the request;
/// * a `401 UNAUTHORIZED` refreshes once and retries the request once;
/// * a `401 TOKEN_BLACKLISTED` (session ended elsewhere) signs out, no refresh;
/// * only one refresh runs at a time — concurrent 401s wait for it.
///
/// Never logs bodies, tokens, passwords or codes.
class ApiClient {
  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              // Trailing slash so a base path like `/api/v1` is preserved when a
              // relative path is appended (see [_rel]).
              baseUrl: _baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/',
              connectTimeout: NetworkConfig.connectTimeout,
              receiveTimeout: NetworkConfig.receiveTimeout,
              contentType: 'application/json',
            )) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final path = options.path;
          if (!_isPublicPath(path)) {
            // About to expire → refresh first (not before a logout: the user
            // is leaving, and the session is being ended anyway).
            final exp = accessExpiry;
            if (authToken != null &&
                !_rejected &&
                exp != null &&
                !_isNoRefreshPath(path) &&
                onRefreshToken != null &&
                exp.isBefore(DateTime.now().add(NetworkConfig.refreshAhead))) {
              await _refreshOnce();
            }
            if (authToken != null) options.headers['Authorization'] = 'Bearer $authToken';
          }
          // Browsers forbid setting User-Agent; native platforms send ours so
          // the gateway can name the device in the session list.
          if (!kIsWeb) options.headers['User-Agent'] = userAgent;
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;

  /// `RoyaleArcade/1.0.0 (Android)` — stable per platform.
  static String get userAgent =>
      '${NetworkConfig.userAgentProduct}/${NetworkConfig.appVersion} (${_platformName()})';

  static String _platformName() => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'Android',
        TargetPlatform.iOS => 'iOS',
        TargetPlatform.macOS => 'macOS',
        TargetPlatform.windows => 'Windows',
        TargetPlatform.linux => 'Linux',
        TargetPlatform.fuchsia => 'Fuchsia',
      };

  /// Invoked when the session can't be recovered: a 401 that survived a
  /// refresh, a failed refresh, or `TOKEN_BLACKLISTED`. Gets the reason (a ban
  /// from the refresh, when that was the cause). The app wires this to sign
  /// out + tell the player why. A plain 403 is "not allowed", never a sign-out.
  void Function(AppException reason)? onUnauthorized;

  /// Refreshes the token pair (POST /auth/refresh); resolves true when a new
  /// access token was set. May throw an [AppException] (e.g. `ACCOUNT_BANNED`)
  /// to explain why it failed.
  Future<bool> Function()? onRefreshToken;
  Future<bool>? _refreshing;

  /// Set by the session while a token refresh runs: the access token it is
  /// replacing. A 401 on a token newer than that (the refresh's own profile
  /// read) must not start another refresh, or it would wait on itself.
  String? refreshingFrom;
  AppException? _refreshError;

  /// The access token whose refresh the server rejected (401/403): never try
  /// refreshing it again — the session is over.
  String? _deadToken;
  bool get _rejected => authToken != null && authToken == _deadToken;
  static bool _isRejection(AppException e) => e.statusCode == 401 || e.statusCode == 403;

  /// The bearer token attached to every request (set by SessionController).
  String? authToken;

  /// When the access token expires (`now + expires_in` from the token reply).
  /// Null = unknown (no refresh ahead of time; a 401 still refreshes).
  DateTime? accessExpiry;

  /// Strip a leading slash so the path stays relative to the base URL's path
  /// (Dio/Uri treat a leading-slash path as host-absolute, dropping `/api/v1`).
  String _rel(String path) => path.startsWith('/') ? path.substring(1) : path;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(path, () => _dio.get(_rel(path), queryParameters: query));

  /// [headers]: extra per-call headers (e.g. `Idempotency-Key`).
  Future<dynamic> post(String path, {Object? body, Map<String, String>? headers}) =>
      _send(path, () => _dio.post(_rel(path), data: body, options: headers == null ? null : Options(headers: headers)));

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(path, () => _dio.patch(_rel(path), data: body));

  Future<dynamic> put(String path, {Object? body}) =>
      _send(path, () => _dio.put(_rel(path), data: body));

  Future<dynamic> delete(String path, {Object? body}) =>
      _send(path, () => _dio.delete(_rel(path), data: body));

  static String _bare(String path) => path.startsWith('/') ? path.substring(1) : path;

  /// Public calls: sent WITHOUT the bearer token (01-auth.md "Needs a token: no").
  static const _public = {
    'auth/login',
    'auth/register',
    'auth/refresh',
    'auth/forgot-password',
    'auth/forgot-password/verify',
    'auth/reset-password',
    'guest/create',
    'otp/login/send',
    'otp/login/verify',
  };
  static bool _isPublicPath(String path) => _public.contains(_bare(path));

  /// Never refreshed around: a logout (the user is leaving — clear locally
  /// whatever happens, and don't report it as an ended session).
  static bool _isNoRefreshPath(String path) => _bare(path) == 'auth/logout';

  /// 401 codes that mean the session is over → sign out. Not
  /// `INVALID_CREDENTIALS` (a wrong password or code, e.g. on change password).
  static const _sessionEnded = {
    ApiErrorCode.unauthorized,
    ApiErrorCode.tokenBlacklisted,
    ApiErrorCode.tokenExpired,
    ApiErrorCode.sessionNotFound,
    ApiErrorCode.fingerprintMismatch,
  };

  Future<dynamic> _send(String path, Future<Response<dynamic>> Function() run,
      {bool retried = false, bool busyRetried = false}) async {
    try {
      final res = await run();
      ServerClock.fromHttpDate(res.headers.value('date'));
      return res.data;
    } on DioException catch (e) {
      ServerClock.fromHttpDate(e.response?.headers.value('date'));
      final status = e.response?.statusCode;
      final code = _code(e.response?.data);
      // 503 DATABASE_BUSY (Retry-After: 1): retry once after a second.
      if (status == 503 && code == ApiErrorCode.databaseBusy && !busyRetried) {
        await Future<void>.delayed(NetworkConfig.busyRetryDelay);
        return _send(path, run, retried: retried, busyRetried: true);
      }
      final sent = e.requestOptions.headers['Authorization'];
      final sentToken = sent is String && sent.isNotEmpty;
      final sessionCall = sentToken && !_isPublicPath(path) && !_isNoRefreshPath(path);
      // Only UNAUTHORIZED (an expired or bad access token) refreshes, once.
      // TOKEN_BLACKLISTED & co. = session ended: no refresh (01-auth.md §4).
      final expired = status == 401 && sessionCall && (code == null || code == ApiErrorCode.unauthorized);
      if (expired && !retried) {
        // A refresh already ran since this request left → just retry.
        if (authToken != null && sent != 'Bearer $authToken') return _send(path, run, retried: true);
        // Sent with the token a refresh in progress just issued (the refresh's
        // own profile read): waiting for that refresh would wait on itself.
        final from = refreshingFrom;
        if (from != null && authToken != from) throw _map(e);
        if (!_rejected && onRefreshToken != null && await _refreshOnce()) return _send(path, run, retried: true);
        final failure = _refreshError;
        // The refresh couldn't reach the server → keep the session, report that.
        if (failure != null && !_isRejection(failure)) throw failure;
        final reason = failure ?? _map(e);
        _signOut(reason);
        throw reason;
      }
      final err = _map(e);
      if (status == 401 && sessionCall && (code == null || _sessionEnded.contains(code))) {
        _signOut(_refreshError ?? err);
      }
      // 12-safety.md §4: ACCOUNT_BANNED from ANY signed-in route ends the
      // session (never retried); §6: a region refusal is reported by kind.
      if (status == 403 && code == ApiErrorCode.accountBanned && sessionCall) _signOut(err);
      if (status == 403 && code == ApiErrorCode.geoBlocked) {
        final geo = geoBlockFor(e.requestOptions.method, path);
        onGeoBlocked?.call(geo);
        throw AppException(geo.text,
            kind: err.kind, statusCode: status, code: code, field: err.field, detail: err.detail);
      }
      throw err;
    }
  }

  /// `403 GEO_BLOCKED` from any route (12-safety.md §6), with what it
  /// blocks: the whole app, changes only, or the store.
  void Function(GeoBlock kind)? onGeoBlocked;

  /// A sign-in or any read refused → the whole app; a write → read-only;
  /// a `/sensitive/shop|iap|subscriptions` route → the store only.
  static GeoBlock geoBlockFor(String method, String path) {
    final p = _bare(path);
    if (p.startsWith('sensitive/shop') || p.startsWith('sensitive/iap') || p.startsWith('sensitive/subscriptions')) {
      return GeoBlock.store;
    }
    if (_isPublicPath(path) || method.toUpperCase() == 'GET') return GeoBlock.full;
    return GeoBlock.writes;
  }

  void _signOut(AppException reason) {
    if (authToken == null || onUnauthorized == null) return;
    // Defer so we don't re-enter Dio while an error is unwinding.
    Future.microtask(() => onUnauthorized!(reason));
  }

  /// One refresh at a time: concurrent callers wait for the same refresh.
  Future<bool> _refreshOnce() {
    return _refreshing ??= () async {
      _refreshError = null;
      try {
        return await onRefreshToken!();
      } on AppException catch (e) {
        _refreshError = e;
        if (_isRejection(e)) _deadToken = authToken;
        return false;
      } on Object catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  static String? _code(dynamic data) => (data is Map && data['error'] is String) ? data['error'] as String : null;

  /// Server error → [AppException] with the app's own text (the server's
  /// `message` is for developers and isn't translated — never shown).
  AppException _map(DioException e) {
    final status = e.response?.statusCode;
    final kind = switch (e.type) {
      DioExceptionType.connectionError => AppErrorKind.offline,
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        AppErrorKind.timeout,
      _ => switch (status ?? 0) {
          401 || 403 => AppErrorKind.unauthorized,
          404 => AppErrorKind.notFound,
          >= 500 => AppErrorKind.server,
          0 => AppErrorKind.offline,
          _ => AppErrorKind.unknown,
        },
    };
    final data = e.response?.data;
    final body = data is Map ? data : const {};
    final code = _code(data);
    final field = body['field'] is String ? body['field'] as String : null;
    final until = body['until'] is String ? DateTime.tryParse(body['until'] as String) : null;
    return AppException(
      messageFor(
        kind: kind,
        status: status,
        code: code,
        field: field,
        until: until,
        serverMessage: body['message'] is String ? body['message'] as String : null,
      ),
      kind: kind,
      statusCode: status,
      code: code,
      field: field,
      until: until,
      detail: body['message'] is String ? body['message'] as String : null,
    );
  }

  /// The generic text for an error. Screens may override it with
  /// context-specific text (e.g. 409 on sign-up, 400 on a reset code).
  static String messageFor({
    required AppErrorKind kind,
    int? status,
    String? code,
    String? field,
    DateTime? until,
    String? serverMessage,
  }) {
    // An operator's pause: their text is written for players (00-conventions).
    if (code == ApiErrorCode.killSwitch && serverMessage != null && serverMessage.isNotEmpty) return serverMessage;
    switch (kind) {
      case AppErrorKind.offline:
      case AppErrorKind.timeout:
        return "Can't reach the server. Check your connection.";
      case AppErrorKind.server:
        return 'Something went wrong. Try again.';
      default:
    }
    return switch (code) {
      ApiErrorCode.validation => validationMessage(field),
      ApiErrorCode.conflict => 'That username or email is already registered.',
      ApiErrorCode.rateLimited => 'Too many attempts. Try again in a minute.',
      ApiErrorCode.invalidCredentials => 'Email or password is incorrect.',
      ApiErrorCode.accountBanned => banMessage(until),
      ApiErrorCode.geoBlocked => "Royale Arcade isn't available in your region.",
      ApiErrorCode.tokenBlacklisted => 'You were signed out. Please log in again.',
      ApiErrorCode.unauthorized ||
      ApiErrorCode.tokenExpired ||
      ApiErrorCode.sessionNotFound ||
      ApiErrorCode.fingerprintMismatch =>
        'Your session has ended. Please log in again.',
      ApiErrorCode.forbidden => "You're not allowed to do that.",
      ApiErrorCode.notFound => 'Not found.',
      _ => switch (status) {
          401 => 'Your session has ended. Please log in again.',
          403 => "You're not allowed to do that.",
          404 => 'Not found.',
          _ => 'Something went wrong. Try again.',
        },
    };
  }
}

/// App-wide client. Overridden in tests; auth token set by the session layer.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// What a region refusal covers (12-safety.md §6). Ordered by reach.
enum GeoBlock {
  none(''),
  store("The store isn't available in your region."),
  writes("This action isn't available in your region."),
  full("Royale Arcade isn't available in your region.");

  const GeoBlock(this.text);

  /// The player's text for a refused call.
  final String text;
}
