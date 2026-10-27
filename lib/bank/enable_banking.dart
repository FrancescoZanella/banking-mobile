import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';

const maxPages = 200;
const _timeout = Duration(seconds: 60);
const catalogTtl = Duration(hours: 24);

class EnableBankingError implements Exception {
  EnableBankingError(this.label, this.status, [this.code]);

  final String label;
  final int status;
  final String? code;

  /// Sessione scaduta, revocata o non più autorizzata dalla banca.
  bool get isConsentProblem {
    final text = (code ?? '').toUpperCase();
    return status == 401 ||
        status == 403 ||
        ['SESSION', 'CONSENT', 'EXPIRED', 'REVOKED'].any(text.contains);
  }

  @override
  String toString() => '$label: HTTP $status${code != null ? ' (codice: $code)' : ''}';
}

/// Errore "nostro" (configurazione, risposta inattesa): messaggio per l'utente.
class AppError implements Exception {
  AppError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Credenziali dell'applicazione Enable Banking, custodite nello storage sicuro.
class Credentials {
  const Credentials(this.appId, this.privateKeyPem);
  final String appId;
  final String privateKeyPem;
}

/// Client dell'API Enable Banking. `http.Client` e orologio sono iniettabili
/// per i test; in produzione si usa sempre HTTPS verso `apiBaseUrl`.
class EnableBankingClient {
  EnableBankingClient(this._credentials, {http.Client? client, DateTime Function()? clock})
      : _http = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final Future<Credentials?> Function() _credentials;
  final http.Client _http;
  final DateTime Function() _clock;
  final Map<String, (DateTime, List<Map<String, dynamic>>)> _catalog = {};

  Future<String> _jwt() async {
    final creds = await _credentials();
    if (creds == null || creds.appId.isEmpty || creds.privateKeyPem.isEmpty) {
      throw AppError('Configura APP_ID e chiave privata in Impostazioni.');
    }
    final now = _clock().toUtc().millisecondsSinceEpoch ~/ 1000;
    final token = JWT(
      {'iss': 'enablebanking.com', 'aud': 'api.enablebanking.com', 'iat': now, 'exp': now + 300},
      header: {'kid': creds.appId, 'typ': 'JWT'},
    );
    try {
      return token.sign(RSAPrivateKey(creds.privateKeyPem), algorithm: JWTAlgorithm.RS256);
    } catch (_) {
      throw AppError('Chiave privata non valida: reimportala in Impostazioni.');
    }
  }

  Future<http.Response> _call(String method, String path,
      {Map<String, String>? query, Object? json}) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path').replace(queryParameters: query);
    final headers = {
      'Authorization': 'Bearer ${await _jwt()}',
      'Accept': 'application/json',
      if (json != null) 'Content-Type': 'application/json',
    };
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (json != null) request.body = jsonEncode(json);
    final streamed = await _http.send(request).timeout(_timeout);
    return http.Response.fromStream(streamed);
  }

  static Map<String, dynamic> _jsonOrEmpty(http.Response r) {
    try {
      final data = jsonDecode(utf8.decode(r.bodyBytes));
      return data is Map<String, dynamic> ? data : {};
    } catch (_) {
      return {};
    }
  }

  static String? _errorCode(Map<String, dynamic> data) =>
      (data['error'] ?? data['code'] ?? data['error_code'])?.toString();

  /// Esegue la chiamata e solleva [EnableBankingError] se non è un 200.
  Future<Map<String, dynamic>> _callJson(String label, String method, String path,
      {Map<String, String>? query, Object? json}) async {
    final r = await _call(method, path, query: query, json: json);
    final data = _jsonOrEmpty(r);
    if (r.statusCode != 200) throw EnableBankingError(label, r.statusCode, _errorCode(data));
    return data;
  }

  Future<Map<String, dynamic>> checkApplication() async {
    final data = await _callJson('Verifica applicazione fallita', 'GET', '/application');
    if ('${data['environment'] ?? ''}'.toUpperCase() != 'PRODUCTION') {
      throw AppError("L'applicazione non risulta PRODUCTION. Controlla APP_ID e chiave privata.");
    }
    return data;
  }

  /// Catalogo delle banche di un paese, in cache per 24 ore.
  Future<List<Map<String, dynamic>>> listAspsps(String country) async {
    final cached = _catalog[country];
    if (cached != null && cached.$1.isAfter(_clock())) return cached.$2;
    final data = await _callJson('Lettura catalogo fallita', 'GET', '/aspsps', query: {
      'country': country,
      'psu_type': AppConfig.psuType,
      'service': AppConfig.service,
    });
    final list = [for (final a in (data['aspsps'] as List? ?? [])) Map<String, dynamic>.from(a as Map)];
    _catalog[country] = (_clock().add(catalogTtl), list);
    return list;
  }

  /// La banca con esattamente questo nome nel catalogo, oppure null.
  Future<Map<String, dynamic>?> getAspsp(String name, String country) async {
    for (final item in await listAspsps(country)) {
      if (item['name'] == name) return item;
    }
    return null;
  }

  Future<String> startAuth(Map<String, dynamic> aspsp, String state) async {
    final data = await _callJson('Avvio autorizzazione fallito', 'POST', '/auth', json: {
      'access': {
        'balances': true,
        'transactions': true,
        'valid_until': consentValidUntil(aspsp, _clock()),
      },
      'aspsp': {'name': aspsp['name'], 'country': aspsp['country']},
      'state': state,
      'redirect_url': AppConfig.redirectUri,
      'psu_type': AppConfig.psuType,
      'language': AppConfig.language,
    });
    final url = data['url'] as String?;
    if (url == null || url.isEmpty) throw AppError("La risposta dell'API non contiene l'URL atteso.");
    return url;
  }

  Future<Map<String, dynamic>> createSession(String code) =>
      _callJson('Creazione sessione fallita', 'POST', '/sessions', json: {'code': code});

  /// Revoca il consenso presso Enable Banking (e quindi presso la banca).
  Future<void> deleteSession(String sessionId) async {
    final r = await _call('DELETE', '/sessions/$sessionId');
    // 404/401: sessione già scaduta o revocata, il risultato è lo stesso.
    if (![200, 204, 401, 404].contains(r.statusCode)) {
      throw EnableBankingError('Revoca del consenso fallita', r.statusCode, _errorCode(_jsonOrEmpty(r)));
    }
  }

  Future<List<Map<String, dynamic>>> getBalances(String uid) async {
    final data = await _callJson('Lettura saldi fallita', 'GET', '/accounts/$uid/balances');
    return [for (final b in (data['balances'] as List? ?? [])) Map<String, dynamic>.from(b as Map)];
  }

  Future<List<Map<String, dynamic>>> getTransactions(String uid, String dateFrom,
      {String? dateTo, String strategy = 'default'}) async {
    final transactions = <Map<String, dynamic>>[];
    String? continuationKey;
    for (var page = 0; page < maxPages; page++) {
      final data = await _callJson('Lettura movimenti fallita', 'GET', '/accounts/$uid/transactions',
          query: {
            'date_from': dateFrom,
            'strategy': strategy,
            'date_to': ?dateTo,
            'continuation_key': ?continuationKey,
          });
      for (final t in (data['transactions'] as List? ?? [])) {
        transactions.add(Map<String, dynamic>.from(t as Map));
      }
      continuationKey = data['continuation_key'] as String?;
      if (continuationKey == null || continuationKey.isEmpty) return transactions;
    }
    throw AppError('Raggiunto il limite di $maxPages pagine: paginazione da verificare.');
  }
}

/// Durata massima concessa dalla banca, meno un piccolo margine.
String consentValidUntil(Map<String, dynamic> aspsp, [DateTime? now]) {
  final maximum = int.tryParse('${aspsp['maximum_consent_validity'] ?? 0}') ?? 0;
  if (maximum <= 0) throw AppError('Durata massima del consenso non valida.');
  final seconds = maximum - AppConfig.consentMarginSeconds;
  final until = (now ?? DateTime.now()).toUtc().add(Duration(seconds: seconds < 3600 ? 3600 : seconds));
  return '${until.toIso8601String().split('.').first.replaceAll(RegExp(r'Z$'), '')}Z';
}
