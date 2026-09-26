class ProfileClaim {
  const ProfileClaim({
    required this.id,
    required this.text,
    required this.approved,
    required this.discarded,
  });

  factory ProfileClaim.fromJson(Map<String, dynamic> json) {
    return ProfileClaim(
      id: json['id'] as String,
      text: json['text'] as String,
      approved: json['approved'] as bool? ?? false,
      discarded: json['discarded'] as bool? ?? false,
    );
  }

  final String id;
  final String text;
  final bool approved;
  final bool discarded;

  ProfileClaim copyWith({String? text, bool? approved, bool? discarded}) {
    return ProfileClaim(
      id: id,
      text: text ?? this.text,
      approved: approved ?? this.approved,
      discarded: discarded ?? this.discarded,
    );
  }
}
