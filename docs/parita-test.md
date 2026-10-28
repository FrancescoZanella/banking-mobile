# Parità dei test con la versione web

Ogni test di `banking-dashboard/tests/` ha un corrispondente qui, che verifica lo stesso
comportamento per l'utente. Stato: ✅ portato e verde · ⏳ fase successiva · ➖ non applicabile (motivo indicato).

## tests/test_core.py → test/core_test.dart
| Web | App | Stato |
|---|---|---|
| test_to_cents (5 casi) | `to_cents` | ✅ |
| test_dedup_and_pending_replaced | `dedup and pending replaced` | ✅ |
| test_categorization_rules_and_manual_override | `categorization rules and manual override` | ✅ |
| test_internal_transfers_only_by_own_iban | `internal transfers only by own iban` | ✅ |
| test_migration_removes_rules_towards_transfers | `migration removes rules towards transfers` | ✅ |
| test_pending_state_validation | `pending state validation` | ✅ |
| test_save_session_reuses_account_without_iban | `save session reuses account without iban` | ✅ |
| test_consent_valid_until_uses_bank_maximum | `consent valid until uses bank maximum` | ✅ |
| test_consent_error_detection | `consent error detection` | ✅ |
| test_db_is_encrypted | `integration_test/db_encryption_test.dart` (SQLCipher sul telefono: senza chiave e con chiave errata illeggibile, testo assente dal file) | ✅ scritto, da eseguire sul telefono |
| test_is_due_respects_interval | `is_due respects interval` | ✅ |
| test_same_iban_different_currencies_are_separate_accounts | `same iban different currencies are separate accounts` | ✅ |
| test_migration_adds_hidden_column | `migration adds hidden column` | ✅ |
| test_hidden_accounts_still_count_for_internal_transfers | `hidden accounts still count for internal transfers` | ✅ |
| test_day_label | `day label` | ✅ |
| test_default_categories_have_icons | `default categories have icons` | ✅ |
| test_own_party_rule | `own party rule` | ✅ |
| test_transfer_to_myself_detected | `transfer to myself detected` | ✅ |
| test_paypal_is_an_external_service | `paypal is an external service` | ✅ |
| test_classifier_version_triggers_recalculation | `classifier version triggers recalculation` | ✅ |

## tests/test_analysis.py → test/analysis_test.dart
| Web | App | Stato |
|---|---|---|
| test_period_bounds_and_labels | `period bounds and labels` | ✅ |
| test_comparable_window_same_day_of_previous_period | `comparable window same day of previous period` | ✅ |
| test_totals_cumulative_categories_merchants | `totals, cumulative, categories, merchants` (curva in centesimi invece che in euro: stesso dato) | ✅ |

## tests/test_cashflow.py → test/cashflow_test.dart
| Web | App | Stato |
|---|---|---|
| test_detect_recurring_monthly_salary | `detect recurring monthly salary` | ✅ |
| test_detect_recurring_rejects_irregular_or_few | `detect recurring rejects irregular or few` | ✅ |
| test_totals_rate_and_sources | `totals, rate and sources` | ✅ |

## tests/test_budget.py → test/budget_test.dart
| Web | App | Stato |
|---|---|---|
| test_parse_euro | `parse_euro` | ✅ |
| test_forecast_and_states | `forecast and states` | ✅ |
| test_budget_overview_and_alerts | `budget overview and alerts` | ✅ |
| test_subscriptions_detection_and_ignore | `subscriptions detection and ignore` | ✅ |

## tests/test_web.py → test/ui/*, test/bank/*, integration_test/*
| Web | App | Stato |
|---|---|---|
| test_requires_login_and_security_headers | `security_test: bloccata: solo la schermata di sblocco` (+ FLAG_SECURE in MainActivity) | ✅ |
| test_foreign_host_rejected | ➖ nessun server: niente header Host. Equivalente: nessuna porta aperta, verificato nell'audit | ⏳ fase 8 |
| test_post_without_csrf_rejected | ➖ nessun form web. Equivalente: deep link accettato solo con `state` valido, monouso, schema `bankingmobile://callback` (`bank_test: ritorno con state sconosciuto…`) | ✅ |
| test_login_flow_and_pages | `security_test: bloccata… → sblocco → barra con le 5 voci`, `Altro → Impostazioni` | ✅ (pagine complete nelle fasi 3-6) |
| test_wrong_password | `AppLock: si sblocca solo con autenticazione riuscita`, `senza blocco schermo resta bloccata` | ✅ |
| test_logout_invalidates_copied_cookie | `si blocca dopo 30 minuti di inattività`, `blocco per inattività nasconde subito i dati` | ✅ |
| test_change_password | ➖ niente password (sblocco biometrico/PIN, scelta di progetto) | ➖ |
| test_auth_pages_have_no_sidebar | `bloccata: … nessuna NavigationBar` | ✅ |
| test_callback_with_unknown_state_is_refused | `bank_test: ritorno con state sconosciuto, già usato o con schema estraneo` + `deep link di ritorno: esito mostrato` | ✅ |
| test_manual_category_creates_rule | `transactions_test: categoria a mano con regola` (il `back` verso siti esterni non esiste: il dettaglio è un pannello che si chiude) | ✅ |
| test_connect_shows_bank_page_instead_of_redirect | `bank_test: banca nuova salvata solo dopo il login` (restituisce l'URL https della banca, aperto in Custom Tab) | ✅ |
| test_accounts_page_lists_catalog_in_dropdown | `bank_test: catalogo nel menu, in ordine` | ✅ |
| test_accounts_page_survives_catalog_error | `bank_test: … errore del catalogo → null` (avviso «Elenco banche non disponibile») | ✅ |
| test_new_bank_not_in_catalog_is_refused | `bank_test: banca fuori catalogo rifiutata (solo nome esatto)` | ✅ |
| test_new_bank_saved_only_after_successful_login | `bank_test: banca nuova salvata solo dopo il login riuscito` | ✅ |
| test_new_bank_failed_login_leaves_nothing | `bank_test: login fallito non lascia nulla` | ✅ |
| test_new_bank_existing_reuses_key | `bank_test: banca già nota riusa la sua chiave` | ✅ |
| test_new_bank_without_accounts_explains_control_panel | `bank_test: nessun conto restituito → spiega il Control Panel` | ✅ |
| test_renewal_without_accounts_keeps_existing_link | `bank_test: rinnovo a vuoto non sgancia i conti` | ✅ |
| test_disconnect_revokes_and_keeps_history | `bank_test: scollega: revoca il consenso e tiene lo storico` | ✅ |
| test_delete_bank_requires_exact_name | `bank_test: elimina solo scrivendo il nome esatto, e solo quella banca` | ✅ |
| test_hidden_account_excluded_from_totals_and_list | `transactions_test: conto nascosto escluso dai totali e dalla lista` | ✅ |
| test_home_feed_and_detail_panel | `transactions_test: Home: patrimonio, feed per giorno, dettaglio con lo storico` (i nomi sono testo, mai HTML: niente escape da verificare; id inesistente → «Movimento non trovato.») | ✅ |
| test_detail_requires_login | `bloccata: nessuna pagina con dati costruita` (vale per ogni schermata, dettaglio incluso) | ✅ |
| test_category_change_from_home_returns_home | `transactions_test: cambio categoria dal dettaglio: si resta in Home` | ✅ |
| test_analysis_page_periods | `analysis_flows_test: Analisi: periodi, confronto allo stesso giorno, categoria → Movimenti filtrati` + `barre fino al mese del periodo…` (date non valide o future non esistono: il periodo si sceglie solo con i pulsanti) | ✅ |
| test_flows_page | `analysis_flows_test: Flussi: solo mese e anno, totali, tasso di risparmio, entrate ricorrenti` | ✅ |
| test_budget_page_and_forms | Budget: pagina e moduli | ⏳ fase 6 |
| test_category_icons | Categorie: icone | ⏳ fase 6 |
| test_transactions_periods_and_grouping | `transactions_test: periodi, raggruppamento…, CSV` + `Movimenti: chip attivi, «Azzera filtri», totali e gruppi per giorno` (CSV condiviso con Android) | ✅ |
| test_accounts_page_states | `bank_test: pagina Conti: stati dei consensi, conto nascosto, azioni` | ✅ |
| test_manual_transfer_and_visibility | `transactions_test: giroconto scelto a mano` (la parte sulle regole verso Giroconti nella pagina Categorie arriva in fase 6) | ✅ / ⏳ fase 6 |

## Solo mobile (sicurezza)
| Controllo | Test | Stato |
|---|---|---|
| Chiave DB 256 bit, creata una volta, formato verificato | `security_test: chiave del database` | ✅ |
| Credenziali Enable Banking validate e salvate solo nel Keystore, mai nel DB | `security_test: credenziali validate…`, `Altro → Impostazioni…` | ✅ |
| Rinomina (max 40, vuoto = nome banca) e nascondi | `bank_test: rinomina … e nascondi` | ✅ |
| Notifica consensi: solo nomi e giorni, mai importi | `bank_test: notifica dei consensi` | ✅ |
