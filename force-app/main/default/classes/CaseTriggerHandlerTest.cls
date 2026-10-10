/**
 * @description CaseTriggerHandler 동작을 검증하는 테스트 클래스 (D5 초안, D6에서 확장)
 *              ① 같은 장비 접수 3건 → 3번째 반복 고장 (차례로 / 한 번에) ② 200건 insert 후 장비 누적 수 정확
 *              ③ 접수 삭제 시 누적 수 감소 ④ 스위치를 끄면 아무 처리 안 함
 *              + 장비 변경·취소 전환 시 재계산 (after update), 같은 트랜잭션 연속 update 회귀
 *              불허: 장비 없는 접수 거부, 200건 중 일부 거부 시 저장된 건만 집계
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
 * ----------------------------------------------------------------------------
 * @see CaseTriggerHandler
 */
@isTest
private class CaseTriggerHandlerTest {
  private static final Integer ASSET_COUNT = 5;

  @TestSetup
  static void setupData() {
    Id corporationRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Corporation')
      .getRecordTypeId();
    Account account = new Account(
      Name = '테스트 고객사',
      RecordTypeId = corporationRtId,
      BusinessRegistrationNumber__c = '1234567890',
      BillingContactEmail__c = 'billing@example.com'
    );
    insert account;

    // DESC: 사무실 용도 → 저장 전 Flow가 긴급으로 바꾸지 않음 (긴급 메일 Flow 미실행)
    CustomerSite__c site = new CustomerSite__c(
      Name = '테스트 사업장',
      Account__c = account.Id,
      ServiceCenter__c = 'GyeonggiSouth',
      UsageType__c = 'Office'
    );
    insert site;

    List<Asset> assets = new List<Asset>();
    for (Integer i = 0; i < ASSET_COUNT; i++) {
      assets.add(
        new Asset(
          Name = '테스트 장비 ' + i,
          SerialKey__c = 'TEST-CASE-' + i,
          AccountId = account.Id,
          CustomerSite__c = site.Id,
          Status = 'Installed',
          SalesChannel__c = 'Direct',
          InstallationDateSource__c = 'CommissioningReport',
          InstallDate = Date.today().addMonths(-6),
          WarrantyBasis__c = 'InstallationDate'
        )
      );
    }
    insert assets;
  }

  // ① 같은 장비 접수 3건을 차례로 → 3번째만 반복 고장
  @isTest
  static void thirdCaseOnSameAssetIsRepeatFailure() {
    Asset asset = getAsset(0);

    Test.startTest();
    Case first = newCase(asset.Id, 1);
    insert first;
    Case second = newCase(asset.Id, 2);
    insert second;
    Case third = newCase(asset.Id, 3);
    insert third;
    Test.stopTest();

    Map<Id, Case> casesById = new Map<Id, Case>(
      [SELECT Id, RepeatFailure__c FROM Case WHERE AssetId = :asset.Id]
    );
    Assert.isFalse(
      casesById.get(first.Id).RepeatFailure__c,
      '1번째 접수는 반복 고장이 아니어야 함'
    );
    Assert.isFalse(
      casesById.get(second.Id).RepeatFailure__c,
      '2번째 접수는 반복 고장이 아니어야 함'
    );
    Assert.isTrue(
      casesById.get(third.Id).RepeatFailure__c,
      '3번째 접수는 반복 고장이어야 함 (DB 2건 + 묶음 1건)'
    );
  }

  // ② 200건 한 번에 insert → 장비별 누적 접수 수·최근 접수일 정확
  @isTest
  static void bulkInsertUpdatesAssetTotals() {
    List<Asset> assets = [SELECT Id FROM Asset ORDER BY SerialKey__c];
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < 200; i++) {
      cases.add(newCase(assets[Math.mod(i, assets.size())].Id, i));
    }

    Test.startTest();
    insert cases;
    Test.stopTest();

    for (Asset a : [SELECT TotalCaseCount__c, LastCaseDate__c FROM Asset]) {
      Assert.areEqual(
        200 / ASSET_COUNT,
        a.TotalCaseCount__c,
        '장비별 누적 접수 수'
      );
      Assert.areEqual(Date.today(), a.LastCaseDate__c, '최근 접수일');
    }
    // DESC: 장비당 40건을 순서대로 세면 3번째부터 표시 → 장비당 38건 × 5대
    Assert.areEqual(
      190,
      [SELECT COUNT() FROM Case WHERE RepeatFailure__c = TRUE],
      '장비별 3번째 접수부터 반복 고장'
    );
  }

  // ①-2 같은 장비 3건을 한 번에 insert → Trigger.new 순서대로 세어 3번째만 반복 고장
  @isTest
  static void sameAssetThreeInOneBatchFlagsOnlyThird() {
    Asset asset = getAsset(0);
    List<Case> cases = new List<Case>{
      newCase(asset.Id, 1),
      newCase(asset.Id, 2),
      newCase(asset.Id, 3)
    };

    Test.startTest();
    insert cases;
    Test.stopTest();

    Map<Id, Case> casesById = new Map<Id, Case>(
      [SELECT Id, RepeatFailure__c FROM Case WHERE AssetId = :asset.Id]
    );
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

  // ③ 접수 삭제 → 장비 누적 수 감소 (after delete)
  @isTest
  static void deleteDecrementsAssetTotal() {
    Asset asset = getAsset(0);
    List<Case> cases = new List<Case>{
      newCase(asset.Id, 1),
      newCase(asset.Id, 2),
      newCase(asset.Id, 3)
    };
    insert cases;

    Test.startTest();
    delete cases[0];
    Test.stopTest();

    Assert.areEqual(
      2,
      [SELECT TotalCaseCount__c FROM Asset WHERE Id = :asset.Id]
      .TotalCaseCount__c,
      '삭제 후 누적 수'
    );
  }

  // ④ 스위치를 끄면 반복 고장 표시·장비 집계 모두 하지 않음
  @isTest
  static void switchOffSkipsAllLogic() {
    Asset asset = getAsset(0);
    TriggerHandler.activeOverridesByObject.put('Case', false);

    Test.startTest();
    insert new List<Case>{
      newCase(asset.Id, 1),
      newCase(asset.Id, 2),
      newCase(asset.Id, 3)
    };
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Case WHERE RepeatFailure__c = TRUE],
      '반복 고장 표시 없음'
    );
    Assert.isNull(
      [SELECT TotalCaseCount__c FROM Asset WHERE Id = :asset.Id]
      .TotalCaseCount__c,
      '장비 집계 없음'
    );
  }

  // + 장비 변경 시 이전·새 장비 모두 재계산, 취소로 바뀌면 누적 수에서 제외 (after update)
  @isTest
  static void updateRecalculatesOldNewAndCanceled() {
    Asset assetA = getAsset(0);
    Asset assetB = getAsset(1);
    Case moved = newCase(assetA.Id, 1);
    Case canceled = newCase(assetB.Id, 2);
    insert new List<Case>{ moved, canceled };

    Test.startTest();
    moved.AssetId = assetB.Id;
    canceled.Status = 'Canceled';
    canceled.CancelReason__c = '고객 요청으로 취소';
    update new List<Case>{ moved, canceled };
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT TotalCaseCount__c FROM Asset WHERE Id = :assetA.Id]
      .TotalCaseCount__c,
      '이전 장비는 0건'
    );
    Assert.areEqual(
      1,
      [SELECT TotalCaseCount__c FROM Asset WHERE Id = :assetB.Id]
      .TotalCaseCount__c,
      '새 장비는 옮겨 온 1건만 (취소 제외)'
    );
  }

  // 불허 ① 장비 없는 접수 → Validation Rule(Asset_Required)로 저장 거부, 트리거 처리 흔적 없음
  @isTest
  static void caseWithoutAssetIsRejected() {
    Case noAsset = new Case(
      Subject = '장비 없는 접수',
      Status = 'New',
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

  // 불허 ② 200건 중 20건이 거부(장비 없음)돼도 나머지 180건은 저장되고 장비 집계는 저장된 건만 반영
  @isTest
  static void bulkPartialRejectKeepsValidTotals() {
    List<Asset> assets = [SELECT Id FROM Asset ORDER BY SerialKey__c];
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < 200; i++) {
      // DESC: 10건마다 1건은 장비를 비워 Validation Rule에 걸리게 함
      Id assetId = (Math.mod(i, 10) == 9)
        ? null
        : assets[Math.mod(i, assets.size())].Id;
      cases.add(newCase(assetId, i));
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

  // 회귀: 같은 트랜잭션에서 장비 변경 → 취소를 연달아 해도 두 번 모두 재계산 (200건 update 벌크에서 발견한 결함)
  @isTest
  static void consecutiveUpdatesInSameTransactionRecalculate() {
    Asset assetA = getAsset(0);
    Asset assetB = getAsset(1);
    Case target = newCase(assetA.Id, 1);
    insert target;

    Test.startTest();
    target.Subject = '제목만 수정';
    update target;
    target.AssetId = assetB.Id;
    update target;
    Assert.areEqual(
      1,
      [SELECT TotalCaseCount__c FROM Asset WHERE Id = :assetB.Id]
      .TotalCaseCount__c,
      '장비 변경 후 새 장비 1건'
    );
    target.Status = 'Canceled';
    target.CancelReason__c = '고객 요청으로 취소';
    update target;
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT TotalCaseCount__c FROM Asset WHERE Id = :assetA.Id]
      .TotalCaseCount__c,
      '이전 장비 0건'
    );
    Assert.areEqual(
      0,
      [SELECT TotalCaseCount__c FROM Asset WHERE Id = :assetB.Id]
      .TotalCaseCount__c,
      '취소 후 새 장비도 0건'
    );
  }

  private static Asset getAsset(Integer index) {
    return [SELECT Id FROM Asset WHERE SerialKey__c = :('TEST-CASE-' + index)];
  }

  private static Case newCase(Id assetId, Integer seq) {
    return new Case(
      AssetId = assetId,
      Subject = '테스트 접수 ' + seq,
      Status = 'New',
      Origin = 'Phone'
    );
  }
}
