part of 'establishment_bloc.dart';

abstract class EstablishmentState extends Equatable {
  const EstablishmentState();

  @override
  List<Object?> get props => [];
}

/// Estado BUILDÁVEL único (não há lista): [loading] = carregando o GET
/// inicial; [draft] null + !loading = falha no GET (tela de erro com
/// retry); [saving] = PUT em andamento (desabilita as ações do shell).
class EstablishmentPanelState extends EstablishmentState {
  const EstablishmentPanelState({
    this.loading = false,
    this.saving = false,
    this.draft,
  });

  final bool loading;
  final bool saving;
  final ObjectEstablishment? draft;

  @override
  List<Object?> get props => [loading, saving, draft];
}

/// One-shot para a ponte de feedback (Framework de Mensagens) — sucesso =
/// SnackBar (R1). [ibscbsNoticeFrom] (ISO, D-IB105): o salvamento tirou o
/// estabelecimento do Simples e há opção de apuração 2/3 a partir dessa
/// data — a página soma ao SnackBar o aviso NÃO bloqueante (dialog info).
class EstablishmentActionSuccess extends EstablishmentState {
  const EstablishmentActionSuccess(this.messageKey, {this.ibscbsNoticeFrom});

  final String messageKey;
  final String? ibscbsNoticeFrom;

  @override
  List<Object?> get props => [messageKey, ibscbsNoticeFrom];
}

/// One-shot de falha — a página decide dialog genérico ou ancorar
/// fields[] no campo (showServerFieldError).
class EstablishmentActionFailure extends EstablishmentState {
  const EstablishmentActionFailure(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}
