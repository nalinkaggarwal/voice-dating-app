/// A single exception type for anything the UI needs to show a message
/// for (network failure, backend-returned error, validation failure).
/// Feature-level code catches raw exceptions (http, decode errors, etc.)
/// and rethrows as this, so presentation code only ever has one type to
/// handle.
class AppException implements Exception {
  const AppException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AppException($statusCode): $message';
}
