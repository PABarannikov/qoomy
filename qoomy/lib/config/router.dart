import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qoomy/providers/auth_provider.dart';
import 'package:qoomy/providers/team_provider.dart';
import 'package:qoomy/providers/room_provider.dart';
import 'package:qoomy/screens/auth/login_screen.dart';
import 'package:qoomy/screens/auth/register_screen.dart';
import 'package:qoomy/screens/home/home_screen.dart';
import 'package:qoomy/screens/room/create_room_screen.dart';
import 'package:qoomy/screens/room/join_room_screen.dart';
import 'package:qoomy/screens/room/lobby_screen.dart';
import 'package:qoomy/screens/game/game_screen.dart';
import 'package:qoomy/screens/game/results_screen.dart';
import 'package:qoomy/screens/team/teams_list_screen.dart';
import 'package:qoomy/screens/team/create_team_screen.dart';
import 'package:qoomy/screens/team/team_details_screen.dart';
import 'package:qoomy/screens/team/join_team_screen.dart';
import 'package:qoomy/screens/admin/admin_screen.dart';
import 'package:qoomy/screens/profile/profile_screen.dart';
import 'package:qoomy/screens/welcome/welcome_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.valueOrNull;

  // Watch teams for logged in user to detect new users
  final userTeams = user != null
      ? ref.watch(userTeamsProvider(user.uid))
      : const AsyncValue<List<dynamic>>.data([]);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = user != null;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      final isJoinTeamRoute = state.matchedLocation.startsWith('/join-team/');
      final isWelcomeRoute = state.matchedLocation == '/welcome';

      // If user is not logged in and trying to join a team via deep link,
      // store the invite code and redirect to login
      if (!isLoggedIn && isJoinTeamRoute) {
        final inviteCode = state.pathParameters['inviteCode'];
        if (inviteCode != null) {
          ref.read(pendingTeamInviteProvider.notifier).state = inviteCode;
        }
        return '/login';
      }

      if (!isLoggedIn && !isAuthRoute) {
        return '/login';
      }

      // If logged in and on auth route, check for pending team invite
      if (isLoggedIn && isAuthRoute) {
        final pendingInvite = ref.read(pendingTeamInviteProvider);
        if (pendingInvite != null) {
          return '/join-team/$pendingInvite';
        }
        // Check if user has teams - if not, show welcome screen
        final teams = userTeams.valueOrNull ?? [];
        if (teams.isEmpty) {
          return '/welcome';
        }
        return '/';
      }

      // If logged in, going to home, and has no teams - show welcome
      // But not if user has already skipped welcome screen
      if (isLoggedIn && state.matchedLocation == '/' && !isWelcomeRoute) {
        final welcomeSkipped = ref.read(welcomeSkippedProvider);
        if (!welcomeSkipped) {
          final teams = userTeams.valueOrNull;
          // Only redirect if we have loaded teams data and it's empty
          if (teams != null && teams.isEmpty) {
            return '/welcome';
          }
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
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
      GoRoute(
        path: '/teams',
        builder: (context, state) => const TeamsListScreen(),
      ),
      GoRoute(
        path: '/teams/create',
        builder: (context, state) => const CreateTeamScreen(),
      ),
      GoRoute(
        path: '/teams/:teamId',
        builder: (context, state) {
          final teamId = state.pathParameters['teamId']!;
          return TeamDetailsScreen(teamId: teamId);
        },
      ),
      GoRoute(
        path: '/join-team',
        builder: (context, state) => const JoinTeamScreen(),
      ),
      GoRoute(
        path: '/join-team/:inviteCode',
        builder: (context, state) {
          final inviteCode = state.pathParameters['inviteCode']!;
          return JoinTeamScreen(initialCode: inviteCode);
        },
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.error}'),
      ),
    ),
  );
});
