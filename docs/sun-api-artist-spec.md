# sun-api: 나도 예술가 엔드포인트 스펙

앱은 **API 키를 갖지 않으며** sun-api만 호출합니다. 인증/레이트리밋/바디사이즈는 기존 상담 API와 동일하게 적용하세요.

## POST /artist/finish

### Request

- **Headers**: `Content-Type: application/json` (상담 API와 동일, 인증 토큰 정책 동일)
- **Body** (JSON):
  - `image_base64` (string): 캔버스 PNG를 base64 인코딩한 문자열 (**접두어 없이** 순수 base64만)
  - `style` (string): `abstract` | `oil` | `watercolor` | `comic`

```json
{
  "image_base64": "<base64_png_without_prefix>",
  "style": "abstract"
}
```

### Response (성공)

- **200** + JSON:
  - `result_base64` (string): 생성된 이미지 PNG base64

```json
{
  "result_base64": "<base64_png>"
}
```

### Response (실패)

- **4xx/5xx** 시 앱은 스낵바 "다시 한 번 시도해 주세요"만 노출하며 크래시하지 않음.

### 서버 구현 요약

1. **OPENAI_API_KEY** (서버 환경변수)만 사용. 키는 서버에만 존재하며 앱에는 sk- 키가 포함되면 안 됨.
2. OpenAI Images API **edits** (gpt-image-1) 사용.
3. 입력: 요청의 `image_base64` 디코딩 → PNG 바이트, `style`에 따라 프롬프트 생성.
4. 프롬프트:  
   `"사용자가 그린 스케치를 기반으로 선은 유지하되 전체를 {style} 스타일의 고급 예술작품으로 완성해줘. 배경은 자연스럽게 채우고 조화로운 색감으로 완성해줘."`
5. 출력: 1024x1024 PNG base64 → `result_base64`로 반환.

### 보안

- Flutter 앱에 sk- 키가 포함되면 안 됨.
- 서버에서만 OpenAI 호출.
- CORS/인증은 기존 상담앱 방식 그대로.
