const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS, GET",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS_HEADERS },
  });
}

function textResponse(text, status = 200) {
  return new Response(text, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8", ...CORS_HEADERS },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    // ✅ CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    // ✅ version check (배포 확인용)
    if (request.method === "GET" && path === "/ver") {
      return textResponse("sun-api version = 2026-01-31-3", 200);
    }

    // ✅ 살아있는지 확인용
    if (request.method === "GET" && path === "/") {
      return textResponse("OK - sun-api is running", 200);
    }

    // ✅ POST만 (나머지 엔드포인트는 모두 POST)
    if (request.method !== "POST") {
      return new Response("Only POST allowed", { status: 405, headers: CORS_HEADERS });
    }

    // ✅ API KEY 체크
    if (!env.OPENAI_API_KEY) {
      return json({ error: "OPENAI_API_KEY not configured in Worker secrets" }, 500);
    }

    try {
      // =========================
      // 1) 상담용: /chat (JSON)
      // =========================
      if (path === "/chat") {
        const body = await request.json(); // { messages, temperature, model? }

        const model = body.model || "gpt-4o-mini";
        const messages = body.messages || [];
        const temperature = body.temperature ?? 0.7;

        const openaiRes = await fetch("https://api.openai.com/v1/chat/completions", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${env.OPENAI_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ model, messages, temperature }),
        });

        const text = await openaiRes.text();
        return new Response(text, {
          status: openaiRes.status,
          headers: { "Content-Type": "application/json; charset=utf-8", ...CORS_HEADERS },
        });
      }

      // ==========================================
      // 2) 나도 예술가: /artist/finish (multipart)
      //    ✅ JSON 반환: { "image": "data:image/png;base64,..." } (앱에서 파싱)
      // ==========================================
      if (path === "/artist/finish") {
        const ct = request.headers.get("content-type") || "";
        if (!ct.includes("multipart/form-data")) {
          return json(
            { error: "Use multipart/form-data. Example: curl -F image=@file.png -F style=comic" },
            400
          );
        }

        const form = await request.formData();
        const style = (form.get("style") || "comic").toString();

        // ✅ 앱/라이브러리마다 필드명이 다를 수 있어서 다 받음
        const imageFile =
          form.get("image") ||
          form.get("file") ||
          form.get("photo") ||
          form.get("drawing") ||
          form.get("upload");

        if (!imageFile) {
          return json({ error: "No file found", gotKeys: [...form.keys()] }, 400);
        }

        // ✅ imageFile이 File/Blob 형태인지 최소 검증
        const isBlobLike =
          typeof imageFile === "object" &&
          imageFile !== null &&
          ("arrayBuffer" in imageFile);

        if (!isBlobLike) {
          return json(
            { error: "Uploaded value is not a file/blob", gotType: typeof imageFile, gotKeys: [...form.keys()] },
            400
          );
        }

        const styleMap = {
          abstract: "추상화",
          oil: "유화",
          watercolor: "수채화",
          comic: "만화풍",
          princess: "공주님",
          robot: "로보트",
        };
        const styleKo = styleMap[style] || style;

        const filename =
          (imageFile && typeof imageFile.name === "string" && imageFile.name.trim())
            ? imageFile.name
            : "input.png";

        // 공통: 정사각형 캔버스 꽉 채우고, 밑그림 구도·형태·비율을 거의 그대로 유지
        const compositionRule =
          "출력 이미지는 정사각형 캔버스 전체를 여백 없이 꽉 채워야 하고, 사용자 밑그림의 구도·형태·배치·비율·포즈를 거의 그대로 유지해줘. 형태와 구성을 바꾸지 말고 스타일만 변환해줘.";
        const isPrincess = style === "princess";
        const isRobot = style === "robot";
        let normalPrompt;
        if (isPrincess) {
          normalPrompt = `사용자 밑그림(스케치)을 그대로 따라가줘. 밑그림의 선·형태·포즈·구도·비율·배치를 변경하지 말고 거의 동일하게 유지한 채, 공주님 스타일(의상·분위기)만 입혀서 변환해줘. ${compositionRule} 결과물의 형태와 구도는 밑그림과 거의 같아야 해. 아름다운 공주님 느낌으로 마무리해줘.`;
        } else if (isRobot) {
          normalPrompt = `사용자 밑그림(스케치)을 그대로 따라가줘. 밑그림의 선·형태·포즈·구도·비율·배치를 변경하지 말고 거의 동일하게 유지한 채, 로봇 스타일(금속·기계 느낌)만 입혀서 변환해줘. ${compositionRule} 결과물의 형태와 구도는 밑그림과 거의 같아야 해. 로봇 느낌으로 마무리해줘.`;
        } else {
          normalPrompt = `사용자가 그린 스케치를 기반으로 선 느낌은 최대한 유지하되, 전체를 '${styleKo}' 스타일의 완성된 작품처럼 고퀄로 정리해줘. ${compositionRule} 배경/명암/디테일을 자연스럽게 보완하고 결과가 예쁘게 나오도록.`;
        }

        const safePrompt = isPrincess
          ? `Transform this user sketch into a princess character. CRITICAL: Preserve the exact same composition, pose, proportions, shape, and layout as the sketch—do not alter the figure or arrangement. Only apply princess style (dress, crown, etc.). Fill the entire square canvas with no margins. Family-friendly, beautiful princess style only.`
          : isRobot
            ? `Transform this user sketch into a robot character. CRITICAL: Preserve the exact same composition, pose, proportions, shape, and layout as the sketch—do not alter the figure or arrangement. Only apply robot style (metal, mechanical). Fill the entire square canvas with no margins. Family-friendly, cool robot style only.`
            : `Transform this user sketch into a completely safe, family-friendly artwork. Preserve the exact same composition, pose, and layout as the sketch. Fill the entire square canvas with no margins. Apply '${styleKo}' style. Ensure the result is appropriate for all ages. Output a clean, artistic image only.`;

        async function tryEdit(prompt) {
          const fd = new FormData();
          fd.append("model", "gpt-image-1");
          fd.append("image", imageFile, filename);
          fd.append("prompt", prompt);
          const res = await fetch("https://api.openai.com/v1/images/edits", {
            method: "POST",
            headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}` },
            body: fd,
          });
          const raw = await res.text();
          let data;
          try {
            data = JSON.parse(raw);
          } catch {
            return { ok: false, data: null, status: res.status };
          }
          return { ok: res.ok, data, status: res.status };
        }

        let result = await tryEdit(normalPrompt);

        if (!result.ok && result.data) {
          const code = result.data?.error?.code;
          const msg = (result.data?.error?.message || "").toLowerCase();
          const isModeration = code === "moderation_blocked" || msg.includes("safety_violations") || msg.includes("safety system");
          if (isModeration) {
            result = await tryEdit(safePrompt);
            if (!result.ok && result.data) {
              const code2 = result.data?.error?.code;
              const msg2 = (result.data?.error?.message || "").toLowerCase();
              if (code2 === "moderation_blocked" || msg2.includes("safety")) {
                result = await tryEdit("Create a simple, abstract, colorful and family-friendly artwork based on this image. Safe for all ages. Stylized only.");
              }
            }
          }
        }

        if (!result.ok) {
          if (result.data?.error?.code === "moderation_blocked" || (result.data?.error?.message || "").toLowerCase().includes("safety")) {
            return json(
              { error: "safety_filter", detail: "이미지가 안전 검사에서 차단되었습니다. 다른 스케치로 시도해 주세요." },
              400
            );
          }
          return json({ error: "OpenAI error", detail: result.data }, result.status || 500);
        }

        const b64 = result.data?.data?.[0]?.b64_json;
        if (!b64) {
          return json({ error: "No image in response", detail: result.data }, 500);
        }

        return json({ image: `data:image/png;base64,${b64}` }, 200);
      }

      // ==========================================
      // 3) TTS: POST /tts (JSON → mp3 바이너리 반환)
      //    앱에서 상담 채팅 음성 읽기용 (천사썬/팩폭썬)
      // ==========================================
      if (path === "/tts") {
        const ct = request.headers.get("content-type") || "";
        if (!ct.includes("application/json")) {
          return json({ error: "Use application/json. Body: { input, voice, model?, speed?, instructions? }" }, 400);
        }

        const body = await request.json();
        const input = body.input || body.text || "";
        const voice = body.voice || "alloy";
        const model = body.model || "gpt-4o-mini-tts";
        const speed = body.speed ?? 1.25;
        const instructions = body.instructions || null;

        if (!input || typeof input !== "string") {
          return json({ error: "Missing or invalid 'input' (text to speak)" }, 400);
        }

        const payload = { model, input, voice, speed };
        if (instructions) payload.instructions = instructions;

        const openaiRes = await fetch("https://api.openai.com/v1/audio/speech", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${env.OPENAI_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(payload),
        });

        if (!openaiRes.ok) {
          const errText = await openaiRes.text();
          let errJson;
          try {
            errJson = JSON.parse(errText);
          } catch {
            return json({ error: "OpenAI TTS error", detail: errText.slice(0, 300) }, openaiRes.status);
          }
          return json({ error: "OpenAI TTS error", detail: errJson }, openaiRes.status);
        }

        const mp3Bytes = await openaiRes.arrayBuffer();
        return new Response(mp3Bytes, {
          status: 200,
          headers: {
            "Content-Type": "audio/mpeg",
            "Cache-Control": "no-store",
            ...CORS_HEADERS,
          },
        });
      }

      // =========================
      // 라우트 없음
      // =========================
      return json({ error: "Not Found", available: ["/chat", "/artist/finish", "/tts", "/ver"] }, 404);
    } catch (err) {
      return json({ error: err?.message || String(err) }, 500);
    }
  },
};
