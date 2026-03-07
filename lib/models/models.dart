// ─── Router Status ────────────────────────────────────────────────────────────
class RouterStatus {
  final double cpuPercent;
  final int ramUsedMB;
  final int ramTotalMB;
  final String uptime;
  final String wanIp;
  final String lanIp;
  final String firmware;
  final String routerModel;
  final String wifiSsid;
  final bool isOnline;

  RouterStatus({
    required this.cpuPercent,
    required this.ramUsedMB,
    required this.ramTotalMB,
    required this.uptime,
    required this.wanIp,
    required this.lanIp,
    required this.firmware,
    required this.routerModel,
    required this.wifiSsid,
    required this.isOnline,
  });

  double get ramPercent => ramTotalMB > 0 ? ramUsedMB / ramTotalMB * 100 : 0;
  String get cpuUsage => '${cpuPercent.toStringAsFixed(1)}%';
  String get ramUsage => '${ramUsedMB} MB';
  String get ramTotal => '${ramTotalMB} MB';

  factory RouterStatus.empty() => RouterStatus(
    cpuPercent: 0, ramUsedMB: 0, ramTotalMB: 0,
    uptime: '-', wanIp: '-', lanIp: '-',
    firmware: '-', routerModel: 'FreshTomato Router',
    wifiSsid: '-', isOnline: false,
  );
}

// ─── Connected Device ─────────────────────────────────────────────────────────
class ConnectedDevice {
  final String mac;
  final String ip;
  String name;
  final String interface;
  final String rssi;
  bool isBlocked;
  final DateTime lastSeen;

  ConnectedDevice({
    required this.mac,
    required this.ip,
    required this.name,
    required this.interface,
    required this.rssi,
    required this.isBlocked,
    required this.lastSeen,
  });

  String get displayName => name.isNotEmpty ? name : mac;
  bool get isWireless => interface.startsWith('wl') || interface == 'wifi';
  String get connectionType => isWireless ? 'WiFi' : 'Ethernet';

  ConnectedDevice copyWith({String? name, bool? isBlocked}) => ConnectedDevice(
    mac: mac, ip: ip,
    name: name ?? this.name,
    interface: interface, rssi: rssi,
    isBlocked: isBlocked ?? this.isBlocked,
    lastSeen: lastSeen,
  );
}

// ─── Bandwidth ────────────────────────────────────────────────────────────────
class BandwidthPoint {
  final DateTime time;
  final double rxKbps;
  final double txKbps;
  BandwidthPoint({required this.time, required this.rxKbps, required this.txKbps});
}

class BandwidthStats {
  final List<BandwidthPoint> points;
  final double currentRx;
  final double currentTx;
  final double peakRx;
  final double peakTx;

  BandwidthStats({
    required this.points,
    required this.currentRx,
    required this.currentTx,
    required this.peakRx,
    required this.peakTx,
  });

  factory BandwidthStats.empty() => BandwidthStats(
    points: [], currentRx: 0, currentTx: 0, peakRx: 0, peakTx: 0,
  );
}

// ─── QoS Rule ─────────────────────────────────────────────────────────────────
class QosRule {
  final String id;
  String name;
  String mac;
  int downloadKbps;
  int uploadKbps;
  bool enabled;

  QosRule({
    required this.id, required this.name, required this.mac,
    required this.downloadKbps, required this.uploadKbps, required this.enabled,
  });
}

// ─── Port Forward ─────────────────────────────────────────────────────────────
class PortForwardRule {
  final String id;
  String name;
  String protocol;
  int externalPort;
  int internalPort;
  String internalIp;
  bool enabled;

  PortForwardRule({
    required this.id, required this.name, required this.protocol,
    required this.externalPort, required this.internalPort,
    required this.internalIp, required this.enabled,
  });
}

// ─── Log Entry ────────────────────────────────────────────────────────────────
class LogEntry {
  final DateTime time;
  final String process;
  final String level;
  final String message;

  LogEntry({
    required this.time, required this.process,
    required this.level, required this.message,
  });

  bool get isError => level == 'err' || level == 'crit' || level == 'alert';
  bool get isWarning => level == 'warn';
}

// ─── Router Config ────────────────────────────────────────────────────────────
class TomatoConfig {
  final String host;
  final String username;
  final String password;
  final int sshPort;

  TomatoConfig({
    required this.host,
    required this.username,
    required this.password,
    this.sshPort = 22,
  });

  Map<String, dynamic> toJson() => {
    'host': host, 'username': username,
    'password': password, 'sshPort': sshPort,
  };

  factory TomatoConfig.fromJson(Map<String, dynamic> j) => TomatoConfig(
    host: j['host'] ?? '192.168.1.1',
    username: j['username'] ?? 'root',
    password: j['password'] ?? '',
    sshPort: j['sshPort'] ?? 22,
  );
}
