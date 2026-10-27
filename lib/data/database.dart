import 'package:sqflite_common/sqlite_api.dart';

import '../domain/categorize.dart';
import 'defaults.dart';

/// Schema del database: le stesse tabelle della versione web. Sul telefono il
/// file è cifrato con SQLCipher (vedi `secure_database.dart`); nei test si usa
/// SQLite in memoria.
const schema = [
  '''CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL)''',
  '''CREATE TABLE IF NOT EXISTS banks (
    key TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    aspsp_name TEXT,
    country TEXT)''',
  '''CREATE TABLE IF NOT EXISTS consents (
    id INTEGER PRIMARY KEY,
    bank_key TEXT NOT NULL REFERENCES banks(key),
    session_id TEXT NOT NULL UNIQUE,
    valid_until TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TEXT NOT NULL)''',
  '''CREATE TABLE IF NOT EXISTS pending_auth (
    state TEXT PRIMARY KEY,
    bank_key TEXT NOT NULL,
    aspsp_json TEXT NOT NULL,
    created_at REAL NOT NULL)''',
  // uid cambia a ogni nuovo consenso: l'id interno resta stabile.
  '''CREATE TABLE IF NOT EXISTS accounts (
    id INTEGER PRIMARY KEY,
    bank_key TEXT NOT NULL REFERENCES banks(key),
    uid TEXT UNIQUE,
    consent_id INTEGER REFERENCES consents(id),
    iban TEXT,
    name TEXT,
    nickname TEXT,
    currency TEXT,
    hidden INTEGER NOT NULL DEFAULT 0,
    last_sync_at TEXT,
    created_at TEXT NOT NULL)''',
  '''CREATE TABLE IF NOT EXISTS balances (
    id INTEGER PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(id),
    balance_type TEXT,
    amount_cents INTEGER NOT NULL,
    currency TEXT,
    reference_date TEXT,
    fetched_at TEXT NOT NULL)''',
  '''CREATE TABLE IF NOT EXISTS categories (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    kind TEXT NOT NULL CHECK (kind IN ('expense', 'income', 'transfer')),
    color TEXT NOT NULL,
    icon TEXT)''',
  '''CREATE TABLE IF NOT EXISTS category_rules (
    id INTEGER PRIMARY KEY,
    category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    field TEXT NOT NULL CHECK (field IN ('text', 'mcc')),
    pattern TEXT NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    UNIQUE (field, pattern))''',
  '''CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(id),
    booking_date TEXT,
    value_date TEXT,
    amount_cents INTEGER NOT NULL,
    currency TEXT,
    status TEXT,
    counterparty TEXT,
    counterparty_iban TEXT,
    description TEXT,
    mcc TEXT,
    raw_json TEXT NOT NULL,
    category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
    category_source TEXT,
    is_internal INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL)''',
  'CREATE INDEX IF NOT EXISTS ix_tx_account_date ON transactions(account_id, booking_date)',
  'CREATE INDEX IF NOT EXISTS ix_tx_date ON transactions(booking_date)',
  // Limite mensile per categoria (il budget totale sta in settings).
  '''CREATE TABLE IF NOT EXISTS budgets (
    category_id INTEGER PRIMARY KEY REFERENCES categories(id) ON DELETE CASCADE,
    amount_cents INTEGER NOT NULL CHECK (amount_cents > 0))''',
  // Pagamenti ricorrenti che hai indicato come "non è un abbonamento".
  '''CREATE TABLE IF NOT EXISTS subscription_ignores (
    party TEXT PRIMARY KEY,
    created_at TEXT NOT NULL)''',
  '''CREATE TABLE IF NOT EXISTS sync_runs (
    id INTEGER PRIMARY KEY,
    account_id INTEGER REFERENCES accounts(id),
    kind TEXT NOT NULL,
    started_at TEXT NOT NULL,
    ok INTEGER NOT NULL,
    n_new INTEGER NOT NULL DEFAULT 0,
    error TEXT)''',
];

Future<String?> getSetting(DatabaseExecutor db, String key, [String? fallback]) async {
  final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
  return rows.isEmpty ? fallback : rows.first['value'] as String;
}

Future<void> setSetting(DatabaseExecutor db, String key, String value) => db.rawInsert(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );

Future<void> _addColumnIfMissing(
    DatabaseExecutor db, String table, String column, String definition) async {
  final columns = await db.rawQuery('PRAGMA table_info($table)');
  if (!columns.any((c) => c['name'] == column)) {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}

/// Crea o aggiorna lo schema. Idempotente: gira a ogni apertura.
Future<void> initDb(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
  for (final statement in schema) {
    await db.execute(statement);
  }
  // Migrazioni dei database creati con versioni precedenti dello schema.
  await _addColumnIfMissing(db, 'accounts', 'hidden', 'INTEGER NOT NULL DEFAULT 0');
  await _addColumnIfMissing(db, 'categories', 'icon', 'TEXT');

  final hasCategories = (await db.rawQuery('SELECT 1 FROM categories LIMIT 1')).isNotEmpty;
  if (!hasCategories) {
    final batch = db.batch();
    for (final c in defaultCategories) {
      batch.insert('categories', {'name': c.name, 'kind': c.kind, 'color': c.color});
    }
    await batch.commit(noResult: true);
  }
  for (final c in defaultCategories) {
    await db.rawUpdate(
        'UPDATE categories SET icon = ? WHERE name = ? AND icon IS NULL', [c.icon, c.name]);
  }
  await db.rawUpdate('UPDATE categories SET icon = ? WHERE icon IS NULL', [defaultIcon]);

  final version = int.parse(await getSetting(db, 'default_rules_version', '0') ?? '0');
  if (version < defaultRulesVersion) {
    if (version < 3) {
      // Dalla v3 i giroconti si riconoscono solo da IBAN o a mano: le regole
      // di testo verso categorie "giroconto" non valgono più.
      await db.rawDelete('DELETE FROM category_rules WHERE category_id IN '
          "(SELECT id FROM categories WHERE kind = 'transfer')");
    }
    final ids = {
      for (final r in await db.query('categories', columns: ['id', 'name']))
        r['name'] as String: r['id'] as int,
    };
    for (final entry in defaultRules.entries) {
      final categoryId = ids[entry.key];
      if (categoryId == null) continue;
      for (final field in entry.value.entries) {
        for (final pattern in field.value) {
          await db.rawInsert(
            'INSERT OR IGNORE INTO category_rules (category_id, field, pattern) VALUES (?, ?, ?)',
            [categoryId, field.key, pattern],
          );
        }
      }
    }
    await setSetting(db, 'default_rules_version', '$defaultRulesVersion');
    await recategorize(db);
    await setSetting(db, 'classifier_version', '$classifierVersion');
  } else if (int.parse(await getSetting(db, 'classifier_version', '0') ?? '0') <
      classifierVersion) {
    await recategorize(db);
    await setSetting(db, 'classifier_version', '$classifierVersion');
  }
}
