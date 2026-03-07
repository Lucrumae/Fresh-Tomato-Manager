import 'package:flutter/material.dart';

// English-only localization
class AppL10n {
  final Locale locale;
  AppL10n(this.locale);

  static AppL10n of(BuildContext context) =>
    Localizations.of<AppL10n>(context, AppL10n)!;

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();
  static const supportedLocales = [Locale('en')];

  // ── General ──────────────────────────────────────────────────────────────
  String get appTitle      => 'Tomato Manager';
  String get appSubtitle   => 'Manage your FreshTomato router from anywhere via SSH.';
  String get btnStart      => 'Get Started';
  String get btnConnect    => 'Connect';
  String get btnCancel     => 'Cancel';
  String get btnSave       => 'Save';
  String get btnReboot     => 'Reboot';
  String get btnDisconnect => 'Disconnect';
  String get btnChange     => 'Change';

  // ── Setup screen ─────────────────────────────────────────────────────────
  String get connectTitle    => 'Connect via SSH';
  String get connectSubtitle => 'Make sure SSH is enabled: Administration → Admin Access → SSH';
  String get fieldIp         => 'Router IP Address';
  String get fieldPort       => 'SSH Port';
  String get fieldUsername   => 'Username';
  String get fieldPassword   => 'Password';
  String get tipsTitle       => 'Tips';
  String get tipsContent     => '• FreshTomato username is usually: root\n• Password = router admin password';
  String get rememberMe      => 'Remember Me';
  String get connecting      => 'Connecting...';
  String get reconnectFailed => 'Failed to reconnect. Please login again.';

  // ── Navigation ───────────────────────────────────────────────────────────
  String get dashboard  => 'Dashboard';
  String get devices    => 'Devices';
  String get bandwidth  => 'Bandwidth';
  String get logs       => 'Logs';
  String get terminal   => 'Terminal';
  String get files      => 'Files';
  String get settings   => 'Settings';

  // ── Settings ─────────────────────────────────────────────────────────────
  String get darkMode       => 'Dark Mode';
  String get darkModeOn     => 'Enabled';
  String get darkModeOff    => 'Disabled';
  String get display        => 'Display';
  String get network        => 'Network';
  String get qosRules       => 'QoS Rules';
  String get qosSubtitle    => 'Bandwidth limit per device';
  String get portForwarding => 'Port Forwarding';
  String get portSubtitle   => 'Manage port forwarding rules';
  String get reboot         => 'Reboot Router';
  String get rebootSubtitle => 'Restart the router remotely';
  String get disconnectTitle=> 'Disconnect';
  String get disconnectSub  => 'Return to login screen';
  String get connected      => 'Connected';
  String get version        => 'Version';
  String get connection     => 'Connection';

  // ── Dashboard ────────────────────────────────────────────────────────────
  String get cpu         => 'CPU';
  String get memory      => 'Memory';
  String get uptime      => 'Uptime';
  String get loadAverage => 'Load Average';
  String get wan         => 'WAN';
  String get lan         => 'LAN';
  String get wifi        => 'WiFi';
  String get routerInfo  => 'Router Info';

  // ── Devices ──────────────────────────────────────────────────────────────
  String get searchDevices   => 'Search by name, IP, or MAC...';
  String get noDevices       => 'No devices found';
  String get blockAccess     => 'Block Internet Access';
  String get unblockAccess   => 'Unblock Device';
  String get rename          => 'Rename';
  String get block           => 'Block';
  String get unblock         => 'Unblock';
  String get blocked         => 'Blocked';
  String get ethernet        => 'Ethernet';

  // ── Logs ─────────────────────────────────────────────────────────────────
  String get refreshLogs => 'Refresh';
  String get clearLogs   => 'Clear';
  String get noLogs      => 'No logs available';

  // ── Files ────────────────────────────────────────────────────────────────
  String get upload   => 'Upload';
  String get download => 'Download';
  String get delete   => 'Delete';
  String get newFolder => 'New Folder';
  // ── Missing getters (used in screens) ────────────────────────────────────
  String get blockDevice        => 'Block Device';
  String get portForward        => 'Port Forwarding';
  String get portForwardSubtitle=> 'Manage port forwarding rules';
  String get rebootRouter       => 'Reboot Router';
  String get rebootConfirm      => 'Reboot Router?';
  String get rebootMessage      => 'The router will restart. You may lose connection for a minute.';
  String get rebootSent         => 'Reboot command sent.';
  String get disconnectMessage  => 'Return to login screen';
  String get disconnectConfirm  => 'Disconnect?';

}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();
  @override bool isSupported(Locale l) => l.languageCode == 'en';
  @override Future<AppL10n> load(Locale l) async => AppL10n(l);
  @override bool shouldReload(_AppL10nDelegate old) => false;
}
