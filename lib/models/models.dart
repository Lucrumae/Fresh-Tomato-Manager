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
  final String wifiSsid5;
  final bool wifi24enabled;
  final bool wifi5enabled;
  final bool wifi5present;
  final double cpuTempC;
  final bool isOnline;
  final String wanIface;
  final String wifiChannel24;
  final String wifiChannel5;
  final String wifiSecurity24;
  final String wifiSecurity5;
  final String wifiTxpower24;
  final String wifiTxpower5;
  // Extended wifi fields
  final String wifiNetMode24;  // auto/b-only/g-only/bg-mixed/n-only
  final String wifiNetMode5;
  final String wifiBroadcast24; // 0=hidden, 1=broadcast
  final String wifiBroadcast5;
  final String wifiChanspec24;  // e.g. 6u, 36/80
  final String wifiChanspec5;
  final String wifiAkm24;      // psk/psk2/wpa/wpa2/radius
  final String wifiAkm5;
  final String wifiAuthMode24; // none/shared/radius
  final String wifiAuthMode5;
  final String wifiPassword24;
  final String wifiPassword5;
  final String wifiCrypto24;   // aes/tkip/aes+tkip
  final String wifiCrypto5;
  final String wifiMode24;     // ap/sta/wet/wds
  final String wifiMode5;
  final String wifiNctrlsb24;  // upper/lower
  final String wifiNctrlsb5;
  final double wifiTemp24;   // wireless phy temp °C
  final double wifiTemp5;

  RouterStatus({
    required this.cpuPercent, required this.ramUsedMB, required this.ramTotalMB,
    required this.uptime, required this.wanIp, required this.lanIp,
    required this.firmware, required this.routerModel,
    required this.wifiSsid, required this.isOnline,
    this.wifiSsid5 = '',
    this.wifi24enabled = true,
    this.wifi5enabled = true,
    this.wifi5present = false,
    this.cpuTempC = 0,
    this.wanIface = '',
    this.wifiChannel24 = '',
    this.wifiChannel5 = '',
    this.wifiSecurity24 = '',
    this.wifiSecurity5 = '',
    this.wifiTxpower24 = '',
    this.wifiTxpower5 = '',
    this.wifiNetMode24 = '',
    this.wifiNetMode5 = '',
    this.wifiBroadcast24 = '1',
    this.wifiBroadcast5 = '1',
    this.wifiChanspec24 = '',
    this.wifiChanspec5 = '',
    this.wifiAkm24 = '',
    this.wifiAkm5 = '',
    this.wifiAuthMode24 = '',
    this.wifiAuthMode5 = '',
    this.wifiPassword24 = '',
    this.wifiPassword5 = '',
    this.wifiCrypto24 = '',
    this.wifiCrypto5 = '',
    this.wifiMode24 = '',
    this.wifiMode5 = '',
    this.wifiNctrlsb24 = '',
    this.wifiNctrlsb5 = '',
    this.wifiTemp24 = 0,
    this.wifiTemp5 = 0,
  });

  String get cpuTemp => cpuTempC > 0 ? '${cpuTempC.toStringAsFixed(1)}°C' : '-';
  double get ramPercent => ramTotalMB > 0 ? ramUsedMB / ramTotalMB * 100 : 0;
  String get cpuUsage => '${cpuPercent.toStringAsFixed(1)}%';
  String get ramUsage => '${ramUsedMB} MB';
  String get ramTotal => '${ramTotalMB} MB';

  factory RouterStatus.empty() => RouterStatus(
    cpuPercent: 0, ramUsedMB: 0, ramTotalMB: 0,
    uptime: '-', wanIp: '-', lanIp: '-',
    firmware: '-', routerModel: 'FreshTomato Router',
    wifiSsid: '-', wifiSsid5: '',
    wifi24enabled: true, wifi5enabled: true, wifi5present: false,
    isOnline: false, cpuTempC: 0,
  );
}

// ─── Connected Device ─────────────────────────────────────────────────────────
class ConnectedDevice {
  final String mac;
  final String ip;
  String name;
  final String hostname;
  final String interface;
  final String rssi;
  bool isBlocked;
  final DateTime lastSeen;

  ConnectedDevice({
    required this.mac, required this.ip, required this.name,
    this.hostname = '',
    required this.interface, required this.rssi,
    required this.isBlocked, required this.lastSeen,
  });

  String get displayName => name.isNotEmpty ? name : (hostname.isNotEmpty ? hostname : mac);
  bool get isWireless => interface.startsWith('wl') || interface == 'wifi' || interface == 'eth1' || interface == 'eth2';
  String get connectionType => isWireless ? 'WiFi' : 'Ethernet';
  // WiFi band from interface: eth1/wl0=2.4GHz, eth2/wl1=5GHz
  String get wifiBand {
    if (!isWireless) return '';
    if (interface == 'eth1' || interface == 'wl0' || interface.contains('wl0')) return '2.4 GHz';
    if (interface == 'eth2' || interface == 'wl1' || interface.contains('wl1')) return '5 GHz';
    return 'WiFi';
  }

  ConnectedDevice copyWith({String? name, bool? isBlocked}) => ConnectedDevice(
    mac: mac, ip: ip, name: name ?? this.name,
    hostname: hostname,
    interface: interface, rssi: rssi,
    isBlocked: isBlocked ?? this.isBlocked, lastSeen: lastSeen,
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
  final double totalRxMB;
  final double totalTxMB;

  BandwidthStats({
    required this.points,
    required this.currentRx, required this.currentTx,
    required this.peakRx, required this.peakTx,
    this.totalRxMB = 0, this.totalTxMB = 0,
  });

  factory BandwidthStats.empty() => BandwidthStats(
    points: [], currentRx: 0, currentTx: 0,
    peakRx: 0, peakTx: 0, totalRxMB: 0, totalTxMB: 0,
  );
}

// ─── QoS Rule ─────────────────────────────────────────────────────────────────
class QosRule {
  final String id;
  String name;
  String mac;
  int downloadKbps;
  int uploadKbps;
  int priority;
  bool enabled;

  QosRule({
    required this.id, required this.name, required this.mac,
    required this.downloadKbps, required this.uploadKbps,
    this.priority = 5, required this.enabled,
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
  final String source; // 'system' or 'kernel'

  LogEntry({
    required this.time, required this.process,
    required this.level, required this.message,
    this.source = 'system',
  });

  bool get isError => level == 'err' || level == 'crit' || level == 'alert';
  bool get isWarning => level == 'warn';
  bool get isKernel  => source == 'kernel';
  bool get isSyslog  => source == 'system'; // all non-kernel entries
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
