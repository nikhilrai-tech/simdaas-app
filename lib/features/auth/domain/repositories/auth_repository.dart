import '../entities/user.dart';

abstract class AuthRepository {
  Future<User> signIn(String usernameOrEmail, String password);
  Future<void> logout();
}
