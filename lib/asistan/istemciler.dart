import 'package:http/http.dart' as http;

import 'anthropic.dart';
import 'yz.dart';

/// Bağlayıcısı yazılmış, ayarlarda seçilebilen sağlayıcılar.
const desteklenenSaglayicilar = [Saglayici.anthropic];

/// Seçili sağlayıcının istemcisini oluşturur.
YzIstemcisi istemciOlustur({
  required YzModeli model,
  required String apiAnahtari,
  http.Client? httpIstemcisi,
  Duration? tekrarBeklemesi,
}) {
  switch (model.saglayici) {
    case Saglayici.anthropic:
      return AnthropicIstemcisi(
        apiAnahtari: apiAnahtari,
        model: model,
        httpIstemcisi: httpIstemcisi,
        tekrarBeklemesi: tekrarBeklemesi,
      );
    case Saglayici.openai:
    case Saglayici.gemini:
    case Saglayici.deepseek:
      throw UnimplementedError('${model.saglayici.ad} henüz eklenmedi.');
  }
}
