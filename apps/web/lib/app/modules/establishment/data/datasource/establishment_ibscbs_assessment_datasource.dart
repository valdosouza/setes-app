import 'package:core/core.dart';

import '../../domain/entity/establishment_ibscbs_assessment_entity.dart';

/// Sub-recurso OPÇÃO DE APURAÇÃO DO IBS/CBS do PRÓPRIO estabelecimento
/// (D-IB99/D-IB100): `/api/establishment/ibscbs-assessments` na setes-api.
/// Institution SEMPRE implícita (token); a data de início é a identidade da
/// linha. Todo ato devolve a visão inteira atualizada.
abstract class EstablishmentIbscbsAssessmentDatasource {
  Future<IbscbsAssessmentView> get();
  Future<IbscbsAssessmentView> create(
      {required String validFrom, required String assessment});
  Future<IbscbsAssessmentView> change(String validFrom,
      {required String assessment});
  Future<IbscbsAssessmentView> remove(String validFrom);
}

class EstablishmentIbscbsAssessmentDatasourceImpl
    implements EstablishmentIbscbsAssessmentDatasource {
  const EstablishmentIbscbsAssessmentDatasourceImpl({required this.client});

  final ApiClient client;

  static const _base = '/api/establishment/ibscbs-assessments';

  /// `{ ok: true, data: {…} }` ou falha técnica; tipo trocado na leitura =
  /// falha de leitura (a seção só captura Failure — nunca spinner eterno).
  IbscbsAssessmentView _view(Map<String, dynamic> json) {
    final data = envelopeData(json, service: 'setes-api');
    try {
      return IbscbsAssessmentView.fromJson(data);
    } on Failure {
      rethrow;
    } catch (e) {
      throw invalidResponseFailure(e, service: 'setes-api');
    }
  }

  @override
  Future<IbscbsAssessmentView> get() async => _view(await client.get(_base));

  @override
  Future<IbscbsAssessmentView> create(
          {required String validFrom, required String assessment}) async =>
      _view(await client.post(
          _base, {'validFrom': validFrom, 'assessment': assessment}));

  @override
  Future<IbscbsAssessmentView> change(String validFrom,
          {required String assessment}) async =>
      _view(await client
          .put('$_base/$validFrom', {'assessment': assessment}));

  @override
  Future<IbscbsAssessmentView> remove(String validFrom) async =>
      _view(await client.delete('$_base/$validFrom'));
}
