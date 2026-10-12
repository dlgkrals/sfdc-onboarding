/**
 * @description 접수(Case) 집계 서비스
 *              1) 장비별 누적 접수 수·최근 접수일·최근 N일 접수 수·반복 고장 장비 재계산
 *                 (장비 → 접수가 Lookup이라 Roll-Up Summary를 쓸 수 없어 Apex로 대체)
 *              2) 새 접수의 반복 고장 표시 (BR-14, 접수 시점 스냅샷 — 이후 다시 판정하지 않음)
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-07
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-07    Edwin     최초 작성 (D4 실습: 벌크 안전 집계·일괄 처리)
 * 1.1    2026-10-08    Edwin     markRepeatFailures 대상에서 종결·취소 접수 제외 (Case.Closed_Lock 충돌 방지)
 * 1.2    2026-10-08    Edwin     before insert용 반복 고장 판정(묶음 내 건수 포함) applyRepeatFailureFlagsForInsert 추가,
 *                                최근 접수 집계를 countRecentCasesByAsset로 분리
 * 1.3    2026-10-11    Edwin     applyRepeatFailureFlagsForInsert: 묶음 안에서는 Trigger.new 순서대로 세어 기준 횟수째부터만 표시
 * 1.4    2026-10-12    Edwin     recalculateAssetCaseStats가 장비의 최근 N일 접수 수(RecentCaseCount__c)·반복 고장 장비(RepeatFailure__c)도 계산.
 *                                markRepeatFailures·applyRepeatFailureFlags 삭제 (접수 반복 고장은 접수 시점 스냅샷, 재판정하지 않음)
 * 1.5    2026-10-12    Edwin     집계 조회·장비 저장을 시스템 모드로 명시 (상담원 사용자 접수 시 장비 재계산이 필드 권한 오류로 실패하던 결함)
 * ----------------------------------------------------------------------------
 * @see CaseTriggerHandler (before insert: applyRepeatFailureFlagsForInsert / after 이벤트: recalculateAssetCaseStats),
 *      AssetRepeatFailureBatch (매일 밤 recalculateAssetCaseStats)
 */
// DESC: 집계는 실행 사용자의 공유 범위와 상관없이 장비의 "전체" 접수를 세야 정확하므로 without sharing
// WARN: 장비 집계 필드는 사용자에게 읽기 전용(시스템이 계산). 이 org에서는 상담원 사용자로 실행되는 트리거의 Asset update가
//       필드 권한 오류(fields being inaccessible)로 실패해 조회·저장을 WITH SYSTEM_MODE / AccessLevel.SYSTEM_MODE로 명시 (1.5)
public without sharing class CaseStatsService {
  private static final String STATUS_CANCELED = 'Canceled';
  private static final Integer DEFAULT_REPEAT_DAYS = 90;
  private static final Integer DEFAULT_REPEAT_COUNT = 3;

  /**
   * @description 장비별 누적 접수 수(TotalCaseCount__c)·최근 접수일(LastCaseDate__c)·
   *              최근 N일 접수 수(RecentCaseCount__c)·반복 고장 장비(RepeatFailure__c)를 다시 계산해 저장
   *              취소된 접수는 제외. 접수가 하나도 없는 장비는 0 / null / false로 되돌림
   *              최근 N일·기준 횟수는 ServiceSetting__mdt(RepeatFailureDays·RepeatFailureCount)
   * @param assetIds 재계산할 장비 Id 집합 (여러 건을 한 번에)
   * @return 저장에 성공한 장비 수
   */
  public static Integer recalculateAssetCaseStats(Set<Id> assetIds) {
    if (assetIds == null || assetIds.isEmpty()) {
      return 0;
    }
    Set<Id> targetIds = new Set<Id>(assetIds);
    targetIds.remove(null);
    if (targetIds.isEmpty()) {
      return 0;
    }

    Map<Id, Integer> caseCountsByAsset = new Map<Id, Integer>();
    Map<Id, Datetime> lastCaseDatesByAsset = new Map<Id, Datetime>();

    // PERF: 집계 쿼리 1회 (장비 수와 상관없이)
    for (AggregateResult ar : [
      SELECT AssetId assetId, COUNT(Id) cnt, MAX(CreatedDate) lastDt
      FROM Case
      WHERE AssetId IN :targetIds AND Status != :STATUS_CANCELED
      WITH SYSTEM_MODE
      GROUP BY AssetId
    ]) {
      Id assetId = (Id) ar.get('assetId');
      caseCountsByAsset.put(assetId, (Integer) ar.get('cnt'));
      lastCaseDatesByAsset.put(assetId, (Datetime) ar.get('lastDt'));
    }

    // PERF: 최근 N일 집계 쿼리 1회 (장비 수와 상관없이)
    Map<Id, Integer> recentCountsByAsset = countRecentCasesByAsset(targetIds);
    Integer threshold = getSettingInt(
      'RepeatFailureCount',
      DEFAULT_REPEAT_COUNT
    );

    // DESC: 집계 결과가 아니라 입력 집합 기준으로 돌아야 접수가 모두 지워진 장비도 0으로 되돌릴 수 있음
    List<Asset> assetsToUpdate = new List<Asset>();
    for (Id assetId : targetIds) {
      Datetime lastDt = lastCaseDatesByAsset.get(assetId);
      Integer recentCount = recentCountsByAsset.containsKey(assetId)
        ? recentCountsByAsset.get(assetId)
        : 0;
      assetsToUpdate.add(
        new Asset(
          Id = assetId,
          TotalCaseCount__c = caseCountsByAsset.containsKey(assetId)
            ? caseCountsByAsset.get(assetId)
            : 0,
          LastCaseDate__c = (lastDt == null) ? null : lastDt.date(),
          RecentCaseCount__c = recentCount,
          RepeatFailure__c = recentCount >= threshold
        )
      );
    }

    // PERF: DML 1회
    // WARN: allOrNone = false. 일부 장비가 Validation Rule 등으로 실패해도 나머지는 저장하고 실패는 로그로 남김
    return countSuccess(
      Database.update(assetsToUpdate, false, AccessLevel.SYSTEM_MODE),
      'recalculateAssetCaseStats'
    );
  }

  /**
   * @description before insert용 반복 고장 판정 (DML 없음, 값만 세팅)
   *              기준: 최근 N일(RepeatFailureDays), 취소 제외, 기준 횟수(RepeatFailureCount)
   *              새 접수는 아직 DB에 없으므로 "DB 집계 건수 + 이번 묶음에서 이 접수까지 같은 장비의 새 접수 수"로 판정
   *              묶음 안에서는 Trigger.new 순서대로 세므로 기준 횟수째 접수부터만 표시
   *              예) DB에 최근 90일 0건 + 같은 장비 3건을 한 번에 → 1·2번째 false, 3번째 true
   *              예) DB에 최근 90일 2건 + 이번 묶음에 같은 장비 1건 → 3건째 → 반복 고장
   * @param newCases Trigger.new (before insert)
   * @return 값이 실제로 바뀐 접수만 담은 리스트
   */
  public static List<Case> applyRepeatFailureFlagsForInsert(
    List<Case> newCases
  ) {
    List<Case> changedCases = new List<Case>();
    if (newCases == null || newCases.isEmpty()) {
      return changedCases;
    }

    Integer threshold = getSettingInt(
      'RepeatFailureCount',
      DEFAULT_REPEAT_COUNT
    );

    Set<Id> assetIds = new Set<Id>();
    for (Case c : newCases) {
      if (c.AssetId != null) {
        assetIds.add(c.AssetId);
      }
    }
    // PERF: 집계 쿼리 1회 (묶음 크기와 상관없이)
    Map<Id, Integer> recentCountsByAsset = countRecentCasesByAsset(assetIds);

    // DESC: 장비별로 지금까지 센 묶음 내 새 접수 수 (Trigger.new 순서대로 누적, 취소 상태로 들어오는 접수는 세지 않음)
    Map<Id, Integer> runningCountsByAsset = new Map<Id, Integer>();
    for (Case c : newCases) {
      Boolean isRepeat = false;
      if (c.AssetId != null) {
        Integer runningCount = runningCountsByAsset.containsKey(c.AssetId)
          ? runningCountsByAsset.get(c.AssetId)
          : 0;
        if (c.Status != STATUS_CANCELED) {
          runningCount++;
          runningCountsByAsset.put(c.AssetId, runningCount);
        }
        Integer dbCount = recentCountsByAsset.containsKey(c.AssetId)
          ? recentCountsByAsset.get(c.AssetId)
          : 0;
        isRepeat = (dbCount + runningCount) >= threshold;
      }
      if (c.RepeatFailure__c != isRepeat) {
        c.RepeatFailure__c = isRepeat;
        changedCases.add(c);
      }
    }
    return changedCases;
  }

  // DESC: 장비별 최근 N일(기준값) 접수 수 집계. 취소 제외. 집계 쿼리 1회
  private static Map<Id, Integer> countRecentCasesByAsset(Set<Id> assetIds) {
    Map<Id, Integer> recentCountsByAsset = new Map<Id, Integer>();
    if (assetIds == null || assetIds.isEmpty()) {
      return recentCountsByAsset;
    }
    // DESC: Custom Metadata getInstance()는 SOQL 한도를 쓰지 않음
    Integer days = getSettingInt('RepeatFailureDays', DEFAULT_REPEAT_DAYS);
    // DESC: LAST_N_DAYS 리터럴에는 변수를 넣을 수 없어 기준 시각을 계산해 바인드
    Datetime since = System.now().addDays(-days);
    for (AggregateResult ar : [
      SELECT AssetId assetId, COUNT(Id) cnt
      FROM Case
      WHERE
        AssetId IN :assetIds
        AND CreatedDate >= :since
        AND Status != :STATUS_CANCELED
      WITH SYSTEM_MODE
      GROUP BY AssetId
    ]) {
      recentCountsByAsset.put((Id) ar.get('assetId'), (Integer) ar.get('cnt'));
    }
    return recentCountsByAsset;
  }

  // DESC: 기준값을 정수로 읽기. 레코드가 없으면 기본값
  private static Integer getSettingInt(
    String developerName,
    Integer defaultValue
  ) {
    ServiceSetting__mdt setting = ServiceSetting__mdt.getInstance(
      developerName
    );
    return (setting == null ||
      setting.Value__c == null)
      ? defaultValue
      : setting.Value__c.intValue();
  }

  // DESC: 부분 저장 결과에서 성공 건수를 세고 실패는 WARN 로그로 남김
  private static Integer countSuccess(
    List<Database.SaveResult> results,
    String context
  ) {
    Integer successCount = 0;
    for (Database.SaveResult result : results) {
      if (result.isSuccess()) {
        successCount++;
        continue;
      }
      for (Database.Error err : result.getErrors()) {
        System.debug(
          LoggingLevel.WARN,
          context +
            ' 저장 실패: ' +
            err.getStatusCode() +
            ' ' +
            err.getMessage()
        );
      }
    }
    return successCount;
  }
}
