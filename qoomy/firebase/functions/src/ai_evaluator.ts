import Anthropic from "@anthropic-ai/sdk";

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY || "",
});

interface EvaluationResult {
  isCorrect: boolean;
  confidence: number;
  explanation: string;
}

export async function evaluateAnswer(
  question: string,
  expectedAnswer: string,
  playerAnswer: string
): Promise<EvaluationResult> {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.warn("ANTHROPIC_API_KEY not set, falling back to simple comparison");
    return simpleEvaluation(expectedAnswer, playerAnswer);
  }

  try {
    const message = await anthropic.messages.create({
      model: "claude-sonnet-4-20250514",
      max_tokens: 256,
      messages: [
        {
          role: "user",
          content: `You are evaluating quiz answers. Determine if the player's answer is semantically correct, even if not an exact match.

Question: ${question}
Expected Answer: ${expectedAnswer}
Player Answer: ${playerAnswer}

Respond with JSON only in this format:
{"isCorrect": true/false, "confidence": 0.0-1.0, "explanation": "brief reason"}

Be lenient with:
- Spelling variations
- Synonyms  
- Different phrasing
- Abbreviations

Be strict about:
- Fundamentally wrong answers
- Different concepts
- Unrelated responses`,
        },
      ],
    });

    const responseText =
      message.content[0].type === "text" ? message.content[0].text : "";

    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      const result = JSON.parse(jsonMatch[0]);
      return {
        isCorrect: Boolean(result.isCorrect),
        confidence: Number(result.confidence) || 0.5,
        explanation: String(result.explanation) || "",
      };
    }

    return simpleEvaluation(expectedAnswer, playerAnswer);
  } catch (error) {
    console.error("AI evaluation error:", error);
    return simpleEvaluation(expectedAnswer, playerAnswer);
  }
}

function simpleEvaluation(
  expectedAnswer: string,
  playerAnswer: string
): EvaluationResult {
  const normalizedExpected = expectedAnswer.toLowerCase().trim();
  const normalizedPlayer = playerAnswer.toLowerCase().trim();

  const isExactMatch = normalizedExpected === normalizedPlayer;
  const containsAnswer =
    normalizedPlayer.includes(normalizedExpected) ||
    normalizedExpected.includes(normalizedPlayer);

  if (isExactMatch) {
    return {
      isCorrect: true,
      confidence: 1.0,
      explanation: "Exact match",
    };
  }

  if (containsAnswer && Math.abs(normalizedExpected.length - normalizedPlayer.length) < 5) {
    return {
      isCorrect: true,
      confidence: 0.8,
      explanation: "Close match",
    };
  }

  return {
    isCorrect: false,
    confidence: 0.9,
    explanation: "Does not match expected answer",
  };
}
