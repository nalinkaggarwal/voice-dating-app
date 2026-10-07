/// The matched user's identity, revealed for the first time once a
/// Connection is mutual -- see ConnectionsService.getReveal on the backend.
class RevealProfile {
  const RevealProfile({required this.userId, required this.displayName, required this.photoUrl});

  factory RevealProfile.fromJson(Map<String, dynamic> json) {
    return RevealProfile(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
    );
  }

  /// The OTHER party's id -- needed to address a block()/report() call
  /// against them; see trust_safety/.
  final String userId;
  final String? displayName;
  final String? photoUrl;
}
