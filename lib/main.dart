import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, HttpHeaders, HttpClient;
import 'dart:math';
import 'package:appsflyer_sdk/appsflyer_sdk.dart' as af_core;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;

// ============================================================================
// Константы (яичные)
// ============================================================================
const String kEggStatEndpoint = "https://api.gardencare.cfd/stat";

// ============================================================================
// Утилиты логирования
// ============================================================================
void eggLogI(Object msg) => debugPrint("[I] $msg");
void eggLogW(Object msg) => debugPrint("[W] $msg");
void eggLogE(Object msg) => debugPrint("[E] $msg");

// ============================================================================
// Сеть (яичная)
// ============================================================================
class EggNet {
  Future<void> postJson(String url, Map<String, dynamic> data) async {
    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      );
      eggLogI("POST $url => ${res.statusCode}");
    } catch (e) {
      eggLogE("postJson error: $e");
    }
  }
}

// ============================================================================
// Профиль устройства (яичный)
// ============================================================================
class EggDevice {
  String? eggId;
  String? batchId = "single-egg";
  String? platform;
  String? osBuild;
  String? appVersion;
  String? language;
  String? timezone;
  bool pushAllowed = true; // заглушка

  Future<void> boil() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      eggId = a.id;
      platform = "android";
      osBuild = a.version.release;
    } else if (Platform.isIOS) {
      final i = await info.iosInfo;
      eggId = i.identifierForVendor;
      platform = "ios";
      osBuild = i.systemVersion;
    }
    final pkg = await PackageInfo.fromPlatform();
    appVersion = pkg.version;
    language = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    timezone = tz_zone.local.name;
    batchId = "batch-${DateTime.now().millisecondsSinceEpoch}";
  }

  Map<String, dynamic> toMap({String? yolk}) => {
    "fcm_token": yolk ?? 'missing_yolk',
    "device_id": eggId ?? 'missing_egg',
    "app_name": "eggcarton",
    "instance_id": batchId ?? 'missing_batch',
    "platform": platform ?? 'missing_platform',
    "os_version": osBuild ?? 'missing_os',
    "app_version": appVersion ?? 'missing_app',
    "language": language ?? 'en',
    "timezone": timezone ?? 'UTC',
    "push_enabled": pushAllowed,
  };
}

// ============================================================================
// AppsFlyer (яичный советник)
// ============================================================================
class EggAdvisor with ChangeNotifier {
  af_core.AppsFlyerOptions? _opts;
  af_core.AppsflyerSdk? _sdk;

  String shellId = "";
  String albumen = "";

  void hatch(VoidCallback markDirty) {
    final cfg = af_core.AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6754609255",
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );
    _opts = cfg;
    _sdk = af_core.AppsflyerSdk(cfg);

    _sdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    _sdk?.startSDK(
      onSuccess: () => eggLogI("EggAdvisor hatched"),
      onError: (int c, String m) => eggLogE("EggAdvisor error $c: $m"),
    );
    _sdk?.onInstallConversionData((data) {
      albumen = data.toString();
      markDirty();
      notifyListeners();
    });
    _sdk?.getAppsFlyerUID().then((v) {
      shellId = v.toString();
      markDirty();
      notifyListeners();
    });
  }
}

// ============================================================================
// Egg Cargo и портовый рабочий (без BLoC/Provider)
// ============================================================================
class EggCargoModel {
  final EggDevice device;
  final EggAdvisor advisor;
  EggCargoModel({required this.device, required this.advisor});

  Map<String, dynamic> devicePayload(String? yolk) => device.toMap(yolk: yolk);

  Map<String, dynamic> afPayload(String? yolk) => {
    "content": {
      "af_data": advisor.albumen,
      "af_id": advisor.shellId,
      "fb_app_name": "eggsway",
      "app_name": "eggsway",
      "deep": null,
      "bundle_identifier": "com.glolp.ghijj.eggway",
      "app_version": "1.0.0",
      "apple_id": "6754609255",
      "fcm_token": yolk ?? "no_yolk",
      "device_id": device.eggId ?? "no_device",
      "instance_id": device.batchId ?? "no_batch",
      "platform": device.platform ?? "no_platform",
      "os_version": device.osBuild ?? "no_os",
      "app_version": device.appVersion ?? "no_app",
      "language": device.language ?? "en",
      "timezone": device.timezone ?? "UTC",
      "push_enabled": device.pushAllowed,
      "useruid": advisor.shellId,
    },
  };
}

class EggPorter {
  final EggCargoModel model;
  final InAppWebViewController Function() pickWeb;

  String? _lastUrl;
  int _lastMs = 0;
  static const int _throttleMs = 2000;

  EggPorter({required this.model, required this.pickWeb});

  Future<void> putDeviceIntoLocalStorage(String? yolk) async {
    final m = model.devicePayload(yolk);
    await pickWeb().evaluateJavascript(source: '''
try { localStorage.setItem('app_data', JSON.stringify(${jsonEncode(m)})); } catch (_) {}
''');
  }

  Future<void> pourAFRaw(String? yolk, {String? currentUrl}) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - _lastMs < _throttleMs) {
      eggLogW("pourAFRaw throttled (time)");
      return;
    }
    if (currentUrl != null && _lastUrl == currentUrl) {
      eggLogW("pourAFRaw skipped (same url)");
      return;
    }

    final payload = model.afPayload(yolk);
    final jsonString = jsonEncode(payload);
    eggLogI("pourAFRaw: $jsonString");

    await pickWeb().evaluateJavascript(source: "try { sendRawData(${jsonEncode(jsonString)}); } catch(_) {}");

    _lastMs = now;
    if (currentUrl != null) _lastUrl = currentUrl;
  }
}

// ============================================================================
// Кэш «желтка» без сторонних хранилищ
// ============================================================================
class EggYolkStore {
  String? _yolk;

  String? get yolk => _yolk;

  Future<void> initOrGenerate() async {
    // Попытка вытащить из страницы, если она уже что-то сохранила (можно вызвать позже)
    _yolk ??= "yolk-${DateTime.now().millisecondsSinceEpoch}";
  }

  void setYolk(String s) {
    if (s.isEmpty) return;
    _yolk = s;
  }
}

// ============================================================================
// Статистика (яичная)
// ============================================================================
Future<String> eggFinalUrl(String startUrl, {int maxHops = 10}) async {
  final client = HttpClient();
  client.userAgent = 'Mozilla/5.0 (Flutter; dart:io HttpClient)';
  try {
    var current = Uri.parse(startUrl);
    for (int i = 0; i < maxHops; i++) {
      final req = await client.getUrl(current);
      req.followRedirects = false;
      final res = await req.close();
      if (res.isRedirect) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        if (loc == null || loc.isEmpty) break;
        final next = Uri.parse(loc);
        current = next.hasScheme ? next : current.resolveUri(next);
        continue;
      }
      return current.toString();
    }
    return current.toString();
  } catch (e) {
    debugPrint("eggFinalUrl error: $e");
    return startUrl;
  } finally {
    client.close(force: true);
  }
}

Future<void> postEggStat({
  required String event,
  required int timeStart,
  required String url,
  required int timeFinish,
  required String appYolk,
  int? firstPageLoadTs,
}) async {
  try {
    final finalUrl = await eggFinalUrl(url);
    final payload = {
      "event": event,
      "timestart": timeStart,
      "timefinsh": timeFinish,
      "url": finalUrl,
      "appleID": "6754609255",
      "open_count": "$appYolk/$timeStart",
    };

    debugPrint("eggstat $payload");
    final res = await http.post(
      Uri.parse("$kEggStatEndpoint/$appYolk"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );
    debugPrint("postEggStat status=${res.statusCode} body=${res.body}");
  } catch (e) {
    debugPrint("postEggStat error: $e");
  }
}

// ============================================================================
// Лоадер: жёлтый фон + чёрное яйцо, слегка качается
// ============================================================================
class EggSwingLoader extends StatefulWidget {
  const EggSwingLoader({Key? key}) : super(key: key);

  @override
  State<EggSwingLoader> createState() => _EggSwingLoaderState();
}

class _EggSwingLoaderState extends State<EggSwingLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _angle;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _angle = Tween<double>(begin: -0.06, end: 0.06).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFEB3B), // насыщённый жёлтый
      child: Center(
        child: AnimatedBuilder(
          animation: _angle,
          builder: (context, _) {
            return Transform.rotate(
              angle: _angle.value,
              child: CustomPaint(
                size: const Size(120, 160),
                painter: _EggShapePainter(),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EggShapePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black..style = PaintingStyle.fill;
    // Овальная форма яйца (слегка вытянута вверх)
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(60));
    final path = Path()..addRRect(rrect);

    // Сужение внизу: скейл по Y
    canvas.save();
    final matrix4 = Matrix4.identity();
    matrix4.translate(size.width / 2, size.height / 2);
    matrix4.scale(0.88, 1.05);
    matrix4.translate(-size.width / 2, -size.height / 2);
    canvas.transform(matrix4.storage);

    // Лёгкая деформация для более «яичной» формы
    final deform = Path();
    deform.addOval(Rect.fromLTWH(size.width * 0.08, size.height * 0.05, size.width * 0.84, size.height * 0.92));
    canvas.drawPath(deform, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// Внешние URL: через платформенный канал (вместо url_launcher)
// ============================================================================
class EggExternalOpener {
  static const _channel = MethodChannel('com.example.egg/external');

  static Future<bool> open(Uri uri) async {
    try {
      final ok = await _channel.invokeMethod<bool>('openExternalUri', {'uri': uri.toString()});
      return ok ?? false;
    } catch (e) {
      eggLogE("open external failed: $e");
      return false;
    }
  }
}

// ============================================================================
// Главный WebView — EggHarbor
// ============================================================================
class EggHarbor extends StatefulWidget {
  final String? yolk;
  const EggHarbor({super.key, required this.yolk});

  @override
  State<EggHarbor> createState() => _EggHarborState();
}

class _EggHarborState extends State<EggHarbor> with WidgetsBindingObserver {
  late InAppWebViewController _web;
  bool _busy = false;
  final String _home = "https://y.eggsway.xyz/";
  final EggDevice _device = EggDevice();
  final EggAdvisor _advisor = EggAdvisor();

  DateTime? _sleepAt;
  bool _veil = false;
  bool _cover = true;

  bool _sentOnce = false; // без кэша — одноразовая метка в рантайме
  int? _firstPageTs;

  EggPorter? _porter;
  EggCargoModel? _cargo;

  String _currentUrl = "";
  var _loadStartTs = 0;

  final Map<String, bool> _afPushedForUrl = {};
  final Set<String> _schemes = {
    'tg', 'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
  };

  final Set<String> _externalHosts = {
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'm.me',
    'signal.me',
    'bnl.com', 'www.bnl.com',
  };

  final EggYolkStore _yolkStore = EggYolkStore();
  bool _bootAfSentOnce = false;
  bool _notificationHandlerBound = false;
  bool _handledServerResponse = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firstPageTs = DateTime.now().millisecondsSinceEpoch;

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _cover = false);
    });

    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() => _veil = true);
    });

    _boot();
  }

  Future<void> sendEggLoadedOnce({required String url, required int timestart}) async {
    if (_sentOnce) {
      debugPrint("Egg Loaded already sent, skipping");
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await postEggStat(
      event: "Loaded",
      timeStart: timestart,
      timeFinish: now,
      url: url,
      appYolk: _advisor.shellId,
      firstPageLoadTs: _firstPageTs,
    );
    _sentOnce = true;
  }

  void _boot() async {
    _advisor.hatch(() => setState(() {}));
    _bindNotificationTap();
    await _prepareDevice();
    print("");
    Future.delayed(const Duration(seconds: 6), () async {
      if (!_bootAfSentOnce) {
        _bootAfSentOnce = true;
        await _pushAF(currentUrl: _currentUrl.isEmpty ? _home : _currentUrl);
      }
      await _pushDevice();
    });
  }

  void _bindNotificationTap() {
    if (_notificationHandlerBound) return;
    _notificationHandlerBound = true;

    const ch = MethodChannel('com.example.egg/notification');
    ch.setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(call.arguments);
        final uri = payload["uri"]?.toString();
        if (uri != null && uri.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => EggWatchtower(uri)),
                  (route) => false,
            );
          });
        }
      }
      return null;
    });
  }

  Future<void> _prepareDevice() async {
    try {
      await _device.boil();
      await _yolkStore.initOrGenerate();
      _cargo = EggCargoModel(device: _device, advisor: _advisor);
      _porter = EggPorter(model: _cargo!, pickWeb: () => _web);
    } catch (e) {
      eggLogE("prepare-egg-device fail: $e");
    }
  }

  Future<void> _pushDevice() async {
    eggLogI("YOLK ship ${widget.yolk}");
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final yolk = (widget.yolk != null && widget.yolk!.isNotEmpty)
          ? widget.yolk
          : _yolkStore.yolk;
      await _porter?.putDeviceIntoLocalStorage(yolk);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pushAF({String? currentUrl}) async {
    final yolk = (widget.yolk != null && widget.yolk!.isNotEmpty)
        ? widget.yolk
        : _yolkStore.yolk;
    await _porter?.pourAFRaw(yolk, currentUrl: currentUrl);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) {
      _sleepAt = DateTime.now();
    }
    if (s == AppLifecycleState.resumed) {
      if (Platform.isIOS && _sleepAt != null) {
        final now = DateTime.now();
        final drift = now.difference(_sleepAt!);
        if (drift > const Duration(minutes: 25)) {
          _reboard();
        }
      }
      _sleepAt = null;
    }
  }

  void _reboard() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => EggHarbor(yolk: widget.yolk)),
            (route) => false,
      );
    });
  }

  // ================== URL helpers (яичные) ==================
  bool _isBareEmail(Uri u) {
    final s = u.scheme;
    if (s.isNotEmpty) return false;
    final raw = u.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  Uri _toMailto(Uri u) {
    final full = u.toString();
    final parts = full.split('?');
    final email = parts.first;
    final qp = parts.length > 1 ? Uri.splitQueryString(parts[1]) : <String, String>{};
    return Uri(scheme: 'mailto', path: email, queryParameters: qp.isEmpty ? null : qp);
  }

  bool _isPlatformish(Uri u) {
    final s = u.scheme.toLowerCase();
    if (_schemes.contains(s)) return true;

    if (s == 'http' || s == 'https') {
      final h = u.host.toLowerCase();
      if (_externalHosts.contains(h)) return true;
      if (h.endsWith('t.me')) return true;
      if (h.endsWith('wa.me')) return true;
      if (h.endsWith('m.me')) return true;
      if (h.endsWith('signal.me')) return true;
    }
    return false;
  }

  Uri _httpize(Uri u) {
    final s = u.scheme.toLowerCase();

    if (s == 'tg' || s == 'telegram') {
      final qp = u.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {if (qp['start'] != null) 'start': qp['start']!});
      }
      final path = u.path.isNotEmpty ? u.path : '';
      return Uri.https('t.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if ((s == 'http' || s == 'https') && u.host.toLowerCase().endsWith('t.me')) {
      return u;
    }

    if (s == 'viber') return u;

    if (s == 'whatsapp') {
      final qp = u.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https('wa.me', '/${_digits(phone)}', {if (text != null && text.isNotEmpty) 'text': text});
      }
      return Uri.https('wa.me', '/', {if (text != null && text.isNotEmpty) 'text': text});
    }

    if ((s == 'http' || s == 'https') &&
        (u.host.toLowerCase().endsWith('wa.me') || u.host.toLowerCase().endsWith('whatsapp.com'))) {
      return u;
    }

    if (s == 'skype') return u;

    if (s == 'fb-messenger') {
      final path = u.pathSegments.isNotEmpty ? u.pathSegments.join('/') : '';
      final qp = u.queryParameters;
      final id = qp['id'] ?? qp['user'] ?? path;
      if (id.isNotEmpty) {
        return Uri.https('m.me', '/$id', u.queryParameters.isEmpty ? null : u.queryParameters);
      }
      return Uri.https('m.me', '/', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if (s == 'sgnl') {
      final qp = u.queryParameters;
      final ph = qp['phone'];
      final un = u.queryParameters['username'];
      if (ph != null && ph.isNotEmpty) return Uri.https('signal.me', '/#p/${_digits(ph)}');
      if (un != null && un.isNotEmpty) return Uri.https('signal.me', '/#u/$un');
      final path = u.pathSegments.join('/');
      if (path.isNotEmpty) return Uri.https('signal.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
      return u;
    }

    if (s == 'tel') return Uri.parse('tel:${_digits(u.path)}');
    if (s == 'mailto') return u;

    if (s == 'bnl') {
      final newPath = u.path.isNotEmpty ? u.path : '';
      return Uri.https('bnl.com', '/$newPath', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    return u;
  }

  Future<bool> _openMailWeb(Uri mailto) async {
    // Открываем через платформенный канал
    return await EggExternalOpener.open(mailto);
  }

  Future<bool> _openExternal(Uri u) async {
    return await EggExternalOpener.open(u);
  }

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            if (_cover)
              const EggSwingLoader()
            else
              Container(
                color: Colors.white,
                child: Stack(
                  children: [
                    InAppWebView(
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        disableDefaultErrorPage: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        allowsPictureInPictureMediaPlayback: true,
                        useOnDownloadStart: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true,
                        transparentBackground: false,
                      ),
                      initialUrlRequest: URLRequest(url: WebUri(_home)),
                      onWebViewCreated: (c) {
                        _web = c;

                        _cargo ??= EggCargoModel(device: _device, advisor: _advisor);
                        _porter ??= EggPorter(model: _cargo!, pickWeb: () => _web);

                        _web.addJavaScriptHandler(
                          handlerName: 'onServerResponse',
                          callback: (args) {
                            if (_handledServerResponse) {
                              if (args.isEmpty) return null;
                              try { return args.reduce((curr, next) => curr + next); } catch (_) { return args.first; }
                            }
                            try {
                              final saved = args.isNotEmpty &&
                                  args[0] is Map &&
                                  args[0]['savedata'].toString() == "false";

                              print("datasaved "+args[0]['savedata'].toString());
                              if (saved && !_handledServerResponse) {
                                _handledServerResponse = true;
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(builder: (context) => EggHelp()),
                                      (route) => false,
                                );

                              }
                            } catch (_) {}
                            if (args.isEmpty) return null;
                            try { return args.reduce((curr, next) => curr + next); } catch (_) { return args.first; }
                          },
                        );
                      },
                      onLoadStart: (c, u) async {
                        setState(() {
                          _loadStartTs = DateTime.now().millisecondsSinceEpoch;
                          _busy = true;
                        });
                        if (u != null) {
                          if (_isBareEmail(u)) {
                            try { await c.stopLoading(); } catch (_) {}
                            final mailto = _toMailto(u);
                            await _openMailWeb(mailto);
                            return;
                          }
                          final sch = u.scheme.toLowerCase();
                          if (sch != 'http' && sch != 'https') {
                            try { await c.stopLoading(); } catch (_) {}
                          }
                        }
                      },
                      onLoadError: (controller, url, code, message) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final ev = "InAppWebViewError(code=$code, message=$message)";
                        await postEggStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: url?.toString() ?? '',
                          appYolk: _advisor.shellId,
                          firstPageLoadTs: _firstPageTs,
                        );
                        if (mounted) setState(() => _busy = false);
                      },
                      onReceivedHttpError: (controller, request, errorResponse) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final ev = "HTTPError(status=${errorResponse.statusCode}, reason=${errorResponse.reasonPhrase})";
                        await postEggStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: request.url?.toString() ?? '',
                          appYolk: _advisor.shellId,
                          firstPageLoadTs: _firstPageTs,
                        );
                      },
                      onReceivedError: (controller, request, error) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final desc = (error.description ?? '').toString();
                        final ev = "WebResourceError(code=${error}, message=$desc)";
                        await postEggStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: request.url?.toString() ?? '',
                          appYolk: _advisor.shellId,
                          firstPageLoadTs: _firstPageTs,
                        );
                      },
                      onLoadStop: (c, u) async {
                        await c.evaluateJavascript(source: "console.log('Egg Harbor up!');");

                        final urlStr = u?.toString() ?? '';
                        setState(() => _currentUrl = urlStr);

                        await _pushDevice();

                        if (urlStr.isNotEmpty && _afPushedForUrl[urlStr] != true) {
                          _afPushedForUrl[urlStr] = true;
                          await _pushAF(currentUrl: urlStr);
                        }

                        Future.delayed(const Duration(seconds: 20), () {
                          sendEggLoadedOnce(url: _currentUrl.toString(), timestart: _loadStartTs);
                        });

                        if (mounted) setState(() => _busy = false);
                      },
                      shouldOverrideUrlLoading: (c, action) async {
                        final uri = action.request.url;
                        if (uri == null) return NavigationActionPolicy.ALLOW;

                        if (_isBareEmail(uri)) {
                          final mailto = _toMailto(uri);
                          await _openMailWeb(mailto);
                          return NavigationActionPolicy.CANCEL;
                        }

                        final sch = uri.scheme.toLowerCase();

                        if (sch == 'mailto') {
                          await _openMailWeb(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (sch == 'tel') {
                          await _openExternal(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (_isPlatformish(uri)) {
                          final web = _httpize(uri);
                          if (web.scheme == 'http' || web.scheme == 'https') {
                            // Откроем в отдельном InApp окне
                            Navigator.push(context, MaterialPageRoute(builder: (_) => EggDeck(web.toString())));
                          } else {
                            // Попытка через натив
                            await _openExternal(uri);
                          }
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (sch != 'http' && sch != 'https') {
                          return NavigationActionPolicy.CANCEL;
                        }

                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (c, req) async {
                        final uri = req.request.url;
                        if (uri == null) return false;

                        if (_isBareEmail(uri)) {
                          final mailto = _toMailto(uri);
                          await _openMailWeb(mailto);
                          return false;
                        }

                        final sch = uri.scheme.toLowerCase();

                        if (sch == 'mailto') {
                          await _openMailWeb(uri);
                          return false;
                        }

                        if (sch == 'tel') {
                          await _openExternal(uri);
                          return false;
                        }

                        if (_isPlatformish(uri)) {
                          final web = _httpize(uri);
                          if (web.scheme == 'http' || web.scheme == 'https') {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => EggDeck(web.toString())));
                          } else {
                            await _openExternal(uri);
                          }
                          return false;
                        }

                        if (sch == 'http' || sch == 'https') {
                          c.loadUrl(urlRequest: URLRequest(url: uri));
                        }
                        return false;
                      },
                      onDownloadStartRequest: (c, req) async {
                        // Попробуем открыть через натив
                        await _openExternal(req.url);
                      },
                    ),
                    Visibility(
                      visible: !_veil,
                      child: const EggSwingLoader(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Внешний WebView (яичный)
// ============================================================================
class EggDeck extends StatefulWidget {
  final String url;
  const EggDeck(this.url, {super.key});

  @override
  State<EggDeck> createState() => _EggDeckState();
}

class _EggDeckState extends State<EggDeck> {
  late InAppWebViewController _deck;

  @override
  Widget build(BuildContext context) {
    final night = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: night ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: InAppWebView(
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            disableDefaultErrorPage: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            allowsPictureInPictureMediaPlayback: true,
            useOnDownloadStart: true,
            javaScriptCanOpenWindowsAutomatically: true,
            useShouldOverrideUrlLoading: true,
            supportMultipleWindows: true,
          ),
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
          onWebViewCreated: (c) => _deck = c,
        ),
      ),
    );
  }
}

// ============================================================================
// Help (яичный)
// ============================================================================
class EggHelp extends StatefulWidget {
  const EggHelp({super.key});
  @override
  State<EggHelp> createState() => _EggHelpState();
}

class _EggHelpState extends State<EggHelp> {
  InAppWebViewController? _ctrl;
  bool _spin = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              InAppWebView(
                initialFile: 'assets/egg.html',
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  supportZoom: false,
                  disableHorizontalScroll: false,
                  disableVerticalScroll: false,
                ),
                onWebViewCreated: (c) => _ctrl = c,
                onLoadStart: (c, u) => setState(() => _spin = true),
                onLoadStop: (c, u) async => setState(() => _spin = false),
                onLoadError: (c, u, code, msg) => setState(() => _spin = false),
              ),
              if (_spin) const EggSwingLoader(),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Вышка-наблюдатель (яичная)
// ============================================================================
class EggWatchtower extends StatefulWidget {
  final String url;
  const EggWatchtower(this.url, {super.key});

  @override
  State<EggWatchtower> createState() => _EggWatchtowerState();
}

class _EggWatchtowerState extends State<EggWatchtower> {
  @override
  Widget build(BuildContext context) {
    return EggDeck(widget.url);
  }
}

// ============================================================================
// Стартовый экран (яичный)
// ============================================================================
class EggFoyer extends StatefulWidget {
  const EggFoyer({Key? key}) : super(key: key);

  @override
  State<EggFoyer> createState() => _EggFoyerState();
}

class _EggFoyerState extends State<EggFoyer> {
  final EggYolkStore _yolkStore = EggYolkStore();
  bool _once = false;
  Timer? _fallback;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));

    _prepare();
  }

  Future<void> _prepare() async {
    await _yolkStore.initOrGenerate();
    // Если натив пришлёт yolk — примем (опционально)
    const ch = MethodChannel('com.example.egg/yolk');
    ch.setMethodCallHandler((call) async {
      if (call.method == 'setYolk') {
        final String s = call.arguments as String;
        if (s.isNotEmpty) _yolkStore.setYolk(s);
      }
      return null;
    });

    _go(_yolkStore.yolk ?? "");
    _fallback = Timer(const Duration(seconds: 8), () {
      if (!_once) _go(_yolkStore.yolk ?? "");
    });
  }

  void _go(String sig) {
    if (_once) return;
    _once = true;
    _fallback?.cancel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => EggHarbor(yolk: sig)),
      );
    });
  }

  @override
  void dispose() {
    _fallback?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFFEB3B),
      body: Center(child: EggSwingLoader()),
    );
  }
}

// ============================================================================
// main() (яичный) — без shared_preferences, url_launcher, logger, secure_storage
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  tz_data.initializeTimeZones();

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const EggFoyer(),
    ),
  );
}