# 한결공조 ERP Mock (Cloudflare Workers + D1)

재고의 원본(마스터)인 ERP를 흉내 내는 작은 서버. 한결공조 AS(Salesforce)가 부품 사용(IF-03)·재고 이동(IF-06)을 알리면 위치(창고 `WAREHOUSE` / 기사 차량 `VAN`)별 재고를 줄이고 늘리며 이력을 남긴다.

## API

| 메서드 | 경로                          | 인증             | 내용                                                                                                         |
| ------ | ----------------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------ |
| GET    | `/health`                     | 없음             | 상태 확인 (시연 전 깨우기용)                                                                                 |
| GET    | `/`                           | 없음             | 위치별 재고·최근 이력 50건 화면 + ERP 입고·조정 입력 (F5로 새로 고침)                                        |
| POST   | `/ui/stock/receive`           | 없음 (화면 전용) | 화면의 입고 입력 `{ locationCode, partCode, quantity, note }` — 로직은 `/api/stock/receive`와 같음           |
| POST   | `/ui/stock/adjust`            | 없음 (화면 전용) | 화면의 조정 입력 `{ locationCode, partCode, quantityChange(±), note }` — 로직은 `/api/stock/adjust`와 같음   |
| GET    | `/api/movements?after=N`      | `x-api-key`      | 이력 번호 N 이후 변동 (IF-02 역방향, 최대 500건, `latestId` 포함)                                            |
| POST   | `/api/stock/receive`·`adjust` | `x-api-key`      | ERP 입고·조정 (시스템용)                                                                                     |
| GET    | `/api/stock?location=CODE`    | `x-api-key`      | 재고 조회 (IF-04 창고 재고 조회와 같은 형식)                                                                 |
| POST   | `/api/stock/consume`          | `x-api-key`      | 사용 차감 `{ items: [{ refId, locationCode, partCode, quantity, workOrderNumber }] }` (최대 200건)           |
| POST   | `/api/stock/transfer`         | `x-api-key`      | 재고 이동 `{ items: [{ refId, fromLocationCode, toLocationCode, partCode, quantity, reference }] }`          |
| POST   | `/api/admin/seed`             | `x-api-key`      | 초기 재고 적재 `{ reset, locations: [{ code, name, type }], stock: [{ locationCode, partCode, quantity }] }` |
| POST   | `/api/admin/maintenance`      | `x-api-key`      | 시연용 장애 모드 `{ on: true }` → API가 503                                                                  |

- 건별 결과 `status`: `OK`(남은 수량 포함) / `REJECTED`(`code`: `INSUFFICIENT_STOCK`, `UNKNOWN_LOCATION`, `UNKNOWN_PART`, `INVALID_QUANTITY`, `INVALID_REQUEST`)
- 같은 `refId`(Salesforce 레코드 Id)가 다시 오면 처음 결과를 그대로 돌려줌 (`duplicate: true`) → 재전송해도 두 번 차감되지 않음
- HTTP: 업무 결과 200, 키 오류 401, 요청 형식 오류 400, 장애 모드 503, 서버 오류 500

## 수량 단위

- 재고·이력마다 단위를 저장 (초기 적재 때 Salesforce 재고 단위 그대로: `Each`, `kg`). 재고 이동으로 새로 생기는 재고는 출발지 단위
- API 응답(재고 조회, 차감·이동 결과)에 `unit` 포함. 화면 표기는 `Each` → 개, `kg` → kg (ERP 쪽 표기. Salesforce 표기는 Salesforce에서 따로 관리)

## 배포 (처음 한 번, 약 10분)

`erp-mock` 폴더에서 PowerShell로 실행.

```powershell
cd C:\project\my-first-project\erp-mock
npm install                                    # 처음 한 번 (wrangler 설치)

npx wrangler login                             # 1. 브라우저가 열리면 Cloudflare 로그인 → 허용 (직접)
npx wrangler d1 create hg-erp-mock             # 2. 출력의 database_id 를 wrangler.toml 에 붙여 넣기
npx wrangler d1 execute hg-erp-mock --remote --file=schema.sql --yes   # 3. 표 만들기 (원격은 확인 질문이 있어 --yes, 기존 데이터 지워짐)
npx wrangler secret put API_KEY                # 4. API 키 입력 (화면에 보이지 않음, 직접 정한 긴 문자열)
npx wrangler deploy                            # 5. 배포 → https://hg-erp-mock.<계정>.workers.dev
```

- API 키는 Cloudflare 비밀값과 Salesforce External Credential(`HG_ErpMock`)에만 넣는다. 코드·Git·채팅에 붙여 넣지 않는다
- 5번에서 나온 주소를 Salesforce Named Credential `HG_ErpMock` URL에 넣는다 (다음 단계)

## 시연 전 깨우기

Workers는 잠들지 않지만(첫 요청도 바로 응답), 시연 직전에 상태를 확인한다.

```powershell
Invoke-RestMethod https://hg-erp-mock.<계정>.workers.dev/health   # status = ok 이면 준비 완료
```

브라우저에서 `/`(재고 화면)를 열어 두고 F5로 재고 변화를 확인한다. 입고·조정 입력도 이 화면에서 한다.

### 화면 인증 (시연용)

- 재고 화면과 입고·조정 입력(`/ui/…`)은 **시연용이라 인증을 생략**했다. 주소(`*.workers.dev`)를 공개하지 않는다는 전제
- API 키는 서버 비밀값(`API_KEY`)에만 있고 화면 코드나 브라우저로 나가지 않는다. Salesforce가 쓰는 `/api/…`는 지금처럼 키를 확인(없으면 401)
- 운영이라면: **사람은 로그인(SSO 등), 시스템(Salesforce)은 API 키**로 인증을 분리한다

## 로컬 실행 (로그인 없이)

```powershell
npm run db:local                      # 로컬 D1에 표 만들기
"API_KEY=local-test-key" | Out-File -Encoding ascii .dev.vars   # 로컬 전용 키 (Git 제외)
npm run dev                           # http://127.0.0.1:8787
.\test-local.ps1                      # API 10가지 확인
```
