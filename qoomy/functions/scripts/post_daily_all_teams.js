/* Manual run of the real daily-post logic: pick N random quality-screened
   questions ONCE, post the SAME set to every team. Requires ADC + ANTHROPIC_API_KEY.
   Run from qoomy/functions:  ANTHROPIC_API_KEY=... node scripts/post_daily_all_teams.js */
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const Anthropic = require("@anthropic-ai/sdk").default;
initializeApp({ credential: applicationDefault(), projectId: "qoomy-quiz-game" });
const db = getFirestore();
const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY || "" });

const N = Number(process.env.N) || 10;
const MODEL = "claude-sonnet-4-20250514";
const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const code = () => Array.from({ length: 6 }, () => CHARS[Math.floor(Math.random() * CHARS.length)]).join("");
async function uniqueCode() { for (let i = 0; i < 10; i++) { const c = code(); if (!(await db.collection("rooms").doc(c).get()).exists) return c; } return code() + code().slice(0, 2); }

function cleanQuestionText(t) {
  if (!t) return t;
  return t.replace(/\[[^\]]*(ведущему|чтецу|читающему|ведущим)[^\]]*\]/gi, " ").replace(/[ \t]{2,}/g, " ").replace(/\n{3,}/g, "\n\n").trim();
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

async function pickQuality(target) {
  const good = [], seen = new Set();
  let guard = 0;
  while (good.length < target && guard < 100) {
    guard++;
    const snap = await db.collection("questionBank").where("rand", ">=", Math.random()).orderBy("rand").limit(8).get();
    if (snap.empty) continue;
    for (const doc of snap.docs) {
      if (good.length >= target) break;
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const data = doc.data();
      if (data.postable !== true || data.used === true || data.status) continue;
      const cleaned = cleanQuestionText(data.question);
      const v = await judge(cleaned, data.answer, data.comment);
      if (v.ok) { good.push({ id: doc.id, ...data, question: cleaned }); }
      else { await doc.ref.update({ used: true, usedAt: FieldValue.serverTimestamp(), qualityOk: false, status: "unsuitable", qualityReason: v.reason }); console.log(`  ✗ rejected ${doc.id}: ${v.reason}`); }
    }
  }
  return good;
}

async function createRoomForTeam(team, members, q) {
  const c = await uniqueCode();
  const now = Timestamp.now();
  const roomRef = db.collection("rooms").doc(c);
  const batch = db.batch();
  batch.set(roomRef, { hostId: "system", hostName: team.name || "Qoomy", status: "playing", evaluationMode: "ai", question: q.question, answer: q.answer, comment: q.comment || null, zachet: q.zachet || null, imageUrl: q.imageUrl || null, teamId: team.id, teamName: team.name || null, createdAt: now, lastMessageAt: now });
  for (const m of members) batch.set(roomRef.collection("players").doc(m.id), { id: m.id, name: m.name || "", score: 0, joinedAt: now, answer: null, isCorrect: null });
  await batch.commit();
}

(async () => {
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "Europe/Moscow" });
  console.log(`Manual daily post for ${today}: picking ${N} random quality-screened questions...`);
  const questions = await pickQuality(N);
  if (questions.length === 0) { console.error("No questions passed the quality gate."); process.exit(1); }
  console.log(`Selected ${questions.length} questions (${questions.filter((q) => q.hasImage).length} with images):`);
  questions.forEach((q) => console.log(`   ${q.id} ${q.hasImage ? "[img] " : ""}${(q.question || "").replace(/\n/g, " ").slice(0, 60)}`));

  const teamsSnap = await db.collection("teams").get();
  let roomsCreated = 0, postedTeams = 0;
  for (const teamDoc of teamsSnap.docs) {
    if (teamDoc.data().excludeDaily === true) { console.log(`  → "${teamDoc.data().name}" skipped (excludeDaily)`); continue; }
    const team = { id: teamDoc.id, name: teamDoc.data().name };
    const members = (await db.collection("teams").doc(team.id).collection("members").get()).docs.map((m) => ({ id: m.get("id") || m.id, name: m.get("name") }));
    for (const q of questions) { await createRoomForTeam(team, members, q); roomsCreated++; }
    postedTeams++;
    console.log(`  → "${team.name}" (${members.length} members): ${questions.length} rooms`);
  }

  const mb = db.batch();
  for (const q of questions) mb.update(db.collection("questionBank").doc(q.id), { used: true, usedAt: FieldValue.serverTimestamp(), qualityOk: true, status: "posted" });
  await mb.commit();

  await db.collection("dailyQuestionSets").doc(today).set({ date: today, questionIds: questions.map((q) => q.id), teamsCount: postedTeams, roomsCreated, postedAt: FieldValue.serverTimestamp(), manual: true }, { merge: true });

  console.log(`\nDone. Posted the same ${questions.length} questions to ${postedTeams} teams (${roomsCreated} rooms). Recorded dailyQuestionSets/${today}.`);
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
