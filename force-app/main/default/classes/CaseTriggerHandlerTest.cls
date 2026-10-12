/**
 * @description CaseTriggerHandler(접수 트리거) 동작을 검증하는 테스트 클래스
 *              메서드 이름 접두어: normal = 정상, reject = 불허, bulk = 벌크 200건
 *              기준값은 Custom Metadata 기본값(최근 90일·3건)에 의존
 * @testTarget  CaseTriggerHandler, CaseStatsService, TriggerHandler
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-08
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-08    Edwin     최초 작성 (D5 테스트 초안)
 * 1.1    2026-10-11    Edwin     묶음 내 순서 판정 반영(200건 기대값 190), 같은 장비 3건 한 번에 insert 케이스 추가
 * 1.2    2026-10-11    Edwin     불허 케이스 2개(장비 없음 거부, 벌크 일부 거부), 같은 트랜잭션 연속 update 회귀 케이스 추가
 * 1.3    2026-10-12    Edwin     TestDataFactory 사용, 이름에 정상/불허/벌크 접두어, 종결 접수 수정 불허(runAs 상담원)·
 *                                복원·우회·트리거 밖 실행·장비 반복 고장(1.4) 케이스 추가
 * ----------------------------------------------------------------------------
 * @see CaseTriggerHandler, TestDataFactory
 */
@isTest
private class CaseTriggerHandlerTest {
  private static final Integer ASSET_COUNT = 5;
  private static final String SERIAL_PREFIX = 'TEST-CASE-';
  private static final String STATUS_CANCELED = 'Canceled';
  private static final String STATUS_CLOSED = 'Closed';

  @TestSetup
  static void setupData() {
    // DESC: 사용자·권한 집합 배정은 Mixed DML을 피하려고 현재 사용자 runAs 블록에서 먼저 생성
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.createUser('HG_CallCenter', false);
    }
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    TestDataFactory.createAssets(
      account.Id,
      site.Id,
      SERIAL_PREFIX,
      ASSET_COUNT
    );
  }

  // 정상: 같은 장비 접수 3건을 차례로 → 3번째만 반복 고장
  @isTest
  static void normalThirdCaseOnSameAssetIsRepeatFailure() {
    Asset asset = getAsset(0);

    Test.startTest();
    Case first = TestDataFactory.buildCase(asset.Id, 1);
    insert first;
    Case second = TestDataFactory.buildCase(asset.Id, 2);
    insert second;
    Case third = TestDataFactory.buildCase(asset.Id, 3);
    insert third;
    Test.stopTest();

    Map<Id, Case> casesById = getCasesById(asset.Id);
    Assert.isFalse(
      casesById.get(first.Id).RepeatFailure__c,
      '1번째 접수는 반복 고장이 아님'
    );
    Assert.isFalse(
      casesById.get(second.Id).RepeatFailure__c,
      '2번째 접수는 반복 고장이 아님'
    );
    Assert.isTrue(
      casesById.get(third.Id).RepeatFailure__c,
      '3번째 접수는 반복 고장 (DB 2건 + 묶음 1건)'
    );
  }

  // 정상: 같은 장비 3건을 한 번에 insert → Trigger.new 순서대로 세어 3번째만 반복 고장
  @isTest
  static void normalSameAssetThreeInOneBatchFlagsOnlyThird() {
    Asset asset = getAsset(0);
    List<Case> cases = buildCases(asset.Id, 3);

    Test.startTest();
    insert cases;
    Test.stopTest();

    Map<Id, Case> casesById = getCasesById(asset.Id);
    Assert.isFalse(
      casesById.get(cases[0].Id).RepeatFailure__c,
      '묶음 1번째는 반복 고장 아님'
    );
    Assert.isFalse(
      casesById.get(cases[1].Id).RepeatFailure__c,
      '묶음 2번째는 반복 고장 아님'
    );
    Assert.isTrue(
      casesById.get(cases[2].Id).RepeatFailure__c,
      '묶음 3번째만 반복 고장'
    );
  }

  // 정상(1.4): 접수 3건이 쌓이면 장비의 최근 90일 접수 수 3, 반복 고장 장비 true
  @isTest
  static void normalAssetRepeatFailureFlaggedOnInsert() {
    Asset asset = getAsset(0);

    Test.startTest();
    insert buildCases(asset.Id, 2);
    Asset afterTwo = getAssetStats(asset.Id);
    insert TestDataFactory.buildCase(asset.Id, 3);
    Test.stopTest();

    Assert.areEqual(2, afterTwo.RecentCaseCount__c, '2건일 때 최근 접수 수');
    Assert.isFalse(afterTwo.RepeatFailure__c, '2건이면 반복 고장 장비 아님');
    Asset afterThree = getAssetStats(asset.Id);
    Assert.areEqual(3, afterThree.RecentCaseCount__c, '3건일 때 최근 접수 수');
    Assert.isTrue(afterThree.RepeatFailure__c, '3건이면 반복 고장 장비');
  }

  // 정상: 장비 변경 시 이전·새 장비 모두 재계산, 취소로 바뀌면 누적 수에서 제외 (after update)
  @isTest
  static void normalUpdateRecalculatesOldNewAndCanceled() {
    Asset assetA = getAsset(0);
    Asset assetB = getAsset(1);
    Case moved = TestDataFactory.buildCase(assetA.Id, 1);
    Case canceled = TestDataFactory.buildCase(assetB.Id, 2);
    insert new List<Case>{ moved, canceled };

    Test.startTest();
    moved.AssetId = assetB.Id;
    canceled.Status = STATUS_CANCELED;
    canceled.CancelReason__c = '고객 요청으로 취소';
    update new List<Case>{ moved, canceled };
    Test.stopTest();

    Assert.areEqual(
      0,
      getAssetStats(assetA.Id).TotalCaseCount__c,
      '이전 장비는 0건'
    );
    Assert.areEqual(
      1,
      getAssetStats(assetB.Id).TotalCaseCount__c,
      '새 장비는 옮겨 온 1건만 (취소 제외)'
    );
  }

  // 정상: 접수 삭제 → 장비 누적 수 감소 (after delete)
  @isTest
  static void normalDeleteDecrementsAssetTotal() {
    Asset asset = getAsset(0);
    List<Case> cases = buildCases(asset.Id, 3);
    insert cases;

    Test.startTest();
    delete cases[0];
    Test.stopTest();

    Assert.areEqual(
      2,
      getAssetStats(asset.Id).TotalCaseCount__c,
      '삭제 후 누적 수'
    );
  }

  // 정상: 삭제한 접수를 복원 → 장비 누적 수 원래대로 (after undelete)
  @isTest
  static void normalUndeleteRestoresAssetTotal() {
    Asset asset = getAsset(0);
    List<Case> cases = buildCases(asset.Id, 3);
    insert cases;
    delete cases[0];

    Test.startTest();
    undelete cases[0];
    Test.stopTest();

    Assert.areEqual(
      3,
      getAssetStats(asset.Id).TotalCaseCount__c,
      '복원 후 누적 수'
    );
  }

  // 정상: 스위치(TriggerSetting__mdt)를 끄면 반복 고장 표시·장비 집계 모두 하지 않음
  @isTest
  static void normalSwitchOffSkipsAllLogic() {
    Asset asset = getAsset(0);
    TriggerHandler.activeOverridesByObject.put('Case', false);

    Test.startTest();
    insert buildCases(asset.Id, 3);
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Case WHERE RepeatFailure__c = TRUE],
      '반복 고장 표시 없음'
    );
    Assert.isNull(getAssetStats(asset.Id).TotalCaseCount__c, '장비 집계 없음');
  }

  // 정상: 정적 우회(bypassedHandlers)에 핸들러 이름을 넣으면 그 핸들러만 건너뜀 (데이터 이관 스크립트용)
  @isTest
  static void normalBypassedHandlerSkipsLogic() {
    Asset asset = getAsset(0);
    TriggerHandler.bypassedHandlers.add('CaseTriggerHandler');

    Test.startTest();
    insert buildCases(asset.Id, 3);
    Test.stopTest();

    Assert.isNull(
      getAssetStats(asset.Id).TotalCaseCount__c,
      '우회 중에는 장비 집계 없음'
    );
  }

  // 정상: 트리거 밖에서 run()을 불러도 아무 일도 하지 않음 (Trigger.isExecuting = false)
  @isTest
  static void normalRunOutsideTriggerDoesNothing() {
    Test.startTest();
    Integer dmlBefore = Limits.getDmlStatements();
    Integer soqlBefore = Limits.getQueries();
    new CaseTriggerHandler().run();
    Integer dmlDelta = Limits.getDmlStatements() - dmlBefore;
    Integer soqlDelta = Limits.getQueries() - soqlBefore;
    Test.stopTest();

    Assert.areEqual(0, dmlDelta, '트리거 밖에서는 DML 없음');
    Assert.areEqual(0, soqlDelta, '트리거 밖에서는 쿼리 없음');
  }

  // 정상(회귀): 같은 트랜잭션에서 제목 수정 → 장비 변경 → 취소를 연달아 해도 매번 재계산 (D5 update 벌크에서 발견한 결함)
  @isTest
  static void normalRegressionConsecutiveUpdatesRecalculate() {
    Asset assetA = getAsset(0);
    Asset assetB = getAsset(1);
    Case target = TestDataFactory.buildCase(assetA.Id, 1);
    insert target;

    Test.startTest();
    target.Subject = '제목만 수정';
    update target;
    target.AssetId = assetB.Id;
    update target;
    Assert.areEqual(
      1,
      getAssetStats(assetB.Id).TotalCaseCount__c,
      '장비 변경 후 새 장비 1건'
    );
    target.Status = STATUS_CANCELED;
    target.CancelReason__c = '고객 요청으로 취소';
    update target;
    Test.stopTest();

    Assert.areEqual(
      0,
      getAssetStats(assetA.Id).TotalCaseCount__c,
      '이전 장비 0건'
    );
    Assert.areEqual(
      0,
      getAssetStats(assetB.Id).TotalCaseCount__c,
      '취소 후 새 장비도 0건'
    );
  }

  // 불허: 장비 없는 접수 → Validation Rule(Asset_Required)로 저장 거부
  @isTest
  static void rejectCaseWithoutAsset() {
    Case noAsset = new Case(
      Subject = '장비 없는 접수',
      Status = TestDataFactory.STATUS_NEW,
      Origin = 'Phone'
    );

    Test.startTest();
    DmlException caught;
    try {
      insert noAsset;
    } catch (DmlException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(caught, '장비 없는 접수는 저장되면 안 됨');
    Assert.isTrue(
      caught.getMessage().contains('장비'),
      '장비 필수 오류 메시지: ' + caught.getMessage()
    );
    Assert.areEqual(0, [SELECT COUNT() FROM Case], '저장된 접수 없음');
  }

  // 불허: 종결된 접수를 상담원이 수정 → Validation Rule(Closed_Lock)로 저장 거부, 장비 집계도 그대로
  //       관리자는 HG_BypassValidation 권한으로 예외라 상담원 사용자로 실행. 접수 공유가 비공개라 상담원이 직접 만든 접수로 확인
  @isTest
  static void rejectClosedCaseUpdate() {
    User callCenter = getTestUser('HG_CallCenter');
    Asset asset = getAsset(0);

    System.runAs(callCenter) {
      Case target = TestDataFactory.buildCase(asset.Id, 1);
      insert target;
      target.Status = STATUS_CLOSED;
      update target;

      Test.startTest();
      DmlException caught;
      try {
        target.Subject = '종결 후 수정 시도';
        target.AssetId = getAsset(1).Id;
        update target;
      } catch (DmlException e) {
        caught = e;
      }
      Test.stopTest();

      Assert.isNotNull(caught, '종결 접수는 수정되면 안 됨');
      Assert.isTrue(
        caught.getMessage().contains('종결'),
        'Closed_Lock 오류 메시지: ' + caught.getMessage()
      );
    }
    Assert.areEqual(
      1,
      getAssetStats(asset.Id).TotalCaseCount__c,
      '거부됐으므로 원래 장비 집계 유지'
    );
    Assert.isNull(
      getAssetStats(getAsset(1).Id).TotalCaseCount__c,
      '옮겨 가려던 장비는 재계산되지 않음 (접수가 붙은 적 없음)'
    );
  }

  // 벌크: 200건 한 번에 insert → 장비별 누적 접수 수·최근 접수일·최근 접수 수·반복 고장 장비 정확
  @isTest
  static void bulkInsertUpdatesAssetTotals() {
    List<Asset> assets = getAssets();
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < 200; i++) {
      cases.add(
        TestDataFactory.buildCase(assets[Math.mod(i, assets.size())].Id, i)
      );
    }

    Test.startTest();
    insert cases;
    Test.stopTest();

    for (Asset a : [
      SELECT
        TotalCaseCount__c,
        LastCaseDate__c,
        RecentCaseCount__c,
        RepeatFailure__c
      FROM Asset
    ]) {
      Assert.areEqual(
        200 / ASSET_COUNT,
        a.TotalCaseCount__c,
        '장비별 누적 접수 수'
      );
      Assert.areEqual(Date.today(), a.LastCaseDate__c, '최근 접수일');
      Assert.areEqual(
        200 / ASSET_COUNT,
        a.RecentCaseCount__c,
        '장비별 최근 90일 접수 수'
      );
      Assert.isTrue(a.RepeatFailure__c, '40건이면 반복 고장 장비');
    }
    // DESC: 장비당 40건을 순서대로 세면 3번째부터 표시 → 장비당 38건 × 5대
    Assert.areEqual(
      190,
      [SELECT COUNT() FROM Case WHERE RepeatFailure__c = TRUE],
      '장비별 3번째 접수부터 반복 고장'
    );
  }

  // 벌크(불허 포함): 200건 중 20건이 거부(장비 없음)돼도 나머지 180건은 저장되고 장비 집계는 저장된 건만 반영
  @isTest
  static void bulkPartialRejectKeepsValidTotals() {
    List<Asset> assets = getAssets();
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < 200; i++) {
      // DESC: 10건마다 1건은 장비를 비워 Validation Rule에 걸리게 함
      Id assetId = (Math.mod(i, 10) == 9)
        ? null
        : assets[Math.mod(i, assets.size())].Id;
      cases.add(TestDataFactory.buildCase(assetId, i));
    }

    Test.startTest();
    List<Database.SaveResult> results = Database.insert(cases, false);
    Test.stopTest();

    Integer failed = 0;
    for (Database.SaveResult result : results) {
      if (!result.isSuccess()) {
        failed++;
      }
    }
    Assert.areEqual(20, failed, '장비 없는 20건만 거부');
    Assert.areEqual(180, [SELECT COUNT() FROM Case], '나머지 180건 저장');
    AggregateResult total = [SELECT SUM(TotalCaseCount__c) total FROM Asset];
    Assert.areEqual(
      180,
      ((Decimal) total.get('total')).intValue(),
      '장비 누적 합계 = 저장된 접수 수'
    );
  }

  private static List<Asset> getAssets() {
    return [SELECT Id FROM Asset ORDER BY SerialKey__c];
  }

  private static Asset getAsset(Integer index) {
    return [SELECT Id FROM Asset WHERE SerialKey__c = :(SERIAL_PREFIX + index)];
  }

  private static Asset getAssetStats(Id assetId) {
    return [
      SELECT
        TotalCaseCount__c,
        LastCaseDate__c,
        RecentCaseCount__c,
        RepeatFailure__c
      FROM Asset
      WHERE Id = :assetId
    ];
  }

  private static Map<Id, Case> getCasesById(Id assetId) {
    return new Map<Id, Case>(
      [SELECT Id, RepeatFailure__c FROM Case WHERE AssetId = :assetId]
    );
  }

  private static List<Case> buildCases(Id assetId, Integer count) {
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < count; i++) {
      cases.add(TestDataFactory.buildCase(assetId, i));
    }
    return cases;
  }

  private static User getTestUser(String permissionSetName) {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :('테스트 ' + permissionSetName)
      LIMIT 1
    ];
  }
}
