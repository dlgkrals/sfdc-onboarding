/**
 * @description WarrantyService(ProductConsumedTrigger 경유) 유·무상 자동 판정을 검증하는 테스트 클래스 (D5 초안, D6에서 확장)
 *              ① 설치 2년 차 장비: 압축기 무상·일반 부품 유상 ② 보증 미확정 → 유상
 *              ③ 최종 판정을 사람이 정하면 덮어쓰지 않음 ④ 200건 벌크
 *              + 연장보증 장비의 일반 부품은 연장 만료일 기준 무상
 *              기준값은 Custom Metadata 기본값(기본 12·압축기 36·연장 24개월)에 의존
 * @testTarget  WarrantyService, ProductConsumedTriggerHandler
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-08
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-08    Edwin     최초 작성 (D5 테스트 초안)
 * ----------------------------------------------------------------------------
 * @see WarrantyService
 */
@isTest
private class WarrantyServiceTest {
  private static final String ASSET_TWO_YEAR = 'TEST-WTY-2Y';
  private static final String ASSET_UNKNOWN = 'TEST-WTY-UNKNOWN';
  private static final String ASSET_EXTENDED = 'TEST-WTY-EXT';

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

    CustomerSite__c site = new CustomerSite__c(
      Name = '테스트 사업장',
      Account__c = account.Id,
      ServiceCenter__c = 'GyeonggiSouth',
      UsageType__c = 'Office'
    );
    insert site;

    Date twoYearsAgo = Date.today().addYears(-2);
    List<Asset> assets = new List<Asset>{
      // DESC: 설치 2년 차 → 기본(12개월) 만료, 압축기(36개월) 보증 중
      newAsset(account.Id, site.Id, ASSET_TWO_YEAR, twoYearsAgo, false),
      // DESC: 같은 2년 차 + 연장보증 → 기본 만료 후 24개월 연장
      newAsset(account.Id, site.Id, ASSET_EXTENDED, twoYearsAgo, true),
      // DESC: 설치일 근거 미확인 + 보증 기준 없음 → 보증 시작일 미확정
      new Asset(
        Name = '보증 미확정 장비',
        SerialKey__c = ASSET_UNKNOWN,
        AccountId = account.Id,
        CustomerSite__c = site.Id,
        Status = 'Installed',
        SalesChannel__c = 'Direct',
        InstallationDateSource__c = 'Unverified'
      )
    };
    insert assets;

    List<Case> cases = new List<Case>();
    for (Asset a : assets) {
      cases.add(
        new Case(
          AssetId = a.Id,
          Subject = '테스트 접수 ' + a.SerialKey__c,
          Status = 'New',
          Origin = 'Phone'
        )
      );
    }
    insert cases;

    List<WorkOrder> workOrders = new List<WorkOrder>();
    for (Case c : cases) {
      workOrders.add(
        new WorkOrder(
          CaseId = c.Id,
          AssetId = c.AssetId,
          Subject = c.Subject,
          Status = 'Assigned'
        )
      );
    }
    insert workOrders;

    List<Product2> products = new List<Product2>{
      new Product2(
        Name = '테스트 압축기',
        Family = 'Compressor',
        ErpPartCode__c = 'TEST-CMP',
        ErpUnitPrice__c = 500000,
        IsActive = true
      ),
      new Product2(
        Name = '테스트 일반 부품',
        Family = 'General',
        ErpPartCode__c = 'TEST-GEN',
        ErpUnitPrice__c = 20000,
        IsActive = true
      )
    };
    insert products;

    Schema.Location van = new Schema.Location(
      Name = '테스트 차량',
      LocationType = 'Van',
      IsInventoryLocation = true
    );
    insert van;
    insert new List<ProductItem>{
      new ProductItem(
        LocationId = van.Id,
        Product2Id = products[0].Id,
        QuantityOnHand = 1000
      ),
      new ProductItem(
        LocationId = van.Id,
        Product2Id = products[1].Id,
        QuantityOnHand = 1000
      )
    };
  }

  // ① 설치 2년 차: 압축기는 압축기 만료일 기준 무상, 일반 부품은 기본 만료일 기준 유상
  @isTest
  static void twoYearAssetCompressorFreeGeneralPaid() {
    WorkOrder workOrder = getWorkOrder(ASSET_TWO_YEAR);

    Test.startTest();
    ProductConsumed compressor = newPart(
      workOrder.Id,
      getProductItemId('Compressor')
    );
    ProductConsumed general = newPart(
      workOrder.Id,
      getProductItemId('General')
    );
    insert new List<ProductConsumed>{ compressor, general };
    Test.stopTest();

    Asset asset = [
      SELECT fmBasicWarrantyEndDate__c, fmCompressorWarrantyEndDate__c
      FROM Asset
      WHERE SerialKey__c = :ASSET_TWO_YEAR
    ];
    ProductConsumed savedCompressor = getPart(compressor.Id);
    Assert.areEqual(
      WarrantyService.CHARGE_FREE,
      savedCompressor.AutoChargeType__c,
      '압축기 자동 판정'
    );
    Assert.areEqual(
      WarrantyService.CHARGE_FREE,
      savedCompressor.ChargeType__c,
      '최종 판정은 비어 있었으므로 자동 판정 값'
    );
    Assert.areEqual(
      asset.fmCompressorWarrantyEndDate__c,
      savedCompressor.WarrantyEndDateAtJudgment__c,
      '압축기 만료일 기준'
    );
    Assert.areEqual(
      'Compressor',
      savedCompressor.PartCategoryAtUse__c,
      '사용 시점 분류'
    );
    Assert.areEqual(
      500000,
      savedCompressor.UnitPriceAtUse__c,
      '사용 시점 단가 = ERP 단가'
    );

    ProductConsumed savedGeneral = getPart(general.Id);
    Assert.areEqual(
      WarrantyService.CHARGE_PAID,
      savedGeneral.AutoChargeType__c,
      '일반 부품 자동 판정'
    );
    Assert.areEqual(
      asset.fmBasicWarrantyEndDate__c,
      savedGeneral.WarrantyEndDateAtJudgment__c,
      '기본 만료일 기준'
    );
  }

  // ② 보증 미확정(만료일 없음) → 유상, 판정 만료일 비어 있음
  @isTest
  static void unknownWarrantyIsPaid() {
    WorkOrder workOrder = getWorkOrder(ASSET_UNKNOWN);

    Test.startTest();
    ProductConsumed part = newPart(
      workOrder.Id,
      getProductItemId('Compressor')
    );
    insert part;
    Test.stopTest();

    ProductConsumed saved = getPart(part.Id);
    Assert.areEqual(
      WarrantyService.CHARGE_PAID,
      saved.AutoChargeType__c,
      '보증 미확정은 유상'
    );
    Assert.isNull(saved.WarrantyEndDateAtJudgment__c, '적용 만료일 없음');
  }

  // ③ 사람이 정한 최종 판정은 덮어쓰지 않음 (자동 무상이어도 유상 유지)
  @isTest
  static void manualChargeTypeIsNotOverwritten() {
    WorkOrder workOrder = getWorkOrder(ASSET_TWO_YEAR);

    Test.startTest();
    ProductConsumed part = newPart(
      workOrder.Id,
      getProductItemId('Compressor')
    );
    part.ChargeType__c = WarrantyService.CHARGE_PAID;
    // DESC: 자동 판정과 다르게 확정하면 Validation Rule(OverrideReason_Required)로 사유가 필요
    part.OverrideReason__c = '고객 과실 파손';
    insert part;
    Test.stopTest();

    ProductConsumed saved = getPart(part.Id);
    Assert.areEqual(
      WarrantyService.CHARGE_FREE,
      saved.AutoChargeType__c,
      '자동 판정은 무상'
    );
    Assert.areEqual(
      WarrantyService.CHARGE_PAID,
      saved.ChargeType__c,
      '사람이 정한 유상 유지'
    );
  }

  // ④ 200건 한 번에 insert → 전부 판정, 분류별 결과 일치
  @isTest
  static void bulkInsertJudgesAll() {
    WorkOrder workOrder = getWorkOrder(ASSET_TWO_YEAR);
    Id compressorItemId = getProductItemId('Compressor');
    Id generalItemId = getProductItemId('General');
    List<ProductConsumed> parts = new List<ProductConsumed>();
    for (Integer i = 0; i < 200; i++) {
      parts.add(
        newPart(
          workOrder.Id,
          Math.mod(i, 2) == 0 ? compressorItemId : generalItemId
        )
      );
    }

    Test.startTest();
    insert parts;
    Test.stopTest();

    Assert.areEqual(
      100,
      [
        SELECT COUNT()
        FROM ProductConsumed
        WHERE PartCategoryAtUse__c = 'Compressor' AND ChargeType__c = 'Free'
      ],
      '압축기 100건 무상'
    );
    Assert.areEqual(
      100,
      [
        SELECT COUNT()
        FROM ProductConsumed
        WHERE PartCategoryAtUse__c = 'General' AND ChargeType__c = 'Paid'
      ],
      '일반 부품 100건 유상'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM ProductConsumed WHERE AutoChargeType__c = NULL],
      '판정 누락 없음'
    );
  }

  // + 연장보증 장비: 일반 부품도 연장 만료일 기준 무상
  @isTest
  static void extendedWarrantyGeneralIsFree() {
    WorkOrder workOrder = getWorkOrder(ASSET_EXTENDED);

    Test.startTest();
    ProductConsumed part = newPart(workOrder.Id, getProductItemId('General'));
    insert part;
    Test.stopTest();

    Asset asset = [
      SELECT fmExtendedWarrantyEndDate__c
      FROM Asset
      WHERE SerialKey__c = :ASSET_EXTENDED
    ];
    ProductConsumed saved = getPart(part.Id);
    Assert.areEqual(
      WarrantyService.CHARGE_FREE,
      saved.AutoChargeType__c,
      '연장보증 중이면 일반 부품도 무상'
    );
    Assert.areEqual(
      asset.fmExtendedWarrantyEndDate__c,
      saved.WarrantyEndDateAtJudgment__c,
      '연장 만료일 기준'
    );
  }

  private static Asset newAsset(
    Id accountId,
    Id siteId,
    String serialKey,
    Date installDate,
    Boolean hasExtended
  ) {
    return new Asset(
      Name = '테스트 장비 ' + serialKey,
      SerialKey__c = serialKey,
      AccountId = accountId,
      CustomerSite__c = siteId,
      Status = 'Installed',
      SalesChannel__c = 'Direct',
      InstallationDateSource__c = 'CommissioningReport',
      InstallDate = installDate,
      WarrantyBasis__c = 'InstallationDate',
      HasExtendedWarranty__c = hasExtended
    );
  }

  private static WorkOrder getWorkOrder(String serialKey) {
    return [
      SELECT Id
      FROM WorkOrder
      WHERE Asset.SerialKey__c = :serialKey
      LIMIT 1
    ];
  }

  private static Id getProductItemId(String family) {
    return [
      SELECT Id
      FROM ProductItem
      WHERE Product2.Family = :family AND Location.Name = '테스트 차량'
      LIMIT 1
    ]
    .Id;
  }

  private static ProductConsumed newPart(Id workOrderId, Id productItemId) {
    return new ProductConsumed(
      WorkOrderId = workOrderId,
      ProductItemId = productItemId,
      QuantityConsumed = 1
    );
  }

  private static ProductConsumed getPart(Id partId) {
    return [
      SELECT
        AutoChargeType__c,
        ChargeType__c,
        WarrantyEndDateAtJudgment__c,
        PartCategoryAtUse__c,
        UnitPriceAtUse__c
      FROM ProductConsumed
      WHERE Id = :partId
    ];
  }
}
