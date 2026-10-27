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
| test_db_is_encrypted | `integration_test/db_encryption_test.dart` (SQLCipher sul telefono) | ⏳ fase 2 |
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
| test_requires_login_and_security_headers | sblocco richiesto all'avvio | ⏳ fase 2 |
| test_foreign_host_rejected | ➖ nessun server: niente header Host. Equivalente: nessuna porta aperta, verificato nell'audit | ⏳ fase 8 |
| test_post_without_csrf_rejected | ➖ nessun form web. Equivalente: deep link accettato solo con `state` valido | ⏳ fase 3 |
| test_login_flow_and_pages | sblocco → tutte le schermate si aprono | ⏳ fase 2 |
| test_wrong_password | sblocco fallito → app resta bloccata | ⏳ fase 2 |
| test_logout_invalidates_copied_cookie | blocco dopo 30 min di inattività | ⏳ fase 2 |
| test_change_password | ➖ niente password (sblocco biometrico/PIN, scelta di progetto) | ➖ |
| test_auth_pages_have_no_sidebar | schermata di sblocco senza navigazione | ⏳ fase 2 |
| test_callback_with_unknown_state_is_refused | deep link con `state` sconosciuto rifiutato | ⏳ fase 3 |
| test_manual_category_creates_rule | cambio categoria dal dettaglio con regola | ⏳ fase 4 |
| test_connect_shows_bank_page_instead_of_redirect | collega → apre la Custom Tab della banca | ⏳ fase 3 |
| test_accounts_page_lists_catalog_in_dropdown | Conti: catalogo nel menu | ⏳ fase 3 |
| test_accounts_page_survives_catalog_error | Conti: errore catalogo mostrato, pagina utilizzabile | ⏳ fase 3 |
| test_new_bank_not_in_catalog_is_refused | banca fuori catalogo rifiutata | ⏳ fase 3 |
| test_new_bank_saved_only_after_successful_login | banca salvata solo a login riuscito | ⏳ fase 3 |
| test_new_bank_failed_login_leaves_nothing | login fallito non lascia nulla | ⏳ fase 3 |
| test_new_bank_existing_reuses_key | banca già nota riusa la sua chiave | ⏳ fase 3 |
| test_new_bank_without_accounts_explains_control_panel | nessun conto → messaggio sul Control Panel | ⏳ fase 3 |
| test_renewal_without_accounts_keeps_existing_link | rinnovo a vuoto non sgancia i conti | ⏳ fase 3 |
| test_disconnect_revokes_and_keeps_history | scollega: revoca e tiene lo storico | ⏳ fase 3 |
| test_delete_bank_requires_exact_name | elimina solo scrivendo il nome esatto | ⏳ fase 3 |
| test_hidden_account_excluded_from_totals_and_list | conto nascosto escluso da totali ed elenco | ⏳ fase 4 |
| test_home_feed_and_detail_panel | Home: feed e dettaglio | ⏳ fase 4 |
| test_detail_requires_login | dettaglio inaccessibile con app bloccata | ⏳ fase 2 |
| test_category_change_from_home_returns_home | cambio categoria dalla Home resta in Home | ⏳ fase 4 |
| test_analysis_page_periods | Analisi: tutti i periodi | ⏳ fase 5 |
| test_flows_page | Flussi | ⏳ fase 5 |
| test_budget_page_and_forms | Budget: pagina e moduli | ⏳ fase 6 |
| test_category_icons | Categorie: icone | ⏳ fase 6 |
| test_transactions_periods_and_grouping | Movimenti: periodi e raggruppamento | ⏳ fase 4 |
| test_accounts_page_states | Conti: stati dei consensi | ⏳ fase 3 |
| test_manual_transfer_and_visibility | giroconto manuale e visibilità | ⏳ fase 4 |
