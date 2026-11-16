import 'package:equatable/equatable.dart';

import 'object_establishment.dart';

/// Resultado do PUT /api/establishment: o estabelecimento gravado e, quando
/// o salvamento TIROU o estabelecimento do Simples (opSimpNac 3/4 → outro)
/// e já existe linha FUTURA de opção de apuração 2/3, o início dessa linha
/// (D-IB105 — aviso NÃO bloqueante; a API nunca recusa por isso).
///
/// [ibscbsNoticeFrom] = `data.ibscbsAssessmentNotice.validFrom` (ISO
/// AAAA-MM-DD) ou null. Leitura tolerante: campo ausente (API sem a D-IB105)
/// ou fora do formato = sem aviso.
class EstablishmentSaved extends Equatable {
  const EstablishmentSaved({required this.establishment, this.ibscbsNoticeFrom});

  factory EstablishmentSaved.fromJson(Map<String, dynamic> json) {
    final notice = json['ibscbsAssessmentNotice'];
    final from = notice is Map ? notice['validFrom'] : null;
    return EstablishmentSaved(
      establishment: ObjectEstablishment.fromJson(json),
      ibscbsNoticeFrom:
          from is String && _iso.hasMatch(from) ? from : null,
    );
  }

  static final _iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  final ObjectEstablishment establishment;
  final String? ibscbsNoticeFrom;

  @override
  List<Object?> get props => [establishment, ibscbsNoticeFrom];
}
