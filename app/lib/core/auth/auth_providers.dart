import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/auth_repository.dart';

/// The initialized Supabase client. Only valid after `bootstrap()` calls
/// `Supabase.initialize` (i.e. when env config is present).
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

/// Streams Supabase auth state changes (sign-in/out/token-refresh).
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Convenience: the current user, or null when signed out.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(authRepositoryProvider).currentUser;
});

/// The signed-in user's email, or null when browsing as a guest. Lets the UI
/// read auth state without constructing a Supabase [User] (and stays easily
/// overridable in tests).
final signedInEmailProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.email;
});
