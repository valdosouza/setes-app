import 'package:core/core.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:setes_widgets/setes_widgets.dart';

import '../../../../shared/entity/widgets/entity_date.dart';
import '../../../../shared/feedback/feedback.dart';
import '../../../../shared/field_config/entity/field_config_entity.dart';
import '../../../../shared/field_config/field_config_of.dart';
import '../../data/datasource/establishment_ibscbs_assessment_datasource.dart';
import '../../domain/entity/establishment_ibscbs_assessment_entity.dart';

/// Aba AUTÔNOMA "Regime IBS/CBS" do Meu Estabelecimento (fase IBS/CBS,
/// D-IB99/D-IB100 — prompt_fase_ibs_cbs.md §14): a OPÇÃO de apuração do
/// IBS/CBS do Simples (`regApIBSCBSSN`), datada. Mesmo padrão da aba "Emissor
/// fiscal": datasource próprio do sub-recurso, botões próprios, fala SÓ com a
/// PONTE de feedback — o check do shell não a salva.
///
/// - Vale hoje: a opção vigente (sem linha = IBS e CBS pelo Simples — D-IB1).
/// - Aviso quando há opção sem suporte (2/3) vigente ou futura: o faturamento
///   é RECUSADO a partir da data dela (nunca uma nota errada — D-IB99).
/// - Histórico: só a linha FUTURA muda (alterar/excluir) — `editable` da API.
/// - Registrar: data (sugestão = próximo 01/01 ou 01/07) + opção; pendências
///   espelham a regra da API ANTES do envio (a recusa definitiva é dela).
/// - Motor de campos (D-CF4): rótulo do cliente pelo catálogo da interface
///   `establishment` (`valid_from`, `assessment` — seed sql/71).
class EstablishmentIbscbsAssessmentSection extends StatefulWidget {
  const EstablishmentIbscbsAssessmentSection({
    required this.datasource,
    this.fieldConfig = const [],
    this.refreshEpoch = 0,
    super.key,
  });

  final EstablishmentIbscbsAssessmentDatasource datasource;

  /// Config resolvida da interface `establishment` (FieldConfigLoader da página).
  final List<FieldConfigEntity> fieldConfig;

  /// Muda quando a página salva o estabelecimento (o regime do Simples da aba
  /// Principal decide a D-IB102) — a seção relê a visão (ADV-D102-04).
  final int refreshEpoch;

  @override
  State<EstablishmentIbscbsAssessmentSection> createState() =>
      _EstablishmentIbscbsAssessmentSectionState();
}

class _EstablishmentIbscbsAssessmentSectionState
    extends State<EstablishmentIbscbsAssessmentSection> {
  IbscbsAssessmentView? _view;
  bool _loading = true;
  bool _busy = false;

  final _validFrom = TextEditingController();
  final _validFromFocus = FocusNode();
  String? _assessment;

  /// Troca da opção nas linhas futuras (validFrom → opção escolhida).
  final _pending = <String, String>{};

  /// Recria os Dropdowns quando a visão do servidor chega.
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EstablishmentIbscbsAssessmentSection old) {
    super.didUpdateWidget(old);
    // relê SEM apagar o rascunho (data digitada, opção escolhida, trocas pendentes) — re-prova do gate, LOW
    if (old.refreshEpoch != widget.refreshEpoch) _refreshQuietly();
  }

  @override
  void dispose() {
    _validFrom.dispose();
    _validFromFocus.dispose();
    super.dispose();
  }

  void _apply(IbscbsAssessmentView view) {
    _view = view;
    _epoch++;
    _pending.clear();
    _validFrom.text = isoDateToDisplay(suggestedAssessmentStart(view.firstStart));
    _assessment = null;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    IbscbsAssessmentView? view;
    Failure? failure;
    try {
      view = await widget.datasource.get();
    } on Failure catch (f) {
      failure = f;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (view != null) _apply(view);
    });
    if (failure != null) await showFailureFeedback(context, failure);
  }

  /// [focusDate]: só o REGISTRO tem o campo de data — a recusa de uma linha
  /// (alterar/excluir) nunca leva o foco para o campo do registro novo.
  Future<void> _run(Future<IbscbsAssessmentView> Function() action,
      String successKey, {bool focusDate = false}) async {
    setState(() => _busy = true);
    IbscbsAssessmentView? view;
    Failure? failure;
    try {
      view = await action();
    } on Failure catch (f) {
      failure = f;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (view != null) _apply(view);
    });
    if (failure != null) {
      await showFailureFeedback(context, failure);
      if (!mounted) return;
      if (focusDate && failure.fields.any((f) => f.field == 'validFrom')) {
        _validFromFocus.requestFocus();
      }
      await _refreshQuietly();   // ADV-D102-04: a recusa diz que a visão envelheceu (regime, última nota, linhas)
      return;
    }
    await showSuccessFeedback(context, successKey);
  }

  /// Relê a visão sem spinner nem dialog (depois de uma recusa): falhou, fica a
  /// que está — a recusa já foi mostrada pela ponte.
  Future<void> _refreshQuietly() async {
    try {
      final view = await widget.datasource.get();
      if (mounted) setState(() => _view = view);
    } on Failure {
      // a tela segue com a visão anterior
    }
  }

  // ------------------------------------------------------------------
  // Atos
  // ------------------------------------------------------------------

  Future<void> _register() async {
    final view = _view!;
    final validFrom = displayDateToIso(_validFrom.text);
    final pendency = view.pendencyFor(validFrom, _assessment);
    if (pendency != null) {
      await showValidationFeedback(context, _pendencyText(pendency));
      if (mounted && pendency != 'forms.establishment.ibscbsAssessmentRequired') {
        _validFromFocus.requestFocus();
      }
      return;
    }
    if (!await _confirmUnsupported(validFrom!, _assessment!)) return;
    await _run(
      () => widget.datasource.create(validFrom: validFrom, assessment: _assessment!),
      'forms.establishment.ibscbsSaved',
      focusDate: true,
    );
  }

  /// O ato que BLOQUEIA o faturamento a partir da data (regime regular ainda
  /// sem suporte — D-IB99) pede decisão explícita, como a exclusão.
  Future<bool> _confirmUnsupported(String validFrom, String assessment) async {
    if (_view!.supported.contains(assessment)) return true;
    final decision = await askDecision(
      context,
      message: 'forms.establishment.ibscbsUnsupportedConfirm'
          .tr(args: [isoDateToDisplay(validFrom)]),
      yesLabel: 'forms.establishment.ibscbsConfirm'.tr(),
    );
    return decision == SetesDecision.yes && mounted;
  }

  Future<void> _change(IbscbsAssessmentLine line) async {
    final assessment = _pending[line.validFrom] ?? line.assessment;
    final pendency = _view!.pendencyFor(line.validFrom, assessment);
    if (pendency != null) {
      await showValidationFeedback(context, _pendencyText(pendency));
      return;
    }
    if (!await _confirmUnsupported(line.validFrom, assessment)) return;
    await _run(
      () => widget.datasource.change(line.validFrom, assessment: assessment),
      'forms.establishment.ibscbsChanged',
    );
  }

  Future<void> _remove(IbscbsAssessmentLine line) async {
    final decision = await askDecision(
      context,
      message: 'forms.establishment.ibscbsRemoveConfirm'
          .tr(args: [isoDateToDisplay(line.validFrom)]),
      yesLabel: 'forms.establishment.ibscbsRemove'.tr(),
    );
    if (decision != SetesDecision.yes || !mounted) return;
    await _run(() => widget.datasource.remove(line.validFrom),
        'forms.establishment.ibscbsRemoved');
  }

  Future<void> _pickDate() async {
    final view = _view!;
    final currentIso = displayDateToIso(_validFrom.text);
    // o 1º início aceito (hoje ou o dia seguinte à última nota — D-IB101)
    final first = DateTime.parse(view.firstStart);
    final last = DateTime(first.year + 10, 12, 31);
    // a data digitada pode estar fora do intervalo do seletor (passada ou
    // longe demais) — o initialDate fora de [first, last] derruba o Flutter
    var initial = currentIso == null ? first : DateTime.parse(currentIso);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    final iso = '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    setState(() => _validFrom.text = isoDateToDisplay(iso));
  }

  // ------------------------------------------------------------------
  // Rótulos
  // ------------------------------------------------------------------

  String _pendencyText(String key) => key.tr(namedArgs: {
        'today': isoDateToDisplay(_view!.today),
        'start': isoDateToDisplay(_view!.regularStart),
        'invoice': isoDateToDisplay(_view!.lastInvoice),
        'first': isoDateToDisplay(_view!.firstStart),
      });

  String _assessmentLabel(String assessment) =>
      kIbscbsAssessments.contains(assessment)
          ? 'forms.establishment.ibscbsAssessment$assessment'.tr()
          : 'forms.establishment.ibscbsAssessmentUnknown'.tr(args: [assessment]);

  /// opSimpNac gravado, por extenso (D-IB102).
  String _simplesRegimeName(String? regime) => switch (regime) {
        '1' || '2' || '3' || '4' =>
          'forms.establishment.ibscbsSimplesRegime$regime'.tr(),
        _ => 'forms.establishment.ibscbsSimplesRegimeNone'.tr(),
      };

  /// Rótulo do cliente (motor de campos) ou o padrão do app.
  String _label(String field, String i18nKey) =>
      fieldConfigOf(widget.fieldConfig, field)?.caption ?? i18nKey.tr();

  // ------------------------------------------------------------------
  // Blocos
  // ------------------------------------------------------------------

  Widget _currentBlock(BuildContext context) {
    final view = _view!;
    final scheme = Theme.of(context).colorScheme;
    final since = view.currentValidFrom == null
        ? 'forms.establishment.ibscbsNoOption'.tr()
        : 'forms.establishment.ibscbsSince'
            .tr(args: [isoDateToDisplay(view.currentValidFrom)]);
    final unsupported = view.firstUnsupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetesText('forms.establishment.ibscbsCurrent'
            .tr(args: [_assessmentLabel(view.currentAssessment), since])),
        if (view.desktopEmission) ...[
          const SizedBox(height: 8),
          SetesText('forms.establishment.ibscbsDesktopEmissionHint'.tr()),
        ],
        if (!view.regularAllowed) ...[
          const SizedBox(height: 8),
          SetesText('forms.establishment.ibscbsRegularNotAllowedHint'
              .tr(args: [_simplesRegimeName(view.simplesRegime)])),
        ],
        if (unsupported != null) ...[
          const SizedBox(height: 8),
          SetesText(
            'forms.establishment.ibscbsUnsupportedWarning'
                .tr(args: [isoDateToDisplay(unsupported.validFrom)]),
            style: TextStyle(color: scheme.error),
          ),
        ],
      ],
    );
  }

  Widget _lineBlock(BuildContext context, IbscbsAssessmentLine line) {
    final scheme = Theme.of(context).colorScheme;
    final status = line.inEffect
        ? 'forms.establishment.ibscbsInEffect'.tr()
        : line.editable
            ? 'forms.establishment.ibscbsFuture'.tr()
            : 'forms.establishment.ibscbsEnded'.tr();
    final header = Row(
      children: [
        Expanded(
          child: SetesText(
            '${isoDateToDisplay(line.validFrom)} · $status',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (!line.supported)
          SetesText('forms.establishment.ibscbsNotSupported'.tr(),
              style: TextStyle(color: scheme.error, fontSize: 12)),
      ],
    );
    if (!line.editable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, SetesText(_assessmentLabel(line.assessment))],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 8),
        SetesDropdown<String>(
          key: ValueKey('ibscbsLine${line.validFrom}$_epoch'),
          label: _label('assessment', 'forms.establishment.ibscbsAssessment'),
          value: _pending[line.validFrom] ?? line.assessment,
          items: kIbscbsAssessments,
          itemLabel: _assessmentLabel,
          onChanged: (v) {
            if (v != null) setState(() => _pending[line.validFrom] = v);
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            SetesButton(
              label: 'forms.establishment.ibscbsChange'.tr(),
              icon: Icons.save_outlined,
              loading: _busy,
              onPressed: _busy ? null : () => _change(line),
            ),
            SetesButton(
              label: 'forms.establishment.ibscbsRemove'.tr(),
              kind: SetesButtonKind.secondary,
              loading: _busy,
              onPressed: _busy ? null : () => _remove(line),
            ),
          ],
        ),
      ],
    );
  }

  Widget _registerBlock(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SetesText('forms.establishment.ibscbsSuggestion'.tr()),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SetesTextField(
                  label: _label('valid_from', 'forms.establishment.ibscbsValidFrom'),
                  controller: _validFrom,
                  focusNode: _validFromFocus,
                  keyboardType: TextInputType.datetime,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                    LengthLimitingTextInputFormatter(10),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SetesIconButton(
                icon: Icons.calendar_month,
                tooltip: 'forms.establishment.ibscbsPickDate'.tr(),
                onPressed: _busy ? null : _pickDate,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SetesDropdown<String>(
            key: ValueKey('ibscbsNew$_epoch'),
            label: _label('assessment', 'forms.establishment.ibscbsAssessment'),
            value: _assessment,
            items: kIbscbsAssessments,
            itemLabel: _assessmentLabel,
            onChanged: (v) => setState(() => _assessment = v),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: SetesButton(
              label: 'forms.establishment.ibscbsRegister'.tr(),
              icon: Icons.add,
              loading: _busy,
              onPressed: _busy ? null : _register,
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
          padding: EdgeInsets.all(16),
          child: SetesCircularProgressIndicator());
    }
    final view = _view;
    if (view == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SetesButton(
            label: 'register.retry'.tr(),
            icon: Icons.refresh,
            onPressed: _load,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetesCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SetesText.title('forms.establishment.ibscbsSection'.tr()),
              const SizedBox(height: 4),
              SetesText('forms.establishment.ibscbsHelp'.tr()),
              const SizedBox(height: 16),
              _currentBlock(context),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SetesCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SetesText.title('forms.establishment.ibscbsHistory'.tr()),
              const SizedBox(height: 12),
              if (view.items.isEmpty)
                SetesText('forms.establishment.ibscbsHistoryEmpty'.tr()),
              for (final (i, line) in view.items.indexed) ...[
                if (i > 0) const Divider(height: 24),
                _lineBlock(context, line),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SetesCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SetesText.title('forms.establishment.ibscbsNewSection'.tr()),
              const SizedBox(height: 12),
              _registerBlock(context),
            ],
          ),
        ),
      ],
    );
  }
}
