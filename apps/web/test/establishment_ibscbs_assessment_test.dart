// Aba AUTÔNOMA "Regime IBS/CBS" do Meu Estabelecimento (fase IBS/CBS,
// D-IB99/D-IB100): a opção de apuração do IBS/CBS do Simples, datada.
// Entidade (leitura estrita, sugestão de data, pendências que espelham a
// regra da API) e a seção com datasource FALSO: vale hoje, aviso de recusa do
// faturamento com o regime regular, só a linha FUTURA muda, registrar com as
// pendências pela PONTE, rótulo do cliente pelo motor de campos.

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
// Carga direta das traduções no teste (sem o widget EasyLocalization) —
// Localization/Translations não saem pelo barrel do pacote.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setes_web/app/modules/establishment/data/datasource/establishment_ibscbs_assessment_datasource.dart';
import 'package:setes_web/app/modules/establishment/domain/entity/establishment_ibscbs_assessment_entity.dart';
import 'package:setes_web/app/modules/establishment/presentation/widget/establishment_ibscbs_assessment_section.dart';
import 'package:setes_web/app/shared/field_config/entity/field_config_entity.dart';

Map<String, dynamic> _viewJson({
  String today = '2026-11-01',
  String? lastInvoice,
  String? firstStart,
  bool regularAllowed = true,
  String? simplesRegime = '3',
  Map<String, dynamic> current = const {'assessment': '1', 'validFrom': null, 'supported': true},
  List<Map<String, dynamic>> items = const [],
}) =>
    {
      'today': today,
      'lastInvoice': lastInvoice,
      'firstStart': firstStart ?? today,
      'simplesRegime': simplesRegime,
      'regularAllowed': regularAllowed,
      'regularStart': '2027-01-01',
      'supported': ['1'],
      'current': current,
      'items': items,
    };

class _FakeDatasource implements EstablishmentIbscbsAssessmentDatasource {
  _FakeDatasource(this.json);

  Map<String, dynamic> json;
  final calls = <String>[];
  Failure? failOn;

  IbscbsAssessmentView get _view => IbscbsAssessmentView.fromJson(json);

  @override
  Future<IbscbsAssessmentView> get() async {
    calls.add('get');
    return _view;
  }

  @override
  Future<IbscbsAssessmentView> create(
      {required String validFrom, required String assessment}) async {
    if (failOn != null) throw failOn!;
    calls.add('create:$validFrom:$assessment');
    json = _viewJson(items: [
      {'validFrom': validFrom, 'assessment': assessment, 'supported': assessment == '1', 'inEffect': false, 'editable': true},
    ]);
    return _view;
  }

  /// Falha só do change (a recusa de uma LINHA — D-IB101).
  Failure? failChange;

  @override
  Future<IbscbsAssessmentView> change(String validFrom,
      {required String assessment}) async {
    if (failChange != null) throw failChange!;
    calls.add('change:$validFrom:$assessment');
    return _view;
  }

  @override
  Future<IbscbsAssessmentView> remove(String validFrom) async {
    calls.add('remove:$validFrom');
    json = _viewJson();
    return _view;
  }
}

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );

Future<void> _pump(WidgetTester tester, _FakeDatasource ds,
    {List<FieldConfigEntity> fieldConfig = const []}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_wrap(EstablishmentIbscbsAssessmentSection(
      datasource: ds, fieldConfig: fieldConfig)));
  await tester.pumpAndSettle();
}

Finder _button(String text, {int index = 0}) => find
    .ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
    .at(index);

Future<void> _choose(WidgetTester tester, String label, String option, {int index = 0}) async {
  await tester.tap(find.text(label).at(index));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    final json = jsonDecode(File('assets/translations/pt.json').readAsStringSync())
        as Map<String, dynamic>;
    Localization.load(const Locale('pt'), translations: Translations(json));
  });

  group('entidade', () {
    test('leitura estrita: tipo trocado LANÇA (o datasource vira falha de leitura)', () {
      final view = IbscbsAssessmentView.fromJson(_viewJson(items: [
        {'validFrom': '2027-01-01', 'assessment': '3', 'supported': false, 'inEffect': false, 'editable': true},
      ]));
      expect(view.currentValidFrom, isNull);
      expect(view.items.single.editable, isTrue);
      expect(() => IbscbsAssessmentView.fromJson(const {}), throwsA(anything));
      expect(() => IbscbsAssessmentView.fromJson({..._viewJson(), 'items': 'x'}), throwsA(anything));
    });

    test('sugestão = próximo início de semestre (só sugestão — a data é livre)', () {
      expect(suggestedAssessmentStart('2026-11-01'), '2027-01-01');
      expect(suggestedAssessmentStart('2027-01-01'), '2027-01-01');
      expect(suggestedAssessmentStart('2027-03-10'), '2027-07-01');
      expect(suggestedAssessmentStart('2027-07-02'), '2028-01-01');
    });

    test('D-IB101: início ≤ a última nota = pendência própria; o 1º início aceito vem da API', () {
      final view = IbscbsAssessmentView.fromJson(
          _viewJson(lastInvoice: '2027-01-05', firstStart: '2027-01-06', today: '2027-01-01'));
      expect(view.lastInvoice, '2027-01-05');
      expect(view.firstStart, '2027-01-06');
      expect(view.pendencyFor('2027-01-05', '1'), 'forms.establishment.ibscbsDateInvoiced');
      expect(view.pendencyFor('2027-01-06', '1'), isNull);
      expect(() => IbscbsAssessmentView.fromJson({..._viewJson(), 'firstStart': null}), throwsA(anything));
      // ADV-D102-02: sem `regularAllowed` é falha de LEITURA (nunca "não informado" inventado para um ME/EPP)
      expect(() => IbscbsAssessmentView.fromJson({..._viewJson()}..remove('regularAllowed')), throwsA(anything));
    });

    test('D-IB102: sem ME/EPP nem pendente, 2/3 viram pendência própria; a 1 passa', () {
      final view = IbscbsAssessmentView.fromJson(_viewJson(regularAllowed: false, simplesRegime: '1'));
      expect(view.regularAllowed, isFalse);
      expect(view.pendencyFor('2027-01-01', '3'), 'forms.establishment.ibscbsRegularNotSimples');
      expect(view.pendencyFor('2027-01-01', '1'), isNull);
    });

    test('pendências espelham a regra da API (data real, hoje, piso do regular)', () {
      final view = IbscbsAssessmentView.fromJson(_viewJson());
      expect(view.pendencyFor('2027-01-01', '3'), isNull);
      expect(view.pendencyFor('2026-11-01', '1'), isNull);
      expect(view.pendencyFor(null, '1'), 'forms.establishment.ibscbsDateInvalid');
      expect(view.pendencyFor('2027-02-30', '1'), 'forms.establishment.ibscbsDateInvalid');
      expect(view.pendencyFor('2027-01-01', null), 'forms.establishment.ibscbsAssessmentRequired');
      expect(view.pendencyFor('2026-10-31', '1'), 'forms.establishment.ibscbsDatePast');
      expect(view.pendencyFor('2026-12-01', '2'), 'forms.establishment.ibscbsRegularTooEarly');
    });

    test('aviso: opção sem suporte vigente ou futura (a passada encerrada não conta)', () {
      expect(IbscbsAssessmentView.fromJson(_viewJson()).firstUnsupported, isNull);
      final future = IbscbsAssessmentView.fromJson(_viewJson(items: [
        {'validFrom': '2027-01-01', 'assessment': '3', 'supported': false, 'inEffect': false, 'editable': true},
      ]));
      expect(future.firstUnsupported?.validFrom, '2027-01-01');
      final ended = IbscbsAssessmentView.fromJson(_viewJson(today: '2027-08-01', items: [
        {'validFrom': '2027-01-01', 'assessment': '3', 'supported': false, 'inEffect': false, 'editable': false},
        {'validFrom': '2027-07-01', 'assessment': '1', 'supported': true, 'inEffect': true, 'editable': false},
      ]));
      expect(ended.firstUnsupported, isNull);
    });
  });

  group('seção', () {
    testWidgets('sem opção: vale a apuração pelo Simples, sem aviso, data sugerida', (tester) async {
      final ds = _FakeDatasource(_viewJson());
      await _pump(tester, ds);
      expect(ds.calls, ['get']);
      expect(find.text('Vale hoje: 1 — IBS e CBS apurados pelo Simples Nacional (sem opção registrada)'), findsOneWidget);
      expect(find.textContaining('será RECUSADO'), findsNothing);
      expect(find.text('Nenhuma opção registrada.'), findsOneWidget);
      expect(find.text('01/01/2027'), findsOneWidget);   // sugestão no campo
    });

    testWidgets('opção 3 futura: aviso da recusa, linha editável (salvar/excluir)', (tester) async {
      final ds = _FakeDatasource(_viewJson(items: [
        {'validFrom': '2027-01-01', 'assessment': '3', 'supported': false, 'inEffect': false, 'editable': true},
      ]));
      await _pump(tester, ds);
      expect(find.text('A partir de 01/01/2027 o faturamento será RECUSADO: o regime regular de IBS/CBS ainda não é suportado pelo sistema.'),
          findsOneWidget);
      expect(find.text('01/01/2027 · futura'), findsOneWidget);
      expect(find.text('regime regular — ainda não suportado'), findsOneWidget);
      await tester.tap(_button('Excluir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir').last);   // confirma a decisão
      await tester.pumpAndSettle();
      expect(ds.calls, contains('remove:2027-01-01'));
    });

    testWidgets('linha vigente/encerrada é só leitura (a API diz editable=false)', (tester) async {
      final ds = _FakeDatasource(_viewJson(
        today: '2027-03-01',
        current: const {'assessment': '1', 'validFrom': '2026-11-05', 'supported': true},
        items: [
          {'validFrom': '2026-11-05', 'assessment': '1', 'supported': true, 'inEffect': true, 'editable': false},
        ],
      ));
      await _pump(tester, ds);
      expect(find.text('05/11/2026 · vigente'), findsOneWidget);
      expect(find.text('Excluir'), findsNothing);
      expect(find.text('Salvar'), findsNothing);
    });

    testWidgets('registrar: pendência pela ponte ANTES da API (regular antes de 2027); válido chama create', (tester) async {
      final ds = _FakeDatasource(_viewJson());
      await _pump(tester, ds);
      await tester.enterText(find.widgetWithText(TextFormField, 'Início da opção (dd/mm/aaaa)'), '01/12/2026');
      await _choose(tester, 'Opção de apuração', '3 — IBS e CBS apurados pelo regime regular');
      await tester.tap(_button('Registrar'));
      await tester.pumpAndSettle();
      expect(find.text('O regime regular (opção 2 ou 3) só pode valer a partir de 01/01/2027'), findsOneWidget);
      expect(ds.calls, ['get']);
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Início da opção (dd/mm/aaaa)'), '01/01/2027');
      // o ato que BLOQUEIA o faturamento pede decisão explícita (gate socrático, LOW 5) — cancelar não envia
      await tester.tap(_button('Registrar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('o faturamento será RECUSADO a partir de 01/01/2027'), findsOneWidget);
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
      expect(ds.calls, ['get']);
      await tester.tap(_button('Registrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar').last);
      await tester.pumpAndSettle();
      expect(ds.calls, ['get', 'create:2027-01-01:3']);
    });

    testWidgets('registrar a opção suportada (1) não pede confirmação', (tester) async {
      final ds = _FakeDatasource(_viewJson());
      await _pump(tester, ds);
      await _choose(tester, 'Opção de apuração', '1 — IBS e CBS apurados pelo Simples Nacional');
      await tester.tap(_button('Registrar'));
      await tester.pumpAndSettle();
      expect(ds.calls, ['get', 'create:2027-01-01:1']);
    });

    testWidgets('falha da API sai pela ponte; a seção segue utilizável', (tester) async {
      final ds = _FakeDatasource(_viewJson())
        ..failOn = const Failure(message: 'Já existe opção de apuração do IBS/CBS a partir de 2027-01-01 — altere a existente',
            code: 'IBSCBS_ASSESSMENT_DUPLICATE');
      await _pump(tester, ds);
      await _choose(tester, 'Opção de apuração', '1 — IBS e CBS apurados pelo Simples Nacional');
      await tester.tap(_button('Registrar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Já existe opção de apuração'), findsOneWidget);
    });

    testWidgets('D-IB101: a sugestão parte do 1º início aceito (dia seguinte à última nota)', (tester) async {
      final ds = _FakeDatasource(_viewJson(today: '2027-03-10', lastInvoice: '2027-03-10', firstStart: '2027-03-11'));
      await _pump(tester, ds);
      expect(find.text('01/07/2027'), findsOneWidget);   // próximo início de semestre a partir de 11/03/2027
    });

    testWidgets('D-IB101 (ADV-D101-05): a recusa de uma LINHA não leva o foco ao campo do registro novo', (tester) async {
      final ds = _FakeDatasource(_viewJson(items: [
        {'validFrom': '2027-01-01', 'assessment': '1', 'supported': true, 'inEffect': false, 'editable': true},
      ]))
        ..failChange = const Failure(message: 'Já existe nota emitida em 2027-01-01 …', code: 'IBSCBS_ASSESSMENT_INVOICED',
            fields: [FailureField(field: 'validFrom', message: 'Depois de 2027-01-01')]);
      await _pump(tester, ds);
      await tester.tap(_button('Salvar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      final field = tester.widget<EditableText>(find.descendant(
          of: find.widgetWithText(TextFormField, 'Início da opção (dd/mm/aaaa)'), matching: find.byType(EditableText)));
      expect(field.focusNode.hasFocus, isFalse);
      expect(ds.calls.where((c) => c == 'get').length, 2);   // ADV-D102-04: a recusa relê a visão
    });

    testWidgets('D-IB102: quem não é do Simples vê o porquê e o registro de 3 para na pendência (nada vai à API)', (tester) async {
      final ds = _FakeDatasource(_viewJson(regularAllowed: false, simplesRegime: '1'));
      await _pump(tester, ds);
      expect(find.textContaining('Regime do Simples gravado: não optante'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Início da opção (dd/mm/aaaa)'), '01/01/2027');
      await _choose(tester, 'Opção de apuração', '3 — IBS e CBS apurados pelo regime regular');
      await tester.tap(_button('Registrar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('só para optante do Simples Nacional ME/EPP'), findsOneWidget);
      expect(ds.calls, ['get']);
    });

    testWidgets('salvar o estabelecimento relê a visão (regularAllowed passa a valer) SEM apagar o rascunho', (tester) async {
      final ds = _FakeDatasource(_viewJson(regularAllowed: false, simplesRegime: '1'));
      Widget host(int epoch) => _wrap(EstablishmentIbscbsAssessmentSection(datasource: ds, refreshEpoch: epoch));
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(0));
      await tester.pumpAndSettle();
      expect(find.textContaining('Regime do Simples gravado: não optante'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Início da opção (dd/mm/aaaa)'), '01/07/2027');
      ds.json = _viewJson();                                    // o admin gravou ME/EPP na aba Principal
      await tester.pumpWidget(host(1));
      await tester.pumpAndSettle();
      expect(ds.calls.where((c) => c == 'get').length, 2);
      expect(find.textContaining('Regime do Simples gravado'), findsNothing);
      expect(find.text('01/07/2027'), findsOneWidget);          // o rascunho ficou
    });

    testWidgets('motor de campos: o rótulo do cliente substitui o padrão do app', (tester) async {
      final ds = _FakeDatasource(_viewJson());
      await _pump(tester, ds, fieldConfig: const [
        FieldConfigEntity(fieldName: 'valid_from', kind: 'Date', requiredTech: true, required: true, caption: 'Vigência a partir de'),
      ]);
      expect(find.widgetWithText(TextFormField, 'Vigência a partir de'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Início da opção (dd/mm/aaaa)'), findsNothing);
    });
  });
}
