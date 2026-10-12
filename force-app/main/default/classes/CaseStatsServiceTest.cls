/**
 * @description CaseStatsService를 직접 호출해 경계·실패 경로를 검증하는 테스트 클래스
 *              (트리거 경유 정상 흐름은 CaseTriggerHandlerTest, 매일 밤 재계산은 AssetRepeatFailureBatchTest)
 *              메서드 이름 접두어: normal = 정상, reject = 불허(저장 실패), bulk = 벌크 200건
 * @testTarget  CaseStatsService
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-12
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-12    Edwin     최초 작성 (D6 실습: 빈 입력·취소 접수·저장 실패·벌크 경로)
 * ----------------------------------------------------------------------------
 * @see CaseStatsService, TestDataFactory
 */
@isTest
private class CaseStatsServiceTest {
  private static final String SERIAL_PREFIX = 'TEST-SVC-';

  @TestSetup
  static void setupData() {
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    TestDataFactory.createAssets(account.Id, site.Id, SERIAL_PREFIX, 2);
  }

  // 정상: 빈 입력(null·빈 집합·null만 든 집합)은 아무것도 하지 않고 0 / 빈 목록
  @isTest
  static void normalEmptyInputReturnsNothing() {
    Test.startTest();
    Integer fromNull = CaseStatsService.recalculateAssetCaseStats(null);
    Integer fromEmpty = CaseStatsService.recalculateAssetCaseStats(
      new Set<Id>()
    );
    Integer fromNullOnly = CaseStatsService.recalculateAssetCaseStats(
      new Set<Id>{ null }
    );
    List<Case> flaggedFromNull = CaseStatsService.applyRepeatFailureFlagsForInsert(
      null
    );
    List<Case> flaggedFromEmpty = CaseStatsService.applyRepeatFailureFlagsForInsert(
      new List<Case>()
    );
    Integer dmlCount = Limits.getDmlStatements();
    Test.stopTest();

    Assert.areEqual(0, fromNull, 'null 입력');
    Assert.areEqual(0, fromEmpty, '빈 집합 입력');
    Assert.areEqual(0, fromNullOnly, 'null만 든 집합 입력');
    Assert.isTrue(flaggedFromNull.isEmpty(), 'null 접수 목록');
    Assert.isTrue(flaggedFromEmpty.isEmpty(), '빈 접수 목록');
    Assert.areEqual(0, dmlCount, '빈 입력에는 DML 없음');
  }

  // 정상: 취소 상태로 들어오는 접수는 묶음 건수에 넣지 않음 → 같은 장비 3건 중 1건이 취소면 3번째도 반복 고장 아님
  @isTest
  static void normalCanceledNewCaseNotCounted() {
    Asset asset = getAsset(0);
    Case first = TestDataFactory.buildCase(asset.Id, 1);
    Case canceled = TestDataFactory.buildCase(asset.Id, 2);
    canceled.Status = 'Canceled';
    canceled.CancelReason__c = '중복 접수';
    Case third = TestDataFactory.buildCase(asset.Id, 3);

    Test.startTest();
    insert new List<Case>{ first, canceled, third };
    Test.stopTest();

    Assert.isFalse(
      [SELECT RepeatFailure__c FROM Case WHERE Id = :third.Id].RepeatFailure__c,
      '취소 제외 2건째라 반복 고장 아님'
    );
    Asset stats = [
      SELECT TotalCaseCount__c, RecentCaseCount__c, RepeatFailure__c
      FROM Asset
      WHERE Id = :asset.Id
    ];
    Assert.areEqual(2, stats.TotalCaseCount__c, '누적 수는 취소 제외 2');
    Assert.areEqual(2, stats.RecentCaseCount__c, '최근 접수 수도 취소 제외 2');
    Assert.isFalse(stats.RepeatFailure__c, '반복 고장 장비 아님');
  }

  // 정상: 접수가 하나도 없는 장비를 재계산하면 0 / 비어 있음 / false로 되돌림
  @isTest
  static void normalAssetWithoutCasesResetToZero() {
    Asset asset = getAsset(0);
    // DESC: 이전에 값이 남아 있던 상황을 만듦 (필드는 API로는 쓸 수 있음)
    update new Asset(
      Id = asset.Id,
      TotalCaseCount__c = 5,
      RecentCaseCount__c = 4,
      RepeatFailure__c = true
    );

    Test.startTest();
    Integer saved = CaseStatsService.recalculateAssetCaseStats(
      new Set<Id>{ asset.Id }
    );
    Test.stopTest();

    Asset stats = [
      SELECT
        TotalCaseCount__c,
        LastCaseDate__c,
        RecentCaseCount__c,
        RepeatFailure__c
      FROM Asset
      WHERE Id = :asset.Id
    ];
    Assert.areEqual(1, saved, '저장 성공 1대');
    Assert.areEqual(0, stats.TotalCaseCount__c, '누적 0');
    Assert.isNull(stats.LastCaseDate__c, '최근 접수일 없음');
    Assert.areEqual(0, stats.RecentCaseCount__c, '최근 접수 0');
    Assert.isFalse(stats.RepeatFailure__c, '반복 고장 해제');
  }

  // 불허: 저장할 수 없는 장비(삭제됨)가 섞여 있으면 그 장비만 실패하고 나머지는 저장 (Database.update allOrNone = false)
  @isTest
  static void rejectDeletedAssetCountsOnlySaved() {
    Asset alive = getAsset(0);
    Asset removed = getAsset(1);
    delete removed;

    Test.startTest();
    Integer saved = CaseStatsService.recalculateAssetCaseStats(
      new Set<Id>{ alive.Id, removed.Id }
    );
    Test.stopTest();

    Assert.areEqual(1, saved, '삭제된 장비는 실패, 성공 1대만 셈');
    Assert.areEqual(
      0,
      [SELECT TotalCaseCount__c FROM Asset WHERE Id = :alive.Id]
      .TotalCaseCount__c,
      '살아 있는 장비는 저장됨'
    );
  }

  // 벌크: 장비 200대를 한 번에 재계산 → SOQL 2회(누적 집계·최근 집계) + DML 1회, 모두 저장
  @isTest
  static void bulkRecalculate200Assets() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    CustomerSite__c site = [SELECT Id FROM CustomerSite__c LIMIT 1];
    List<Asset> assets = TestDataFactory.createAssets(
      account.Id,
      site.Id,
      'TEST-SVC-BULK-',
      200
    );
    Set<Id> assetIds = new Map<Id, Asset>(assets).keySet();

    Test.startTest();
    Integer saved = CaseStatsService.recalculateAssetCaseStats(assetIds);
    Integer soql = Limits.getQueries();
    Integer dml = Limits.getDmlStatements();
    Test.stopTest();

    Assert.areEqual(200, saved, '200대 저장');
    Assert.areEqual(2, soql, '장비 수와 상관없이 집계 쿼리 2회');
    Assert.areEqual(1, dml, '장비 수와 상관없이 update 1회');
  }

  private static Asset getAsset(Integer index) {
    return [SELECT Id FROM Asset WHERE SerialKey__c = :(SERIAL_PREFIX + index)];
  }
}
