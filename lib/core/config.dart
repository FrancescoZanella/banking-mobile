/// Parametri non segreti: gli stessi valori di `config.json` della versione web.
class AppConfig {
  static const apiBaseUrl = 'https://api.enablebanking.com';
  static const country = 'IT';
  static const psuType = 'personal';
  static const service = 'AIS';
  static const language = 'it';

  /// Margine tolto alla durata massima del consenso concessa dalla banca.
  static const consentMarginSeconds = 120;

  /// Validità dello `state` di un collegamento in corso.
  static const pendingAuthorizationTtl = Duration(seconds: 1200);

  /// Limite PSD2: circa 4 accessi al giorno senza utente presente, quindi al
  /// massimo una sincronizzazione ogni 12 ore per conto.
  static const minSyncInterval = Duration(hours: 12);
  static const overlapDays = 10;
  static const backfillDays = 730;
  static const expiryWarningDays = 14;

  /// Blocco dell'app dopo inattività (come il logout del web).
  static const idleLock = Duration(minutes: 30);

  /// Pagina relay (GitHub Pages) che riporta all'app dopo il login con la banca.
  static const redirectUri = 'https://francescozanella.github.io/Bankrelay/app/';
  static const callbackScheme = 'bankingmobile';
  static const callbackHost = 'callback';
}
