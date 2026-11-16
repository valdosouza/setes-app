import 'package:core/core.dart';
import 'package:dartz/dartz.dart';

import '../entity/establishment_saved.dart';
import '../entity/object_establishment.dart';
import '../repository/establishment_repository.dart';

class EstablishmentPut {
  const EstablishmentPut({required this.repository});

  final EstablishmentRepository repository;

  Future<Either<Failure, EstablishmentSaved>> call(
          ObjectEstablishment establishment) =>
      repository.put(establishment);
}
