# Qoomy Deployment Guide

## Project Info
- **Firebase Project**: qoomy-quiz-game
- **Live URL**: https://qoomy-quiz-game.web.app
- **GitHub Repository**: https://github.com/PABarannikov/qoomy
- **Custom Domain**: qoomy.online (pending DNS verification)

## Recommended Deployment Method: GitHub CI/CD

**Always use GitHub CI/CD for deployment.** Simply push to the `master` branch and the deployment happens automatically.

### How to Deploy

1. Make your changes locally
2. Commit and push to master:
```bash
git add .
git commit -m "Your commit message"
git push origin master
```
3. GitHub Actions will automatically:
   - Check out the code
   - Set up Flutter 3.27.0
   - Install dependencies
   - Run code analysis
   - Build the web app
   - Deploy to Firebase Hosting

### Monitor Deployment

- View workflow runs: https://github.com/PABarannikov/qoomy/actions
- Check deployment status in GitHub Actions tab
- Live site updates within minutes of push

### Workflow Configuration

The CI/CD workflow is defined in `.github/workflows/deploy.yml`:
- Triggers on push to `master` branch
- Also runs on pull requests (build only, no deploy)
- Uses `FIREBASE_SERVICE_ACCOUNT` secret for deployment

### Required GitHub Secrets

- `FIREBASE_SERVICE_ACCOUNT`: Firebase service account JSON (already configured)

---

## Alternative: Manual Deployment (Not Recommended)

Only use manual deployment if GitHub CI/CD is unavailable.

### Prerequisites
- Flutter SDK installed at `C:/flutter/flutter`
- Firebase CLI installed and logged in
- Node.js for Cloud Functions

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

---

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

### GitHub Actions Failing

1. Check workflow logs: https://github.com/PABarannikov/qoomy/actions
2. Verify `FIREBASE_SERVICE_ACCOUNT` secret is set correctly
3. Ensure Flutter version in workflow matches project requirements
