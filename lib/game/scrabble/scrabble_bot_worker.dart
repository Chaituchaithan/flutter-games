import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'scrabble_engine.dart';
import 'scrabble_words.g.dart';

Lexicon _buildLexicon() => Lexicon([
  for (final w in scrabbleWordList.split('\n'))
    if (w.length >= 2) w,
]);

/// The computer's Scrabble move search on one long-lived background isolate.
///
/// The isolate builds its word list once (from the compiled-in constant, so
/// nothing is copied over) and keeps it for every later move. Spawning a
/// fresh isolate per move instead meant sending 168k words across and
/// rebuilding the lookup set every turn.
class ScrabbleBotWorker {
  ScrabbleBotWorker._();
  static final instance = ScrabbleBotWorker._();

  Future<SendPort>? _port;

  /// Web has no isolates: search on the main thread with a cached list.
  Lexicon? _localLexicon;

  Future<ScrabblePlay?> choose(List<Tile?> board, List<Tile> rack, int difficulty, int seed) async {
    if (kIsWeb) {
      final lex = _localLexicon ??= _buildLexicon();
      return chooseScrabblePlay(board, rack, lex, difficulty, seed);
    }
    final SendPort port;
    try {
      port = await (_port ??= _spawn());
    } catch (_) {
      _port = null; // let the next move try again
      rethrow;
    }
    final reply = ReceivePort();
    try {
      port.send((reply.sendPort, (board, rack, difficulty, seed)));
      final result = await reply.first;
      if (result is RemoteError) throw result;
      return result as ScrabblePlay?;
    } finally {
      reply.close();
    }
  }

  static Future<SendPort> _spawn() async {
    final ready = ReceivePort();
    await Isolate.spawn(_main, ready.sendPort, debugName: 'scrabble-bot');
    return await ready.first as SendPort;
  }

  static void _main(SendPort ready) {
    final lex = _buildLexicon();
    final inbox = ReceivePort();
    ready.send(inbox.sendPort);
    inbox.listen((msg) {
      final (SendPort reply, (List<Tile?>, List<Tile>, int, int) job) =
          msg as (SendPort, (List<Tile?>, List<Tile>, int, int));
      try {
        reply.send(chooseScrabblePlay(job.$1, job.$2, lex, job.$3, job.$4));
      } catch (e, st) {
        reply.send(RemoteError('$e', '$st'));
      }
    });
  }
}
