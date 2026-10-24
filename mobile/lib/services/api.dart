import 'dart:async';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// HTTP 423 equivalent: Safe Mode is locked (PIN needed).
class LockedException extends ApiException {
  LockedException() : super(423, 'Locked');
}

/// Turns low-level errors into a key that strings.dart can translate.
String errorKey(Object e) {
  if (e is TimeoutException) return 'err_timeout';
  return 'err_generic';
}
