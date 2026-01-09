# Qoomy Deployment Guide

## Project Info
- **Firebase Project**: qoomy-quiz-game
- **Live URL**: https://qoomy-quiz-game.web.app
- **Custom Domain**: qoomy.online (pending DNS verification)

## Prerequisites
- Flutter SDK installed at `C:/flutter/flutter`
- Firebase CLI installed and logged in
- Node.js for Cloud Functions

## Build & Deploy Commands

### Full Deployment (Frontend + Functions)
```bash
cd C:/Qoomy/qoomy
"C:/flutter/flutter/bin/flutter.bat" build web --release
firebase deploy
```

### Frontend Only
```bash
cd C:/Qoomy/qoomy
"C:/flutter/flutter/bin/flutter.bat" build web --release
firebase deploy --only hosting
```

### Cloud Functions Only
```bash
cd C:/Qoomy/qoomy
firebase deploy --only functions
```

## Environment Configuration

### Anthropic API Key (for AI evaluation)
```bash
firebase functions:config:set anthropic.key="YOUR_API_KEY"
firebase deploy --only functions
```

### View Current Config
```bash
firebase functions:config:get
```

## Local Development

### Run Flutter Web Locally
```bash
cd C:/Qoomy/qoomy
"C:/flutter/flutter/bin/flutter.bat" run -d chrome
```

### Run on Specific Port
```bash
"C:/flutter/flutter/bin/flutter.bat" run -d web-server --web-port=8080
```

## Custom Domain Setup (qoomy.online)

1. Add custom domain in Firebase Console:
   - Go to Hosting > Add custom domain
   - Enter: qoomy.online

2. Add DNS records at your domain registrar:
   - Type: A, Host: @, Value: (Firebase IP addresses)
   - Type: TXT, Host: @, Value: (Firebase verification token)

3. Wait for DNS propagation (up to 48 hours)

4. Check status:
```bash
firebase hosting:sites:list
```

## Project Structure

```
C:/Qoomy/qoomy/
├── lib/                    # Flutter source code
│   ├── config/            # Theme, router
│   ├── l10n/              # Localization (EN/RU)
│   ├── models/            # Data models
│   ├── providers/         # Riverpod providers
│   └── screens/           # UI screens
├── functions/             # Firebase Cloud Functions
│   └── index.js          # AI evaluation logic
├── build/web/            # Built web app (after build)
├── firebase.json         # Firebase config
└── pubspec.yaml          # Flutter dependencies
```

## Troubleshooting

### Flutter Build Errors
```bash
"C:/flutter/flutter/bin/flutter.bat" clean
"C:/flutter/flutter/bin/flutter.bat" pub get
"C:/flutter/flutter/bin/flutter.bat" build web --release
```

### Functions Deployment Errors
```bash
cd C:/Qoomy/qoomy/functions
npm install
cd ..
firebase deploy --only functions
```

### Check Function Logs
```bash
firebase functions:log
```
