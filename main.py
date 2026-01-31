"""
관공서/프로필 사진 처리 이중 분기 API
- POST /process-photo: image + mode (gov | profile)
- gov: rembg 배경 제거 + 흰색 배경
- profile: OpenAI 이미지 편집 (enhance selfie)
"""
import io
import os
import base64
from typing import Literal

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from openai import OpenAI
from PIL import Image
from rembg import remove, new_session
import uvicorn

app = FastAPI(title="Photo Process API", version="1.0.0")

# OpenAI (profile 모드용). 없으면 profile 요청 시 501
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
PROFILE_PROMPT = "enhance selfie, smooth skin, natural light, clear background"

# rembg 세션: 모델을 직접 로컬에서 로딩
REMBG_SESSION = new_session(model_path="./models/u2net.onnx")


def _apply_white_background(pil_img: Image.Image) -> Image.Image:
    """RGBA 이미지를 흰 배경 위에 합성."""
    if pil_img.mode != "RGBA":
        pil_img = pil_img.convert("RGBA")
    white = Image.new("RGBA", pil_img.size, (255, 255, 255, 255))
    return Image.alpha_composite(white, pil_img).convert("RGB")


@app.post("/process-photo")
async def process_photo(
    image: UploadFile = File(...),
    mode: Literal["gov", "profile"] = Form(...),
):
    """
    - mode=gov: 얼굴 보정 없음, 배경 제거 + 흰색 배경
    - mode=profile: 얼굴 포함 전체 보정 (OpenAI image edit)
    """
    if not image.content_type or not image.content_type.startswith("image/"):
        raise HTTPException(400, "image 파일이 필요합니다.")

    try:
        raw = await image.read()
        input_pil = Image.open(io.BytesIO(raw)).convert("RGB")
    except Exception as e:
        raise HTTPException(400, f"이미지 처리 실패: {e}") from e

    if mode == "gov":
        try:
            out_pil = remove(input_pil, session=REMBG_SESSION)
            out_pil = _apply_white_background(out_pil)
        except Exception as e:
            print("rembg error:", e)
            raise HTTPException(500, f"배경 제거 실패: {e}") from e

    elif mode == "profile":
        if not OPENAI_API_KEY:
            raise HTTPException(501, "profile 모드는 OPENAI_API_KEY 설정이 필요합니다.")
        try:
            client = OpenAI(api_key=OPENAI_API_KEY)
            buf_in = io.BytesIO()
            input_pil.save(buf_in, format="PNG")
            buf_in.seek(0)
            resp = client.images.edit(
                image=buf_in.read(),
                prompt=PROFILE_PROMPT,
                n=1,
                response_format="b64_json",
            )
            b64 = getattr(resp.data[0], "b64_json", None)
            if not b64:
                raise HTTPException(502, "OpenAI 응답에 이미지가 없습니다.")
            out_pil = Image.open(io.BytesIO(base64.b64decode(b64))).convert("RGB")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(502, f"OpenAI 이미지 편집 실패: {e}") from e

    else:
        raise HTTPException(400, "mode는 gov 또는 profile이어야 합니다.")

    buf_out = io.BytesIO()
    out_pil.save(buf_out, format="PNG", quality=95)
    buf_out.seek(0)
    return Response(
        content=buf_out.getvalue(),
        media_type="image/png",
        headers={"Content-Disposition": "inline; filename=processed.png"},
    )


@app.get("/health")
def health():
    return {"status": "ok"}


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 10000))
    uvicorn.run("main:app", host="0.0.0.0", port=port)
