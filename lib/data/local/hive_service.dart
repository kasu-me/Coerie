import 'package:hive_flutter/hive_flutter.dart';
import '../models/draft_model.dart';
import '../models/account_model.dart';
import '../../core/constants/app_constants.dart';

class HiveService {
  HiveService._();

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(DraftModelAdapter());
    Hive.registerAdapter(AccountModelAdapter());
    await Hive.openBox<DraftModel>(AppConstants.draftsBox);
    await Hive.openBox<AccountModel>(AppConstants.accountsBox);
  }

  static Box<DraftModel> get draftsBox =>
      Hive.box<DraftModel>(AppConstants.draftsBox);

  static Box<AccountModel> get accountsBox =>
      Hive.box<AccountModel>(AppConstants.accountsBox);
}
