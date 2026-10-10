# D5 Flow와 트리거 역할 재정리

- 일자: 2026-10-08 (D5) · 작성: Edwin
- 기준: docs/d5_trigger_design.md 7절, CLAUDE.md, docs/org_inventory.md

## 1. 누가 무엇을 맡는가

| 일 | 맡는 쪽 | 구현 | 이유 |
|---|---|---|---|
| 접수의 고객사·사업장·센터·긴급도 채우기 | 저장 전 Flow (유지) | `Case_BeforeSave_FillFromAsset` | 같은 레코드의 필드 채우기. 선언적으로 충분하고 어드민이 유지보수 가능 |
| 긴급 알림 메일 | 저장 후 Flow (유지) | `Case_AfterSave_UrgentAlert` | 메일은 저장 후에 보내야 함. 실패해도 저장을 막지 않도록 Fault Path 처리 |
| 접수 취소 | Screen Flow (유지) | `Case_Screen_Cancel` | 사용자 입력(취소 사유)을 받는 화면 |
| 센터 Queue 배정 | 할당 규칙 (유지) | `HG_CaseByServiceCenter` | 표준 라우팅. 센터 추가는 항목만 추가 |
| 반복 고장 표시 (BR-14) | **트리거** | `CaseTrigger` → `CaseTriggerHandler` → `CaseStatsService.applyRepeatFailureFlagsForInsert` | 같은 장비의 **다른 접수**를 세야 함. 200건이 한 번에 들어와도 묶음 안의 건수까지 합쳐 판정해야 함 |
| 장비 누적 접수 수·최근 접수일 | **트리거** | `CaseTriggerHandler` → `CaseStatsService.recalculateAssetCaseStats` | 장비 → 접수가 Lookup이라 Roll-Up Summary 불가. 삭제·복원·장비 변경·취소 전환까지 정확히 맞춰야 함 |
| 사용 부품 유·무상 자동 판정 (BR-06) | **트리거** | `ProductConsumedTrigger` → `ProductConsumedTriggerHandler` → `WarrantyService` | 부품(분류)·장비(보증 Formula 3개)·접수(생성일)·Custom Metadata를 함께 보는 판정. Flow로는 레코드마다 조회가 반복되어 벌크에 약함 |
| 출동 유상 부품비 합계 | Roll-Up (유지) | `WorkOrder.ruPaidPartsTotal__c` | ProductConsumed → WorkOrder가 Master-Detail이라 선언적으로 충분 |
| 예외 무상·고액 승인 | 승인 프로세스 (D5 이후) | 미구현 | 사람의 승인·잠금·이력이 필요 |

## 2. 판단 기준 (이번에 적용한 것)

1. **같은 레코드 필드 채우기 → 저장 전 Flow.** 다른 레코드를 세거나 여러 오브젝트를 엮어야 하면 Apex.
2. **다른 레코드 집계 → Master-Detail이면 Roll-Up, Lookup이면 트리거.**
3. **벌크에서 레코드마다 조회가 반복되는 판정 → 트리거.** 트리거는 묶음 전체를 한 번에 조회(Map)하고 계산.
4. **사람의 결정·승인 → 승인 프로세스.** 트리거는 사람이 정한 값(최종 판정 `ChargeType__c`)을 덮어쓰지 않음.
5. **트리거는 끌 수 있어야 함.** `TriggerSetting__mdt.IsActive__c`(오브젝트별)로 데이터 이관·장애 때 끔. 레코드가 없으면 활성.

## 3. 접수 저장 시 실행 순서 (설계 3-3, 이번 구현 기준)

```
저장 전 Flow (고객사·사업장·센터·긴급)
 → before insert 트리거 (반복 고장 표시, DML 없음)
 → Validation Rule
 → 저장
 → after insert 트리거 (장비 집계 → Asset update 1회)
 → 할당 규칙 (센터 Queue)
 → 저장 후 Flow (긴급 메일)
 → 커밋
```

- 트리거는 저장 전 Flow가 채운 값을 그대로 씀(반복 고장 판정은 사용자가 고른 AssetId 기준).
- 할당 규칙은 소유자만 바꾸므로 트리거와 서로 영향 없음.
- after update는 **장비가 바뀌었거나 취소로/취소에서 바뀐 접수만** 재계산 → 제목·우선순위·반복 고장 표시 수정으로는 Asset DML이 생기지 않음. 같은 트랜잭션에서 다시 실행돼도(워크플로 필드 업데이트 등) `TriggerHandler.filterUnprocessed`로 한 번만 처리.

## 4. 남긴 것 / 바꾼 것

| 항목 | 결정 |
|---|---|
| D3 Flow 3개 | 그대로 유지 (역할 중복 없음) |
| D4 `CaseStatsService.markRepeatFailures` | 트리거에서는 쓰지 않음. 이미 저장된 접수를 일괄 재판정할 때(D6 Batch 후보)용으로 남김 |
| Case.Closed_Lock | 트리거는 Case를 update하지 않으므로 충돌 없음 (Asset만 update) |
