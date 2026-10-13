# D6 테스트 결과 보고

- 실행일: 2026-10-12 · org: devorg · 실행: `sf apex run test --test-level RunLocalTests --code-coverage`
- 결과: **36개 메서드 모두 통과** (Tests Ran 40 = 메서드 36 + @TestSetup 4) · **org 전체 커버리지 94%** (목표 85%, 운영 배포 기준 75%)
- 테스트 데이터: `TestDataFactory`(고객사·사업장·장비·접수·출동·부품·재고·사용 부품·테스트 사용자)로 공통화
- 메서드 이름 접두어: `normal` = 정상, `reject` = 불허, `bulk` = 벌크 200건. 모든 메서드에 `Test.startTest/stopTest`와 `Assert` 사용
- 원본 결과: `logs/d6_test/`, `logs/d6_test_result.txt` (커밋 제외)

## 1. 구분별 개수

| 클래스                                   | 정상   | 불허  | 벌크                | 계     |
| ---------------------------------------- | ------ | ----- | ------------------- | ------ |
| CaseTriggerHandlerTest (접수 트리거)     | 10     | 2     | 2 (1개는 불허 포함) | 14     |
| CaseStatsServiceTest (집계 서비스 직접)  | 3      | 1     | 1                   | 5      |
| WarrantyServiceTest (유·무상 판정)       | 8      | 1     | 2 (1개는 불허 포함) | 11     |
| AssetRepeatFailureBatchTest (Batch)      | 4      | 0     | 1                   | 5      |
| AssetRepeatFailureSchedulableTest (예약) | 1      | 0     | 0                   | 1      |
| **합계**                                 | **26** | **4** | **6**               | **36** |

## 2. 테스트 목록

### CaseTriggerHandlerTest

| 메서드                                        | 구분       | 확인                                                                                        |
| --------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------- |
| normalThirdCaseOnSameAssetIsRepeatFailure     | 정상       | 같은 장비 3건을 차례로 → 3번째만 반복 고장                                                  |
| normalSameAssetThreeInOneBatchFlagsOnlyThird  | 정상       | 한 번에 3건 → 묶음 안에서도 3번째만                                                         |
| normalAssetRepeatFailureFlaggedOnInsert       | 정상       | (D6) 2건일 때 장비 최근 접수 2·반복 고장 아님, 3건이면 3·반복 고장 장비                     |
| normalUpdateRecalculatesOldNewAndCanceled     | 정상       | 장비 변경 시 이전·새 장비, 취소 전환 시 재계산                                              |
| normalDeleteDecrementsAssetTotal              | 정상       | 삭제 후 누적 수 감소                                                                        |
| normalUndeleteRestoresAssetTotal              | 정상       | (D6) 복원 후 누적 수 원래대로                                                               |
| normalSwitchOffSkipsAllLogic                  | 정상       | 스위치 끔 → 표시·집계 없음                                                                  |
| normalBypassedHandlerSkipsLogic               | 정상       | (D6) 정적 우회 → 집계 없음                                                                  |
| normalRunOutsideTriggerDoesNothing            | 정상       | (D6) 트리거 밖 run() → 쿼리·DML 0                                                           |
| normalRegressionConsecutiveUpdatesRecalculate | 정상(회귀) | 같은 트랜잭션 제목 → 장비 변경 → 취소, 매번 재계산 (D5 결함 재발 방지)                      |
| rejectCaseWithoutAsset                        | 불허       | 장비 없는 접수 → DmlException(Asset_Required), 저장 0건                                     |
| rejectClosedCaseUpdate                        | 불허       | (D6) **상담원 사용자(runAs)** 가 종결 접수 수정 → DmlException(Closed_Lock), 장비 집계 유지 |
| bulkInsertUpdatesAssetTotals                  | 벌크       | 200건 → 장비별 누적 40·최근 접수 40·반복 고장 장비, 접수 반복 고장 190건                    |
| bulkPartialRejectKeepsValidTotals             | 벌크·불허  | 200건 중 20건 거부 → 180건만 집계                                                           |

### CaseStatsServiceTest (D6 신규)

| 메서드                             | 구분 | 확인                                                        |
| ---------------------------------- | ---- | ----------------------------------------------------------- |
| normalEmptyInputReturnsNothing     | 정상 | null·빈 집합·null만 든 집합 → 0, DML 없음                   |
| normalCanceledNewCaseNotCounted    | 정상 | 취소 상태로 들어온 접수는 묶음 건수·누적·최근 접수에서 제외 |
| normalAssetWithoutCasesResetToZero | 정상 | 접수 없는 장비 → 0 / 비어 있음 / false로 되돌림             |
| rejectDeletedAssetCountsOnlySaved  | 불허 | 삭제된 장비가 섞이면 그 장비만 실패, 성공 수만 반환         |
| bulkRecalculate200Assets           | 벌크 | 장비 200대 → SOQL 2 · DML 1                                 |

### WarrantyServiceTest

| 메서드                                      | 구분      | 확인                                                                                   |
| ------------------------------------------- | --------- | -------------------------------------------------------------------------------------- |
| normalTwoYearAssetCompressorFreeGeneralPaid | 정상      | 2년 차: 압축기 무상(압축기 만료일), 일반 유상(기본 만료일), 분류·단가                  |
| normalUnknownWarrantyIsPaid                 | 정상      | 보증 미확정 → 유상, 만료일 없음                                                        |
| normalExtendedWarrantyGeneralIsFree         | 정상      | 연장보증 → 일반 부품 무상(연장 만료일)                                                 |
| normalManualChargeTypeIsNotOverwritten      | 정상      | 사람이 정한 유상 유지                                                                  |
| normalTechnicianUserJudgesViaTrigger        | 정상      | (D6) **협력 기사 사용자(runAs)** 가 자기 차량 재고로 부품 입력 → 판정·만료일·분류 정상 |
| normalEmptyInputDoesNothing                 | 정상      | (D6) 빈 입력 → 쿼리 0                                                                  |
| normalProduct2IdUsedDirectly                | 정상      | (D6) Product2Id가 있으면 재고를 거치지 않고 분류                                       |
| normalDateHelpersHandleMissingAndLaterDates | 정상      | (D6) 출동·접수·장비 없음, 압축기·연장 만료일 중 늦은 날                                |
| rejectOverrideWithoutReason                 | 불허      | 사유 없이 자동 판정과 다르게 확정 → DmlException(OverrideReason_Required)              |
| bulkInsertJudgesAll                         | 벌크      | 200건 → 압축기 100 무상, 일반 100 유상, 누락 0                                         |
| bulkPartialRejectWithoutReason              | 벌크·불허 | 200건 중 사유 없는 100건만 거부                                                        |

### AssetRepeatFailureBatchTest (D6 신규)

| 메서드                             | 구분 | 확인                                                                                           |
| ---------------------------------- | ---- | ---------------------------------------------------------------------------------------------- |
| normalOldCasesReleaseRepeatFailure | 정상 | `Test.setCreatedDate`로 접수 3건을 100일 전으로 → Batch 후 반복 고장 해제, 최근 0, 누적 3 유지 |
| normalRecentCasesKeepRepeatFailure | 정상 | 최근 3건 → 유지                                                                                |
| normalPartlyOldCasesRecountRecent  | 정상 | 4건 중 2건만 기간 밖 → 최근 2, 해제                                                            |
| normalQuietAssetNotSelected        | 정상 | 최근 접수 0·반복 고장 아님 → Batch 대상 아님(값 그대로)                                        |
| bulk200AssetsCorrected             | 벌크 | 잘못 남은 반복 고장 장비 200대 → Batch 1회(범위 200)로 모두 해제, 실행 단위 1, 오류 0          |

### AssetRepeatFailureSchedulableTest (D6 신규)

| 메서드                      | 구분 | 확인                                                        |
| --------------------------- | ---- | ----------------------------------------------------------- |
| normalScheduleEnqueuesBatch | 정상 | 매일 02:00 예약(WAITING) → 실행 시 Batch Apex가 큐에 들어감 |

## 3. 클래스별 커버리지

| 클래스·트리거                        | 커버리지 | 실행되지 않은 줄                                                               |
| ------------------------------------ | -------- | ------------------------------------------------------------------------------ |
| CaseTrigger · ProductConsumedTrigger | 100%     |                                                                                |
| ProductConsumedTriggerHandler        | 100%     |                                                                                |
| AssetRepeatFailureSchedulable        | 100%     |                                                                                |
| CaseStatsService                     | 99%      | Custom Metadata 레코드가 없을 때의 기본값 분기                                 |
| WarrantyService                      | 99%      | 부품을 찾지 못했을 때 단가를 비우는 분기(재고·부품이 없는 사용 부품)           |
| CaseTriggerHandler                   | 98%      | 같은 상태 재실행 건너뛰기(워크플로 재실행 시에만 발생)                         |
| AssetRepeatFailureBatch              | 96%      | 새로 반복 고장으로 표시되는 경우의 카운트(재계산 직후라 테스트에서 발생 안 함) |
| TriggerHandler                       | 78%      | 재정의하지 않은 이벤트(before update·before delete 등) 분기                    |
| **org 전체**                         | **94%**  |                                                                                |

D5 대비: 74% → **94%**. TriggerHandler 55% → 78% (filterUnprocessed 삭제 + 우회·트리거 밖 실행 테스트), CaseStatsService 69% → 99% (미사용 메서드 삭제 + 경계 테스트).

## 4. 테스트로 찾은 결함 (D6)

| 결함                                                               | 원인                                                                                                                           | 수정                                                                               |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| **협력 기사가 사용 부품을 저장할 수 없음**                         | WarrantyService가 출동의 `CaseId`·장비 보증 필드를 조회하는데, 기사는 접수·장비 권한이 없어 "No such column 'CaseId'" 오류     | WarrantyService 1.1: 조회를 `WITH SYSTEM_MODE`로 명시                              |
| **상담원이 접수를 넣으면 장비 집계가 저장되지 않음** (조용히 실패) | 장비 집계 필드는 사용자에게 읽기 전용인데, 트리거의 Asset update가 실행 사용자 필드 권한으로 막힘("fields being inaccessible") | CaseStatsService 1.5: 집계 조회 `WITH SYSTEM_MODE`, 저장 `AccessLevel.SYSTEM_MODE` |
| Batch도 같은 위험                                                  | 새 필드는 관리자에게도 읽기 전용                                                                                               | Batch 조회 `WITH SYSTEM_MODE` + 서비스 1.5                                         |

D4·D5의 테스트와 벌크 검증은 모두 관리자로 실행해 드러나지 않았고, D6에서 상담원·기사 사용자(`System.runAs`) 테스트를 추가하면서 발견.

### 4-1. 수정 전 오류 원문과 원인 재확인 (2026-10-12)

수정 전 코드(커밋 9070a35: CaseStatsService 1.3 `without sharing`, WarrantyService 1.0 `inherited sharing`)에는 `WITH USER_MODE`·`WITH SECURITY_ENFORCED`·`Security.stripInaccessible`·`AccessLevel.USER_MODE`가 **하나도 없음**. 그런데도 권한 오류가 난 이유를 가리기 위해, 수정 전과 같은 문장을 **API 67.0 클래스와 API 66.0 클래스**에 넣고 같은 사용자로 실행하는 임시 진단 테스트를 돌림(진단 클래스는 실행 후 org에서 삭제, 남은 것 0개. 원문 `logs/d6_diag/diag_mode.txt`, 커밋 제외).

| 사용자 (권한 집합)        | 수정 전 코드 위치                                    | 실행한 문장                                                                                                      | API 67.0 결과 (오류 원문)                                                                                                                                                                         | API 66.0 결과        |
| ------------------------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------- |
| 상담원 (HG_CallCenter)    | CaseStatsService 1.3 `recalculateAssetCaseStats`     | `Database.update(assetsToUpdate, false)` (TotalCaseCount__c·LastCaseDate__c)                                     | `CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY` · "Operation failed due to fields being inaccessible on Sobject Asset, check errors on Exception or Result! fieldNames: TotalCaseCount__c,LastCaseDate__c" | 성공                 |
| 상담원 (HG_CallCenter)    | CaseStatsService 1.3 접수 집계 조회                  | `SELECT AssetId, COUNT(Id) … FROM Case … GROUP BY AssetId`                                                       | 오류 없이 **0건** (관리자 소유 접수가 상담원에게 안 보여 집계에서 빠짐)                                                                                                                           | —                    |
| 협력 기사 (HG_Technician) | WarrantyService 1.0 `applyAutoChargeTypes` 출동 조회 | `SELECT Id, CaseId, Case.CreatedDate, AssetId, Asset.HasExtendedWarranty__c, Asset.fm…EndDate__c FROM WorkOrder` | `System.QueryException` · "No such column 'CaseId' on entity 'WorkOrder'. If you are attempting to use a custom field, be sure to append the '__c' after the custom field name."                  | 성공 (CaseId 조회됨) |

- **원인: org 설정이 아니라 Apex 클래스 API 버전.** API 67.0부터 Apex의 조회·DML은 기본이 user mode(실행 사용자의 오브젝트·필드 권한과 공유 적용)이고, 66.0 이하는 system mode가 기본. 우리 클래스는 모두 `sourceApiVersion` 67.0이라 모드를 적지 않은 문장이 user mode로 실행됨. 같은 사용자·같은 문장이 66.0 클래스에서는 성공하므로 org 설정이 원인일 수 없음
- 클래스의 `without sharing`은 이 동작을 바꾸지 않음(상담원 집계 조회 0건). 67.0에서는 `WITH SECURITY_ENFORCED`도 쓸 수 없고 `WITH USER_MODE` / `WITH SYSTEM_MODE`로 명시해야 함
- 근거: Salesforce Apex Developer Guide "Apex Versioned Behavior Changes" (API 67.0: Apex runs in user context by default)
- 결정(Edwin, 2026-10-12): 시스템이 계산하는 값(장비 집계·유·무상 판정·Batch)은 `WITH SYSTEM_MODE` / `AccessLevel.SYSTEM_MODE`로 명시 유지. 화면 컨트롤러(D7~)는 `WITH USER_MODE`로 명시. 모드를 적지 않은 조회·DML은 두지 않음

## 5. D7 추가 교훈 — Mock 테스트가 못 잡는 것 (2026-10-13)

- **현상**: 협력 기사(최민호, Login As)가 사용 부품을 저장하자 ERP 전송이 `[CONNECTION] You don't have read permissions on the User External Credential object.`로 실패. 같은 기능의 테스트(`ErpInventoryServiceTest.normalTechnicianSaveSyncsToErp`, 기사 runAs)는 통과했음
- **원인**: External Credential을 쓰는 콜아웃은 실행 사용자에게 보안 주체 접근 권한 + **사용자 외부 자격 증명(UserExternalCredential) 오브젝트 읽기 권한**이 필요. 테스트는 `HttpCalloutMock`이 응답을 대신하므로 Named/External Credential 단계를 거치지 않음. 관리자로 한 실제 연동 확인은 관리자 권한이라 문제가 드러나지 않음
- **조치**: HG_Technician·HG_Admin(ERP), HG_CallCenter·HG_CenterManager·HG_Admin(주소 검색) 권한 집합에 UserExternalCredential 읽기 추가, org 반영 확인(ObjectPermissions 4건)
- **교훈**: 외부 호출은 단위 테스트 통과와 별개로 **실제 사용자 권한으로 실제 호출을 1번 확인**해야 함. 리허설 확인 항목: 기사 — 사용 부품 저장·재고 이동 수령(ERP), 상담원·센터장 — 주소 검색(도로명주소)
