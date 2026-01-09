import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/screens/auth/login_screen.dart';
import 'package:qoomy/screens/auth/register_screen.dart';
import 'package:qoomy/screens/home/home_screen.dart';
import 'package:qoomy/screens/room/create_room_screen.dart';
import 'package:qoomy/screens/room/join_room_screen.dart';
import 'package:qoomy/screens/room/lobby_screen.dart';
import 'package:qoomy/screens/game/game_screen.dart';
import 'package:qoomy/screens/game/results_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!isLoggedIn && !isAuthRoute) {
        return '/login';
      }

      if (isLoggedIn && isAuthRoute) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/create-room',
        builder: (context, state) => const CreateRoomScreen(),
      ),
      GoRoute(
        path: '/join-room',
        builder: (context, state) => const JoinRoomScreen(),
      ),
      GoRoute(
        path: '/lobby/:roomCode',
        builder: (context, state) {
          final roomCode = state.pathParameters['roomCode']!;
          return LobbyScreen(roomCode: roomCode);
        },
      ),
      GoRoute(
        path: '/game/:roomCode',
        builder: (context, state) {
          final roomCode = state.pathParameters['roomCode']!;
          return GameScreen(roomCode: roomCode);
        },
      ),
      GoRoute(
        path: '/results/:roomCode',
        builder: (context, state) {
          final roomCode = state.pathParameters['roomCode']!;
          return ResultsScreen(roomCode: roomCode);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.error}'),
      ),
    ),
  );
});
