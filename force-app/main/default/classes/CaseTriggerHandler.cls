/**
 * @description 접수(Case) 트리거 핸들러
 *              1) before insert : 새 접수의 반복 고장 표시 (BR-14, DML 없음)
 *              2) after insert/update/delete/undelete : 장비 누적 접수 수·최근 접수일 재계산
 *                 after update는 장비가 바뀌었거나 취소 상태로/에서 바뀐 접수의 장비만 재계산
 * @layer       TriggerHandler
 * @author      Edwin
 * @date        2026-10-08
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-08    Edwin     최초 작성 (D5 실습: 반복 고장·장비 집계 트리거)
 * 1.1    2026-10-11    Edwin     after update 재귀 방지를 Id 기준(filterUnprocessed)에서 상태 기준으로 변경
 *                                (200건 update 벌크에서 같은 트랜잭션의 두 번째 update 재계산이 빠지는 결함 수정)
 * ----------------------------------------------------------------------------
 * @see CaseTrigger, CaseStatsService, TriggerHandler
 */
public with sharing class CaseTriggerHandler extends TriggerHandler {
  private static final String STATUS_CANCELED = 'Canceled';

  protected override void beforeInsert() {
    CaseStatsService.applyRepeatFailureFlagsForInsert((List<Case>) Trigger.new);
  }

  protected override void afterInsert() {
    recalculateAssets(collectAssetIds((List<Case>) Trigger.new));
  }

  // DESC: 재귀 방지용. 접수별로 마지막으로 재계산한 상태(장비 Id + 취소 여부)
  //       워크플로 필드 업데이트 등으로 같은 DML이 다시 실행되면 상태가 같으므로 건너뜀
  //       같은 트랜잭션이라도 별도 update로 장비·취소 상태가 또 바뀌면 상태가 달라 다시 처리
  private static Map<Id, String> processedStatesByCaseId = new Map<Id, String>();

  protected override void afterUpdate() {
    Map<Id, Case> oldCasesById = (Map<Id, Case>) Trigger.oldMap;

    Set<Id> assetIds = new Set<Id>();
    for (Case newCase : (List<Case>) Trigger.new) {
      Case oldCase = oldCasesById.get(newCase.Id);
      Boolean assetChanged = newCase.AssetId != oldCase.AssetId;
      Boolean cancelChanged =
        (newCase.Status == STATUS_CANCELED) !=
        (oldCase.Status == STATUS_CANCELED);
      // DESC: 제목·우선순위·반복 고장 표시 등 다른 수정은 누적 수에 영향이 없으므로 재계산하지 않음
      if (!assetChanged && !cancelChanged) {
        continue;
      }
      String state =
        String.valueOf(newCase.AssetId) +
        '|' +
        (newCase.Status == STATUS_CANCELED);
      if (processedStatesByCaseId.get(newCase.Id) == state) {
        continue;
      }
      processedStatesByCaseId.put(newCase.Id, state);
      // DESC: 장비가 바뀌면 이전 장비와 새 장비 둘 다 재계산
      if (oldCase.AssetId != null) {
        assetIds.add(oldCase.AssetId);
      }
      if (newCase.AssetId != null) {
        assetIds.add(newCase.AssetId);
      }
    }
    recalculateAssets(assetIds);
  }

  protected override void afterDelete() {
    recalculateAssets(collectAssetIds((List<Case>) Trigger.old));
  }

  protected override void afterUndelete() {
    recalculateAssets(collectAssetIds((List<Case>) Trigger.new));
  }

  private static Set<Id> collectAssetIds(List<Case> cases) {
    Set<Id> assetIds = new Set<Id>();
    for (Case c : cases) {
      if (c.AssetId != null) {
        assetIds.add(c.AssetId);
      }
    }
    return assetIds;
  }

  // PERF: 집계 쿼리 1회 + Asset update DML 1회 (CaseStatsService 안에서)
  private static void recalculateAssets(Set<Id> assetIds) {
    if (!assetIds.isEmpty()) {
      CaseStatsService.recalculateAssetCaseStats(assetIds);
    }
  }
}
