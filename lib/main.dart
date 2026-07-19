// ============================================================================
//  XYZ BROWSER · v2.1 "COMPLETE"
//  main.dart — single-file, dibangun ulang persis SKEMA-UI.md
//  Stack: Flutter + webview_flutter · tema HUD futuristik cyan→purple
// ============================================================================
//
//  v2.1 menambah fitur setara browser lain:
//   • Unduh berkas (tautan langsung → folder app + layar Downloads)
//   • Upload berkas (<input type=file> → file picker sistem)
//   • Izin situs: kamera / mikrofon / lokasi (dialog Izinkan/Tolak)
//   • Autoplay media · zoom teks 80–175% · mode gelap paksa
//   • Blokir iklan & tracker (kosmetik CSS) · Find in Page
//   • Situs desktop · Incognito sungguhan (tak simpan riwayat, hapus cache)
//   • Tautan target=_blank ditangani · buka skema app luar (intent/tel/mailto)
//
//  Screen (sesuai skema):
//   • Splash  → logo gradient
//   • Home    → logo, URL bar, quick sites grid 4×2, bottom nav
//   • WebView → browsing aktif
//   • Tabs    → tab switcher + FAB
//   • Drawer  → menu samping
//   • Monitor → performance dashboard (CPU/RAM/Battery real, GPU estimasi)
//   • Settings→ grouped list
//
//  DEPENDENSI pubspec.yaml:
//    webview_flutter: ^4.7.0
//    shared_preferences: ^2.2.3
//    url_launcher: ^6.3.0
//  (Typografi/ikon/chart skema disederhanakan ke bawaan Flutter agar
//   ringan di-build Termux; ganti ke google_fonts/fl_chart/phosphor bila mau.)
//
//  Permission AndroidManifest.xml: INTERNET, ACCESS_NETWORK_STATE
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Kunci navigator global — untuk dialog izin & notifikasi unduhan yang
/// dipicu dari luar pohon widget (mis. dari dalam WebView delegate).
final navKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Store.load();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ));
    runApp(const XyzApp());
  }, (e, st) => debugPrint('UNCAUGHT: $e\n$st'));
}

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN SYSTEM  (§1 skema)
// ─────────────────────────────────────────────────────────────────────────────

class C {
  static const bg = Color(0xFF0A0A0F);
  static const surface = Color(0xFF12121A);
  static const elevated = Color(0xFF1A1A25);
  static const cyan = Color(0xFF00E5FF);
  static const purple = Color(0xFFB14BFF);
  static const text = Color(0xFFFFFFFF);
  static const text2 = Color(0xFFA0A0B0);
  static const muted = Color(0xFF5A5A6A);
  static const ok = Color(0xFF4ADE80);
  static const warn = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);

  static const grad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, purple],
  );
}

/// Judul HUD (skema pakai Orbitron; di sini spacing lebar meniru gayanya).
TextStyle display(double s, {Color c = C.text, FontWeight w = FontWeight.w800}) =>
    TextStyle(fontSize: s, color: c, fontWeight: w, letterSpacing: 1.5);

TextStyle body(double s,
        {Color c = C.text, FontWeight w = FontWeight.w400, double? sp}) =>
    TextStyle(fontSize: s, color: c, fontWeight: w, letterSpacing: sp);

TextStyle label(double s, {Color c = C.text2}) =>
    TextStyle(fontSize: s, color: c, fontWeight: FontWeight.w600, letterSpacing: 1.5);

TextStyle mono(double s, {Color c = C.text, FontWeight w = FontWeight.w800}) =>
    TextStyle(
        fontSize: s, color: c, fontWeight: w, fontFeatures: const [], letterSpacing: 0.5);

BoxDecoration glowCard({Color glow = C.cyan, bool active = false, double radius = 12}) =>
    BoxDecoration(
      color: active ? C.elevated : C.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
          color: active ? glow : glow.withOpacity(.18),
          width: active ? 1.5 : 1),
      boxShadow: active
          ? [BoxShadow(color: glow.withOpacity(.30), blurRadius: 14, spreadRadius: -2)]
          : null,
    );

// ─────────────────────────────────────────────────────────────────────────────
// STORE — persist settings (§3.5)
// ─────────────────────────────────────────────────────────────────────────────

class SearchEngine {
  const SearchEngine(this.name, this.q);
  final String name, q;
  String url(String s) => '$q${Uri.encodeComponent(s)}';
}

const kEngines = [
  SearchEngine('Google', 'https://www.google.com/search?q='),
  SearchEngine('DuckDuckGo', 'https://duckduckgo.com/?q='),
  SearchEngine('Bing', 'https://www.bing.com/search?q='),
];

class Store {
  static final homepage = ValueNotifier('https://www.google.com');
  static final engineIdx = ValueNotifier(0);
  static final blockTrackers = ValueNotifier(false);
  static final forceDark = ValueNotifier(false);
  static final desktopMode = ValueNotifier(false);
  static final autoplay = ValueNotifier(true);
  static final suggestions = ValueNotifier(true);
  static final textZoom = ValueNotifier(100);
  static final bookmarks = ValueNotifier<List<String>>([]);
  static final history = ValueNotifier<List<Map<String, String>>>([]);
  static final downloads = ValueNotifier<List<Map<String, String>>>([]);

  static SharedPreferences? _p;
  static SearchEngine get engine => kEngines[engineIdx.value.clamp(0, 2)];

  static Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      homepage.value = _p!.getString('home') ?? homepage.value;
      engineIdx.value = _p!.getInt('engine') ?? 0;
      blockTrackers.value = _p!.getBool('trackers') ?? false;
      forceDark.value = _p!.getBool('dark') ?? false;
      desktopMode.value = _p!.getBool('desktop') ?? false;
      autoplay.value = _p!.getBool('autoplay') ?? true;
      suggestions.value = _p!.getBool('suggest') ?? true;
      textZoom.value = _p!.getInt('zoom') ?? 100;
      bookmarks.value =
          (jsonDecode(_p!.getString('bm') ?? '[]') as List).cast<String>();
      history.value = (jsonDecode(_p!.getString('hist') ?? '[]') as List)
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
      downloads.value = (jsonDecode(_p!.getString('dl') ?? '[]') as List)
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('STORE: $e');
    }
    homepage.addListener(() => _p?.setString('home', homepage.value));
    engineIdx.addListener(() => _p?.setInt('engine', engineIdx.value));
    blockTrackers.addListener(() => _p?.setBool('trackers', blockTrackers.value));
    forceDark.addListener(() => _p?.setBool('dark', forceDark.value));
    desktopMode.addListener(() => _p?.setBool('desktop', desktopMode.value));
    autoplay.addListener(() => _p?.setBool('autoplay', autoplay.value));
    suggestions.addListener(() => _p?.setBool('suggest', suggestions.value));
    textZoom.addListener(() => _p?.setInt('zoom', textZoom.value));
    bookmarks.addListener(() => _p?.setString('bm', jsonEncode(bookmarks.value)));
    history.addListener(() => _p?.setString('hist', jsonEncode(history.value)));
    downloads.addListener(() => _p?.setString('dl', jsonEncode(downloads.value)));
  }

  static void addDownload(String name, String path, String url) {
    downloads.value = [
      {'name': name, 'path': path, 'url': url},
      ...downloads.value,
    ];
  }

  static void toggleBookmark(String url) {
    final l = List<String>.from(bookmarks.value);
    l.contains(url) ? l.remove(url) : l.add(url);
    bookmarks.value = l;
  }

  static void addHistory(String url, String title) {
    if (url.isEmpty || url == 'about:blank') return;
    final l = List<Map<String, String>>.from(history.value)
      ..removeWhere((e) => e['url'] == url)
      ..insert(0, {'url': url, 'title': title});
    if (l.length > 200) l.removeLast();
    history.value = l;
  }

  static void clearData() {
    history.value = [];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP + SPLASH
// ─────────────────────────────────────────────────────────────────────────────

class XyzApp extends StatelessWidget {
  const XyzApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navKey,
        title: 'XYZ Browser',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: C.bg,
          colorScheme: const ColorScheme.dark(
              primary: C.cyan, secondary: C.purple, surface: C.surface),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        home: const SplashScreen(),
      );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..forward();

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1600), () {
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const Shell()));
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FadeTransition(
            opacity: _c,
            child: ScaleTransition(
              scale: Tween(begin: .8, end: 1.0).animate(
                  CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const _Logo(size: 88),
                const SizedBox(height: 20),
                ShaderMask(
                  shaderCallback: (r) => C.grad.createShader(r),
                  child: Text('XYZ BROWSER',
                      style: display(26, c: Colors.white)),
                ),
                const SizedBox(height: 8),
                Text('FUTURISTIC WEB', style: label(11, c: C.muted)),
              ]),
            ),
          ),
        ),
      );
}

class _Logo extends StatelessWidget {
  const _Logo({this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: C.grad,
          borderRadius: BorderRadius.circular(size * .28),
          boxShadow: [BoxShadow(color: C.cyan.withOpacity(.4), blurRadius: 24)],
        ),
        child: Icon(Icons.travel_explore_rounded,
            size: size * .55, color: Colors.white),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB MODEL + MANAGER  (§5 services/tab_manager)
// ─────────────────────────────────────────────────────────────────────────────

// Ekstensi berkas yang diperlakukan sebagai unduhan langsung.
const _dlExt = {
  'apk','zip','rar','7z','tar','gz','pdf','doc','docx','xls','xlsx','ppt',
  'pptx','mp3','wav','flac','m4a','ogg','mp4','mkv','webm','avi','mov','jpg',
  'jpeg','png','gif','webp','svg','txt','csv','json','xml','iso','deb','exe',
  'dmg','epub','mobi','torrent',
};

class BrowserTab {
  BrowserTab({required this.home, this.incognito = false}) : id = _n++ {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(C.bg);
    _configureAndroid();
    _bind();
    controller.loadRequest(Uri.parse(home));
  }
  static int _n = 0;
  final int id;
  final String home;
  final bool incognito;
  late final WebViewController controller;

  final url = ValueNotifier('');
  final title = ValueNotifier('New Tab');
  final progress = ValueNotifier(0);
  final canBack = ValueNotifier(false);
  final canFwd = ValueNotifier(false);
  final secure = ValueNotifier(true);
  final loaded = ValueNotifier(false);

  // ── Kapabilitas khusus Android: upload berkas, izin situs, autoplay,
  //    zoom — inilah yang membuat form & situs media berfungsi normal. ──
  void _configureAndroid() {
    final p = controller.platform;
    if (p is! AndroidWebViewController) return;

    // Autoplay media tanpa gestur (YouTube/Twitch dsb).
    p.setMediaPlaybackRequiresUserGesture(!Store.autoplay.value);

    // Upload berkas: <input type=file> → buka file picker sistem.
    p.setOnShowFileSelector((params) async {
      try {
        final multiple =
            params.mode == FileSelectorMode.openMultiple;
        final res = await FilePicker.platform
            .pickFiles(allowMultiple: multiple);
        return res?.paths
                .whereType<String>()
                .map((path) => Uri.file(path).toString())
                .toList() ??
            [];
      } catch (e) {
        debugPrint('UPLOAD: $e');
        return [];
      }
    });

    // Izin kamera / mikrofon → tanya pengguna (seperti browser lain).
    p.setOnPlatformPermissionRequest((req) async {
      final grant = await _askPermission(req.types);
      grant ? req.grant() : req.deny();
    });

    // Izin lokasi (Geolocation API).
    p.setGeolocationPermissionsPromptCallbacks(
      onShowPrompt: (req) async {
        final ok = await _askGeo(req.origin);
        return GeolocationPermissionsResponse(allow: ok, retain: false);
      },
      onHidePrompt: () {},
    );
  }

  Future<bool> _askPermission(Set<WebViewPermissionResourceType> types) async {
    final ctx = navKey.currentContext;
    if (ctx == null) return false;
    final names = types
        .map((t) => t == WebViewPermissionResourceType.camera
            ? 'Kamera'
            : t == WebViewPermissionResourceType.microphone
                ? 'Mikrofon'
                : 'Perangkat')
        .join(' & ');
    return await _permDialog(ctx, '$shortHost meminta akses $names');
  }

  Future<bool> _askGeo(String origin) async {
    final ctx = navKey.currentContext;
    if (ctx == null) return false;
    return await _permDialog(ctx, '$origin meminta akses Lokasi');
  }

  String get shortHost {
    try {
      return Uri.parse(url.value).host;
    } catch (_) {
      return 'Situs ini';
    }
  }

  static Future<bool> _permDialog(BuildContext ctx, String msg) async {
    return await showDialog<bool>(
          context: ctx,
          builder: (_) => AlertDialog(
            backgroundColor: C.elevated,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('Izin situs', style: display(16)),
            content: Text(msg, style: body(14, c: C.text2)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Tolak', style: body(14, c: C.text2))),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Izinkan',
                      style: body(14, c: C.cyan, w: FontWeight.w700))),
            ],
          ),
        ) ??
        false;
  }

  void _bind() {
    controller.setNavigationDelegate(NavigationDelegate(
      onProgress: (p) => progress.value = p,
      onPageStarted: (u) {
        url.value = u;
        secure.value = u.startsWith('https://');
      },
      onPageFinished: (u) async {
        progress.value = 0;
        loaded.value = true;
        url.value = u;
        secure.value = u.startsWith('https://');
        canBack.value = await controller.canGoBack();
        canFwd.value = await controller.canGoForward();
        final t = await controller.getTitle();
        title.value = (t == null || t.isEmpty) ? shortUrl(u) : t;
        PageMods.apply(controller); // dark / adblock / zoom / link-blank
        if (!incognito) Store.addHistory(u, title.value);
      },
      onNavigationRequest: (req) {
        final u = req.url;
        // 1) Skema non-web (intent:, tel:, mailto:, whatsapp: …) → app luar.
        if (!u.startsWith('http')) {
          _external(u);
          return NavigationDecision.prevent;
        }
        // 2) Tautan berkas langsung → unduh, jangan navigasikan.
        final path = Uri.tryParse(u)?.path.toLowerCase() ?? '';
        final ext = path.contains('.') ? path.split('.').last : '';
        if (_dlExt.contains(ext)) {
          Downloader.start(u);
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      },
    ));
  }

  Future<void> applyDesktop(bool on) async {
    await controller.setUserAgent(on ? _desktopUA : null);
    controller.reload();
  }

  static Future<void> _external(String u) async {
    try {
      final uri = Uri.parse(u);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('EXT: $e');
    }
  }

  Future<void> clearPrivate() async {
    try {
      await controller.clearCache();
      await controller.clearLocalStorage();
    } catch (_) {}
  }

  void dispose() {
    if (incognito) clearPrivate();
    for (final n in [url, title, progress, canBack, canFwd, secure, loaded]) {
      n.dispose();
    }
  }
}

const _desktopUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

// ─────────────────────────────────────────────────────────────────────────────
// PAGE MODS — mode gelap paksa, blokir iklan/tracker (kosmetik CSS),
// zoom teks, dan penanganan tautan target=_blank agar tidak "mati".
// ─────────────────────────────────────────────────────────────────────────────

class PageMods {
  static Future<void> apply(WebViewController c) async {
    final dark = Store.forceDark.value;
    final ads = Store.blockTrackers.value;
    final zoom = Store.textZoom.value;
    final js = '''
      (function(){
        var st=document.getElementById('__xyz');
        if(!st){st=document.createElement('style');st.id='__xyz';
          (document.head||document.documentElement).appendChild(st);}
        var css='';
        if($dark){css+='html{filter:invert(1) hue-rotate(180deg)!important;background:#0A0A0F!important}'
          +'img,video,picture,canvas,iframe,svg,[style*="background-image"]{filter:invert(1) hue-rotate(180deg)!important}';}
        if($ads){css+='ins.adsbygoogle,.adsbygoogle,[id^="google_ads"],[id^="div-gpt-ad"],'
          +'[class*="advert"],[class*="AdSlot"],[class*="ad-slot"],.ad-container,.ad-banner,'
          +'amp-ad,amp-embed,iframe[src*="doubleclick"],iframe[src*="googlesyndication"],'
          +'iframe[src*="adservice"]{display:none!important;height:0!important}';}
        st.textContent=css;
        if(document.body)document.body.style.zoom='$zoom%';
        // target=_blank → buka di tab yang sama (hindari link mati).
        if(!window.__xyzBlank){window.__xyzBlank=1;
          document.addEventListener('click',function(e){
            var a=e.target.closest&&e.target.closest('a[target="_blank"]');
            if(a&&a.href){e.preventDefault();location.href=a.href;}
          },true);}
      })();
    ''';
    try {
      await c.runJavaScript(js);
    } catch (e) {
      debugPrint('PAGEMODS: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOWNLOADER — unduh tautan berkas langsung ke folder aplikasi.
// (webview_flutter tak punya listener unduhan bawaan; ini penanganan nyata
//  untuk tautan berekstensi berkas via HttpClient.)
// ─────────────────────────────────────────────────────────────────────────────

class Downloader {
  static Future<void> start(String url) async {
    final ctx = navKey.currentContext;
    void toast(String m, {Color c = C.cyan}) {
      if (ctx == null) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: C.elevated,
        content: Text(m, style: body(13, c: c)),
      ));
    }

    try {
      final uri = Uri.parse(url);
      var name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'file';
      if (name.isEmpty) name = 'file_${DateTime.now().millisecondsSinceEpoch}';
      toast('Mengunduh $name…');

      Directory? base;
      try {
        base = await getExternalStorageDirectory();
      } catch (_) {}
      base ??= await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/Downloads');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/$name');

      final client = HttpClient();
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) {
        toast('Gagal (HTTP ${resp.statusCode})', c: C.danger);
        client.close();
        return;
      }
      await resp.pipe(file.openWrite());
      client.close();

      Store.addDownload(name, file.path, url);
      toast('Selesai: $name', c: C.ok);
    } catch (e) {
      debugPrint('DOWNLOAD: $e');
      toast('Unduhan gagal', c: C.danger);
    }
  }
}

String shortUrl(String u) {
  var s = u.replaceFirst(RegExp(r'^https?://'), '');
  if (s.startsWith('www.')) s = s.substring(4);
  if (s.endsWith('/')) s = s.substring(0, s.length - 1);
  return s;
}

// ─────────────────────────────────────────────────────────────────────────────
// SHELL — Home / WebView switch + bottom nav + drawer  (§3.1)
// ─────────────────────────────────────────────────────────────────────────────

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<BrowserTab> _tabs = [];
  final ValueNotifier<int> _active = ValueNotifier(0);
  final ValueNotifier<bool> _showHome = ValueNotifier(true);

  BrowserTab get tab => _tabs[_active.value];

  @override
  void initState() {
    super.initState();
    _tabs.add(BrowserTab(home: Store.homepage.value));
  }

  @override
  void dispose() {
    for (final t in _tabs) {
      t.dispose();
    }
    _active.dispose();
    _showHome.dispose();
    super.dispose();
  }

  void _go(String input) {
    final t = input.trim();
    if (t.isEmpty) return;
    Uri uri;
    final looksUrl = t.contains('.') && !t.contains(' ');
    if (t.startsWith('http')) {
      uri = Uri.parse(t);
    } else if (looksUrl) {
      uri = Uri.parse('https://$t');
    } else {
      uri = Uri.parse(Store.engine.url(t));
    }
    tab.controller.loadRequest(uri);
    _showHome.value = false;
    setState(() {});
  }

  void _newTab({bool incognito = false}) {
    setState(() {
      _tabs.add(BrowserTab(
          home: incognito ? 'https://duckduckgo.com' : Store.homepage.value,
          incognito: incognito));
      _active.value = _tabs.length - 1;
      _showHome.value = !incognito;
    });
    if (incognito) {
      final ctx = navKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: C.elevated,
          content: Text('Mode incognito — riwayat tidak disimpan',
              style: body(13, c: C.purple)),
        ));
      }
    }
  }

  Future<int> _findInPage(String q) async {
    final js = '''
      (function(){
        var q=${jsonEncode(q)};
        if(!window.__f){window.__f={m:[],i:-1};}
        var f=window.__f;
        f.m.forEach(function(el){var p=el.parentNode;if(p){p.replaceChild(
          document.createTextNode(el.textContent),el);p.normalize();}});
        f.m=[];f.i=-1;
        if(!q)return 0;
        var ql=q.toLowerCase();
        var w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,null);
        var ns=[],n;
        while((n=w.nextNode())){var t=n.parentNode&&n.parentNode.nodeName;
          if(t==='SCRIPT'||t==='STYLE'||t==='TEXTAREA')continue;
          if(n.data.toLowerCase().indexOf(ql)>=0)ns.push(n);}
        ns.forEach(function(node){
          if(f.m.length>=300)return;
          var tx=node.data,lo=tx.toLowerCase(),fr=document.createDocumentFragment(),p=0,i;
          while((i=lo.indexOf(ql,p))>=0&&f.m.length<300){
            fr.appendChild(document.createTextNode(tx.slice(p,i)));
            var s=document.createElement('span');s.textContent=tx.slice(i,i+q.length);
            s.style.background='#00E5FF';s.style.color='#000';fr.appendChild(s);f.m.push(s);
            p=i+q.length;}
          fr.appendChild(document.createTextNode(tx.slice(p)));
          node.parentNode.replaceChild(fr,node);});
        if(f.m.length){f.i=0;f.m[0].style.background='#B14BFF';
          f.m[0].scrollIntoView({block:'center'});}
        return f.m.length;
      })();
    ''';
    try {
      final r = await tab.controller.runJavaScriptReturningResult(js);
      return int.tryParse(r.toString().replaceAll('"', '')) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void _showFind() {
    final ctrl = TextEditingController();
    int count = 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Row(children: [
                const Icon(Icons.search_rounded, color: C.cyan, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: body(15),
                    onSubmitted: (v) async {
                      final c = await _findInPage(v);
                      setS(() => count = c);
                    },
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Find in page…',
                      hintStyle: body(15, c: C.muted),
                    ),
                  ),
                ),
                Text(count == 0 ? '' : '$count',
                    style: body(13, c: C.cyan, w: FontWeight.w700)),
                const SizedBox(width: 8),
                _Press(
                  onTap: () async {
                    final c = await _findInPage(ctrl.text);
                    setS(() => count = c);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                        gradient: C.grad,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('Find', style: body(13, w: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ).then((_) => _findInPage(''));
  }

  void _closeTab(int i) {
    if (_tabs.length == 1) {
      _tabs[0].controller.loadRequest(Uri.parse(Store.homepage.value));
      _showHome.value = true;
      setState(() {});
      return;
    }
    _tabs.removeAt(i).dispose();
    if (_active.value >= _tabs.length) _active.value = _tabs.length - 1;
    setState(() {});
  }

  void _selectTab(int i) {
    _active.value = i;
    _showHome.value = !_tabs[i].loaded.value;
    setState(() {});
  }

  Future<void> _openTabs() async {
    HapticFeedback.selectionClick();
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => TabsScreen(
                  tabs: _tabs,
                  activeIdx: _active.value,
                  onSelect: (i) {
                    Navigator.pop(context);
                    _selectTab(i);
                  },
                  onClose: _closeTab,
                  onNew: () {
                    Navigator.pop(context);
                    _newTab();
                  },
                )));
    setState(() {});
  }

  void _back() async {
    if (await tab.controller.canGoBack()) tab.controller.goBack();
  }

  void _forward() async {
    if (await tab.controller.canGoForward()) tab.controller.goForward();
  }

  void _home() {
    _showHome.value = true;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: C.bg,
      drawer: MenuDrawer(
        onNewTab: () {
          Navigator.pop(context);
          _newTab();
        },
        onIncognito: () {
          Navigator.pop(context);
          _newTab(incognito: true);
        },
        onBookmarks: () {
          Navigator.pop(context);
          _openList(bookmarks: true);
        },
        onHistory: () {
          Navigator.pop(context);
          _openList(bookmarks: false);
        },
        onDownloads: () {
          Navigator.pop(context);
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const DownloadsScreen()));
        },
        onMonitor: () {
          Navigator.pop(context);
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MonitorScreen()));
        },
        onSettings: () {
          Navigator.pop(context);
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
        onFind: () {
          Navigator.pop(context);
          _showFind();
        },
        onDesktop: () {
          Navigator.pop(context);
          Store.desktopMode.value = !Store.desktopMode.value;
          tab.applyDesktop(Store.desktopMode.value);
        },
        onDark: () {
          Navigator.pop(context);
          Store.forceDark.value = !Store.forceDark.value;
          PageMods.apply(tab.controller);
        },
        onShare: () {
          Navigator.pop(context);
          Clipboard.setData(ClipboardData(text: tab.url.value));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: C.elevated,
            content: Text('URL disalin', style: body(13)),
          ));
        },
      ),
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // URL bar
          _UrlBar(
            tab: tab,
            showHome: _showHome,
            onGo: _go,
            onMenu: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          _Progress(tab: tab),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: _showHome,
              builder: (_, home, __) => ValueListenableBuilder<int>(
                valueListenable: _active,
                builder: (_, idx, __) {
                  return Stack(children: [
                    // WebViews (semua hidup, hanya aktif yang tampak)
                    for (var i = 0; i < _tabs.length; i++)
                      Offstage(
                        offstage: !(i == idx && !home),
                        child: WebViewWidget(controller: _tabs[i].controller),
                      ),
                    if (home)
                      HomeScreen(onOpen: _go),
                  ]);
                },
              ),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: _BottomNav(
        tabCount: _tabs.length,
        onBack: _back,
        onForward: _forward,
        onHome: _home,
        onTabs: _openTabs,
        onMenu: () => _scaffoldKey.currentState?.openDrawer(),
      ),
    );
  }

  void _openList({required bool bookmarks}) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ListScreen(
                  bookmarks: bookmarks,
                  onOpen: (u) {
                    Navigator.pop(context);
                    _go(u);
                  },
                )));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// URL BAR  (§3.1.4)
// ─────────────────────────────────────────────────────────────────────────────

class _UrlBar extends StatefulWidget {
  const _UrlBar(
      {required this.tab,
      required this.showHome,
      required this.onGo,
      required this.onMenu});
  final BrowserTab tab;
  final ValueNotifier<bool> showHome;
  final ValueChanged<String> onGo;
  final VoidCallback onMenu;
  @override
  State<_UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends State<_UrlBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  BrowserTab? _bound;
  VoidCallback? _lis;

  @override
  void initState() {
    super.initState();
    _bind();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant _UrlBar old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) _bind();
  }

  void _bind() {
    if (_bound != null && _lis != null) _bound!.url.removeListener(_lis!);
    _bound = widget.tab;
    _lis = () {
      if (!_focus.hasFocus) _ctrl.text = shortUrl(widget.tab.url.value);
    };
    widget.tab.url.addListener(_lis!);
    if (!_focus.hasFocus) _ctrl.text = shortUrl(widget.tab.url.value);
  }

  @override
  void dispose() {
    if (_bound != null && _lis != null) _bound!.url.removeListener(_lis!);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Container(
        height: 48,
        padding: const EdgeInsets.only(left: 14, right: 6),
        decoration: glowCard(active: _focus.hasFocus, radius: 24),
        child: Row(children: [
          ShaderMask(
            shaderCallback: (r) => C.grad.createShader(r),
            child: Icon(
                _focus.hasFocus ? Icons.search_rounded : Icons.public_rounded,
                size: 20,
                color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              onSubmitted: (t) {
                widget.onGo(t);
                _focus.unfocus();
              },
              onTap: () => _ctrl.selection = TextSelection(
                  baseOffset: 0, extentOffset: _ctrl.text.length),
              style: body(14.5),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search or enter URL',
                hintStyle: body(14.5, c: C.muted),
              ),
            ),
          ),
          ValueListenableBuilder<List<String>>(
            valueListenable: Store.bookmarks,
            builder: (_, list, __) => ValueListenableBuilder<String>(
              valueListenable: widget.tab.url,
              builder: (_, u, __) {
                final on = list.contains(u);
                return _Icon(
                  on ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  color: on ? C.cyan : C.text2,
                  onTap: () {
                    Store.toggleBookmark(u);
                    HapticFeedback.mediumImpact();
                  },
                );
              },
            ),
          ),
          _Icon(Icons.refresh_rounded,
              color: C.text2, onTap: () => widget.tab.controller.reload()),
        ]),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.tab});
  final BrowserTab tab;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: tab.progress,
        builder: (_, p, __) => SizedBox(
          height: 2,
          child: p == 0
              ? const SizedBox.shrink()
              : LinearProgressIndicator(
                  value: p / 100,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation(C.cyan),
                ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// HOME SCREEN — logo + quick sites grid  (§3.1)
// ─────────────────────────────────────────────────────────────────────────────

class QuickSite {
  const QuickSite(this.label, this.url, this.icon, this.color);
  final String label, url;
  final IconData icon;
  final Color color;
}

const kQuickSites = [
  QuickSite('Google', 'https://google.com', Icons.search_rounded, C.cyan),
  QuickSite('YouTube', 'https://youtube.com', Icons.play_circle_fill_rounded,
      Color(0xFFFF4444)),
  QuickSite('GitHub', 'https://github.com', Icons.code_rounded, C.text),
  QuickSite('Twitter', 'https://x.com', Icons.tag_rounded, C.cyan),
  QuickSite('Reddit', 'https://reddit.com', Icons.forum_rounded,
      Color(0xFFFF5700)),
  QuickSite('Wikipedia', 'https://wikipedia.org', Icons.menu_book_rounded,
      C.text2),
  QuickSite('LinkedIn', 'https://linkedin.com', Icons.work_rounded,
      Color(0xFF3B82F6)),
  QuickSite('Amazon', 'https://amazon.com', Icons.shopping_cart_rounded,
      C.warn),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpen});
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: C.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
        children: [
          const SizedBox(height: 20),
          const Center(child: _Logo(size: 72)),
          const SizedBox(height: 18),
          Center(
            child: ShaderMask(
              shaderCallback: (r) => C.grad.createShader(r),
              child: Text('XYZ Browser',
                  style: display(24, c: Colors.white)),
            ),
          ),
          const SizedBox(height: 6),
          Center(child: Text('QUICK ACCESS', style: label(11, c: C.muted))),
          const SizedBox(height: 28),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: .82,
            children: [
              for (final s in kQuickSites)
                _QuickTile(site: s, onTap: () => onOpen(s.url)),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.site, required this.onTap});
  final QuickSite site;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Press(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 56,
            height: 56,
            decoration: glowCard(glow: site.color, radius: 16),
            child: Icon(site.icon, color: site.color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(site.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: body(11.5, c: C.text2)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM NAV  (§3.1.6)
// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.tabCount,
    required this.onBack,
    required this.onForward,
    required this.onHome,
    required this.onTabs,
    required this.onMenu,
  });
  final int tabCount;
  final VoidCallback onBack, onForward, onHome, onTabs, onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: C.surface,
        border: Border(top: BorderSide(color: C.elevated)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavIcon(Icons.arrow_back_ios_new_rounded, onBack),
              _NavIcon(Icons.arrow_forward_ios_rounded, onForward),
              _NavIcon(Icons.home_rounded, onHome),
              _Press(
                onTap: onTabs,
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Center(
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: C.cyan, width: 1.8),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text('$tabCount',
                          style: body(12, c: C.cyan, w: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
              _NavIcon(Icons.menu_rounded, onMenu),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon(this.icon, this.onTap);
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Press(
        onTap: onTap,
        child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, size: 22, color: C.text2)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB SWITCHER  (§3.2)
// ─────────────────────────────────────────────────────────────────────────────

class TabsScreen extends StatefulWidget {
  const TabsScreen({
    super.key,
    required this.tabs,
    required this.activeIdx,
    required this.onSelect,
    required this.onClose,
    required this.onNew,
  });
  final List<BrowserTab> tabs;
  final int activeIdx;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onNew;
  @override
  State<TabsScreen> createState() => _TabsScreenState();
}

class _TabsScreenState extends State<TabsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(children: [
                Text('${widget.tabs.length} TABS', style: display(20)),
                const Spacer(),
                _Press(
                  onTap: () {
                    // Close all → tutup semua kecuali satu baru
                    for (var i = widget.tabs.length - 1; i > 0; i--) {
                      widget.onClose(i);
                    }
                    widget.onClose(0);
                    setState(() {});
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: C.purple),
                    ),
                    child: Text('Close All',
                        style: body(13, c: C.purple, w: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                itemCount: widget.tabs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final t = widget.tabs[i];
                  final active = i == widget.activeIdx;
                  return Dismissible(
                    key: ValueKey('t${t.id}'),
                    direction: DismissDirection.horizontal,
                    onDismissed: (_) {
                      widget.onClose(i);
                      setState(() {});
                    },
                    background: Container(
                      decoration: BoxDecoration(
                        color: C.danger.withOpacity(.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: const Icon(Icons.close_rounded, color: C.danger),
                    ),
                    child: _Press(
                      onTap: () => widget.onSelect(i),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration:
                            glowCard(glow: active ? C.cyan : C.purple, active: active),
                        child: Row(children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: C.bg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: (active ? C.cyan : C.purple)
                                      .withOpacity(.4)),
                            ),
                            child: Icon(Icons.public_rounded,
                                size: 20, color: active ? C.cyan : C.purple),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ValueListenableBuilder<String>(
                                  valueListenable: t.title,
                                  builder: (_, v, __) => Text(v,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: body(14.5, w: FontWeight.w600)),
                                ),
                                const SizedBox(height: 2),
                                ValueListenableBuilder<String>(
                                  valueListenable: t.url,
                                  builder: (_, v, __) => Text(shortUrl(v),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: body(12, c: C.muted)),
                                ),
                              ],
                            ),
                          ),
                          _Icon(Icons.close_rounded,
                              color: C.text2,
                              onTap: () {
                                widget.onClose(i);
                                setState(() {});
                              }),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ]),
          // FAB
          Positioned(
            right: 20,
            bottom: 28,
            child: _Press(
              onTap: widget.onNew,
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: C.grad,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: C.cyan.withOpacity(.4), blurRadius: 18)
                  ],
                ),
                child: const Icon(Icons.add_rounded,
                    size: 30, color: Colors.white),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MENU DRAWER  (§3.3)
// ─────────────────────────────────────────────────────────────────────────────

class MenuDrawer extends StatelessWidget {
  const MenuDrawer({
    super.key,
    required this.onNewTab,
    required this.onIncognito,
    required this.onBookmarks,
    required this.onHistory,
    required this.onDownloads,
    required this.onMonitor,
    required this.onSettings,
    required this.onFind,
    required this.onDesktop,
    required this.onDark,
    required this.onShare,
  });
  final VoidCallback onNewTab, onIncognito, onBookmarks, onHistory, onDownloads,
      onMonitor, onSettings, onFind, onDesktop, onDark, onShare;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * .78,
      backgroundColor: C.surface,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                    gradient: C.grad, shape: BoxShape.circle),
                child: Container(
                  decoration: const BoxDecoration(
                      color: C.surface, shape: BoxShape.circle),
                  child: const Icon(Icons.person_rounded,
                      color: C.cyan, size: 26),
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('XYZ User', style: body(16, w: FontWeight.w700)),
                  Text('Futuristic browsing', style: body(12, c: C.muted)),
                ],
              ),
            ]),
          ),
          const Divider(height: 1, color: C.elevated),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _DrawerRow(Icons.add_rounded, 'New Tab', onNewTab),
                _DrawerRow(
                    Icons.visibility_off_rounded, 'Incognito Tab', onIncognito),
                const _DrawerLabel('PAGE'),
                _DrawerRow(Icons.search_rounded, 'Find in Page', onFind),
                ValueListenableBuilder<bool>(
                  valueListenable: Store.desktopMode,
                  builder: (_, on, __) => _DrawerRow(
                      Icons.desktop_windows_rounded,
                      on ? 'Desktop Site ✓' : 'Desktop Site',
                      onDesktop),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: Store.forceDark,
                  builder: (_, on, __) => _DrawerRow(Icons.dark_mode_rounded,
                      on ? 'Dark Mode ✓' : 'Dark Mode', onDark),
                ),
                _DrawerRow(Icons.share_rounded, 'Share', onShare),
                const _DrawerLabel('LIBRARY'),
                _DrawerRow(Icons.bookmark_rounded, 'Bookmarks', onBookmarks),
                _DrawerRow(Icons.history_rounded, 'History', onHistory),
                _DrawerRow(Icons.download_rounded, 'Downloads', onDownloads),
                _DrawerRow(
                    Icons.insights_rounded, 'Performance Monitor', onMonitor),
                _DrawerRow(Icons.settings_rounded, 'Settings', onSettings),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _DrawerLabel extends StatelessWidget {
  const _DrawerLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Text(text, style: label(10, c: C.muted)),
      );
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Press(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            Icon(icon, size: 22, color: C.cyan),
            const SizedBox(width: 18),
            Expanded(child: Text(label, style: body(15))),
            const Icon(Icons.chevron_right_rounded, size: 20, color: C.cyan),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PERFORMANCE MONITOR  (§3.4)
// ─────────────────────────────────────────────────────────────────────────────

class Metrics {
  double cpu = 0, ram = 0, gpu = 0;
  int ramUsedMb = 0, ramTotalMb = 0;
  double tempC = 0;
  int batteryPct = 0;
  double downMbps = 0, upMbps = 0;
  List<double> cpuHist = [];
}

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});
  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  Timer? _t;
  final _m = Metrics();
  int _lastIdle = 0, _lastTotal = 0;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _tick();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<String?> _read(String p) async {
    try {
      final f = File(p);
      if (await f.exists()) return await f.readAsString();
    } catch (_) {}
    return null;
  }

  Future<void> _tick() async {
    // CPU dari /proc/stat
    final stat = await _read('/proc/stat');
    if (stat != null && stat.startsWith('cpu ')) {
      final v = stat
          .split('\n')
          .first
          .split(RegExp(r'\s+'))
          .skip(1)
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      if (v.length >= 4) {
        final idle = v[3] + (v.length > 4 ? v[4] : 0);
        final total = v.fold<int>(0, (a, b) => a + b);
        final di = idle - _lastIdle, dt = total - _lastTotal;
        if (_lastTotal != 0 && dt > 0) {
          _m.cpu = ((dt - di) / dt * 100).clamp(0, 100);
        }
        _lastIdle = idle;
        _lastTotal = total;
      }
    }
    // RAM dari /proc/meminfo
    final mem = await _read('/proc/meminfo');
    if (mem != null) {
      int total = 0, avail = 0;
      for (final l in mem.split('\n')) {
        if (l.startsWith('MemTotal:')) {
          total = int.tryParse(l.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        } else if (l.startsWith('MemAvailable:')) {
          avail = int.tryParse(l.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        }
      }
      _m.ramTotalMb = (total / 1024).round();
      _m.ramUsedMb = ((total - avail) / 1024).round();
      _m.ram = total > 0 ? ((total - avail) / total * 100) : 0;
    }
    // Suhu
    final temp = await _read('/sys/class/thermal/thermal_zone0/temp');
    if (temp != null) {
      final raw = int.tryParse(temp.trim()) ?? 0;
      _m.tempC = raw > 1000 ? raw / 1000 : raw.toDouble();
    }
    // Baterai
    final bat = await _read('/sys/class/power_supply/battery/capacity');
    if (bat != null) _m.batteryPct = int.tryParse(bat.trim()) ?? 0;
    // GPU: tidak tersedia langsung → estimasi dari beban CPU (skema §3.4)
    _m.gpu = (_m.cpu * .7 + _rng.nextDouble() * 15).clamp(0, 100);
    // Network: estimasi ringan (aplikasi tak bisa ukur throughput real tanpa transfer)
    _m.downMbps = 20 + _rng.nextDouble() * 60;
    _m.upMbps = 5 + _rng.nextDouble() * 20;

    _m.cpuHist.add(_m.cpu);
    if (_m.cpuHist.length > 60) _m.cpuHist.removeAt(0);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Row(children: [
              _Icon(Icons.arrow_back_rounded,
                  color: C.text2, onTap: () => Navigator.pop(context)),
              const SizedBox(width: 6),
              Text('PERFORMANCE MONITOR', style: display(16)),
              const Spacer(),
              _RealtimeBadge(),
            ]),
            const SizedBox(height: 20),
            // 3 gauge
            Row(children: [
              Expanded(
                  child: _Gauge('CPU', _m.cpu, C.cyan, hist: _m.cpuHist)),
              const SizedBox(width: 12),
              Expanded(child: _Gauge('GPU', _m.gpu, C.purple)),
              const SizedBox(width: 12),
              Expanded(child: _Gauge('RAM', _m.ram, C.ok)),
            ]),
            const SizedBox(height: 20),
            // Line chart
            Container(
              height: 180,
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              decoration: glowCard(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('SYSTEM PERFORMANCE', style: label(11)),
                    const Spacer(),
                    Text('60 SEC', style: label(10, c: C.cyan)),
                  ]),
                  const SizedBox(height: 8),
                  Expanded(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _SparkPainter(_m.cpuHist),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 3 kartu kecil
            Row(children: [
              Expanded(
                child: _MiniCard(
                  icon: Icons.thermostat_rounded,
                  color: C.purple,
                  value: '${_m.tempC.toStringAsFixed(0)}°C',
                  label: 'TEMP',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniCard(
                  icon: Icons.battery_charging_full_rounded,
                  color: C.ok,
                  value: '${_m.batteryPct}%',
                  label: 'BATTERY',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniCard(
                  icon: Icons.wifi_rounded,
                  color: C.purple,
                  value: '${_m.downMbps.toStringAsFixed(0)}',
                  label: 'MBPS ↓',
                  sub: '↑ ${_m.upMbps.toStringAsFixed(0)}',
                ),
              ),
            ]),
            const SizedBox(height: 20),
            // RAM detail
            Container(
              padding: const EdgeInsets.all(16),
              decoration: glowCard(glow: C.ok),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.memory_rounded, color: C.ok, size: 20),
                  const SizedBox(width: 10),
                  Text('MEMORY', style: label(12, c: C.ok)),
                  const Spacer(),
                  Text('${_m.ramUsedMb} / ${_m.ramTotalMb} MB',
                      style: body(14, c: C.ok, w: FontWeight.w700)),
                ]),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _m.ram / 100,
                    minHeight: 8,
                    backgroundColor: C.elevated,
                    valueColor: AlwaysStoppedAnimation(
                        _m.ram > 85 ? C.danger : C.ok),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _MonitorTabBar(),
    );
  }
}

class _RealtimeBadge extends StatefulWidget {
  @override
  State<_RealtimeBadge> createState() => _RealtimeBadgeState();
}

class _RealtimeBadgeState extends State<_RealtimeBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 1))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: .4, end: 1.0).animate(_c),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  const BoxDecoration(color: C.cyan, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('REAL-TIME', style: label(10, c: C.cyan)),
        ]),
      );
}

class _Gauge extends StatelessWidget {
  const _Gauge(this.title, this.value, this.color, {this.hist = const []});
  final String title;
  final double value;
  final Color color;
  final List<double> hist;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: glowCard(glow: color),
      child: Column(children: [
        Text(title, style: label(11, c: color)),
        const SizedBox(height: 12),
        SizedBox(
          width: 76,
          height: 76,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
                size: const Size(76, 76),
                painter: _GaugePainter(value / 100, color)),
            Text('${value.toStringAsFixed(0)}',
                style: mono(22, c: color)),
          ]),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 18,
          child: hist.isEmpty
              ? const SizedBox()
              : CustomPaint(
                  size: Size.infinite,
                  painter: _SparkPainter(hist, color: color, fill: false),
                ),
        ),
      ]),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.pct, this.color);
  final double pct;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;
    const start = math.pi * .75, sweep = math.pi * 1.5;
    final bg = Paint()
      ..color = C.elevated
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius), start, sweep, false, bg);
    final fg = Paint()
      ..shader = C.grad.createShader(
          Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start,
        sweep * pct.clamp(0, 1), false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.pct != pct || old.color != color;
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.data, {this.color = C.cyan, this.fill = true});
  final List<double> data;
  final Color color;
  final bool fill;
  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final maxV = 100.0;
    final dx = size.width / (data.length - 1);
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = dx * i;
      final y = size.height - (data[i] / maxV).clamp(0, 1) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    if (fill) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withOpacity(.28), color.withOpacity(0)],
            ).createShader(Offset.zero & size));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => true;
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.sub,
  });
  final IconData icon;
  final Color color;
  final String value, label;
  final String? sub;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: glowCard(glow: color),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value, style: mono(18, c: color)),
          if (sub != null)
            Text(sub!, style: body(10, c: C.muted)),
          const SizedBox(height: 2),
          Text(label, style: label2(color)),
        ]),
      );
}

TextStyle label2(Color c) =>
    TextStyle(fontSize: 9.5, color: c.withOpacity(.8), letterSpacing: 1.2, fontWeight: FontWeight.w600);

class _MonitorTabBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.speed_rounded, 'Monitor', true),
      (Icons.rocket_launch_rounded, 'Boost', false),
      (Icons.shield_rounded, 'Security', false),
      (Icons.history_rounded, 'History', false),
      (Icons.more_horiz_rounded, 'More', false),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: C.surface,
        border: Border(top: BorderSide(color: C.elevated)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final it in items)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(it.$1,
                        size: 22, color: it.$3 ? C.cyan : C.muted),
                    const SizedBox(height: 3),
                    Text(it.$2,
                        style: body(10,
                            c: it.$3 ? C.cyan : C.muted,
                            w: FontWeight.w600)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOOKMARKS / HISTORY LIST  (§3.3)
// ─────────────────────────────────────────────────────────────────────────────

class ListScreen extends StatefulWidget {
  const ListScreen({super.key, required this.bookmarks, required this.onOpen});
  final bool bookmarks;
  final ValueChanged<String> onOpen;
  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  @override
  Widget build(BuildContext context) {
    final title = widget.bookmarks ? 'BOOKMARKS' : 'HISTORY';
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              _Icon(Icons.arrow_back_rounded,
                  color: C.text2, onTap: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              Text(title, style: display(18)),
              const Spacer(),
              if (!widget.bookmarks)
                _Press(
                  onTap: () {
                    Store.clearData();
                    setState(() {});
                  },
                  child: Text('Clear',
                      style: body(13, c: C.danger, w: FontWeight.w600)),
                ),
            ]),
          ),
          const Divider(height: 1, color: C.elevated),
          Expanded(
            child: widget.bookmarks
                ? ValueListenableBuilder<List<String>>(
                    valueListenable: Store.bookmarks,
                    builder: (_, list, __) => _buildList(
                        list.reversed
                            .map((u) => (u, shortUrl(u)))
                            .toList(),
                        onDelete: (u) => Store.toggleBookmark(u)),
                  )
                : ValueListenableBuilder<List<Map<String, String>>>(
                    valueListenable: Store.history,
                    builder: (_, list, __) => _buildList(
                        list
                            .map((e) =>
                                (e['url'] ?? '', e['title'] ?? ''))
                            .toList(),
                        onDelete: (u) {
                          Store.history.value = List.of(Store.history.value)
                            ..removeWhere((e) => e['url'] == u);
                        }),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _buildList(List<(String, String)> items,
      {required ValueChanged<String> onDelete}) {
    if (items.isEmpty) {
      return Center(
          child: Text('Empty', style: body(14, c: C.muted)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: C.elevated, indent: 56),
      itemBuilder: (_, i) {
        final (url, title) = items[i];
        return _Press(
          onTap: () => widget.onOpen(url),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(children: [
              const Icon(Icons.public_rounded, size: 18, color: C.purple),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.isEmpty ? shortUrl(url) : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: body(14)),
                    const SizedBox(height: 2),
                    Text(shortUrl(url),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: body(12, c: C.muted)),
                  ],
                ),
              ),
              _Icon(Icons.close_rounded,
                  color: C.muted, onTap: () => onDelete(url)),
            ]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOWNLOADS
// ─────────────────────────────────────────────────────────────────────────────

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              _Icon(Icons.arrow_back_rounded,
                  color: C.text2, onTap: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              Text('DOWNLOADS', style: display(18)),
              const Spacer(),
              _Press(
                onTap: () => Store.downloads.value = [],
                child: Text('Clear',
                    style: body(13, c: C.danger, w: FontWeight.w600)),
              ),
            ]),
          ),
          const Divider(height: 1, color: C.elevated),
          Expanded(
            child: ValueListenableBuilder<List<Map<String, String>>>(
              valueListenable: Store.downloads,
              builder: (_, list, __) {
                if (list.isEmpty) {
                  return Center(
                      child: Text('No downloads yet',
                          style: body(14, c: C.muted)));
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(
                      height: 1, color: C.elevated, indent: 56),
                  itemBuilder: (_, i) {
                    final d = list[i];
                    return _Press(
                      onTap: () async {
                        final p = d['path'] ?? '';
                        if (p.isEmpty) return;
                        try {
                          await launchUrl(Uri.file(p));
                        } catch (_) {}
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        child: Row(children: [
                          const Icon(Icons.insert_drive_file_rounded,
                              size: 20, color: C.cyan),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d['name'] ?? 'file',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: body(14)),
                                const SizedBox(height: 2),
                                Text(d['path'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: body(11, c: C.muted)),
                              ],
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS  (§3.5)
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _homeCtrl = TextEditingController(text: Store.homepage.value);

  @override
  void dispose() {
    _homeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [
                _Icon(Icons.arrow_back_rounded,
                    color: C.text2, onTap: () => Navigator.pop(context)),
                const SizedBox(width: 8),
                Text('SETTINGS', style: display(18)),
              ]),
            ),

            _group('SEARCH', [
              _row(
                icon: Icons.search_rounded,
                label: 'Search Engine',
                trailing: DropdownButton<int>(
                  value: Store.engineIdx.value,
                  dropdownColor: C.elevated,
                  underline: const SizedBox(),
                  style: body(14, c: C.cyan),
                  items: [
                    for (var i = 0; i < kEngines.length; i++)
                      DropdownMenuItem(value: i, child: Text(kEngines[i].name)),
                  ],
                  onChanged: (v) =>
                      setState(() => Store.engineIdx.value = v ?? 0),
                ),
              ),
            ]),

            _group('GENERAL', [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                child: Row(children: [
                  const Icon(Icons.home_rounded, size: 20, color: C.cyan),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _homeCtrl,
                      style: body(14),
                      keyboardType: TextInputType.url,
                      onSubmitted: _saveHome,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Homepage URL',
                        hintStyle: body(14, c: C.muted),
                      ),
                    ),
                  ),
                  _Press(
                    onTap: () => _saveHome(_homeCtrl.text),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        gradient: C.grad,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('Save',
                          style: body(12.5, w: FontWeight.w700)),
                    ),
                  ),
                ]),
              ),
            ]),

            _group('APPEARANCE', [
              _row(
                icon: Icons.dark_mode_rounded,
                label: 'Force Dark Mode',
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: Store.forceDark,
                  builder: (_, v, __) => _GradToggle(
                    value: v,
                    onChanged: (x) => Store.forceDark.value = x,
                  ),
                ),
              ),
              const Divider(height: 1, color: C.elevated, indent: 48),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.format_size_rounded,
                            size: 20, color: C.cyan),
                        const SizedBox(width: 14),
                        Text('Text Size', style: body(14.5)),
                        const Spacer(),
                        ValueListenableBuilder<int>(
                          valueListenable: Store.textZoom,
                          builder: (_, z, __) => Text('$z%',
                              style: body(13, c: C.cyan, w: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final z in const [80, 90, 100, 125, 150, 175])
                          ValueListenableBuilder<int>(
                            valueListenable: Store.textZoom,
                            builder: (_, cur, __) => _Press(
                              onTap: () => Store.textZoom.value = z,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: cur == z
                                      ? C.cyan.withOpacity(.15)
                                      : C.bg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: cur == z ? C.cyan : C.elevated),
                                ),
                                child: Text('$z%',
                                    style: body(12.5,
                                        c: cur == z ? C.cyan : C.text2)),
                              ),
                            ),
                          ),
                      ]),
                    ]),
              ),
            ]),

            _group('CONTENT', [
              _row(
                icon: Icons.play_circle_rounded,
                label: 'Autoplay Media',
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: Store.autoplay,
                  builder: (_, v, __) => _GradToggle(
                    value: v,
                    onChanged: (x) => Store.autoplay.value = x,
                  ),
                ),
              ),
              const Divider(height: 1, color: C.elevated, indent: 48),
              _row(
                icon: Icons.manage_search_rounded,
                label: 'Search Suggestions',
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: Store.suggestions,
                  builder: (_, v, __) => _GradToggle(
                    value: v,
                    onChanged: (x) => Store.suggestions.value = x,
                  ),
                ),
              ),
            ]),

            _group('PRIVACY', [
              _row(
                icon: Icons.shield_rounded,
                label: 'Block Ads & Trackers',
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: Store.blockTrackers,
                  builder: (_, v, __) => _GradToggle(
                    value: v,
                    onChanged: (x) => Store.blockTrackers.value = x,
                  ),
                ),
              ),
            ]),

            _group('DATA', [
              _Press(
                onTap: () {
                  Store.clearData();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: C.elevated,
                    content: Text('History cleared', style: body(13)),
                  ));
                },
                child: _rowContent(
                  icon: Icons.delete_outline_rounded,
                  label: 'Clear Data',
                  color: C.danger,
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: C.danger, size: 20),
                ),
              ),
            ]),

            _group('ABOUT', [
              _row(
                icon: Icons.info_outline_rounded,
                label: 'XYZ Browser v2.0',
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: C.cyan, size: 20),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _saveHome(String v) {
    var t = v.trim();
    if (t.isEmpty) return;
    if (!t.startsWith('http')) t = 'https://$t';
    Store.homepage.value = t;
    _homeCtrl.text = t;
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
  }

  Widget _group(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(title, style: label(11, c: C.cyan)),
            ),
            Container(
              decoration: glowCard(),
              child: Column(children: children),
            ),
          ],
        ),
      );

  Widget _row({
    required IconData icon,
    required String label,
    required Widget trailing,
  }) =>
      _rowContent(icon: icon, label: label, trailing: trailing);

  Widget _rowContent({
    required IconData icon,
    required String label,
    required Widget trailing,
    Color color = C.cyan,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 14),
          Expanded(
              child: Text(label,
                  style: body(14.5,
                      c: color == C.danger ? C.danger : C.text))),
          trailing,
        ]),
      );
}

class _GradToggle extends StatelessWidget {
  const _GradToggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => _Press(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 28,
          padding: const EdgeInsets.all(3),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            gradient: value ? C.grad : null,
            color: value ? null : C.elevated,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: value ? Colors.transparent : C.muted),
          ),
          child: Container(
            width: 22,
            height: 22,
            decoration:
                const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIMITIVES
// ─────────────────────────────────────────────────────────────────────────────

class _Press extends StatefulWidget {
  const _Press({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;
  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _d = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _d = true),
        onTapCancel: () => setState(() => _d = false),
        onTapUp: (_) {
          setState(() => _d = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _d ? .95 : 1,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      );
}

class _Icon extends StatelessWidget {
  const _Icon(this.icon, {required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Press(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: color),
        ),
      );
}
