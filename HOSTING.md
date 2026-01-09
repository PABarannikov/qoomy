# Qoomy Hosting Configuration

## Overview

Qoomy uses Firebase for all backend services:

| Service | Provider | URL |
|---------|----------|-----|
| Web Hosting | Firebase Hosting | https://qoomy.online |
| Database | Firebase Firestore | - |
| Authentication | Firebase Auth | - |
| Cloud Functions | Firebase Functions | - |
| AI Evaluation | Anthropic Claude API | - |

## Firebase Project

- **Project ID:** qoomy-quiz-game
- **Console:** https://console.firebase.google.com/project/qoomy-quiz-game

## Domains

| Domain | Status |
|--------|--------|
| https://qoomy.online | Custom domain (primary) |
| https://www.qoomy.online | Custom domain |
| https://qoomy-quiz-game.web.app | Firebase default |
| https://qoomy-quiz-game.firebaseapp.com | Firebase default |

## DNS Configuration (qoomy.online)

DNS records configured at reg.ru:

| Type | Host | Value |
|------|------|-------|
| A | @ | 199.36.158.100 |
| A | www | 199.36.158.100 |
| TXT | @ | hosting-site=qoomy-quiz-game |

## Deployment

### Build and Deploy Web App

```bash
cd C:\Qoomy\qoomy

# Build Flutter web
flutter build web --release

# Deploy to Firebase Hosting
firebase deploy --only hosting
```

### Deploy Cloud Functions

```bash
cd C:\Qoomy\qoomy

# Deploy functions only
firebase deploy --only functions
```

### Deploy Everything

```bash
firebase deploy
```

## Cloud Functions

Located in `functions/index.js`:

| Function | Type | Description |
|----------|------|-------------|
| `evaluateAnswer` | HTTPS Callable | Manual AI answer evaluation |
| `onAnswerSubmitted` | Firestore Trigger | Auto-evaluates answers in AI mode |

### Configuration

Anthropic API key is stored in Firebase Functions config:

```bash
# Set API key
firebase functions:config:set anthropic.key="YOUR_API_KEY"

# View current config
firebase functions:config:get
```

### View Logs

```bash
firebase functions:log
```

## Costs

### Firebase (Blaze Plan - Pay as you go)

| Service | Free Tier | Cost after |
|---------|-----------|------------|
| Hosting Storage | 10 GB | $0.026/GB |
| Hosting Transfer | 360 MB/day | $0.15/GB |
| Firestore Reads | 50K/day | $0.06/100K |
| Firestore Writes | 20K/day | $0.18/100K |
| Cloud Functions | 2M invocations/mo | $0.40/million |

### Anthropic API (Claude 3 Haiku)

| Type | Cost |
|------|------|
| Input tokens | $0.25 / million |
| Output tokens | $1.25 / million |

**Per answer evaluation:** ~$0.0001 (1/100th of a cent)

Monitor usage: https://console.anthropic.com/settings/usage

## SSL Certificate

SSL is automatically provisioned by Firebase Hosting after domain verification. No manual configuration needed.

## Troubleshooting

### DNS not propagating

Check DNS with Google's DNS:
```bash
nslookup qoomy.online 8.8.8.8
```

Should return `199.36.158.100`. If showing old IP, wait 15-30 minutes.

### Domain verification failing

1. Ensure A record points to `199.36.158.100`
2. Ensure TXT record has `hosting-site=qoomy-quiz-game`
3. Wait for DNS propagation
4. Click "Verify" in Firebase Console

### Cloud Functions not working

1. Check logs: `firebase functions:log`
2. Verify API key is set: `firebase functions:config:get`
3. Ensure Blaze plan is active
