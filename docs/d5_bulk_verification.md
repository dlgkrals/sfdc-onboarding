# D5 200건 벌크 검증 결과

- 실행일: 2026-10-10 (insert), 2026-10-11 (update) · org: devorg · 실행: `sf apex run` (Anonymous Apex)
- 스크립트: `scripts/apex/d5_bulk_case.apex`, `scripts/apex/d5_bulk_parts.apex`, `scripts/apex/d5_bulk_case_update.apex`, 정리 `scripts/apex/d5_cleanup.apex`
- 판정 기준(설계 5-4): insert·update 구간의 SOQL·DML **횟수**가 20건과 200건에서 같고 행 수만 늘면 통과
- 조건: 냉동창고·서버실 사업장 장비 제외(긴급 메일 방지), 테스트 데이터 표시 제목 `[BULK5]`, 위치 `BULK5 차량`
- 원본 로그: `logs/` (커밋 제외)

## 1. 접수 트리거 (`CaseTrigger`)

서비스를 직접 부르지 않고 접수 insert만 실행 → 트리거가 반복 고장 표시·장비 집계를 하는지 확인.

| 항목                                   | 20건                   | 200건                    |
| -------------------------------------- | ---------------------- | ------------------------ |
| insert 구간 SOQL                       | **+4**                 | **+4**                   |
| insert 구간 DML                        | **+2**                 | **+2**                   |
| insert 구간 DML 행                     | 40 (접수 20 + 장비 20) | 247 (접수 200 + 장비 47) |
| 트랜잭션 전체 SOQL / DML               | 8 / 2                  | 8 / 2                    |
| CPU                                    | 125 ms                 | 287 ms                   |
| 반복 고장 표시                         | 4 / 20                 | 200 / 200                |
| 장비 누적 접수 합계 (대상 47대)        | 28 → 48 (+20)          | 28 → 228 (+200)          |
| 정리 후 남은 접수 / 재계산 불일치 장비 | 0 / 0대                | 0 / 0대                  |
| **판정**                               | **통과**               | **통과**                 |

insert 구간 SOQL·DML 내역

| 단계                                             | SOQL  | DML   | 비고                                                                         |
| ------------------------------------------------ | ----- | ----- | ---------------------------------------------------------------------------- |
| 저장 전 Flow `Case_BeforeSave_FillFromAsset`     | 2     | 0     | 장비·사업장 조회 (Flow가 묶음 단위로 처리). 코드 밖이라 횟수는 전체에서 역산 |
| before insert `applyRepeatFailureFlagsForInsert` | 1     | 0     | 장비별 최근 90일 접수 집계 1회                                               |
| 저장 (Case insert)                               | 0     | 1     |                                                                              |
| after insert `recalculateAssetCaseStats`         | 1     | 1     | 장비별 집계 1회 + Asset update 1회                                           |
| **합계**                                         | **4** | **2** | 건수와 무관                                                                  |

반복 고장 표시 해석

- 20건: 장비 20대에 1건씩 → 기존 최근 90일 접수가 2건 이상인 장비 4대만 기준 3건을 넘음.
- 200건: 장비 47대에 4~5건씩 한 묶음 → "DB 건수 + 묶음 내 같은 장비 건수 ≥ 3" 이 모두 성립 → 전부 표시 (설계 3-2대로 묶음 안의 첫 접수도 묶음 건수에 포함).

정리(`d5_cleanup.apex`): 접수 delete 1회 → after delete 트리거가 장비 재계산(Asset update 1회). 정리 후 장비 `TotalCaseCount__c`가 실제 접수 수와 다른 장비 0대 → **after delete 자동 재계산 확인**.

## 2. 사용 부품 트리거 (`ProductConsumedTrigger`)

준비(측정 구간 밖): `BULK5 차량` 위치 + 부품 12종(Compressor 4, General 8) 재고 각 10,000, 진행 중 접수 10건에 출동 1건씩. 사용 부품은 ProductItemId 방식, 수량 1.

| 항목                                        | 20건          | 200건         |
| ------------------------------------------- | ------------- | ------------- |
| insert 구간 SOQL                            | **+3**        | **+3**        |
| insert 구간 DML                             | **+1**        | **+1**        |
| insert 구간 DML 행                          | 20            | 200           |
| 트랜잭션 전체 SOQL / DML                    | 9 / 4         | 9 / 4         |
| CPU (트랜잭션 전체)                         | 365 ms        | 1,056 ms      |
| 판정 만료일 채워짐                          | 20 / 20       | 200 / 200     |
| 판정 누락(자동·최종 판정 비어 있음)         | 0             | 0             |
| 정리 후 남은 출동 / 재고 / 위치 / 사용 부품 | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| **판정**                                    | **통과**      | **통과**      |

insert 구간 SOQL·DML 내역

| 단계                                                                              | SOQL  | DML   | 비고                                                                              |
| --------------------------------------------------------------------------------- | ----- | ----- | --------------------------------------------------------------------------------- |
| before insert `WarrantyService.judgeChargeTypes` ① 출동 + 접수 생성일 + 장비 보증 | 1     | 0     |                                                                                   |
| ② 재고 → 부품 Id                                                                  | 1     | 0     | ProductItemId 방식은 before insert 시점에 Product2Id가 비어 있음                  |
| ③ 부품 분류·ERP 단가                                                              | 1     | 0     |                                                                                   |
| 저장 (ProductConsumed insert)                                                     | 0     | 1     | 출동 Roll-Up(`ruPaidPartsTotal__c`) 재계산은 플랫폼 처리로 DML 횟수에 잡히지 않음 |
| **합계**                                                                          | **3** | **1** | 건수와 무관                                                                       |

자동 판정 분포 (실제 데이터의 장비 보증 상태에 따름)

| 분류 / 자동 판정  | 20건 | 200건 |
| ----------------- | ---- | ----- |
| Compressor / Free | 6    | 60    |
| Compressor / Paid | 2    | 8     |
| General / Free    | 5    | 53    |
| General / Paid    | 7    | 79    |

## 3. 접수 update (`d5_bulk_case_update.apex`, 2026-10-11)

준비(측정 구간 밖)로 접수 N건 insert 후, update 3종을 각각 DML 1회로 실행.

| 구간                              | 20건 SOQL / DML / 행 | 200건 SOQL / DML / 행 | 기대 동작                                                                     |
| --------------------------------- | -------------------- | --------------------- | ----------------------------------------------------------------------------- |
| ① 제목만 수정                     | **0 / 1** / 20       | **0 / 1** / 200       | 재계산 없음. 저장 전 Flow도 AssetId가 안 바뀌어 미실행                        |
| ② 장비 변경                       | **3 / 2** / 41       | **3 / 2** / 247       | Flow 2(장비·사업장 재조회) + after update 집계 1 / Case update + Asset update |
| ③ 취소로 전환                     | **1 / 2** / 40       | **1 / 2** / 247       | after update 집계 1 / Case update + Asset update                              |
| 트랜잭션 전체 SOQL / DML / CPU    | 12 / 7 / 349 ms      | 12 / 7 / 980 ms       |                                                                               |
| 누적 접수 합계 (전부 취소 후)     | 48 → 28 = 실제 28    | 228 → 28 = 실제 28    | 취소된 접수는 누적에서 제외                                                   |
| 정리 후 남은 접수 / 재계산 불일치 | 0 / 0대              | 0 / 0대               |                                                                               |
| **판정**                          | **통과**             | **통과**              |                                                                               |

**발견한 결함과 리팩터링** (커리큘럼 "위반 시 리팩터링")

- 첫 실행(CaseTriggerHandler 1.0): ② 장비 변경 SOQL +2, ③ 취소 SOQL +0 → **after update 재계산이 전혀 실행되지 않음**. 누적 합계 48 → 48 (실제 28과 불일치).
- 원인: 재귀 방지 `TriggerHandler.filterUnprocessed`가 **Id 기준**이라, ① 제목 수정 때 "처리 완료"로 기록된 접수를 같은 트랜잭션의 ②·③ update에서도 건너뜀.
- 수정(CaseTriggerHandler 1.1): 접수별 **마지막 처리 상태(장비 Id + 취소 여부)**로 막도록 변경. 같은 상태가 다시 오면(워크플로 재실행) 건너뛰고, 상태가 바뀌면 처리. 회귀 테스트 `consecutiveUpdatesInSameTransactionRecalculate` 추가.
- 수정 후 위 표대로 통과. 결함 실행 로그는 덮어써져 남지 않음(이 문서와 채팅 기록이 근거).

## 4. 결론

- 두 트리거 모두 20건 → 200건에서 insert·update 구간별 **SOQL·DML 횟수가 같고 행 수만 증가** → 루프 안 SOQL/DML 없음, 벌크 안전.
- 한도 여유: 200건 기준 최대 SOQL 12/100, DML 7/150, CPU 1,056/10,000 ms.
- update 벌크에서 재귀 방지 결함을 찾아 수정. 재계산이 필요한 수정(장비 변경·취소 전환)만 Asset DML을 만들고, 그 외 수정은 Asset DML 0.
- 정리 스크립트로 테스트 데이터 전부 삭제, 남은 건수 0 확인.

## 5. 테스트 초안 결과 (`sf apex run test`, 2026-10-11)

| 클래스                 | 메서드                                                                                                                        | 구분                                             | 결과           |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ | -------------- |
| CaseTriggerHandlerTest | thirdCaseOnSameAssetIsRepeatFailure, sameAssetThreeInOneBatchFlagsOnlyThird                                                   | 정상                                             | Pass           |
|                        | updateRecalculatesOldNewAndCanceled, deleteDecrementsAssetTotal, switchOffSkipsAllLogic                                       | 정상                                             | Pass           |
|                        | consecutiveUpdatesInSameTransactionRecalculate                                                                                | 회귀(update 결함)                                | Pass           |
|                        | caseWithoutAssetIsRejected                                                                                                    | **불허**                                         | Pass           |
|                        | bulkInsertUpdatesAssetTotals                                                                                                  | 벌크 200                                         | Pass           |
|                        | bulkPartialRejectKeepsValidTotals                                                                                             | **불허 + 벌크 200** (20건 거부, 180건 저장·집계) | Pass           |
| WarrantyServiceTest    | twoYearAssetCompressorFreeGeneralPaid, unknownWarrantyIsPaid, extendedWarrantyGeneralIsFree, manualChargeTypeIsNotOverwritten | 정상                                             | Pass           |
|                        | overrideWithoutReasonIsRejected                                                                                               | **불허** (사유 없는 판정 변경)                   | Pass           |
|                        | bulkInsertJudgesAll                                                                                                           | 벌크 200                                         | Pass           |
|                        | bulkPartialRejectWithoutReason                                                                                                | **불허 + 벌크 200** (100건 거부, 100건 저장)     | Pass           |
| **합계**               |                                                                                                                               |                                                  | **16/16 Pass** |

| 클래스·트리거                 | 커버리지 | 빠진 부분 (D6 보강)                                                                                                  |
| ----------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------- |
| CaseTrigger                   | 100%     |                                                                                                                      |
| ProductConsumedTrigger        | 100%     |                                                                                                                      |
| ProductConsumedTriggerHandler | 100%     |                                                                                                                      |
| CaseTriggerHandler            | 93%      | afterUndelete, 같은 상태 재실행 건너뛰기(워크플로 재실행 상황)                                                       |
| WarrantyService               | 89%      | 빈 입력, Product2Id 직접 지정 경로, 접수 없는 출동(오늘 기준), 장비 없는 출동, 압축기·연장 만료일 둘 다 있을 때 비교 |
| TriggerHandler                | 55%      | `filterUnprocessed`(CaseTriggerHandler 1.1부터 미사용), 우회(bypassedHandlers), 쓰지 않는 가상 이벤트                |
| CaseStatsService              | 69%      | D4 메서드 `applyRepeatFailureFlags`·`markRepeatFailures` (트리거 미사용, D6에서 정리)                                |
| Org 전체                      | 74%      | 목표 85% (D6). TriggerHandler 미사용 메서드 때문에 77% → 74%                                                         |

## 6. 후속 변경과 이 검증의 관계 (2026-10-11)

- **CaseStatsService 1.3**: 묶음 안에서는 `Trigger.new` 순서대로 세어 기준 횟수째부터만 반복 고장 표시. 1절의 insert 벌크 실행은 1.2 기준이라 "반복 고장 표시 200/200"은 1.3에서는 달라짐(장비별 3번째 접수부터 표시). **쿼리·DML 구조는 같으므로 SOQL·DML 횟수 비교 결과(통과)는 그대로 유효**.
- **ProductConsumedTriggerHandler 1.1**: before update 재판정 제거(출동·재고·부품은 생성 후 수정 불가). 2절은 insert만 측정했으므로 영향 없음.
- **CaseTriggerHandler 1.1**: after update 재귀 방지를 상태 기준으로 변경(3절). insert·delete 경로는 바뀌지 않아 1절 결과 유효.

## 7. D6 보완과 변경 영향 (2026-10-12)

- **200건 update(접수 → 취소)**: 3절 ③ "취소 전환"이 해당 검증(20건·200건 모두 SOQL 1 · DML 2, 전부 취소 후 누적 합계 = 실제 접수 수 28).
- **불허 테스트 보완**: 종결 접수 수정 → `rejectClosedCaseUpdate`(상담원 사용자 runAs, Validation Rule `Case.Closed_Lock`), 판정 변경 사유 누락 → `rejectOverrideWithoutReason`(Validation Rule `ProductConsumed.OverrideReason_Required`). 두 규칙 모두 org에 있음. 결과는 `docs/d6_test_report.md`.
- **CaseStatsService 1.4~1.5 영향**: after insert에서 최근 90일 집계 쿼리가 1회 늘어 접수 200건 insert 구간이 **SOQL 5 · DML 2**(1절의 4 · 2에서 +1). 20건·200건 횟수가 같다는 판정은 그대로. 재실행 로그 `logs/d6_case_200_v15.log`(반복 고장 표시 133/200, 정리 후 불일치 0대).
- **D5 시점 결함(D6에서 발견·수정)**: 1~3절의 검증은 관리자로 실행. 상담원 사용자가 접수를 넣으면 장비 재계산이, 협력 기사가 사용 부품을 넣으면 판정 조회가 필드 권한으로 실패하고 있었음 → CaseStatsService 1.5 · WarrantyService 1.1에서 시스템 모드로 수정. 원인은 org 설정이 아니라 API 67.0의 기본 user mode (오류 원문·재확인: `docs/d6_test_report.md` 4-1절).
