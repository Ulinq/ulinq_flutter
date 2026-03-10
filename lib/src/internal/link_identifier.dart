class LinkIdentifier {
  const LinkIdentifier({this.installToken, this.token, this.slug});

  final String? installToken;
  final String? token;
  final String? slug;

  bool get isEmpty =>
      (installToken == null || installToken!.isEmpty) &&
      (token == null || token!.isEmpty) &&
      (slug == null || slug!.isEmpty);
}
