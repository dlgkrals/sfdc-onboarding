/**
 * @description 장비 단위 반복 고장 재계산 Batch (매일 밤)
 *              최근 N일 접수 수(RecentCaseCount__c)와 반복 고장 장비(RepeatFailure__c)는 시간이 지나면 값이 바뀜
 *              (예: 90일 전 접수가 기간 밖으로 빠지면 반복 고장이 풀림) → 접수 저장이 없어도 매일 다시 계산
 *              대상: RecentCaseCount__c > 0 또는 RepeatFailure__c = true 인 장비 (시간이 지나 값이 바뀔 수 있는 장비만)
 *              접수의 RepeatFailure__c는 접수 시점 스냅샷이라 다시 판정하지 않음
 * @layer       Batch
 * @author      Edwin
 * @date        2026-10-12
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-12    Edwin     최초 작성 (D6 실습: 장비 반복 고장 재계산)
 * ----------------------------------------------------------------------------
 * @see AssetRepeatFailureSchedulable, CaseStatsService.recalculateAssetCaseStats
 */
// DESC: Database.Stateful로 실행 단위(execute)를 넘어 처리 건수를 누적해 finish에서 로그로 남김
public with sharing class AssetRepeatFailureBatch implements Database.Batchable<SObject>, Database.Stateful {
  @TestVisible
  private Integer processedCount = 0;
  @TestVisible
  private Integer savedCount = 0;
  @TestVisible
  private Integer releasedCount = 0;
  @TestVisible
  private Integer flaggedCount = 0;

  public Database.QueryLocator start(Database.BatchableContext context) {
    // DESC: 최근 접수가 없고 반복 고장도 아닌 장비는 시간이 지나도 값이 바뀌지 않으므로 대상에서 제외
    return Database.getQueryLocator(
      [
        SELECT Id, RepeatFailure__c
        FROM Asset
        WHERE RecentCaseCount__c > 0 OR RepeatFailure__c = TRUE
        WITH SYSTEM_MODE
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<Asset> scope) {
    Map<Id, Boolean> wasRepeatById = new Map<Id, Boolean>();
    for (Asset asset : scope) {
      wasRepeatById.put(asset.Id, asset.RepeatFailure__c);
    }

    // PERF: 집계 쿼리 2회 + 장비 update 1회 (CaseStatsService 안에서, 범위 크기와 상관없이)
    savedCount += CaseStatsService.recalculateAssetCaseStats(
      wasRepeatById.keySet()
    );
    processedCount += scope.size();

    // DESC: 재계산 전후 반복 고장 장비 값을 비교해 풀린 수·새로 표시된 수를 셈 (조회 1회)
    for (Asset asset : [
      SELECT Id, RepeatFailure__c
      FROM Asset
      WHERE Id IN :wasRepeatById.keySet()
      WITH SYSTEM_MODE
    ]) {
      Boolean wasRepeat = wasRepeatById.get(asset.Id);
      if (wasRepeat && !asset.RepeatFailure__c) {
        releasedCount++;
      } else if (!wasRepeat && asset.RepeatFailure__c) {
        flaggedCount++;
      }
    }
  }

  public void finish(Database.BatchableContext context) {
    System.debug(
      LoggingLevel.WARN,
      'AssetRepeatFailureBatch 완료  대상 장비 ' +
        processedCount +
        '대, 저장 성공 ' +
        savedCount +
        '대, 반복 고장 해제 ' +
        releasedCount +
        '대, 새로 표시 ' +
        flaggedCount +
        '대'
    );
  }
}
