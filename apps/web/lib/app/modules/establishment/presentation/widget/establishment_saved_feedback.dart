import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

import '../../../../shared/entity/widgets/entity_date.dart';
import '../../../../shared/feedback/feedback.dart';
import '../bloc/establishment_bloc.dart';

/// Desfecho do salvar do estabelecimento pela PONTE (Framework de
/// Mensagens): sucesso = SnackBar (R1) e, quando o salvamento TIROU o
/// estabelecimento do Simples com opção de apuração 2/3 futura (D-IB105),
/// o aviso NÃO bloqueante (dialog info) com a data da 1ª linha futura em
/// dd/mm/aaaa. O salvamento já seguiu — o aviso só informa.
void showEstablishmentSavedFeedback(
    BuildContext context, EstablishmentActionSuccess state) {
  showSuccessFeedback(context, state.messageKey);
  final noticeFrom = state.ibscbsNoticeFrom;
  if (noticeFrom == null) return;
  showInfoFeedback(
    context,
    'forms.establishment.ibscbsLeftSimplesNotice'
        .tr(args: [isoDateToDisplay(noticeFrom)]),
  );
}
