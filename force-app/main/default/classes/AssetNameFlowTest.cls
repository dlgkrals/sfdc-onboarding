/**
 * @description 장비 이름 자동 생성 Flow 테스트 (D8)
 *              Asset_BeforeSave_NameAndSerialKey: 이름 = 모델/고객사/사업장/시리얼 끝자리, 시리얼 키 = 일련번호
 *              CustomerSite_AfterSave_RenameAssets · Account_AfterSave_RenameAssets: 이름이 바뀌면 그 장비들 이름 다시 생성
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-14
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-14    Edwin     최초 작성 (D8 장비 이름 자동 생성)
 * ----------------------------------------------------------------------------
 * @see Flow Asset_BeforeSave_NameAndSerialKey, CustomerSite_AfterSave_RenameAssets, Account_AfterSave_RenameAssets
 */
@isTest
private class AssetNameFlowTest {
  private static final String MODEL = 'HAC-300';

  @TestSetup
  static void setupData() {
    Account account = TestDataFactory.createAccount();
    TestDataFactory.createSite(account.Id);
    insert new Product2(
      Name = MODEL,
      Family = 'EquipmentModel',
      IsActive = true
    );
  }

  private static Asset buildAsset(String serialNumber) {
    Asset asset = TestDataFactory.buildAsset(
      [SELECT Id FROM Account LIMIT 1].Id,
      [SELECT Id FROM CustomerSite__c LIMIT 1].Id,
      null,
      Date.today().addMonths(-6),
      false
    );
    asset.Product2Id = [SELECT Id FROM Product2 WHERE Name = :MODEL].Id;
    asset.SerialNumber = serialNumber;
    return asset;
  }

  private static Asset reload(Id assetId) {
    return [
      SELECT Name, SerialNumber, SerialKey__c
      FROM Asset
      WHERE Id = :assetId
    ];
  }

  // 정상: 생성 시 이름 = 모델/고객사/사업장/시리얼 끝자리(마지막 하이픈 뒤), 시리얼 키 = 일련번호
  @isTest
  static void normalNameBuiltOnInsert() {
    Asset asset = buildAsset('HG-HAC300-2202-0063');

    Test.startTest();
    insert asset;
    Test.stopTest();

    Asset saved = reload(asset.Id);
    Assert.areEqual(
      'HAC-300/테스트 고객사/테스트 사업장/0063',
      saved.Name,
      '이름'
    );
    Assert.areEqual(
      'HG-HAC300-2202-0063',
      saved.SerialKey__c,
      '시리얼 키 = 일련번호'
    );
  }

  // 정상: 빈 칸은 건너뜀(사업장·모델 없음), 하이픈 없는 시리얼은 전체, 일련번호가 비고 시리얼 키만 있으면 일련번호로 채움
  @isTest
  static void normalBlankPartsSkippedAndSerialKeyFillsNumber() {
    Asset asset = buildAsset(null);
    asset.CustomerSite__c = null;
    asset.Product2Id = null;
    asset.SerialKey__c = 'NOHYPHEN01';

    Test.startTest();
    insert asset;
    Test.stopTest();

    Asset saved = reload(asset.Id);
    Assert.areEqual('테스트 고객사/NOHYPHEN01', saved.Name, '빈 칸 건너뜀');
    Assert.areEqual(
      'NOHYPHEN01',
      saved.SerialNumber,
      '일련번호를 시리얼 키로 채움'
    );
  }

  // 정상: 시리얼이 바뀌면 이름 다시 생성 · 불허: 이름을 손으로 고쳐도 규칙대로 되돌림
  @isTest
  static void normalRegeneratedOnChangeAndManualNameReverted() {
    Asset asset = buildAsset('HG-HAC300-2202-0063');
    insert asset;

    Test.startTest();
    update new Asset(Id = asset.Id, SerialNumber = 'HG-HAC300-2202-0099');
    update new Asset(Id = asset.Id, Name = '손으로 바꾼 이름');
    Test.stopTest();

    Asset saved = reload(asset.Id);
    Assert.areEqual(
      'HAC-300/테스트 고객사/테스트 사업장/0099',
      saved.Name,
      '새 끝자리, 손 이름은 되돌림'
    );
    Assert.areEqual(
      'HG-HAC300-2202-0099',
      saved.SerialKey__c,
      '시리얼 키도 따라감'
    );
  }

  // 벌크: 한 사업장의 장비 200건 → 사업장 이름 변경 한 번에 모두 새 이름
  @isTest
  static void bulkSiteRenameUpdatesAllAssets() {
    List<Asset> assets = new List<Asset>();
    Asset template = buildAsset(null);
    for (Integer i = 0; i < 200; i++) {
      Asset a = template.clone();
      a.SerialNumber = 'HG-BULK-' + String.valueOf(i).leftPad(4, '0');
      assets.add(a);
    }
    insert assets;
    CustomerSite__c site = [SELECT Id FROM CustomerSite__c LIMIT 1];

    Test.startTest();
    update new CustomerSite__c(Id = site.Id, Name = '이름 바뀐 사업장');
    Test.stopTest();

    Assert.areEqual(
      200,
      [
        SELECT COUNT()
        FROM Asset
        WHERE Name LIKE 'HAC-300/테스트 고객사/이름 바뀐 사업장/%'
      ],
      '200건 모두 새 사업장 이름'
    );
  }

  // 정상: 고객사 이름이 바뀌면 그 고객사 장비 이름 다시 생성
  @isTest
  static void normalAccountRenameUpdatesAssets() {
    Asset asset = buildAsset('HG-HAC300-2202-0063');
    insert asset;
    Account account = [SELECT Id FROM Account LIMIT 1];

    Test.startTest();
    update new Account(Id = account.Id, Name = '이름 바뀐 고객사');
    Test.stopTest();

    Assert.areEqual(
      'HAC-300/이름 바뀐 고객사/테스트 사업장/0063',
      reload(asset.Id).Name,
      '새 고객사 이름'
    );
  }

  // 불허: 사업장의 이름이 아닌 값(상세주소)만 바뀌면 장비는 건드리지 않음
  @isTest
  static void rejectNonNameSiteChangeDoesNotTouchAssets() {
    Asset asset = buildAsset('HG-HAC300-2202-0063');
    insert asset;
    update new Asset(Id = asset.Id, Description = '표시');
    Datetime before = [SELECT LastModifiedDate FROM Asset WHERE Id = :asset.Id]
    .LastModifiedDate;
    CustomerSite__c site = [SELECT Id FROM CustomerSite__c LIMIT 1];

    Test.startTest();
    update new CustomerSite__c(Id = site.Id, DetailAddress__c = '3층');
    Test.stopTest();

    Assert.areEqual(
      before,
      [SELECT LastModifiedDate FROM Asset WHERE Id = :asset.Id]
      .LastModifiedDate,
      '장비 저장 안 됨'
    );
  }
}
