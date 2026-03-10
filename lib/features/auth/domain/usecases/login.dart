import '../../../../core/usecases/usecase.dart';
import '../repositories/auth_repository.dart';

class Login implements UseCase<void, LoginParams> {
  final AuthRepository repository;
  Login(this.repository);

  @override
  Future<void> call(LoginParams params) async {
    await repository.signIn(params.usernameOrEmail, params.password);
  }
}

class LoginParams {
  final String usernameOrEmail;
  final String password;
  LoginParams({required this.usernameOrEmail, required this.password});
}
