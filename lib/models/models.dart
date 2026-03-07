// ─── Router Status ───────────────────────────────────────────────────────────
class RouterStatus {
  final String cpuUsage;
  final String ramUsage;
  final String ramTotal;
  final String uptime;
  final String wanIp;
  final String lanIp;
  final String firmware;
  final String routerModel;
  final double cpuPercent;
  final double ramPercent;
  final int connectedDevices;
  final String wifiSsid;
  final bool isOnline;

  RouterStatus({
    required this.cpuUsage,
    required this.ramUsage,
    required this.ramTotal,
    required this.uptime,
    required this.wanIp,
    required this.lanIp,
    required this.firmware,
    required this.routerModel,
    required this.cpuPercent,
    required this.ramPercent,
    required this.connectedDevices,
    required this.wifiSsid,
    required this.isOnline,
  });

  factory RouterStatus.empty() => RouterStatus(
    cpuUsage: '0%', ramUsage: '0 MB', ramTotal: '0 MB',
    uptime: '-', wanIp: '-', lanIp: '-',
    firmware: '-', routerModel: '-',
    cpuPercent: 0, ramPercent: 0,
    connectedDevices: 0, wifiSsid: '-', isOnline: false,
  );

  factory RouterStatus.fromNvram(Map<String, String> nvram, Map<String, dynamic> sysinfo) {
    final ramFree = int.tryParse(sysinfo['memfree']?.toString() ?? '0') ?? 0;
    final ramTotal = int.tryParse(sysinfo['memtotal']?.toString() ?? '0') ?? 0;
    final ramUsed = ramTotal - ramFree;
    final ramPercent = ramTotal > 0 ? (ramUsed / ramTotal * 100) : 0.0;
    final cpu = double.tryParse(sysinfo['cpu']?.toString() ?? '0') ?? 0.0;

    return RouterStatus(
      cpuUsage: '${cpu.toStringAsFixed(1)}%',
      ramUsage: '${(ramUsed / 1024).toStringAsFixed(0)} MB',
      ramTotal: '${(ramTotal / 1024).toStringAsFixed(0)} MB',
      uptime: sysinfo['uptime']?.toString() ?? '-',
      wanIp: nvram['wan_ipaddr'] ?? '-',
      lanIp: nvram['lan_ipaddr'] ?? '192.168.1.1',
      firmware: nvram['os_version'] ?? '-',
      routerModel: nvram['t_model_name'] ?? 'FreshTomato Router',
      cpuPercent: cpu.clamp(0, 100),
      ramPercent: ramPercent.clamp(0, 100),
      connectedDevices: int.tryParse(sysinfo['wl_count']?.toString() ?? '0') ?? 0,
      wifiSsid: nvram['wl0_ssid'] ?? '-',
      isOnline: true,
    );
  }
}

// ─── Connected Device ─────────────────────────────────────────────────────────
class ConnectedDevice {
  final String mac;
  final String ip;
  String name;
  final String interface; // wl0, wl1, br0, eth
  final int txRate;
  final int rxRate;
  final String rssi;
  bool isBlocked;
  final DateTime firstSeen;
  DateTime lastSeen;

  ConnectedDevice({
    required this.mac,
    required this.ip,
    required this.name,
    required this.interface,
    required this.txRate,
    required this.rxRate,
    required this.rssi,
    required this.isBlocked,
    required this.firstSeen,
    required this.lastSeen,
  });

  String get displayName => name.isNotEmpty ? name : mac;
  bool get isWireless => interface.startsWith('wl');
  String get connectionType => isWireless ? 'WiFi' : 'Ethernet';

  ConnectedDevice copyWith({String? name, bool? isBlocked}) => ConnectedDevice(
    mac: mac, ip: ip,
    name: name ?? this.name,
    interface: interface,
    txRate: txRate, rxRate: rxRate, rssi: rssi,
    isBlocked: isBlocked ?? this.isBlocked,
    firstSeen: firstSeen, lastSeen: lastSeen,
  );
}

// ─── Bandwidth Data ───────────────────────────────────────────────────────────
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
    required this.currentRx,
    required this.currentTx,
    required this.peakRx,
    required this.peakTx,
    required this.totalRxMB,
    required this.totalTxMB,
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
  int downloadKbps;  // 0 = unlimited
  int uploadKbps;    // 0 = unlimited
  int priority;      // 1-10
  bool enabled;

  QosRule({
    required this.id,
    required this.name,
    required this.mac,
    required this.downloadKbps,
    required this.uploadKbps,
    required this.priority,
    required this.enabled,
  });

  factory QosRule.fromMap(Map<String, dynamic> map) => QosRule(
    id: map['id'] ?? '',
    name: map['name'] ?? '',
    mac: map['mac'] ?? '',
    downloadKbps: map['dl'] ?? 0,
    uploadKbps: map['ul'] ?? 0,
    priority: map['prio'] ?? 5,
    enabled: map['enabled'] == true || map['enabled'] == '1',
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'mac': mac,
    'dl': downloadKbps, 'ul': uploadKbps,
    'prio': priority, 'enabled': enabled,
  };
}

// ─── Port Forward ─────────────────────────────────────────────────────────────
class PortForwardRule {
  final String id;
  String name;
  String protocol;  // tcp, udp, both
  int externalPort;
  int internalPort;
  String internalIp;
  bool enabled;

  PortForwardRule({
    required this.id,
    required this.name,
    required this.protocol,
    required this.externalPort,
    required this.internalPort,
    required this.internalIp,
    required this.enabled,
  });

  factory PortForwardRule.fromString(String s) {
    // FreshTomato format: "on<proto><ext><int><ip><desc>"
    final parts = s.split('<');
    return PortForwardRule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: parts.length > 5 ? parts[5] : '',
      protocol: parts.length > 1 ? parts[1] : 'tcp',
      externalPort: int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
      internalPort: int.tryParse(parts.length > 3 ? parts[3] : '0') ?? 0,
      internalIp: parts.length > 4 ? parts[4] : '',
      enabled: s.startsWith('on'),
    );
  }
}

// ─── Log Entry ────────────────────────────────────────────────────────────────
class LogEntry {
  final DateTime time;
  final String facility;
  final String level;
  final String process;
  final String message;

  LogEntry({
    required this.time,
    required this.facility,
    required this.level,
    required this.process,
    required this.message,
  });

  bool get isError => level == 'err' || level == 'crit' || level == 'alert';
  bool get isWarning => level == 'warn';
}

// ─── Router Config ────────────────────────────────────────────────────────────
class TomatoConfig {
  final String host;         // LAN IP, e.g. 192.168.1.1
  final String username;
  final String password;
  final int port;
  final bool useHttps;
  final bool vpnEnabled;
  final String vpnConfig;    // OpenVPN config file content

  TomatoConfig({
    required this.host,
    required this.username,
    required this.password,
    this.port = 80,
    this.useHttps = false,
    this.vpnEnabled = false,
    this.vpnConfig = '',
  });

  String get baseUrl => '${useHttps ? 'https' : 'http'}://$host${port != 80 ? ':$port' : ''}';

  Map<String, dynamic> toJson() => {
    'host': host, 'username': username, 'password': password,
    'port': port, 'useHttps': useHttps,
    'vpnEnabled': vpnEnabled, 'vpnConfig': vpnConfig,
  };

  factory TomatoConfig.fromJson(Map<String, dynamic> j) => TomatoConfig(
    host: j['host'] ?? '192.168.1.1',
    username: j['username'] ?? 'admin',
    password: j['password'] ?? '',
    port: j['port'] ?? 80,
    useHttps: j['useHttps'] ?? false,
    vpnEnabled: j['vpnEnabled'] ?? false,
    vpnConfig: j['vpnConfig'] ?? '',
  );
}
