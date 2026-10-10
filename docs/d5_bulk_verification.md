# D5 200건 벌크 검증 결과

- 실행일: 2026-10-10 · org: devorg · 실행: `sf apex run` (Anonymous Apex)
- 스크립트: `scripts/apex/d5_bulk_case.apex`, `scripts/apex/d5_bulk_parts.apex`, 정리 `scripts/apex/d5_cleanup.apex`
- 판정 기준(설계 5-4): insert 구간의 SOQL·DML **횟수**가 20건과 200건에서 같고 행 수만 늘면 통과
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

준비(측정 구간 밖): `BULK5 차량` 위치 + 부품 12종(Compressor 4, General 8) 제품 항목 각 재고 10,000, 진행 중 접수 10건에 출동 1건씩. 사용 부품은 ProductItemId 방식, 수량 1.

| 항목                                             | 20건          | 200건         |
| ------------------------------------------------ | ------------- | ------------- |
| insert 구간 SOQL                                 | **+3**        | **+3**        |
| insert 구간 DML                                  | **+1**        | **+1**        |
| insert 구간 DML 행                               | 20            | 200           |
| 트랜잭션 전체 SOQL / DML                         | 9 / 4         | 9 / 4         |
| CPU (트랜잭션 전체)                              | 365 ms        | 1,056 ms      |
| 판정 만료일 채워짐                               | 20 / 20       | 200 / 200     |
| 판정 누락(자동·최종 판정 비어 있음)              | 0             | 0             |
| 정리 후 남은 출동 / 제품 항목 / 위치 / 사용 부품 | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| **판정**                                         | **통과**      | **통과**      |

insert 구간 SOQL·DML 내역

| 단계                                                                              | SOQL  | DML   | 비고                                                                              |
| --------------------------------------------------------------------------------- | ----- | ----- | --------------------------------------------------------------------------------- |
| before insert `WarrantyService.judgeChargeTypes` ① 출동 + 접수 생성일 + 장비 보증 | 1     | 0     |                                                                                   |
| ② 제품 항목 → 부품 Id                                                             | 1     | 0     | ProductItemId 방식은 before insert 시점에 Product2Id가 비어 있음                  |
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

## 3. 결론

- 두 트리거 모두 20건 → 200건에서 **SOQL·DML 횟수가 같고 행 수만 증가** → 루프 안 SOQL/DML 없음, 벌크 안전.
- 한도 여유: 200건 기준 SOQL 9/100, DML 4/150, CPU 1,056/10,000 ms.
- 정리 스크립트로 테스트 데이터 전부 삭제, 남은 건수 0 확인.

## 4. 테스트 초안 결과 (`sf apex run test`, 2026-10-11, CaseStatsService 1.3·ProductConsumedTriggerHandler 1.1 반영)

| 클래스                 | 메서드                                                                                                                                                                                                  | 결과     |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| CaseTriggerHandlerTest | thirdCaseOnSameAssetIsRepeatFailure / sameAssetThreeInOneBatchFlagsOnlyThird / bulkInsertUpdatesAssetTotals / deleteDecrementsAssetTotal / switchOffSkipsAllLogic / updateRecalculatesOldNewAndCanceled | 6/6 Pass |
| WarrantyServiceTest    | twoYearAssetCompressorFreeGeneralPaid / unknownWarrantyIsPaid / manualChargeTypeIsNotOverwritten / bulkInsertJudgesAll / extendedWarrantyGeneralIsFree                                                  | 5/5 Pass |

| 클래스·트리거                 | 커버리지 | 빠진 부분 (D6 보강)                                                                                                  |
| ----------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------- |
| CaseTrigger                   | 100%     |                                                                                                                      |
| ProductConsumedTrigger        | 100%     |                                                                                                                      |
| ProductConsumedTriggerHandler | 100%     | (1.1에서 before update 재판정 제거)                                                                                  |
| CaseTriggerHandler            | 92%      | afterUndelete, 재계산 대상이 아닌 수정(제목 등)을 건너뛰는 분기                                                      |
| WarrantyService               | 89%      | 빈 입력, Product2Id 직접 지정 경로, 접수 없는 출동(오늘 기준), 장비 없는 출동, 압축기·연장 만료일 둘 다 있을 때 비교 |
| TriggerHandler                | 76%      | 우회(bypassedHandlers), 쓰지 않는 가상 이벤트                                                                        |
| CaseStatsService              | 68%      | D4 메서드 `applyRepeatFailureFlags`·`markRepeatFailures` (트리거 미사용, D6에서 정리)                                |
| Org 전체                      | 77%      | 목표 85% (D6)                                                                                                        |

## 5. 후속 변경과 이 검증의 관계 (2026-10-11)

- **CaseStatsService 1.3**: 묶음 안에서는 `Trigger.new` 순서대로 세어 기준 횟수째부터만 반복 고장 표시. 1절의 벌크 실행은 1.2 기준이라 "반복 고장 표시 200/200"은 1.3에서는 달라짐(장비별 3번째 접수부터 표시). **쿼리·DML 구조는 같으므로 SOQL·DML 횟수 비교 결과(통과)는 그대로 유효**.
- **ProductConsumedTriggerHandler 1.1**: before update 재판정 제거(출동·제품 항목·부품은 생성 후 수정 불가). 2절은 insert만 측정했으므로 영향 없음.
