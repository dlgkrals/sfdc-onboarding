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

  protected override void afterUpdate() {
    // DESC: 워크플로 필드 업데이트 등으로 같은 트랜잭션에서 다시 실행돼도 같은 접수는 한 번만 처리
    List<Case> cases = (List<Case>) filterUnprocessed(
      Trigger.new,
      'afterUpdate'
    );
    Map<Id, Case> oldCasesById = (Map<Id, Case>) Trigger.oldMap;

    Set<Id> assetIds = new Set<Id>();
    for (Case newCase : cases) {
      Case oldCase = oldCasesById.get(newCase.Id);
      Boolean assetChanged = newCase.AssetId != oldCase.AssetId;
      Boolean cancelChanged =
        (newCase.Status == STATUS_CANCELED) !=
        (oldCase.Status == STATUS_CANCELED);
      // DESC: 제목·우선순위·반복 고장 표시 등 다른 수정은 누적 수에 영향이 없으므로 재계산하지 않음
      if (!assetChanged && !cancelChanged) {
        continue;
      }
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
