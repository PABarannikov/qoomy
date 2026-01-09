# Qoomy - Quiz Game

A real-time quiz game built with Flutter and Firebase, featuring AI-powered answer evaluation.

## Features

- Create quiz rooms with custom questions
- Real-time chat with answers and comments
- Two evaluation modes:
  - **Manual:** Host marks answers as correct/wrong
  - **AI Mode:** Claude AI automatically evaluates answers
- Score tracking and leaderboard
- Works on web, Android, and iOS

## Tech Stack

- **Frontend:** Flutter 3.x
- **Backend:** Firebase (Firestore, Auth, Functions, Hosting)
- **AI:** Anthropic Claude API (claude-3-haiku)
- **State Management:** Riverpod
- **Routing:** GoRouter

## Project Structure

```
qoomy/
├── lib/
│   ├── config/           # Theme, constants
│   ├── models/           # Data models
│   ├── providers/        # Riverpod providers
│   ├── screens/          # UI screens
│   │   ├── auth/         # Login, Register
│   │   ├── home/         # Home screen
│   │   ├── room/         # Create, Join, Lobby
│   │   └── game/         # Host, Player, Results
│   ├── services/         # Firebase services
│   └── main.dart
├── functions/            # Cloud Functions
│   └── index.js          # AI evaluation functions
├── firebase.json         # Firebase config
└── firestore.rules       # Security rules
```

## Getting Started

### Prerequisites

- Flutter SDK 3.x
- Firebase CLI
- Node.js 20+

### Installation

1. Clone the repository
2. Install Flutter dependencies:
   ```bash
   cd qoomy
   flutter pub get
   ```
3. Install Cloud Functions dependencies:
   ```bash
   cd functions
   npm install
   ```

### Running Locally

```bash
flutter run -d chrome
```

### Deployment

See [HOSTING.md](HOSTING.md) for deployment instructions.

## Game Flow

1. **Host** creates a room with a question and correct answer
2. **Host** chooses evaluation mode (Manual or AI)
3. **Players** join using room code
4. **Host** starts the game
5. **Players** send answers in chat
6. Answers are evaluated (by host or AI)
7. **Host** ends game to show results

## AI Evaluation

In AI mode, Claude evaluates answers with generous criteria:
- Spelling mistakes are accepted
- Synonyms are accepted
- Different languages are accepted
- Transliterations are accepted
- Partial answers with key info are accepted

## Environment

- **Production:** https://qoomy.online
- **Firebase Console:** https://console.firebase.google.com/project/qoomy-quiz-game

## License

Private project.
