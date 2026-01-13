const functions = require('firebase-functions');
const admin = require('firebase-admin');
const Anthropic = require('@anthropic-ai/sdk');

admin.initializeApp();

const db = admin.firestore();

/**
 * Cloud Function to evaluate a player's answer using Claude AI
 * Called when a new answer message is added to the chat
 */
exports.evaluateAnswer = functions.https.onCall(async (data, context) => {
  const { question, correctAnswer, playerAnswer } = data;

  if (!question || !correctAnswer || !playerAnswer) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Missing required fields: question, correctAnswer, playerAnswer'
    );
  }

  try {
    const apiKey = functions.config().anthropic?.key;
    if (!apiKey) {
      console.error('Anthropic API key not configured');
      return {
        isCorrect: null,
        confidence: 0,
        reasoning: 'AI evaluation not configured',
      };
    }

    const anthropic = new Anthropic({ apiKey });

    const prompt = `You are a strict quiz answer evaluator. Your job is to check if the player's answer is correct.

Question: ${question}
Correct Answer: ${correctAnswer}
Player's Answer: ${playerAnswer}

STEP 1 - COUNT WORDS (DO THIS FIRST):
Count meaningful words in the correct answer (exclude: the, a, an).
Count meaningful words in the player's answer (exclude: the, a, an).

STEP 2 - CHECK WORD COUNT RULE:
If correct answer has 2+ words AND player answer has only 1 word → IMMEDIATELY return isCorrect: false
NO EXCEPTIONS. Even if the single word is semantically related, it is WRONG.

Examples that MUST be marked WRONG:
- "Отряд самоубийц" (2 words) → "suicide" (1 word) = WRONG
- "Отряд самоубийц" (2 words) → "Suicide" (1 word) = WRONG
- "Отряд самоубийц" (2 words) → "squad" (1 word) = WRONG
- "Suicide Squad" (2 words) → "Suicide" (1 word) = WRONG
- "Eiffel Tower" (2 words) → "Tower" (1 word) = WRONG

STEP 3 - If word count is OK, then check if meaning matches:
- Allow spelling mistakes, synonyms, translations, transliterations
- "Отряд самоубийц" = "Suicide Squad" (both 2 words, same meaning) = CORRECT
- Allow character aliases and alternative names (birth name = title/known name)
- Examples: "Эдмонд Дантес" = "Граф Монте-Кристо" (same character), "Дантес" = "Монте-Кристо"
- The same person/character referred to by a different name (pen name, stage name, nickname, title) = CORRECT

Respond in JSON format only:
{
  "isCorrect": true/false,
  "confidence": 0.0-1.0,
  "reasoning": "brief explanation in the same language as the question"
}`;

    const response = await anthropic.messages.create({
      model: 'claude-3-haiku-20240307',
      max_tokens: 200,
      messages: [{ role: 'user', content: prompt }],
    });

    const text = response.content[0].text;
    const jsonMatch = text.match(/\{[\s\S]*\}/);

    if (jsonMatch) {
      const result = JSON.parse(jsonMatch[0]);
      return {
        isCorrect: result.isCorrect,
        confidence: Math.min(1, Math.max(0, result.confidence)),
        reasoning: result.reasoning,
      };
    }

    return {
      isCorrect: null,
      confidence: 0,
      reasoning: 'Could not parse AI response',
    };
  } catch (error) {
    console.error('AI evaluation error:', error);
    return {
      isCorrect: null,
      confidence: 0,
      reasoning: 'AI evaluation failed',
    };
  }
});

/**
 * Firestore trigger: automatically evaluate answers when added to AI-mode rooms
 */
exports.onAnswerSubmitted = functions.firestore
  .document('rooms/{roomCode}/chat/{messageId}')
  .onCreate(async (snap, context) => {
    const { roomCode, messageId } = context.params;
    const message = snap.data();

    // Only process answer messages
    if (message.type !== 'answer') {
      return null;
    }

    // Get room data to check if AI mode is enabled
    const roomDoc = await db.collection('rooms').doc(roomCode).get();
    if (!roomDoc.exists) {
      return null;
    }

    const room = roomDoc.data();
    if (room.evaluationMode !== 'ai') {
      return null;
    }

    try {
      const apiKey = functions.config().anthropic?.key;
      if (!apiKey) {
        console.log('Anthropic API key not configured, skipping AI evaluation');
        return null;
      }

      const anthropic = new Anthropic({ apiKey });

      const prompt = `You are a strict quiz answer evaluator. Your job is to check if the player's answer is correct.

Question: ${room.question}
Correct Answer: ${room.answer}
Player's Answer: ${message.text}

STEP 1 - COUNT WORDS (DO THIS FIRST):
Count meaningful words in the correct answer (exclude: the, a, an).
Count meaningful words in the player's answer (exclude: the, a, an).

STEP 2 - CHECK WORD COUNT RULE:
If correct answer has 2+ words AND player answer has only 1 word → IMMEDIATELY return isCorrect: false
NO EXCEPTIONS. Even if the single word is semantically related, it is WRONG.

Examples that MUST be marked WRONG:
- "Отряд самоубийц" (2 words) → "suicide" (1 word) = WRONG
- "Отряд самоубийц" (2 words) → "Suicide" (1 word) = WRONG
- "Отряд самоубийц" (2 words) → "squad" (1 word) = WRONG
- "Suicide Squad" (2 words) → "Suicide" (1 word) = WRONG
- "Eiffel Tower" (2 words) → "Tower" (1 word) = WRONG

STEP 3 - If word count is OK, then check if meaning matches:
- Allow spelling mistakes, synonyms, translations, transliterations
- "Отряд самоубийц" = "Suicide Squad" (both 2 words, same meaning) = CORRECT
- Allow character aliases and alternative names (birth name = title/known name)
- Examples: "Эдмонд Дантес" = "Граф Монте-Кристо" (same character), "Дантес" = "Монте-Кристо"
- The same person/character referred to by a different name (pen name, stage name, nickname, title) = CORRECT

Respond in JSON format only:
{
  "isCorrect": true/false,
  "confidence": 0.0-1.0,
  "reasoning": "brief explanation in the same language as the question"
}`;

      const response = await anthropic.messages.create({
        model: 'claude-3-haiku-20240307',
        max_tokens: 200,
        messages: [{ role: 'user', content: prompt }],
      });

      const text = response.content[0].text;
      const jsonMatch = text.match(/\{[\s\S]*?\}/);

      if (jsonMatch) {
        let result;
        try {
          // Clean up the JSON string before parsing
          let jsonStr = jsonMatch[0]
            .replace(/[\r\n]+/g, ' ')  // Remove newlines
            .replace(/,\s*}/g, '}')    // Remove trailing commas
            .replace(/:\s*"([^"]*?)"/g, (match, p1) => `: "${p1.replace(/"/g, '\\"')}"`)  // Escape quotes in values
            .trim();
          result = JSON.parse(jsonStr);
        } catch (parseError) {
          // Fallback: try to extract values manually
          const isCorrectMatch = text.match(/["']?isCorrect["']?\s*:\s*(true|false)/i);
          const confidenceMatch = text.match(/["']?confidence["']?\s*:\s*([\d.]+)/);
          const reasoningMatch = text.match(/["']?reasoning["']?\s*:\s*["']([^"']+)["']/);

          result = {
            isCorrect: isCorrectMatch ? isCorrectMatch[1].toLowerCase() === 'true' : null,
            confidence: confidenceMatch ? parseFloat(confidenceMatch[1]) : 0.5,
            reasoning: reasoningMatch ? reasoningMatch[1] : 'AI evaluation completed',
          };
        }

        if (result.isCorrect !== null) {
          // In AI mode, automatically mark the answer (AI replaces host)
          await snap.ref.update({
            isCorrect: result.isCorrect,
            aiConfidence: Math.min(1, Math.max(0, result.confidence || 0.5)),
            aiReasoning: result.reasoning || 'AI evaluation completed',
          });

          // Update player score if correct
          if (result.isCorrect) {
            const playerRef = db.collection('rooms').doc(roomCode).collection('players').doc(message.playerId);
            await playerRef.update({
              score: admin.firestore.FieldValue.increment(1),
            });
          }

          console.log(`AI auto-marked answer for room ${roomCode}: ${result.isCorrect} (${result.confidence})`);
        }
      }
    } catch (error) {
      console.error('AI evaluation error:', error);
      // Mark as needing manual review on error
      await snap.ref.update({
        isCorrect: null,
        aiReasoning: 'AI evaluation failed - needs manual review',
      });
    }

    return null;
  });
