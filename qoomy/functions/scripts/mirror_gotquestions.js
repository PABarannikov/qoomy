/**
 * Mirror the ENTIRE gotquestions.online ЧГК base into Firestore `questionBank`.
 *
 * This is a LOCAL one-shot tool (it is NOT a Cloud Function and is not deployed).
 * It writes every question with a deterministic doc id (gq_<questionId>) using
 * create(), so it is fully idempotent:
 *   - first run: mirrors the whole base (~6,700 packs, ~150k–250k questions)
 *   - later runs: only add questions that aren't there yet (e.g. newly published
 *     packs, which appear on page 1) and never clobber a question's used/rand state.
 *
 * Each question doc matches what the Cloud Functions expect:
 *   question, answer, zachet, nezachet, comment, sourceText, authors, packId,
 *   packTitle, hasMedia, postable, used:false, usedAt:null, rand, createdAt.
 * Questions with images/audio/handout-pics are still stored (full mirror) but
 * flagged postable:false so the daily poster never selects them.
 *
 * ── Setup (one time) ────────────────────────────────────────────────────────
 *   1. Firebase console → Project settings → Service accounts →
 *      "Generate new private key". Save the JSON file OUTSIDE this repo.
 *   2. Point Application Default Credentials at it (see run commands below).
 *
 * ── Run (Windows PowerShell), from C:\Qoomy\qoomy\functions ─────────────────
 *   $env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\serviceAccountKey.json"
 *   node scripts/mirror_gotquestions.js
 *
 * ── Run (bash) ──────────────────────────────────────────────────────────────
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/key.json node scripts/mirror_gotquestions.js
 *
 * Optional env vars:
 *   GQ_PROJECT       Firestore project id (default: qoomy-quiz-game)
 *   GQ_CONCURRENCY   parallel pack workers (default: 6)
 *   GQ_FROM_PAGE     first packs page to crawl (default: 1)
 *   GQ_TO_PAGE       last packs page to crawl (default: all)
 *   GQ_MAX           stop after adding N new questions (for test runs)
 *
 * Progress is saved to scripts/.mirror_progress.json after every few packs, so
 * the job is safe to Ctrl+C and re-run — it resumes where it left off.
 */
const fs = require("fs");
const path = require("path");
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const GQ_BASE = "https://gotquestions.online";
const PROJECT_ID = process.env.GQ_PROJECT || "qoomy-quiz-game";
const CONCURRENCY = Number(process.env.GQ_CONCURRENCY) || 6;
const FROM_PAGE = Number(process.env.GQ_FROM_PAGE) || 1;
const TO_PAGE = Number(process.env.GQ_TO_PAGE) || Infinity;
const MAX_ADD = Number(process.env.GQ_MAX) || Infinity; // stop after N new questions (for test runs)
const GQ_EMAIL = process.env.GQ_EMAIL || ""; // gotquestions API now requires login
const GQ_PASSWORD = process.env.GQ_PASSWORD || "";
const PROGRESS_FILE = path.join(__dirname, ".mirror_progress.json");

// Accept EITHER a service-account key (GOOGLE_APPLICATION_CREDENTIALS) OR gcloud
// Application Default Credentials (from `gcloud auth application-default login`).
const adcPath = process.env.APPDATA
  ? path.join(process.env.APPDATA, "gcloud", "application_default_credentials.json")
  : path.join(process.env.HOME || "", ".config", "gcloud", "application_default_credentials.json");
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && !fs.existsSync(adcPath)) {
  console.error(
    "ERROR: no Google credentials found. Use one of:\n" +
      "  • gcloud auth application-default login   (recommended)\n" +
      "  • set GOOGLE_APPLICATION_CREDENTIALS to a service-account key JSON path"
  );
  process.exit(1);
}

initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
const db = getFirestore();

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// gotquestions.online requires JWT auth: POST /api/token/obtain/ {email,password}
// → {access, refresh}. Send "Authorization: JWT <access>". Access tokens are
// short-lived, so we refresh (or re-login) when a request returns 401.
let accessToken = "";
let refreshToken = "";

async function login() {
  if (!GQ_EMAIL || !GQ_PASSWORD) {
    throw new Error("Set GQ_EMAIL and GQ_PASSWORD env vars (gotquestions API requires login).");
  }
  const res = await fetch(`${GQ_BASE}/api/token/obtain/`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: GQ_EMAIL, password: GQ_PASSWORD }),
  });
  if (!res.ok) throw new Error(`gotquestions login failed: HTTP ${res.status}`);
  const j = await res.json();
  accessToken = j.access || j.token || "";
  refreshToken = j.refresh || "";
  if (!accessToken) throw new Error("gotquestions login returned no token");
}

async function refreshAccess() {
  if (!refreshToken) return login();
  try {
    const res = await fetch(`${GQ_BASE}/api/token/refresh/`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh: refreshToken }),
    });
    if (!res.ok) return login();
    const j = await res.json();
    accessToken = j.access || accessToken;
  } catch {
    return login();
  }
}

async function fetchJson(url, tries = 4) {
  for (let attempt = 1; attempt <= tries; attempt++) {
    try {
      const res = await fetch(url, {
        headers: {
          Accept: "application/json",
          "User-Agent": "QoomyMirror/1.0 (+https://qoomy.online)",
          ...(accessToken ? { Authorization: `JWT ${accessToken}` } : {}),
        },
      });
      if (res.status === 404) return null;
      if (res.status === 401) {
        await refreshAccess();
        throw new Error("HTTP 401 (re-authenticated, retrying)");
      }
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.json();
    } catch (e) {
      if (attempt === tries) throw e;
      await sleep(500 * attempt);
    }
  }
}

function questionHasMedia(q) {
  return Boolean(
    q.razdatkaPic || q.answerPic || q.audio || q.commentAudio || q.commentPic
  );
}

// Multi-part questions (дуплет/блиц/триплет — 2+ sub-answers on one blank) don't
// fit a single-answer room, so they are flagged postable:false (never posted).
function isMultiPartQuestion(text, answer) {
  if (/^\s*[«"(\[]?\s*(дуплет|блиц|триплет|перестрелка)/i.test(text || "")) {
    return true;
  }
  const parts = ((answer || "").match(/(^|[\s;(])\d+[.)]\s/g) || []).length;
  return parts >= 2;
}

// Strip editorial host-notes ("[Ведущему: …]" / "[Чтецу: …]") from question text.
function cleanQuestionText(text) {
  if (!text) return text;
  return text
    .replace(/\[[^\]]*(ведущему|чтецу|читающему|ведущим)[^\]]*\]/gi, " ")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function normalize(q, pack) {
  if (!q || q.id == null) return null;
  const text = (q.text || "").trim();
  if (!text) return null;
  const answer = (q.answer || "").trim();
  const multiPart = isMultiPartQuestion(text, answer);
  const razdatkaPic = (q.razdatkaPic || "").trim();
  const blockingMedia = Boolean((q.audio || "").trim() || (q.answerPic || "").trim());
  const imageUrl = razdatkaPic
    ? (razdatkaPic.startsWith("http") ? razdatkaPic : GQ_BASE + razdatkaPic)
    : "";
  const razdatka = (q.razdatkaText || "").trim();
  const question = cleanQuestionText(razdatka ? `${razdatka}\n\n${text}` : text);
  const authors = Array.isArray(q.authors)
    ? q.authors.map((a) => a && a.name).filter(Boolean).join(", ")
    : "";
  return {
    source: "gotquestions",
    sourceId: String(q.id),
    sourceUrl: `${GQ_BASE}/question/${q.id}`,
    packId: pack && pack.id != null ? Number(pack.id) : null,
    packTitle: (pack && pack.title) || q.packTitle || "",
    question,
    answer,
    zachet: (q.zachet || "").trim(),
    nezachet: (q.nezachet || "").trim(),
    comment: (q.comment || "").trim(),
    sourceText: (q.source || "").trim(),
    authors,
    hasMedia: questionHasMedia(q),
    hasImage: Boolean(razdatkaPic),
    sourceImageUrl: imageUrl,
    multiPart,
    postable: Boolean(text && answer && !multiPart && !blockingMedia),
    used: false,
    usedAt: null,
    rand: Math.random(),
    createdAt: FieldValue.serverTimestamp(),
  };
}

function flatten(pack) {
  if (Array.isArray(pack.questions) && pack.questions.length) return pack.questions;
  const out = [];
  (pack.tours || []).forEach((t) => (t.questions || []).forEach((q) => out.push(q)));
  return out;
}

function loadProgress() {
  try {
    return JSON.parse(fs.readFileSync(PROGRESS_FILE, "utf8"));
  } catch {
    return { donePackIds: [], totalAdded: 0, totalDuplicates: 0 };
  }
}

// Module-scoped state so the SIGINT handler can persist it.
const progress = loadProgress();
const donePacks = new Set(progress.donePackIds);
let added = progress.totalAdded || 0;
let duplicates = progress.totalDuplicates || 0;
let errors = 0;

function persist() {
  progress.donePackIds = Array.from(donePacks);
  progress.totalAdded = added;
  progress.totalDuplicates = duplicates;
  fs.writeFileSync(PROGRESS_FILE, JSON.stringify(progress));
}

process.on("SIGINT", () => {
  console.log("\nInterrupted — saving progress…");
  persist();
  process.exit(0);
});

/** create() the doc, retrying transient errors; returns "added" | "duplicate". */
async function createDoc(ref, data, tries = 4) {
  for (let attempt = 1; attempt <= tries; attempt++) {
    try {
      await ref.create(data);
      return "added";
    } catch (e) {
      if (e.code === 6 || /ALREADY_EXISTS/i.test(e.message || "")) {
        return "duplicate";
      }
      if (attempt === tries) throw e;
      await sleep(300 * attempt);
    }
  }
}

async function importPack(pid) {
  let pack;
  try {
    pack = await fetchJson(`${GQ_BASE}/api/pack/${pid}/`);
  } catch (e) {
    console.error(`pack ${pid} fetch failed: ${e.message}`);
    errors++;
    return; // not marked done → retried on next run
  }
  if (!pack) {
    donePacks.add(pid);
    return;
  }

  let packHadError = false;
  const results = await Promise.allSettled(
    flatten(pack).map(async (q) => {
      if (added >= MAX_ADD) return;
      const norm = normalize(q, pack);
      if (!norm) return;
      const ref = db.collection("questionBank").doc(`gq_${norm.sourceId}`);
      const r = await createDoc(ref, norm);
      if (r === "added") added++;
      else if (r === "duplicate") duplicates++;
    })
  );
  for (const r of results) {
    if (r.status === "rejected") {
      errors++;
      packHadError = true;
    }
  }
  // Only mark done if every write succeeded, so failures get retried next run.
  if (!packHadError) donePacks.add(pid);
}

async function runPool(ids, worker, concurrency) {
  let cursor = 0;
  let processedSinceSave = 0;
  async function work() {
    while (cursor < ids.length && added < MAX_ADD) {
      const idx = cursor++;
      await worker(ids[idx]);
      if (++processedSinceSave >= 20) {
        processedSinceSave = 0;
        persist();
        console.log(
          `…${idx + 1}/${ids.length} packs | added ${added}, dupes ${duplicates}, errors ${errors}`
        );
      }
    }
  }
  await Promise.all(Array.from({ length: concurrency }, () => work()));
}

async function main() {
  console.log(`Mirroring gotquestions.online → Firestore project "${PROJECT_ID}"`);

  await login();
  console.log(`Authenticated to gotquestions as ${GQ_EMAIL}`);

  // Find the newest pack id (page 1 is newest-first), then iterate ids 1..max.
  // Iterating ids — rather than enumerating all 374 list pages first — lets
  // writes start on the first pack and keeps progress visible throughout. Gap
  // ids (unpublished) just 404 and are skipped.
  const first = await fetchJson(`${GQ_BASE}/api/packs/?page=1`);
  if (!first) {
    throw new Error("Could not reach gotquestions.online packs API");
  }
  const total = first.count || 0;
  const newestId =
    first.results && first.results[0] && first.results[0].id
      ? Number(first.results[0].id)
      : 6900;
  const maxId = Number(process.env.GQ_MAX_ID) || newestId + 25;
  console.log(
    `Total packs: ${total}. Iterating pack ids 1..${maxId} (concurrency ${CONCURRENCY}). Already done: ${donePacks.size}`
  );

  const ids = [];
  for (let id = 1; id <= maxId; id++) {
    if (!donePacks.has(id)) ids.push(id);
  }

  await runPool(ids, importPack, CONCURRENCY);

  persist();
  console.log(
    `DONE. Added ${added}, duplicates ${duplicates}, errors ${errors}. ` +
      `Packs mirrored: ${donePacks.size}.`
  );
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  persist();
  process.exit(1);
});
