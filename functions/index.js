"use strict";

const { onObjectFinalized } = require("firebase-functions/v2/storage");
const { setGlobalOptions }  = require("firebase-functions/v2");
const admin                 = require("firebase-admin");
const vision                = require("@google-cloud/vision");

admin.initializeApp();

// FIX 1: timeoutSeconds bumped to 60s — Flutter now waits 90s so the
// function completes well before Flutter gives up.
// FIX 2: bucket is explicitly named — prevents silent non-triggering.
//         Replace "your-project-id.appspot.com" with your actual bucket name
//         (find it in Firebase Console → Storage → "gs://..." URL).
setGlobalOptions({
  region:         "us-central1",
  memory:         "512MiB",
  timeoutSeconds: 60,           // was 120 — Flutter waits 90s so keep fn faster
});

const BUCKET_NAME = "your-project-id.appspot.com"; // <-- REPLACE THIS

const db           = admin.firestore();
const visionClient = new vision.ImageAnnotatorClient();

// Helper: get the storage bucket reference
function getBucket() {
  return admin.storage().bucket(BUCKET_NAME);
}

// ── TRIGGER 1 — CNIC Upload ───────────────────────────────────────────────────
exports.onCnicUploaded = onObjectFinalized(
  { bucket: BUCKET_NAME },      // FIX 2: explicit bucket
  async (event) => {
    const filePath = event.data.name ?? "";
    const match = filePath.match(/^users\/([^/]+)\/(cnic_front|cnic_back)\.jpg$/);
    if (!match) return null;

    const uid  = match[1];
    const side = match[2];

    console.log(`[OCR] ${side} uploaded for uid=${uid}`);

    await db.collection("users").doc(uid).set(
      { [`${side}Uploaded`]: true },
      { merge: true },
    );

    const snap = await db.collection("users").doc(uid).get();
    const data = snap.data() ?? {};

    const frontReady = side === "cnic_front" ? true : data.cnic_frontUploaded === true;
    const backReady  = side === "cnic_back"  ? true : data.cnic_backUploaded  === true;

    if (!frontReady || !backReady) {
      console.log(`[OCR] Waiting for other side. front=${frontReady} back=${backReady}`);
      return null;
    }

    await db.collection("users").doc(uid).set(
      { verificationStep: "cnic_processing", ocrStatus: "processing" },
      { merge: true },
    );

    try {
      const bucket = getBucket();
      const [frontBytes] = await bucket.file(`users/${uid}/cnic_front.jpg`).download();

      const [ocrResult] = await visionClient.textDetection({
        image: { content: frontBytes.toString("base64") },
      });
      const rawText = ocrResult.fullTextAnnotation?.text ?? "";

      let backText = "";
      try {
        const [backBytes] = await bucket.file(`users/${uid}/cnic_back.jpg`).download();
        const [backOcr]   = await visionClient.textDetection({
          image: { content: backBytes.toString("base64") },
        });
        backText = backOcr.fullTextAnnotation?.text ?? "";
      } catch (_) {
        console.warn("[OCR] Could not read back image");
      }

      const cnicData = parseCnicText(rawText, backText);

      const [faceDetect] = await visionClient.faceDetection({
        image: { content: frontBytes.toString("base64") },
      });
      cnicData.cnicHasFace = (faceDetect.faceAnnotations?.length ?? 0) > 0;

      await db.collection("users").doc(uid).set({
        cnicData,
        ocrStatus:        "success",
        verificationStep: "ocr_done",
        ocrCompletedAt:   admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      console.log(`[OCR] Done for uid=${uid}`, cnicData);
    } catch (err) {
      console.error("[OCR] Failed:", err);
      await db.collection("users").doc(uid).set({
        ocrStatus:        "failed",
        ocrError:         err.message,
        verificationStep: "ocr_failed",
      }, { merge: true });
    }

    return null;
  }
);

// ── TRIGGER 2 — Selfie Upload ─────────────────────────────────────────────────
exports.onSelfieUploaded = onObjectFinalized(
  { bucket: BUCKET_NAME },      // FIX 2: explicit bucket
  async (event) => {
    const filePath = event.data.name ?? "";
    const match = filePath.match(/^users\/([^/]+)\/selfie\.jpg$/);
    if (!match) return null;

    const uid = match[1];
    console.log(`[FACE] Selfie uploaded for uid=${uid}`);

    // FIX 3: Write the "face_matching" step BEFORE any async work so Flutter
    // sees activity immediately and doesn't time out waiting for a first update.
    await db.collection("users").doc(uid).set(
      { verificationStep: "face_matching", faceMatchStatus: "processing" },
      { merge: true },
    );

    try {
      const bucket = getBucket();

      // FIX 4: Verify cnic_front exists before trying to download it —
      // gives a clear error message instead of a cryptic crash.
      const cnicRef = bucket.file(`users/${uid}/cnic_front.jpg`);
      const [cnicExists] = await cnicRef.exists();
      if (!cnicExists) {
        return _saveFaceResult(uid, "error", 0, "CNIC front image not found — please re-upload your CNIC first");
      }

      const [selfieBytes] = await bucket.file(`users/${uid}/selfie.jpg`).download();
      const [cnicBytes]   = await cnicRef.download();

      // ── Liveness check on selfie ────────────────────────────────────────────
      const [selfieDetect] = await visionClient.faceDetection({
        image: { content: selfieBytes.toString("base64") },
      });
      const selfieFaces = selfieDetect.faceAnnotations ?? [];

      if (selfieFaces.length === 0) {
        return _saveFaceResult(uid, "liveness_failed", 0, "No face detected in selfie");
      }
      if (selfieFaces.length > 1) {
        return _saveFaceResult(uid, "liveness_failed", 0, "Multiple faces detected — use a clear selfie");
      }

      const selfieFace = selfieFaces[0];
      const badLikely  = ["LIKELY", "VERY_LIKELY"];

      if (badLikely.includes(selfieFace.blurredLikelihood)) {
        return _saveFaceResult(uid, "liveness_failed", 0, "Selfie is too blurry — retake in good light");
      }
      if (badLikely.includes(selfieFace.underExposedLikelihood)) {
        return _saveFaceResult(uid, "liveness_failed", 0, "Selfie is too dark — retake in a brighter area");
      }

      // ── Face detection on CNIC front ────────────────────────────────────────
      const [cnicDetect] = await visionClient.faceDetection({
        image: { content: cnicBytes.toString("base64") },
      });
      const cnicFaces = cnicDetect.faceAnnotations ?? [];

      if (cnicFaces.length === 0) {
        return _saveFaceResult(uid, "error", 0, "No face found on CNIC image — re-upload CNIC");
      }

      const cnicFace   = cnicFaces[0];
      const confidence = compareFaceLandmarks(selfieFace, cnicFace);
      console.log(`[FACE] Landmark similarity=${confidence.toFixed(1)}% for uid=${uid}`);

      const THRESHOLD = 72;

      if (confidence >= THRESHOLD) {
        await db.collection("users").doc(uid).set({
          verificationStep:     "completed",
          isVerified:           true,
          faceMatchStatus:      "success",
          faceMatchConfidence:  confidence,
          verifiedAt:           admin.firestore.FieldValue.serverTimestamp(),
          faceMatchCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      } else {
        await _saveFaceResult(
          uid,
          "face_mismatch",
          confidence,
          `Face similarity too low (${confidence.toFixed(1)}%) — please retake your selfie`,
        );
      }

    } catch (err) {
      console.error("[FACE] Failed:", err);
      await _saveFaceResult(uid, "error", 0, err.message);
    }

    return null;
  }
);

// ── Face landmark comparison (unchanged) ─────────────────────────────────────

function compareFaceLandmarks(faceA, faceB) {
  const landmarksA = landmarkMap(faceA.landmarks ?? []);
  const landmarksB = landmarkMap(faceB.landmarks ?? []);

  const KEY_POINTS = [
    "LEFT_EYE", "RIGHT_EYE",
    "LEFT_EYE_LEFT_CORNER", "LEFT_EYE_RIGHT_CORNER",
    "RIGHT_EYE_LEFT_CORNER", "RIGHT_EYE_RIGHT_CORNER",
    "NOSE_TIP", "UPPER_LIP", "LOWER_LIP",
    "MOUTH_LEFT", "MOUTH_RIGHT",
    "LEFT_EAR_TRAGION", "RIGHT_EAR_TRAGION",
  ];

  const boxA = boundingBox(faceA.boundingPoly?.vertices ?? []);
  const boxB = boundingBox(faceB.boundingPoly?.vertices ?? []);

  let totalScore = 0;
  let count      = 0;

  for (const pt of KEY_POINTS) {
    if (!landmarksA[pt] || !landmarksB[pt]) continue;
    const nA   = normalize(landmarksA[pt], boxA);
    const nB   = normalize(landmarksB[pt], boxB);
    const dist = Math.sqrt(Math.pow(nA.x - nB.x, 2) + Math.pow(nA.y - nB.y, 2));
    totalScore += Math.max(0, 1 - dist / 0.3) * 100;
    count++;
  }

  return count === 0 ? 0 : totalScore / count;
}

function landmarkMap(landmarks) {
  const map = {};
  for (const lm of landmarks) {
    if (lm.type && lm.position) map[lm.type] = lm.position;
  }
  return map;
}

function boundingBox(vertices) {
  if (!vertices.length) return { x: 0, y: 0, w: 1, h: 1 };
  const xs = vertices.map(v => v.x ?? 0);
  const ys = vertices.map(v => v.y ?? 0);
  const minX = Math.min(...xs), maxX = Math.max(...xs);
  const minY = Math.min(...ys), maxY = Math.max(...ys);
  return { x: minX, y: minY, w: maxX - minX || 1, h: maxY - minY || 1 };
}

function normalize(point, box) {
  return { x: (point.x - box.x) / box.w, y: (point.y - box.y) / box.h };
}

async function _saveFaceResult(uid, step, confidence, reason) {
  console.log(`[FACE] uid=${uid} step=${step} confidence=${confidence} reason="${reason}"`);
  await db.collection("users").doc(uid).set({
    verificationStep:     step,
    faceMatchStatus:      step === "completed" ? "success" : "failed",
    faceMatchConfidence:  confidence,
    faceMatchError:       reason,
    faceMatchCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

// ── CNIC Text Parser (unchanged) ──────────────────────────────────────────────

function parseCnicText(frontText, backText = "") {
  const result   = {};
  const f        = frontText.replace(/\r/g, " ").replace(/\n+/g, "\n").trim();
  const b        = backText.replace(/\r/g, " ").replace(/\n+/g, "\n").trim();
  const combined = `${f}\n${b}`;

  const cnicMatch = combined.match(/\b(\d{5})[-\s](\d{7})[-\s](\d)\b/);
  if (cnicMatch) result.cnicNumber = `${cnicMatch[1]}-${cnicMatch[2]}-${cnicMatch[3]}`;

  const nameMatch = combined.match(
    /\bName\b[:\s]*\n?\s*([A-Z][A-Z\s]{2,40}?)(?=\n|Father|Husband|Date|Gender|$)/im,
  );
  if (nameMatch) result.name = nameMatch[1].trim().replace(/\s{2,}/g, " ");

  const fatherMatch = combined.match(
    /(?:Father|Husband)'?s?\s*Name[:\s]*\n?\s*([A-Z][A-Z\s]{2,40}?)(?=\n|Date|Gender|Identity|$)/im,
  );
  if (fatherMatch) result.fatherOrHusbandName = fatherMatch[1].trim().replace(/\s{2,}/g, " ");

  const dateRx   = /(\d{2}[.\/-]\d{2}[.\/-]\d{4})/g;
  const allDates = [...combined.matchAll(dateRx)].map(m => m[1]);

  const dobMatch = combined.match(/(?:Date\s*of\s*Birth|D\.O\.B|DOB)[:\s]+(\d{2}[.\/-]\d{2}[.\/-]\d{4})/i);
  result.dateOfBirth = dobMatch ? dobMatch[1] : allDates[0] ?? null;

  const issueMatch = combined.match(/(?:Date\s*of\s*Issue|Issue\s*Date)[:\s]+(\d{2}[.\/-]\d{2}[.\/-]\d{4})/i);
  result.dateOfIssue = issueMatch ? issueMatch[1] : allDates[1] ?? null;

  const expiryMatch = combined.match(/(?:Date\s*of\s*Expir[yi]|Expiry|Expiration)[:\s]+(\d{2}[.\/-]\d{2}[.\/-]\d{4})/i);
  result.dateOfExpiry = expiryMatch ? expiryMatch[1] : allDates[2] ?? null;

  if (result.dateOfExpiry) {
    const parts = result.dateOfExpiry.split(/[.\/-]/);
    if (parts.length === 3) {
      result.isExpired = new Date(+parts[2], +parts[1] - 1, +parts[0]) < new Date();
    }
  }

  const genderMatch = combined.match(/\bGender\b[:\s]+(M(?:ale)?|F(?:emale)?)\b/i);
  if (genderMatch) {
    const g = genderMatch[1].toUpperCase();
    result.gender = (g === "M" || g === "MALE") ? "Male" : "Female";
  }

  const addrMatch = b.match(
    /(?:Permanent\s*Address|Address|Residence)[:\s]*\n?\s*([\s\S]+?)(?=\n\n|District|Tehsil|Province|$)/im,
  );
  if (addrMatch) {
    result.address = addrMatch[1].split("\n").map(l => l.trim()).filter(Boolean).join(", ");
  }

  result.rawOcrFront = frontText;
  result.rawOcrBack  = backText;
  result.extractedAt = new Date().toISOString();

  return result;
}