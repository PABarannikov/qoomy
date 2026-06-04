/**
 * Eager image scrape: copy every handout image (questionBank docs with
 * hasImage=true) into Firebase Storage and set each doc's `imageUrl` to the
 * tokenized download URL. Local tool (NOT deployed).
 *
 * Idempotent + resumable: docs that already have `imageUrl` are skipped, so it's
 * safe to Ctrl-C and re-run.
 *
 * Requires ADC (gcloud auth application-default login). Run from qoomy/functions:
 *   node scripts/scrape_images.js
 * Env: IMG_CONCURRENCY (default 5), STORAGE_BUCKET, GQ_PROJECT.
 */
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { randomUUID } = require("crypto");

const PROJECT = process.env.GQ_PROJECT || "qoomy-quiz-game";
const BUCKET = process.env.STORAGE_BUCKET || "qoomy-quiz-game.firebasestorage.app";
const CONCURRENCY = Number(process.env.IMG_CONCURRENCY) || 5;

initializeApp({ credential: applicationDefault(), projectId: PROJECT });
const db = getFirestore();
const bucket = getStorage().bucket(BUCKET);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchBuf(url, tries = 4) {
  for (let a = 1; a <= tries; a++) {
    try {
      const r = await fetch(url, { headers: { "User-Agent": "QoomyMirror/1.0 (+https://qoomy.online)" } });
      if (r.status === 404) return null;
      if (!r.ok) throw new Error("HTTP " + r.status);
      return { buf: Buffer.from(await r.arrayBuffer()), ct: r.headers.get("content-type") || "image/jpeg" };
    } catch (e) {
      if (a === tries) throw e;
      await sleep(400 * a);
    }
  }
}

function extFor(url, ct) {
  const e = (url.split("?")[0].split("#")[0].split(".").pop() || "").toLowerCase();
  if (/^(png|jpg|jpeg|gif|webp)$/.test(e)) return e;
  if (ct.includes("png")) return "png";
  if (ct.includes("webp")) return "webp";
  if (ct.includes("gif")) return "gif";
  return "jpg";
}

let copied = 0, skipped = 0, failed = 0, processed = 0;

async function handle(doc) {
  const data = doc.data();
  if (data.imageUrl) { skipped++; return; }
  const src = data.sourceImageUrl;
  if (!src) { skipped++; return; }
  try {
    const got = await fetchBuf(src);
    if (!got) { failed++; return; }
    const dest = `questionImages/${doc.id}.${extFor(src, got.ct)}`;
    const token = randomUUID();
    await bucket.file(dest).save(got.buf, {
      metadata: { contentType: got.ct, metadata: { firebaseStorageDownloadTokens: token } },
    });
    const url = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(dest)}?alt=media&token=${token}`;
    await doc.ref.update({ imageUrl: url });
    copied++;
  } catch (e) {
    failed++;
    if (failed <= 10) console.error(`fail ${doc.id}: ${e.message}`);
  }
}

async function runPool(items, worker, c) {
  let i = 0;
  async function w() {
    while (i < items.length) {
      const d = items[i++];
      await worker(d);
      if (++processed % 100 === 0) {
        console.log(`…${processed}/${items.length} | copied ${copied}, skipped ${skipped}, failed ${failed}`);
      }
    }
  }
  await Promise.all(Array.from({ length: c }, () => w()));
}

(async () => {
  console.log(`Scraping handout images → gs://${BUCKET} (concurrency ${CONCURRENCY})`);
  const snap = await db
    .collection("questionBank")
    .where("hasImage", "==", true)
    .select("sourceImageUrl", "imageUrl")
    .get();
  console.log(`hasImage docs: ${snap.size}`);
  await runPool(snap.docs, handle, CONCURRENCY);
  console.log(`DONE. copied ${copied}, skipped ${skipped}, failed ${failed}, total ${snap.size}`);
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
