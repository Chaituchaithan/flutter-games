/// A transport-agnostic error the UI can show. Repositories translate raw
/// source/HTTP failures into this so screens never depend on `dio`.
/// See docs/INTEGRATION_PLAN.md §4.
class AppException implements Exception {
  const AppException(this.message, {this.kind = AppErrorKind.unknown, this.statusCode});

  final String message;
  final AppErrorKind kind;
  final int? statusCode;

  bool get isOffline => kind == AppErrorKind.offline;
  bool get isUnauthorized => kind == AppErrorKind.unauthorized;

  @override
  String toString() => 'AppException($kind, $statusCode): $message';
}

enum AppErrorKind { offline, timeout, unauthorized, notFound, server, unknown }
