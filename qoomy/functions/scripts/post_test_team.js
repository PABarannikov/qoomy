/* Post N quality-screened questions to a SINGLE team (test tool).
   Requires ADC + ANTHROPIC_API_KEY. Run from qoomy/functions:
   ANTHROPIC_API_KEY=... TEAM_ID=<id> node scripts/post_test_team.js   */
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const Anthropic = require("@anthropic-ai/sdk").default;
initializeApp({ credential: applicationDefault(), projectId: "qoomy-quiz-game" });
const db = getFirestore();
const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY || "" });

const TEAM_ID = process.env.TEAM_ID;
const N = Number(process.env.N) || 10;
const MODEL = "claude-sonnet-4-20250514";
const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const code = () => Array.from({ length: 6 }, () => CHARS[Math.floor(Math.random() * CHARS.length)]).join("");
async function uniqueCode() { for (let i = 0; i < 10; i++) { const c = code(); if (!(await db.collection("rooms").doc(c).get()).exists) return c; } return code() + code().slice(0, 2); }

function cleanQuestionText(text) {
  if (!text) return text;
  return text
    .replace(/\[[^\]]*(ведущему|чтецу|читающему|ведущим)[^\]]*\]/gi, " ")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function qualityPrompt(q, a, comment) {
  return `Ты — судья качества вопросов "Что? Где? Когда?" (ЧГК) для ежедневной командной викторины.
Реши, годится ли вопрос к публикации. Ответь ТОЛЬКО JSON: {"ok": true/false, "reason": "кратко"}

Отклоняй (ok=false), если верно хотя бы одно:
- Это не вопрос: благодарности ("Автор благодарит..."), указания ведущему ("Ведущему:..."), заголовки туров/блицев, служебный текст.
- Нужен материал, которого нет в тексте: ссылка на раздаточный материал/картинку/аудио.
- Сломан, обрезан или непонятен.
- Ответ отсутствует, пустой или не проверяется по вопросу.
- Явно слабый: банальный, чрезмерно узкий/нишевый или безнадёжно неоднозначный.

Принимай (ok=true) нормальный самодостаточный вопрос ЧГК с чётким ответом — он не обязан быть шедевром, достаточно крепкого уровня.

Вопрос: ${q}
Ответ: ${a}${comment ? `\nКомментарий: ${comment}` : ""}`;
}

async function judge(q, a, comment) {
  if (!process.env.ANTHROPIC_API_KEY) return { ok: true, reason: "no-key" };
  try {
    const m = await anthropic.messages.create({ model: MODEL, max_tokens: 128, messages: [{ role: "user", content: qualityPrompt(q, a, comment) }] });
    const t = m.content[0].type === "text" ? m.content[0].text : "";
    const j = t.match(/\{[\s\S]*\}/);
    if (j) { const r = JSON.parse(j[0]); return { ok: Boolean(r.ok), reason: String(r.reason || "") }; }
    return { ok: true, reason: "unparseable" };
  } catch (e) { console.error("judge error:", e.message); return { ok: true, reason: "error" }; }
}

(async () => {
  if (!TEAM_ID) { console.error("set TEAM_ID"); process.exit(1); }
  const teamDoc = await db.collection("teams").doc(TEAM_ID).get();
  if (!teamDoc.exists) { console.error("team not found"); process.exit(1); }
  const team = { id: teamDoc.id, name: teamDoc.data().name };
  const members = (await db.collection("teams").doc(TEAM_ID).collection("members").get()).docs.map((m) => ({ id: m.get("id") || m.id, name: m.get("name") }));
  console.log(`Team "${team.name}" — ${members.length} members. Quality-screening for ${N} good questions...`);

  const good = [];
  const seen = new Set();
  let evaluated = 0, rejected = 0, guard = 0;
  while (good.length < N && guard < 100) {
    guard++;
    const snap = await db.collection("questionBank").where("rand", ">=", Math.random()).orderBy("rand").limit(8).get();
    if (snap.empty) continue;
    for (const doc of snap.docs) {
      if (good.length >= N) break;
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const data = doc.data();
      if (data.postable !== true || data.used === true || data.status) continue;
      const cleanedQuestion = cleanQuestionText(data.question);
      const v = await judge(cleanedQuestion, data.answer, data.comment);
      evaluated++;
      if (v.ok) {
        good.push({ id: doc.id, ...data, question: cleanedQuestion });
      } else {
        rejected++;
        await doc.ref.update({ used: true, usedAt: FieldValue.serverTimestamp(), qualityOk: false, status: "unsuitable", qualityReason: v.reason });
        console.log(`  ✗ ${doc.id}: ${v.reason} — "${(data.question || "").replace(/\n/g, " ").slice(0, 55)}"`);
      }
    }
  }
  console.log(`Evaluated ${evaluated}, rejected ${rejected}, kept ${good.length}.`);

  for (const q of good) {
    const c = await uniqueCode();
    const now = Timestamp.now();
    const roomRef = db.collection("rooms").doc(c);
    const batch = db.batch();
    batch.set(roomRef, { hostId: "system", hostName: team.name || "Qoomy", status: "playing", evaluationMode: "ai", question: q.question, answer: q.answer, comment: q.comment || null, zachet: q.zachet || null, imageUrl: q.imageUrl || null, teamId: team.id, teamName: team.name || null, createdAt: now, lastMessageAt: now });
    for (const m of members) batch.set(roomRef.collection("players").doc(m.id), { id: m.id, name: m.name || "", score: 0, joinedAt: now, answer: null, isCorrect: null });
    await batch.commit();
    await db.collection("questionBank").doc(q.id).update({ used: true, usedAt: FieldValue.serverTimestamp(), qualityOk: true, status: "posted" });
    console.log(`  ✓ ${c} ${q.hasImage ? "[img] " : ""}${(q.question || "").replace(/\n/g, " ").slice(0, 55)}`);
  }
  console.log(`Done. Posted ${good.length} quality-screened questions to "${team.name}".`);
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
