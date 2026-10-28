/// Link di ritorno dalla banca, anche quando HyperOS ha chiuso l'app durante
/// il login e Android la riavvia per consegnarlo.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';

/// Ciò che serve del plugin `app_links` (nei test una versione finta).
abstract class LinkSource {
  /// Il link con cui è stata creata l'attività: dopo un riavvio può essere
  /// quello vecchio che aveva aperto il task.
  Future<String?> initial();

  /// L'ultimo link ricevuto, anche se è arrivato prima che Flutter ascoltasse.
  Future<String?> latest();

  /// Link successivi; all'iscrizione il plugin ripete [initial].
  Stream<Uri> get stream;
}

class PluginLinkSource implements LinkSource {
  final _links = AppLinks();

  @override
  Future<String?> initial() => _links.getInitialLinkString();

  @override
  Future<String?> latest() => _links.getLatestLinkString();

  @override
  Stream<Uri> get stream => _links.uriLinkStream;
}

/// Ogni link di ritorno una volta sola, senza perdere quello arrivato durante
/// l'avvio. Ad app riavviata Android consegna prima il vecchio link del task e
/// subito dopo quello nuovo, quando Flutter non ascolta ancora: il plugin
/// ripeterebbe solo il vecchio. Qui si prende anche l'ultimo e si scarta il
/// vecchio.
Stream<Uri> returnLinks(LinkSource source) {
  final out = StreamController<Uri>();
  final seen = <String>{};
  String? stale;

  void emit(Uri uri) {
    final key = uri.toString();
    if (key == stale) {
      stale = null;
      return;
    }
    if (seen.add(key)) out.add(uri);
  }

  out.onListen = () async {
    final initial = await source.initial();
    // Iscrizione prima di leggere l'ultimo link: quelli che arrivano dopo
    // passano dallo stream, quelli arrivati prima li dà [LinkSource.latest].
    final early = <Uri>[];
    var started = false;
    final subscription = source.stream.listen((uri) => started ? emit(uri) : early.add(uri), onError: (_) {});
    out.onCancel = subscription.cancel;
    final latest = await source.latest();
    if (initial != null && latest != null && latest != initial) stale = initial;
    if (latest != null) emit(Uri.parse(latest));
    started = true;
    early.forEach(emit);
  };
  return out.stream;
}
