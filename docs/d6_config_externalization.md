# D6 기준값 외부화 점검

- 점검일: 2026-10-12 · 대상: `force-app/main/default/classes`의 Apex 전체(테스트 제외)
- 결론: **새로 옮길 값 없음.** 업무 기준값은 이미 Custom Metadata, Apex에 사용자에게 보이는 메시지는 없음(오류 메시지는 Validation Rule)

## 1. 무엇을 어디에 두나 (선택 기준)

| 구분          | Custom Metadata Type                                                         | Custom Setting (List / Hierarchy)                      | Custom Label                                 |
| ------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------ | -------------------------------------------- |
| 담는 것       | 업무 기준값·매핑 표 (일수, 횟수, 개월, 금액, 스위치)                         | 사용자·프로필별로 달라지는 설정, 자주 바뀌는 운영 값   | 화면·메시지에 보이는 문구 (다국어)           |
| 배포          | **메타데이터라 값까지 배포됨** (Sandbox → 운영 이관 쉬움)                    | 데이터라 배포 안 됨 (org마다 따로 입력)                | 메타데이터, 번역 워크벤치로 다국어           |
| 읽기          | `getInstance()` / `getAll()` — **SOQL 한도 안 씀**                           | `getInstance()` / `getOrgDefaults()` — SOQL 한도 안 씀 | `System.Label.이름`, LWC `@salesforce/label` |
| 수식·Flow에서 | `$CustomMetadata.타입.레코드.필드` 로 Formula·Validation·Flow에서 참조 가능  | `$Setup.설정.필드` (Hierarchy)                         | `$Label.이름`                                |
| 테스트        | 테스트에서 레코드를 insert할 수 없음 → 기본값에 의존하거나 테스트용 override | 테스트에서 insert 가능                                 | 그대로 사용                                  |
| 우리 선택     | **기본**                                                                     | 현재 사용 안 함 (사용자별로 다른 값이 없음)            | LWC 화면 만들 때(D7~) 버튼·메시지 문구       |

판단 순서: 사용자에게 보이는 문구인가 → Label / 사용자별로 다른가 → Hierarchy Setting / 그 외 업무 기준값 → **Custom Metadata**.

## 2. 우리 프로젝트 적용 표

| 값                                                                        | 지금 위치                                                                            | 쓰는 곳                                                | 판단                                                                                             |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| 반복 고장 기간 90일                                                       | `ServiceSetting__mdt.RepeatFailureDays`                                              | CaseStatsService (트리거·Batch)                        | 외부화 완료                                                                                      |
| 반복 고장 기준 3건                                                        | `ServiceSetting__mdt.RepeatFailureCount`                                             | CaseStatsService                                       | 외부화 완료                                                                                      |
| 보증 기간 12 / 36 / 24개월                                                | `WarrantyPolicy__mdt.Months__c` (General·Compressor·Extended)                        | Asset 보증 만료일 Formula 3개 → WarrantyService가 읽음 | 외부화 완료                                                                                      |
| 대리점 시작 유예 3개월, 특약 상한 6개월                                   | `ServiceSetting__mdt`                                                                | Asset `fmWarrantyStartDate__c` Formula                 | 외부화 완료                                                                                      |
| 출장비 30,000 · 승인 기준 500,000 · SLA 24/48/6시간 · 보증 만료 안내 30일 | `ServiceSetting__mdt`                                                                | (승인 프로세스·SLA·안내 기능에서 쓸 예정)              | 외부화 완료, 아직 Apex 사용처 없음                                                               |
| 트리거 켜기/끄기                                                          | `TriggerSetting__mdt.IsActive__c` (Case·ProductConsumed)                             | TriggerHandler                                         | 외부화 완료                                                                                      |
| `DEFAULT_REPEAT_DAYS = 90`, `DEFAULT_REPEAT_COUNT = 3`                    | CaseStatsService 상수                                                                | Custom Metadata 레코드가 **없을 때만** 쓰는 예비값     | **유지** (레코드 삭제 사고 대비, 값은 메타데이터와 같게)                                         |
| `'Canceled'`                                                              | CaseStatsService·CaseTriggerHandler 상수                                             | 취소 접수 제외                                         | **유지** — picklist API 이름(값의 정체성)이지 기준값이 아님                                      |
| `'Free'` / `'Paid'` / `'Compressor'`                                      | WarrantyService 상수                                                                 | 유·무상 판정, 부품 분류                                | **유지** — picklist API 이름                                                                     |
| Batch 범위 200                                                            | `AssetRepeatFailureSchedulable.BATCH_SIZE`                                           | Batch 실행 단위                                        | **유지** — 기술 설정(트리거 묶음 크기와 맞춤). 운영 중 조정이 필요해지면 ServiceSetting으로 이동 |
| 예약 시각 매일 02:00                                                      | `scripts/apex/d6_schedule.apex`의 CRON 식                                            | 예약 등록 시 1회                                       | **유지** — 예약 작업 자체가 설정. 바꾸려면 예약 해제 후 다시 등록                                |
| 사용자에게 보이는 메시지                                                  | Validation Rule 오류 메시지 (Asset_Required, Closed_Lock, OverrideReason_Required …) | 저장 화면                                              | Apex에는 없음. D7 LWC의 버튼·안내 문구는 Custom Label(`BTN_`, `MSG_`, `LABEL_`)로 만들 예정      |
| Batch finish 로그 문구                                                    | AssetRepeatFailureBatch `System.debug`                                               | 개발자용 Debug Log                                     | 사용자 노출 아님 → 유지                                                                          |

## 3. 옮기지 않은 이유 (요약)

- **picklist 값**(`Canceled`, `Free`, `Paid`, `Compressor`)은 "기준"이 아니라 데이터의 이름이라, 메타데이터로 빼면 오히려 값과 코드가 따로 움직일 위험이 생김. 한 클래스 안에서 상수로 한 번만 선언.
- **예비값**(90·3)은 메타데이터 레코드가 지워졌을 때 트리거가 멈추지 않게 하는 안전장치. 실제 기준은 메타데이터.
- **기술 설정**(Batch 범위, CRON)은 업무 담당자가 바꾸는 값이 아님.

## 4. 남은 일

- D7 LWC부터 화면 문구는 Custom Label로 (사내 규칙: `BTN_`, `MSG_`, `LABEL_`, `MISC_`)
- 승인 프로세스(예외 무상·고액)에서 `ApprovalAmount` 500,000을 기준 조건에 사용할 때, 승인 프로세스 조건은 Custom Metadata를 직접 참조할 수 없어 수식 필드 등 우회 방법 검토 필요
