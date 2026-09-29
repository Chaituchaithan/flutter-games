import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_exception.dart';

/// API host/port. Defaults to the dev gateway (Portal Gateway API, §7b) and is
/// overridable at build time: `--dart-define=API_BASE_URL=…`. Point this at a
/// staging/prod HTTPS host before release (and drop the Android cleartext rule).
const _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://169.58.184.121:30080/api/v1',
);

/// Thin wrapper over Dio: attaches the auth bearer token and maps raw
/// `DioException`s into [AppException] so repositories stay transport-agnostic.
///
/// Not yet pointed at a live backend — remote sources are still off by default
/// (repositories use their static source). See docs/INTEGRATION_PLAN.md.
class ApiClient {
  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              // Trailing slash so a base path like `/api/v1` is preserved when a
              // relative path is appended (see [_rel]).
              baseUrl: _baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              contentType: 'application/json',
            )) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  String? _token;

  /// Invoked once when a request comes back unauthorized (401/403). The app wires
  /// this to sign out + show the "session expired" dialog.
  void Function()? onUnauthorized;

  /// Set/clear the bearer token attached to every request (see AuthService).
  set authToken(String? token) => _token = token;

  /// Strip a leading slash so the path stays relative to the base URL's path
  /// (Dio/Uri treat a leading-slash path as host-absolute, dropping `/api/v1`).
  String _rel(String path) => path.startsWith('/') ? path.substring(1) : path;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(_rel(path), queryParameters: query));

  Future<dynamic> post(String path, {Object? body}) =>
      _send(() => _dio.post(_rel(path), data: body));

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(() => _dio.patch(_rel(path), data: body));

  Future<dynamic> delete(String path, {Object? body}) =>
      _send(() => _dio.delete(_rel(path), data: body));

  Future<dynamic> _send(Future<Response<dynamic>> Function() run) async {
    try {
      final res = await run();
      return res.data;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  AppException _map(DioException e) {
    final code = e.response?.statusCode;
    final kind = switch (e.type) {
      DioExceptionType.connectionError => AppErrorKind.offline,
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        AppErrorKind.timeout,
      _ => switch (code ?? 0) {
          401 || 403 => AppErrorKind.unauthorized,
          404 => AppErrorKind.notFound,
          >= 500 => AppErrorKind.server,
          _ => AppErrorKind.unknown,
        },
    };
    // Prefer the server's own message (envelope: {"error":"CODE","message":"…"}).
    final data = e.response?.data;
    final serverMsg = (data is Map && data['message'] is String) ? data['message'] as String : null;
    final message = serverMsg ??
        switch (kind) {
          AppErrorKind.offline => "You're offline. Check your connection.",
          AppErrorKind.timeout => 'The request timed out. Try again.',
          AppErrorKind.unauthorized => 'Please sign in again.',
          AppErrorKind.notFound => 'Not found.',
          AppErrorKind.server => 'Something went wrong on our end.',
          AppErrorKind.unknown => 'Something went wrong. Try again.',
        };
    // Only treat a 401/403 as an expired session when we actually sent a token —
    // a failed login also returns 401 but must NOT sign the (guest) user out.
    if (kind == AppErrorKind.unauthorized && _token != null && onUnauthorized != null) {
      // Defer so we don't re-enter Dio while an error is unwinding.
      Future.microtask(onUnauthorized!);
    }
    return AppException(message, kind: kind, statusCode: code);
  }
}

/// App-wide client. Overridden in tests; auth token set by the session layer.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
