// D-IB105 (setes-app:IBS.E4.P3): ao salvar o estabelecimento TIRANDO-O do
// Simples (opSimpNac 3 → 1/2) com linha FUTURA de opção de apuração 2/3, a
// API devolve `data.ibscbsAssessmentNotice = { validFrom }` e o app mostra o
// aviso NÃO bloqueante com a data da 1ª linha futura — o salvamento segue.
// Cobre: leitura do PUT pelo datasource (com, sem e malformado), o bloc
// (sucesso com a data + o rascunho gravado) e o desfecho na tela (SnackBar de
// salvo + dialog info com o texto aprovado; sem a data, nenhum dialog).

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:setes_web/app/modules/establishment/data/datasource/establishment_datasource.dart';
import 'package:setes_web/app/modules/establishment/data/repository/establishment_repository_impl.dart';
import 'package:setes_web/app/modules/establishment/domain/entity/establishment_saved.dart';
import 'package:setes_web/app/modules/establishment/domain/entity/object_establishment.dart';
import 'package:setes_web/app/modules/establishment/domain/usecase/establishment_get.dart';
import 'package:setes_web/app/modules/establishment/domain/usecase/establishment_put.dart';
import 'package:setes_web/app/modules/establishment/presentation/bloc/establishment_bloc.dart';
import 'package:setes_web/app/modules/establishment/presentation/widget/establishment_saved_feedback.dart';

class _Client extends Mock implements ApiClient {}

Map<String, dynamic> _putData({Object? notice}) => {
      'nameCompany': 'Setes Ltda',
      'nickTrade': 'Setes',
      'document': '12345678000199',
      'personType': 'J',
      'simplesRegime': 1,
      'addresses': <dynamic>[],
      'phones': <dynamic>[],
      'socials': <dynamic>[],
      'ibscbsAssessmentNotice': notice,
    };

const _approvedText = 'Este estabelecimento tem uma opção de apuração do IBS/CBS a partir de 01/07/2027 que só vale para o '
    'Simples Nacional. O faturamento a partir dessa data será recusado até essa opção ser excluída ou trocada.';

EstablishmentBloc _bloc(_Client client) {
  final repo = EstablishmentRepositoryImpl(datasource: EstablishmentDatasourceImpl(client: client));
  return EstablishmentBloc(get: EstablishmentGet(repository: repo), put: EstablishmentPut(repository: repo));
}

void main() {
  setUpAll(() {
    final json = jsonDecode(File('assets/translations/pt.json').readAsStringSync()) as Map<String, dynamic>;
    Localization.load(const Locale('pt'), translations: Translations(json));
  });

  group('leitura do PUT', () {
    test('com o aviso: a data ISO da 1ª linha futura', () {
      final saved = EstablishmentSaved.fromJson(_putData(notice: {'validFrom': '2027-07-01'}));
      expect(saved.ibscbsNoticeFrom, '2027-07-01');
      expect(saved.establishment.simplesRegime, '1');
    });

    test('sem o aviso (null ou ausente — API sem a D-IB105): nenhuma data', () {
      expect(EstablishmentSaved.fromJson(_putData()).ibscbsNoticeFrom, isNull);
      expect(EstablishmentSaved.fromJson(_putData()..remove('ibscbsAssessmentNotice')).ibscbsNoticeFrom, isNull);
    });

    test('aviso malformado não derruba o salvamento: vira sem aviso', () {
      expect(EstablishmentSaved.fromJson(_putData(notice: {'validFrom': '01/07/2027'})).ibscbsNoticeFrom, isNull);
      expect(EstablishmentSaved.fromJson(_putData(notice: {'validFrom': 20270701})).ibscbsNoticeFrom, isNull);
      expect(EstablishmentSaved.fromJson(_putData(notice: '2027-07-01')).ibscbsNoticeFrom, isNull);
    });
  });

  group('bloc: tirar do Simples (3 → 1) com opção futura 2/3', () {
    test('o salvamento SEGUE: sucesso com a data do aviso e o rascunho gravado', () async {
      final client = _Client();
      when(() => client.put('/api/establishment', any()))
          .thenAnswer((_) async => {'ok': true, 'data': _putData(notice: {'validFrom': '2027-07-01'})});
      final bloc = _bloc(client);
      final states = <EstablishmentState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const EstablishmentSaveRequested(ObjectEstablishment(nameCompany: 'Setes Ltda', simplesRegime: '1')));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(states.whereType<EstablishmentActionFailure>(), isEmpty);
      final success = states.whereType<EstablishmentActionSuccess>().single;
      expect(success.messageKey, 'register.saved');
      expect(success.ibscbsNoticeFrom, '2027-07-01');
      final panel = states.last as EstablishmentPanelState;
      expect(panel.saving, isFalse);
      expect(panel.draft?.simplesRegime, '1');
      verify(() => client.put('/api/establishment', any())).called(1);
      await sub.cancel();
      await bloc.close();
    });

    test('sem linha futura 2/3: sucesso sem aviso', () async {
      final client = _Client();
      when(() => client.put('/api/establishment', any()))
          .thenAnswer((_) async => {'ok': true, 'data': _putData()});
      final bloc = _bloc(client);
      final states = <EstablishmentState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const EstablishmentSaveRequested(ObjectEstablishment(nameCompany: 'Setes Ltda', simplesRegime: '1')));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(states.whereType<EstablishmentActionSuccess>().single.ibscbsNoticeFrom, isNull);
      await sub.cancel();
      await bloc.close();
    });
  });

  group('tela: desfecho do salvar', () {
    Future<void> fire(WidgetTester tester, EstablishmentActionSuccess state) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEstablishmentSavedFeedback(context, state),
              child: const Text('salvar'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('salvar'));
      await tester.pumpAndSettle();
    }

    testWidgets('com a data: salvo (SnackBar) + aviso NÃO bloqueante com o texto aprovado e a data dd/mm/aaaa',
        (tester) async {
      await fire(tester, const EstablishmentActionSuccess('register.saved', ibscbsNoticeFrom: '2027-07-01'));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_approvedText), findsOneWidget);
      // Não bloqueia: só OK fecha o aviso — nenhuma pergunta, nada a desfazer.
      expect(find.text('register.yes'.tr()), findsNothing);
      await tester.tap(find.text('register.ok'.tr()));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('sem a data: só o SnackBar de salvo', (tester) async {
      await fire(tester, const EstablishmentActionSuccess('register.saved'));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
