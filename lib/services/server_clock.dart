/// The server's clock, for countdowns to server times (00-conventions.md
/// "Times": the phone's clock can be wrong).
///
/// Two sources keep the offset (`server - device`) current:
/// * a game socket's `connection.established` `timestamp` (milliseconds,
///   preferred), and
/// * the `Date` header of every HTTP reply (whole seconds; used until a
///   socket has set the offset, or when it drifts by more than [_httpSlack]).
library;

abstract final class ServerClock {
  static Duration _offset = Duration.zero;
  static bool _fromSocket = false;

  /// HTTP `Date` is whole seconds and arrives after some latency: within this
  /// of the current offset it adds nothing.
  static const _httpSlack = Duration(seconds: 2);

  /// `server - device`.
  static Duration get offset => _offset;

  /// Now, on the server's clock.
  static DateTime now() => DateTime.now().add(_offset);

  /// Time left until [at] (a server time); never negative.
  static Duration until(DateTime at) {
    final d = at.difference(now());
    return d.isNegative ? Duration.zero : d;
  }

  /// A socket's `connection.established` `timestamp` (epoch ms).
  static void fromSocket(int serverEpochMs) {
    _offset = Duration(milliseconds: serverEpochMs - DateTime.now().millisecondsSinceEpoch);
    _fromSocket = true;
  }

  /// An HTTP reply's `Date` header (RFC 1123, e.g. `Tue, 24 Nov 2026 10:00:00 GMT`).
  static void fromHttpDate(String? header) {
    final at = _parseHttpDate(header);
    if (at == null) return;
    final offset = at.difference(DateTime.now());
    if (_fromSocket && (offset - _offset).abs() <= _httpSlack) return;
    if (!_fromSocket && (offset - _offset).abs() <= const Duration(seconds: 1)) return;
    _offset = offset;
  }

  /// Tests: back to the device clock.
  static void reset() {
    _offset = Duration.zero;
    _fromSocket = false;
  }

  static const _months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  static DateTime? _parseHttpDate(String? h) {
    if (h == null) return null;
    // "Tue, 24 Nov 2026 10:00:00 GMT"
    final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT').firstMatch(h);
    if (m == null) return null;
    final month = _months[m.group(2)];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(m.group(3)!), month, int.parse(m.group(1)!),
      int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!),
    );
  }
}
