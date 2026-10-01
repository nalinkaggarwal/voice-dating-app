/// The matched user's identity, revealed for the first time once a
/// Connection is mutual -- see ConnectionsService.getReveal on the backend.
class RevealProfile {
  const RevealProfile({required this.displayName, required this.photoUrl});

  factory RevealProfile.fromJson(Map<String, dynamic> json) {
    return RevealProfile(
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
    );
  }

  final String? displayName;
  final String? photoUrl;
}
