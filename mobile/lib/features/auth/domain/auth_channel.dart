/// Mirrors backend OtpChannel exactly.
enum AuthChannel { email, phone }

extension AuthChannelJson on AuthChannel {
  String get wireValue => name.toUpperCase();
}
