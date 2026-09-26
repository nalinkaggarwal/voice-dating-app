/// Mirrors backend UserStatus exactly -- keep these two in sync by hand
/// until a shared schema/codegen step exists.
enum UserStatus {
  accountCreated,
  basicInfoDone,
  preferencesDone,
  intentDone,
  voiceRecorded,
  aiReviewDone,
  photoUploaded,
  active,
}

UserStatus _statusFromJson(String raw) {
  final camel = _screamingSnakeToCamel(raw);
  return UserStatus.values.firstWhere(
    (s) => s.name == camel,
    orElse: () => UserStatus.accountCreated,
  );
}

// Backend sends SCREAMING_SNAKE_CASE (e.g. ACCOUNT_CREATED); Dart enums
// here are camelCase (accountCreated) -- compare on a normalized form
// instead of hardcoding a lookup table that could drift from the enum.
String _screamingSnakeToCamel(String screamingSnake) {
  final parts = screamingSnake.toLowerCase().split('_');
  return parts.first + parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

class User {
  const User({
    required this.id,
    required this.status,
    this.email,
    this.phone,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      status: _statusFromJson(json['status'] as String),
    );
  }

  final String id;
  final String? email;
  final String? phone;
  final UserStatus status;
}
