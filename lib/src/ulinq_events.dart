class UlinqSystemEvents {
  UlinqSystemEvents._();

  static const String linkClick = 'link_click';
  static const String install = 'install';
  static const String appOpen = 'app_open';

  static const Set<String> immutable = <String>{
    linkClick,
    install,
    appOpen,
  };
}
