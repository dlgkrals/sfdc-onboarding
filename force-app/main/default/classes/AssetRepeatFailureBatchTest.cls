/**
 * @description AssetRepeatFailureBatch(장비 반복 고장 재계산)를 검증하는 테스트 클래스
 *              Test.setCreatedDate로 오래된 접수를 만들어 시간이 지난 상황을 재현
 *              메서드 이름 접두어: normal = 정상, bulk = 벌크 200대
 * @testTarget  AssetRepeatFailureBatch, CaseStatsService.recalculateAssetCaseStats
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-12
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-12    Edwin     최초 작성 (D6 실습)
 * ----------------------------------------------------------------------------
 * @see AssetRepeatFailureBatch, TestDataFactory
 */
@isTest
private class AssetRepeatFailureBatchTest {
  private static final String SERIAL_PREFIX = 'TEST-BATCH-';

  @TestSetup
  static void setupData() {
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    TestDataFactory.createAssets(account.Id, site.Id, SERIAL_PREFIX, 2);
  }

  // 정상: 접수 3건이 모두 100일 전이 되면(기준 90일 밖) Batch 후 반복 고장 장비가 풀림. 누적 수는 그대로
  @isTest
  static void normalOldCasesReleaseRepeatFailure() {
    Asset asset = getAsset(0);
    List<Case> cases = TestDataFactory.createCases(new List<Asset>{ asset }, 3);
    Assert.isTrue(
      getStats(asset.Id).RepeatFailure__c,
      '접수 직후에는 반복 고장 장비'
    );
    // DESC: 시간이 지난 상황 재현 — 접수 생성일을 100일 전으로
    for (Case c : cases) {
      Test.setCreatedDate(c.Id, Datetime.now().addDays(-100));
    }

    Test.startTest();
    Database.executeBatch(
      new AssetRepeatFailureBatch(),
      AssetRepeatFailureSchedulable.BATCH_SIZE
    );
    Test.stopTest();

    Asset stats = getStats(asset.Id);
    Assert.isFalse(stats.RepeatFailure__c, '90일이 지나 반복 고장 해제');
    Assert.areEqual(0, stats.RecentCaseCount__c, '최근 90일 접수 0');
    Assert.areEqual(3, stats.TotalCaseCount__c, '누적 접수 수는 그대로 3');
  }

  // 정상: 최근 접수 3건이면 Batch 후에도 반복 고장 장비 유지
  @isTest
  static void normalRecentCasesKeepRepeatFailure() {
    Asset asset = getAsset(0);
    TestDataFactory.createCases(new List<Asset>{ asset }, 3);

    Test.startTest();
    Database.executeBatch(
      new AssetRepeatFailureBatch(),
      AssetRepeatFailureSchedulable.BATCH_SIZE
    );
    Test.stopTest();

    Asset stats = getStats(asset.Id);
    Assert.isTrue(stats.RepeatFailure__c, '최근 3건이면 유지');
    Assert.areEqual(3, stats.RecentCaseCount__c, '최근 90일 접수 3');
  }

  // 정상: 접수 4건 중 2건만 기간 밖이 되면 최근 2건 → 반복 고장 해제, 최근 접수 수 2
  @isTest
  static void normalPartlyOldCasesRecountRecent() {
    Asset asset = getAsset(0);
    List<Case> cases = TestDataFactory.createCases(new List<Asset>{ asset }, 4);
    Test.setCreatedDate(cases[0].Id, Datetime.now().addDays(-120));
    Test.setCreatedDate(cases[1].Id, Datetime.now().addDays(-95));

    Test.startTest();
    Database.executeBatch(
      new AssetRepeatFailureBatch(),
      AssetRepeatFailureSchedulable.BATCH_SIZE
    );
    Test.stopTest();

    Asset stats = getStats(asset.Id);
    Assert.areEqual(2, stats.RecentCaseCount__c, '최근 90일 안의 2건만 셈');
    Assert.isFalse(stats.RepeatFailure__c, '2건이면 반복 고장 아님');
  }

  // 정상: 최근 접수도 없고 반복 고장도 아닌 장비는 Batch 대상이 아님 (start 조건)
  @isTest
  static void normalQuietAssetNotSelected() {
    Asset quiet = getAsset(1);
    // DESC: 대상이 아니라면 Batch가 건드리지 않으므로 일부러 넣은 누적 수가 그대로 남아야 함
    update new Asset(
      Id = quiet.Id,
      TotalCaseCount__c = 7,
      RecentCaseCount__c = 0,
      RepeatFailure__c = false
    );

    Test.startTest();
    Database.executeBatch(
      new AssetRepeatFailureBatch(),
      AssetRepeatFailureSchedulable.BATCH_SIZE
    );
    Test.stopTest();

    Assert.areEqual(
      7,
      getStats(quiet.Id).TotalCaseCount__c,
      '대상 아닌 장비는 재계산하지 않음'
    );
  }

  // 벌크: 반복 고장으로 잘못 남아 있던 장비 200대(실제 접수 없음)를 Batch 한 번(범위 200)으로 모두 바로잡음
  @isTest
  static void bulk200AssetsCorrected() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    CustomerSite__c site = [SELECT Id FROM CustomerSite__c LIMIT 1];
    List<Asset> assets = TestDataFactory.createAssets(
      account.Id,
      site.Id,
      'TEST-BATCH-BULK-',
      198
    );
    assets.addAll(
      [
        SELECT Id
        FROM Asset
        WHERE
          SerialKey__c LIKE :(SERIAL_PREFIX + '%')
          AND (NOT SerialKey__c LIKE '%BULK%')
      ]
    );
    for (Asset asset : assets) {
      asset.RecentCaseCount__c = 5;
      asset.RepeatFailure__c = true;
    }
    update assets;

    Test.startTest();
    Id jobId = Database.executeBatch(
      new AssetRepeatFailureBatch(),
      AssetRepeatFailureSchedulable.BATCH_SIZE
    );
    Test.stopTest();

    Assert.areEqual(200, assets.size(), '대상 장비 200대');
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Asset WHERE RepeatFailure__c = TRUE],
      '200대 모두 반복 고장 해제'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Asset WHERE RecentCaseCount__c > 0],
      '200대 모두 최근 접수 0'
    );
    AsyncApexJob job = [
      SELECT Status, NumberOfErrors, TotalJobItems
      FROM AsyncApexJob
      WHERE Id = :jobId
    ];
    Assert.areEqual('Completed', job.Status, 'Batch 완료');
    Assert.areEqual(0, job.NumberOfErrors, '오류 없음');
    Assert.areEqual(1, job.TotalJobItems, '200대가 실행 단위 1번에 처리');
  }

  private static Asset getAsset(Integer index) {
    return [SELECT Id FROM Asset WHERE SerialKey__c = :(SERIAL_PREFIX + index)];
  }

  private static Asset getStats(Id assetId) {
    return [
      SELECT TotalCaseCount__c, RecentCaseCount__c, RepeatFailure__c
      FROM Asset
      WHERE Id = :assetId
    ];
  }
}
