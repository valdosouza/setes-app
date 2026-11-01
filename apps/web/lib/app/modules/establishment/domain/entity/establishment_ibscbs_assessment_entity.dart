// Opção de apuração do IBS/CBS do Simples (`regApIBSCBSSN` da NT 009) — fato
// DATADO do estabelecimento (fase IBS/CBS, D-IB99/D-IB100 —
// prompt_fase_ibs_cbs.md §14). A API é a fonte de TUDO o que decide: o "hoje"
// do estabelecimento (fuso), o piso do regime regular, o que é suportado e o
// que é editável; a tela só espelha as pendências para avisar antes do
// salvar (a recusa definitiva é da API — mesma regra).

/// Domínio da NT 009 (1 IBS e CBS pelo Simples · 2 CBS pelo Simples e IBS pelo
/// regime regular · 3 IBS e CBS pelo regime regular).
const kIbscbsAssessments = ['1', '2', '3'];

/// Opção que NÃO é a do Simples (pede o regime regular).
bool isRegularAssessment(String assessment) => assessment != '1';

/// Data 'yyyy-MM-dd' de calendário real.
bool isIsoDate(String? value) {
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return false;
  }
  final d = DateTime.tryParse('${value}T00:00:00Z');
  return d != null && d.toIso8601String().substring(0, 10) == value;
}

/// Sugestão da data de início: o próximo início de semestre (01/01 ou 01/07)
/// a partir de hoje — o calendário normal da opção (CGSN 194). É SÓ
/// sugestão: a data é livre (MAT, exclusão de ofício — "data do fato
/// motivador"); quem decide o piso é a API.
String suggestedAssessmentStart(String todayIso) {
  final year = int.tryParse(todayIso.substring(0, 4)) ?? DateTime.now().year;
  for (final candidate in ['$year-01-01', '$year-07-01', '${year + 1}-01-01']) {
    if (candidate.compareTo(todayIso) >= 0) return candidate;
  }
  return '${year + 1}-01-01';
}

/// Uma linha do histórico (só as vivas).
class IbscbsAssessmentLine {
  const IbscbsAssessmentLine({
    required this.validFrom,
    required this.assessment,
    this.supported = false,
    this.inEffect = false,
    this.editable = false,
  });

  factory IbscbsAssessmentLine.fromJson(Map<String, dynamic> json) =>
      IbscbsAssessmentLine(
        validFrom: json['validFrom'] as String,
        assessment: json['assessment'] as String,
        supported: json['supported'] == true,
        inEffect: json['inEffect'] == true,
        editable: json['editable'] == true,
      );

  final String validFrom;
  final String assessment;

  /// O faturamento sabe tratar (hoje só a 1 — D-IB99).
  final bool supported;

  /// É a que vale hoje.
  final bool inEffect;

  /// Só linha FUTURA muda (a vigente e as passadas são imutáveis).
  final bool editable;
}

/// GET /api/establishment/ibscbs-assessments (e a resposta de todo ato).
class IbscbsAssessmentView {
  const IbscbsAssessmentView({
    required this.today,
    required this.regularStart,
    required this.currentAssessment,
    this.supported = const ['1'],
    this.currentValidFrom,
    this.currentSupported = true,
    this.items = const [],
  });

  /// Tipo trocado na leitura LANÇA (o datasource converte em falha de leitura
  /// — nunca uma visão inventada sobre `{}`).
  factory IbscbsAssessmentView.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>;
    return IbscbsAssessmentView(
      today: json['today'] as String,
      regularStart: json['regularStart'] as String,
      supported: [for (final s in json['supported'] as List<dynamic>) s as String],
      currentAssessment: current['assessment'] as String,
      currentValidFrom: current['validFrom'] as String?,
      currentSupported: current['supported'] == true,
      items: [
        for (final item in json['items'] as List<dynamic>)
          IbscbsAssessmentLine.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  /// Hoje do estabelecimento (fuso) — a fronteira passado × futuro.
  final String today;

  /// A partir de quando o regime regular (2/3) pode valer.
  final String regularStart;

  /// Opções que o faturamento sabe tratar HOJE (a API decide — D-IB99).
  final List<String> supported;

  final String currentAssessment;

  /// null = sem linha: vale a 1 (efeito legal de não optar — D-IB1).
  final String? currentValidFrom;
  final bool currentSupported;
  final List<IbscbsAssessmentLine> items;

  /// Há opção sem suporte registrada (vigente ou futura): a tela avisa que o
  /// faturamento será recusado a partir da data dela.
  IbscbsAssessmentLine? get firstUnsupported {
    for (final item in items) {
      final vigenteOuFutura =
          item.inEffect || item.validFrom.compareTo(today) > 0;
      if (!item.supported && vigenteOuFutura) return item;
    }
    return null;
  }

  /// Pendência do registro ANTES de chamar a API (espelho da regra da peça):
  /// null = pode enviar; senão a chave i18n do problema.
  String? pendencyFor(String? validFrom, String? assessment) {
    if (!isIsoDate(validFrom)) return 'forms.establishment.ibscbsDateInvalid';
    if (assessment == null || !kIbscbsAssessments.contains(assessment)) {
      return 'forms.establishment.ibscbsAssessmentRequired';
    }
    if (validFrom!.compareTo(today) < 0) {
      return 'forms.establishment.ibscbsDatePast';
    }
    if (isRegularAssessment(assessment) &&
        validFrom.compareTo(regularStart) < 0) {
      return 'forms.establishment.ibscbsRegularTooEarly';
    }
    return null;
  }
}
