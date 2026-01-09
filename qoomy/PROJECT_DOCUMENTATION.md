# Qoomy - Project Documentation

## Overview

**Qoomy** is a real-time multiplayer quiz game application built with Flutter and Firebase. It allows users to create quiz rooms, invite players, and answer questions together with either manual or AI-powered answer evaluation.

**Live URL**: https://qoomy-quiz-game.web.app
**Firebase Project**: qoomy-quiz-game

---

## Technology Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Firestore, Auth, Storage, Cloud Functions)
- **State Management**: Riverpod
- **Routing**: GoRouter
- **Localization**: Custom implementation (English/Russian)
- **AI Integration**: Anthropic Claude API via Cloud Functions
- **Fonts**: Google Fonts (Poppins)

---

## Project Structure

```
lib/
├── main.dart                    # App entry point, Firebase initialization
├── app.dart                     # Root widget with theming and routing
├── config/
│   ├── firebase_options.dart    # Firebase configuration (auto-generated)
│   ├── router.dart              # GoRouter configuration
│   └── theme.dart               # App theme (colors, styles)
├── l10n/
│   └── app_localizations.dart   # Localization strings (EN/RU)
├── models/
│   ├── user_model.dart          # User data model
│   ├── room_model.dart          # Room and Player models
│   ├── chat_message_model.dart  # Chat message model
│   ├── question_model.dart      # Question model
│   └── game_state_model.dart    # Game state model
├── providers/
│   ├── auth_provider.dart       # Authentication state
│   ├── room_provider.dart       # Room and chat state
│   ├── game_provider.dart       # Game state
│   └── locale_provider.dart     # Language state
├── services/
│   ├── auth_service.dart        # Firebase Auth operations
│   ├── room_service.dart        # Firestore room operations
│   ├── user_service.dart        # User data operations
│   ├── game_service.dart        # Game logic operations
│   └── ai_service.dart          # AI evaluation via Cloud Functions
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart    # Login page
│   │   └── register_screen.dart # Registration page
│   ├── home/
│   │   └── home_screen.dart     # Main dashboard
│   ├── room/
│   │   ├── create_room_screen.dart  # Create new room
│   │   ├── join_room_screen.dart    # Join existing room
│   │   └── lobby_screen.dart        # Pre-game lobby
│   └── game/
│       ├── game_screen.dart         # Main game (unified)
│       ├── host_game_screen.dart    # Host-specific view
│       ├── player_game_screen.dart  # Player-specific view
│       └── results_screen.dart      # Game results/leaderboard
└── widgets/
    ├── common/
    │   └── qoomy_logo.dart      # Logo widget
    └── responsive_wrapper.dart  # Responsive container
```

---

## Screens Documentation

### 1. Login Screen (`login_screen.dart`)

**Route**: `/login`

**Purpose**: User authentication

**Features**:
- Email/password sign-in form with validation
- Google Sign-In button
- Language toggle (EN/RU) in app bar
- Link to registration screen
- Form validation (email format, required fields)
- Loading state during authentication
- Error handling with snackbar notifications

**Key Components**:
- `QoomyLogo` widget displaying the app logo
- Email text field with validation
- Password field with visibility toggle
- "Sign In" button with loading indicator
- Google sign-in button with icon

---

### 2. Register Screen (`register_screen.dart`)

**Route**: `/register`

**Purpose**: New user registration

**Features**:
- Full registration form with validation
- Display name field (min 2 characters)
- Email field with format validation
- Password field (min 6 characters)
- Confirm password field with match validation
- Google Sign-Up option
- Language toggle (EN/RU)
- Link to login screen

**Validation Rules**:
- Name: minimum 2 characters
- Email: must contain '@'
- Password: minimum 6 characters
- Confirm password: must match password

---

### 3. Home Screen (`home_screen.dart`)

**Route**: `/` (root)

**Purpose**: Main dashboard showing user's rooms

**Features**:
- **App Bar**:
  - Language toggle button
  - User profile menu with avatar, stats (games played, wins), and logout option

- **Room Lists**:
  - "My Rooms" section: rooms where user is the host (marked with star icon)
  - "Joined Rooms" section: rooms where user is a player

- **Room Cards** display:
  - Room code (6-character alphanumeric)
  - Status badge (Waiting/Playing/Finished with color coding)
  - Question preview (truncated)
  - Evaluation mode (AI or Manual icon)
  - Relative timestamp (just now, X min ago, etc.)
  - Host badge for owned rooms

- **Bottom Navigation**:
  - "Join Room" button (outlined)
  - "Create Room" button (filled)

- **Pull-to-refresh** to update room lists
- Empty state with icon when no rooms exist

---

### 4. Create Room Screen (`create_room_screen.dart`)

**Route**: `/create-room`

**Purpose**: Create a new quiz room

**Features**:
- **Question Field**: Multi-line text input for the quiz question
- **Image Upload** (optional): Pick image from gallery, preview, remove
- **Correct Answer Field**: Hidden from players, only host sees
- **Comment Field** (optional): Explanation shown after answer reveal
- **Evaluation Mode Selection**:
  - **Manual**: Host marks answers as correct/incorrect
  - **AI Assisted**: AI suggests correctness, host confirms
- **Create Button**: Creates room and navigates to host game screen

**Image Handling**:
- Uses `image_picker` package
- Images uploaded to Firebase Storage
- Stored as `rooms/{roomCode}/question_image.jpg`

**Room Code Generation**:
- 6 characters
- Uses: `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (excludes confusing chars like 0, O, I, 1)
- Unique check against existing rooms

---

### 5. Join Room Screen (`join_room_screen.dart`)

**Route**: `/join-room`

**Purpose**: Join an existing room by code

**Features**:
- Large centered input for 6-character room code
- Auto-uppercase input formatter
- Alphanumeric-only filter
- Validation (must be exactly 6 characters)
- Error handling if room not found
- Loading state during join

**Input Styling**:
- Centered text
- Large font (24px)
- Letter spacing for readability
- No counter text shown

---

### 6. Lobby Screen (`lobby_screen.dart`)

**Route**: `/lobby/{roomCode}`

**Purpose**: Pre-game waiting room (currently skipped - games start immediately)

**Features**:
- **Room Code Card**: Large display with copy-to-clipboard functionality
- **Room Info Chips**: Host name, evaluation mode
- **Players List**: Shows all joined players with avatars
- **Player Indicators**:
  - "(You)" label for current user
  - "HOST" badge for the room creator
- **Actions**:
  - Host sees "Start Game" button (enabled when players joined)
  - Players see "Leave Room" button
- **Auto-navigation**: Redirects to game screen when room status changes to "playing"

---

### 7. Game Screen (`game_screen.dart`)

**Route**: `/game/{roomCode}`

**Purpose**: Main unified game view for both hosts and players

**Features**:
- **Header**: Back button, room code with copy, language toggle, user profile menu
- **Question Card**:
  - Expandable/collapsible with image support
  - Different styling for host (white bg) vs player (purple bg)
- **Answer Section** (host only): Show/hide correct answer and comment
- **Chat Area**: Real-time message stream with:
  - Answer messages (marked with purple badge)
  - Comment messages (marked with grey badge)
  - Correct/Wrong indicators after marking
  - AI evaluation indicator (spinner) while processing
  - AI reasoning display after evaluation
- **Message Input**:
  - Host: Comment-only input with "HOST" badge
  - Player: Toggle between Answer/Comment mode

**Answer Marking**:
- **Manual Mode**: Host sees Correct/Wrong buttons on each answer
- **AI Mode**: Automatic evaluation with reasoning shown

---

### 8. Host Game Screen (`host_game_screen.dart`)

**Route**: `/game/host/{roomCode}`

**Purpose**: Dedicated host view (alternative to unified game screen)

**Features**:
- Same as game screen but with host-specific layout
- Question and answer sections at top
- "End Game" button with confirmation dialog
- Player count display
- Host can send comments (not answers)
- Full AI reasoning visible to host

---

### 9. Player Game Screen (`player_game_screen.dart`)

**Route**: `/game/player/{roomCode}`

**Purpose**: Dedicated player view (alternative to unified game screen)

**Features**:
- Question card prominently displayed
- Chat with other players' messages visible
- Answer/Comment toggle in message input
- Correct/Wrong feedback on own answers
- AI reasoning shown only for correct answers

---

### 10. Results Screen (`results_screen.dart`)

**Route**: `/results/{roomCode}`

**Purpose**: Display final game results and leaderboard

**Features**:
- **Trophy Icon**: Celebratory header
- **Podium Display**: Top 3 players with:
  - 1st place: Gold (#FFD700), crown icon, tallest podium
  - 2nd place: Silver (#C0C0C0), medium podium
  - 3rd place: Bronze (#CD7F32), shortest podium
- **Full Rankings List**: All players sorted by score
- **Rank Indicators**: Icons for top 3, numbers for others
- **Score Display**: Points shown in purple badge
- **Back to Home** button

---

## Services Documentation

### AuthService (`auth_service.dart`)

Handles all authentication operations:

- `signInWithEmail(email, password)`: Email/password login
- `signUpWithEmail(email, password, displayName)`: Create new account
- `signInWithGoogle()`: OAuth with Google
- `signOut()`: Logout (both Firebase and Google)
- `resetPassword(email)`: Send password reset email
- `authStateChanges`: Stream of auth state
- `currentUser`: Current Firebase user

**User Document Creation**:
- Creates Firestore document in `users` collection on registration
- Stores: id, email, displayName, createdAt, gamesPlayed, gamesWon

---

### RoomService (`room_service.dart`)

Handles all room-related Firestore operations:

**Room Management**:
- `createRoom(...)`: Create room with question, answer, mode, optional image
- `getRoom(roomCode)`: Fetch room data
- `roomStream(roomCode)`: Real-time room updates
- `deleteRoom(roomCode)`: Delete room and all subcollections

**Player Management**:
- `joinRoom(roomCode, playerId, playerName)`: Add player to room
- `leaveRoom(roomCode, playerId)`: Remove player from room
- `playersStream(roomCode)`: Real-time player list

**Game Flow**:
- `startGame(roomCode)`: Set status to "playing"
- `endGame(roomCode)`: Set status to "finished"

**Chat**:
- `chatStream(roomCode)`: Real-time message stream
- `sendMessage(...)`: Add message to chat
- `markMessageAnswer(...)`: Mark answer as correct/incorrect

**User Queries**:
- `userHostedRoomsStream(userId)`: Rooms created by user
- `userJoinedRoomsStream(userId)`: Rooms user has joined

---

### AiService (`ai_service.dart`)

Handles AI-powered answer evaluation via Firebase Cloud Functions:

- `evaluateAnswer(question, correctAnswer, playerAnswer)`:
  - Calls `evaluateAnswer` Cloud Function
  - Returns `AiEvaluation` with:
    - `isCorrect`: boolean result
    - `confidence`: 0.0-1.0 score
    - `reasoning`: explanation string
  - Falls back to null evaluation on error

**Cloud Function** (in `functions/index.js`):
- Uses Anthropic Claude API
- Compares player answer semantically to correct answer
- Returns structured evaluation result

---

## Models Documentation

### UserModel (`user_model.dart`)

```dart
- id: String
- email: String
- displayName: String
- avatarUrl: String?
- gamesPlayed: int
- gamesWon: int
- createdAt: DateTime
```

### RoomModel (`room_model.dart`)

```dart
- code: String (6-char unique)
- hostId: String
- hostName: String
- status: RoomStatus (waiting, playing, finished)
- evaluationMode: EvaluationMode (manual, ai)
- question: String
- answer: String
- comment: String?
- imageUrl: String?
- createdAt: DateTime
- players: List<Player>
```

### Player

```dart
- id: String
- name: String
- score: int
- joinedAt: DateTime
- answer: String?
- isCorrect: bool?
```

### ChatMessage (`chat_message_model.dart`)

```dart
- id: String
- playerId: String
- playerName: String
- text: String
- type: MessageType (answer, comment)
- sentAt: DateTime
- isCorrect: bool?
- aiReasoning: String?
```

---

## Theme & Styling (`theme.dart`)

**Brand Colors**:
- Primary: `#6C63FF` (Purple)
- Secondary: `#FF6584` (Pink)
- Accent: `#00D9FF` (Cyan)
- Success: `#4CAF50` (Green)
- Error: `#E53935` (Red)
- Warning: `#FF9800` (Orange)

**Design Constants**:
- Max content width: 500px (mobile-first responsive)
- Border radius: 16px (buttons), 20px (cards)
- Font: Poppins (Google Fonts)

**Themes**:
- Light theme with Material 3
- Dark theme with Material 3

---

## Localization (`app_localizations.dart`)

**Supported Languages**:
- English (en) - default
- Russian (ru)

**Categories**:
- App (name, tagline)
- Auth (sign in/up, validation messages)
- Home (rooms, status)
- Room creation (fields, modes)
- Game (chat, marking)
- Results (leaderboard)

**Implementation**:
- Custom `LocalizationsDelegate`
- Map-based string lookup
- Convenience getters for all strings
- Language toggle in app bar

---

## Key Features Implemented

1. **Authentication**
   - Email/password registration and login
   - Google OAuth integration
   - User profile with game statistics

2. **Room System**
   - Unique 6-character room codes
   - Real-time room state synchronization
   - Image attachments for questions
   - Room status tracking (waiting, playing, finished)

3. **Game Modes**
   - **Manual**: Host manually marks answers
   - **AI-Assisted**: Claude API evaluates answers automatically

4. **Real-time Chat**
   - Answer and comment message types
   - Real-time message streaming
   - Answer marking with visual feedback
   - AI reasoning display

5. **Responsive Design**
   - Max 500px content width
   - Mobile-first approach
   - Works on web, Android, iOS

6. **Internationalization**
   - English and Russian languages
   - Easy to add more languages

7. **Leaderboard**
   - Top 3 podium display
   - Full rankings with scores
   - Visual rank indicators

---

## Firebase Structure

### Collections

```
users/
  {userId}/
    - id, email, displayName, avatarUrl
    - gamesPlayed, gamesWon, createdAt

rooms/
  {roomCode}/
    - hostId, hostName, status, evaluationMode
    - question, answer, comment, imageUrl, createdAt

    players/
      {playerId}/
        - id, name, score, joinedAt, answer, isCorrect

    chat/
      {messageId}/
        - playerId, playerName, text, type
        - sentAt, isCorrect, aiReasoning
```

### Storage

```
rooms/
  {roomCode}/
    question_image.jpg
```

---

## Deployment

See [DEPLOYMENT.md](./DEPLOYMENT.md) for deployment instructions.

---

*Last updated: January 2026*
