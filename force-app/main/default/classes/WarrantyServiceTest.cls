/**
 * @description WarrantyService(ProductConsumedTrigger 경유) 유·무상 자동 판정을 검증하는 테스트 클래스
 *              메서드 이름 접두어: normal = 정상, reject = 불허, bulk = 벌크 200건
 *              기준값은 Custom Metadata 기본값(기본 12·압축기 36·연장 24개월)에 의존
 * @testTarget  WarrantyService, ProductConsumedTriggerHandler
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-08
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-08    Edwin     최초 작성 (D5 테스트 초안)
 * 1.1    2026-10-11    Edwin     불허 케이스 2개 추가 (사유 없는 판정 변경 거부, 벌크 일부 거부)
 * 1.2    2026-10-12    Edwin     TestDataFactory 사용, 이름에 정상/불허/벌크 접두어, 협력 기사(runAs) 판정·
 *                                빈 입력·Product2Id 직접 지정·만료일 비교 경로 추가
 * ----------------------------------------------------------------------------
 * @see WarrantyService, TestDataFactory
 */
@isTest
private class WarrantyServiceTest {
  private static final String ASSET_TWO_YEAR = 'TEST-WTY-2Y';
  private static final String ASSET_UNKNOWN = 'TEST-WTY-UNKNOWN';
  private static final String ASSET_EXTENDED = 'TEST-WTY-EXT';
  private static final String FAMILY_COMPRESSOR = 'Compressor';
  private static final String FAMILY_GENERAL = 'General';

  @TestSetup
  static void setupData() {
    // DESC: 사용자·권한 집합 배정은 Mixed DML을 피하려고 현재 사용자 runAs 블록에서 먼저 생성
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.createUser('HG_Technician', true);
    }
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);

    Date twoYearsAgo = Date.today().addYears(-2);
    List<Asset> assets = new List<Asset>{
      // DESC: 설치 2년 차 → 기본(12개월) 만료, 압축기(36개월) 보증 중
      TestDataFactory.buildAsset(
        account.Id,
        site.Id,
        ASSET_TWO_YEAR,
        twoYearsAgo,
        false
      ),
      // DESC: 같은 2년 차 + 연장보증 → 기본 만료 후 24개월 연장
      TestDataFactory.buildAsset(
        account.Id,
        site.Id,
        ASSET_EXTENDED,
        twoYearsAgo,
        true
      ),
      // DESC: 설치일 근거 미확인 + 보증 기준 없음 → 보증 시작일 미확정
      TestDataFactory.buildUnverifiedAsset(account.Id, site.Id, ASSET_UNKNOWN)
    };
    insert assets;

    TestDataFactory.createWorkOrders(TestDataFactory.createCases(assets, 1));
    TestDataFactory.createVanStock(TestDataFactory.createProducts(), 1000);
  }

  // 정상: 설치 2년 차 → 압축기는 압축기 만료일 기준 무상, 일반 부품은 기본 만료일 기준 유상
  @isTest
  static void normalTwoYearAssetCompressorFreeGeneralPaid() {
    WorkOrder workOrder = getWorkOrder(ASSET_TWO_YEAR);

    Test.startTest();
    ProductConsumed compressor = TestDataFactory.buildPart(
      workOrder.Id,
      getProductItemId(FAMILY_COMPRESSOR)
    );
    ProductConsumed general = TestDataFactory.buildPart(
      workOrder.Id,
      getProductItemId(FAMILY_GENERAL)
    );
    insert new List<ProductConsumed>{ compressor, general };
    Test.stopTest();

    Asset asset = getAssetDates(ASSET_TWO_YEAR);
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
      FAMILY_COMPRESSOR,
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

  // 정상: 보증 미확정(만료일 없음) → 유상, 판정 만료일 비어 있음
  @isTest
  static void normalUnknownWarrantyIsPaid() {
    WorkOrder workOrder = getWorkOrder(ASSET_UNKNOWN);

    Test.startTest();
    ProductConsumed part = TestDataFactory.buildPart(
      workOrder.Id,
      getProductItemId(FAMILY_COMPRESSOR)
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

  // 정상: 연장보증 장비 → 일반 부품도 연장 만료일 기준 무상
  @isTest
  static void normalExtendedWarrantyGeneralIsFree() {
    WorkOrder workOrder = getWorkOrder(ASSET_EXTENDED);

    Test.startTest();
    ProductConsumed part = TestDataFactory.buildPart(
      workOrder.Id,
      getProductItemId(FAMILY_GENERAL)
    );
    insert part;
    Test.stopTest();

    ProductConsumed saved = getPart(part.Id);
    Assert.areEqual(
      WarrantyService.CHARGE_FREE,
      saved.AutoChargeType__c,
      '연장보증 중이면 일반 부품도 무상'
    );
    Assert.areEqual(
      getAssetDates(ASSET_EXTENDED).fmExtendedWarrantyEndDate__c,
      saved.WarrantyEndDateAtJudgment__c,
      '연장 만료일 기준'
    );
  }

  // 정상: 사람이 정한 최종 판정은 덮어쓰지 않음 (자동 무상이어도 유상 유지, 사유 입력)
  @isTest
  static void normalManualChargeTypeIsNotOverwritten() {
    WorkOrder workOrder = getWorkOrder(ASSET_TWO_YEAR);

    Test.startTest();
    ProductConsumed part = TestDataFactory.buildPart(
      workOrder.Id,
      getProductItemId(FAMILY_COMPRESSOR)
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

  // 정상: 협력 기사(HG_Technician, 고객사·장비·접수 권한 없음)가 사용 부품을 입력해도 트리거 경유 판정이 정상 동작
  //       기사는 자기 출동만 보므로 출동 소유자를 기사로 둠
  @isTest
  static void normalTechnicianUserJudgesViaTrigger() {
    User technician = [
      SELECT Id
      FROM User
      WHERE LastName = '테스트 HG_Technician'
      LIMIT 1
    ];
    WorkOrder source = [
      SELECT CaseId, AssetId
      FROM WorkOrder
      WHERE Asset.SerialKey__c = :ASSET_TWO_YEAR
      LIMIT 1
    ];
    WorkOrder technicianWorkOrder = new WorkOrder(
      CaseId = source.CaseId,
      AssetId = source.AssetId,
      Subject = '기사 출동',
      Status = 'Assigned',
      OwnerId = technician.Id
    );
    insert technicianWorkOrder;
    // DESC: 운영과 같게 기사 차량 재고는 기사 소유 (관리자 소유 재고는 기사가 쓸 권한이 없음)
    Schema.Location technicianVan = new Schema.Location(
      Name = '기사 차량',
      LocationType = 'Van',
      IsInventoryLocation = true,
      OwnerId = technician.Id
    );
    insert technicianVan;
    ProductItem technicianItem = new ProductItem(
      LocationId = technicianVan.Id,
      Product2Id = [
        SELECT Id
        FROM Product2
        WHERE Family = :FAMILY_COMPRESSOR
        LIMIT 1
      ]
      .Id,
      QuantityOnHand = 10,
      OwnerId = technician.Id
    );
    insert technicianItem;

    ProductConsumed part = TestDataFactory.buildPart(
      technicianWorkOrder.Id,
      technicianItem.Id
    );
    Test.startTest();
    System.runAs(technician) {
      insert part;
    }
    Test.stopTest();

    ProductConsumed saved = getPart(part.Id);
    Assert.areEqual(
      WarrantyService.CHARGE_FREE,
      saved.AutoChargeType__c,
      '기사가 입력해도 압축기 무상 판정'
    );
    Assert.areEqual(
      getAssetDates(ASSET_TWO_YEAR).fmCompressorWarrantyEndDate__c,
      saved.WarrantyEndDateAtJudgment__c,
      '기사 권한으로도 장비 보증 만료일을 읽음'
    );
    Assert.areEqual(
      FAMILY_COMPRESSOR,
      saved.PartCategoryAtUse__c,
      '기사 권한으로도 부품 분류를 읽음'
    );
  }

  // 정상: 빈 입력(null·빈 목록)은 아무것도 하지 않음
  @isTest
  static void normalEmptyInputDoesNothing() {
    Test.startTest();
    WarrantyService.judgeChargeTypes(null);
    WarrantyService.judgeChargeTypes(new List<ProductConsumed>());
    Integer soql = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(0, soql, '빈 입력에는 쿼리 없음');
  }

  // 정상: Product2Id가 이미 채워진 사용 부품은 제품 항목을 거치지 않고 부품으로 바로 분류 (메모리 레코드로 직접 호출)
  @isTest
  static void normalProduct2IdUsedDirectly() {
    WorkOrder workOrder = getWorkOrder(ASSET_TWO_YEAR);
    Id compressorId = [
      SELECT Id
      FROM Product2
      WHERE Family = :FAMILY_COMPRESSOR
      LIMIT 1
    ]
    .Id;
    // DESC: Product2Id는 생성 시 직접 쓸 수 없는 필드라 JSON으로 메모리 레코드를 만듦
    ProductConsumed part = (ProductConsumed) JSON.deserialize(
      '{"attributes":{"type":"ProductConsumed"},"WorkOrderId":"' +
        workOrder.Id +
        '","Product2Id":"' +
        compressorId +
        '"}',
      ProductConsumed.class
    );

    Test.startTest();
    WarrantyService.judgeChargeTypes(new List<ProductConsumed>{ part });
    Test.stopTest();

    Assert.areEqual(FAMILY_COMPRESSOR, part.PartCategoryAtUse__c, '부품 분류');
    Assert.areEqual(
      WarrantyService.CHARGE_FREE,
      part.AutoChargeType__c,
      '압축기 보증 중이라 무상'
    );
  }

  // 정상: 판정 기준일·적용 만료일 보조 계산의 경계 (출동·접수·장비 없음, 압축기·연장 만료일 중 늦은 날)
  @isTest
  static void normalDateHelpersHandleMissingAndLaterDates() {
    Id assetId = [SELECT Id FROM Asset WHERE SerialKey__c = :ASSET_EXTENDED].Id;
    WorkOrder extendedLater = buildMemoryWorkOrder(
      assetId,
      '2027-01-31',
      '2028-06-30'
    );
    WorkOrder compressorLater = buildMemoryWorkOrder(
      assetId,
      '2029-03-31',
      '2028-06-30'
    );

    Test.startTest();
    Date noWorkOrder = WarrantyService.getJudgmentDate(null);
    Date noCase = WarrantyService.getJudgmentDate(new WorkOrder());
    Date endWithoutWorkOrder = WarrantyService.getApplicableEndDate(
      null,
      FAMILY_COMPRESSOR
    );
    Date endWithoutAsset = WarrantyService.getApplicableEndDate(
      new WorkOrder(),
      FAMILY_COMPRESSOR
    );
    Date extendedWins = WarrantyService.getApplicableEndDate(
      extendedLater,
      FAMILY_COMPRESSOR
    );
    Date compressorWins = WarrantyService.getApplicableEndDate(
      compressorLater,
      FAMILY_COMPRESSOR
    );
    Test.stopTest();

    Assert.areEqual(Date.today(), noWorkOrder, '출동 없으면 오늘 기준');
    Assert.areEqual(Date.today(), noCase, '접수 없으면 오늘 기준');
    Assert.isNull(endWithoutWorkOrder, '출동 없으면 만료일 없음');
    Assert.isNull(endWithoutAsset, '장비 없으면 만료일 없음');
    Assert.areEqual(
      Date.newInstance(2028, 6, 30),
      extendedWins,
      '연장 만료일이 늦으면 연장 만료일'
    );
    Assert.areEqual(
      Date.newInstance(2029, 3, 31),
      compressorWins,
      '압축기 만료일이 늦으면 압축기 만료일'
    );
  }

  // 불허: 자동 판정(무상)과 다르게 유상으로 확정하면서 사유가 없으면 저장 거부 (Validation Rule OverrideReason_Required)
  //       트리거가 Validation Rule보다 먼저 자동 판정을 채우므로 규칙이 비교할 값이 있어야 함
  @isTest
  static void rejectOverrideWithoutReason() {
    WorkOrder workOrder = getWorkOrder(ASSET_TWO_YEAR);
    ProductConsumed part = TestDataFactory.buildPart(
      workOrder.Id,
      getProductItemId(FAMILY_COMPRESSOR)
    );
    part.ChargeType__c = WarrantyService.CHARGE_PAID;

    Test.startTest();
    DmlException caught;
    try {
      insert part;
    } catch (DmlException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(caught, '사유 없는 판정 변경은 저장되면 안 됨');
    Assert.isTrue(
      caught.getMessage().contains('사유'),
      '판정 변경 사유 오류 메시지: ' + caught.getMessage()
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM ProductConsumed],
      '저장된 사용 부품 없음'
    );
  }

  // 벌크: 200건 한 번에 insert → 전부 판정, 분류별 결과 일치
  @isTest
  static void bulkInsertJudgesAll() {
    WorkOrder workOrder = getWorkOrder(ASSET_TWO_YEAR);
    Id compressorItemId = getProductItemId(FAMILY_COMPRESSOR);
    Id generalItemId = getProductItemId(FAMILY_GENERAL);
    List<ProductConsumed> parts = new List<ProductConsumed>();
    for (Integer i = 0; i < 200; i++) {
      parts.add(
        TestDataFactory.buildPart(
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

  // 벌크(불허 포함): 200건 중 사유 없이 유상 확정한 100건만 거부, 나머지 100건은 무상으로 저장
  @isTest
  static void bulkPartialRejectWithoutReason() {
    WorkOrder workOrder = getWorkOrder(ASSET_TWO_YEAR);
    Id compressorItemId = getProductItemId(FAMILY_COMPRESSOR);
    List<ProductConsumed> parts = new List<ProductConsumed>();
    for (Integer i = 0; i < 200; i++) {
      ProductConsumed part = TestDataFactory.buildPart(
        workOrder.Id,
        compressorItemId
      );
      if (Math.mod(i, 2) == 1) {
        part.ChargeType__c = WarrantyService.CHARGE_PAID;
      }
      parts.add(part);
    }

    Test.startTest();
    List<Database.SaveResult> results = Database.insert(parts, false);
    Test.stopTest();

    Integer failed = 0;
    for (Database.SaveResult result : results) {
      if (!result.isSuccess()) {
        failed++;
      }
    }
    Assert.areEqual(100, failed, '사유 없는 유상 확정 100건 거부');
    Assert.areEqual(
      100,
      [SELECT COUNT() FROM ProductConsumed WHERE ChargeType__c = 'Free'],
      '나머지 100건은 자동 판정(무상)으로 저장'
    );
  }

  // DESC: 보증 만료일 Formula는 직접 쓸 수 없어 JSON으로 메모리 출동(+장비)을 만듦
  private static WorkOrder buildMemoryWorkOrder(
    Id assetId,
    String compressorEnd,
    String extendedEnd
  ) {
    return (WorkOrder) JSON.deserialize(
      '{"attributes":{"type":"WorkOrder"},"AssetId":"' +
        assetId +
        '","Asset":{"attributes":{"type":"Asset"},"Id":"' +
        assetId +
        '","HasExtendedWarranty__c":true,"fmCompressorWarrantyEndDate__c":"' +
        compressorEnd +
        '","fmExtendedWarrantyEndDate__c":"' +
        extendedEnd +
        '"}}',
      WorkOrder.class
    );
  }

  private static Asset getAssetDates(String serialKey) {
    return [
      SELECT
        fmBasicWarrantyEndDate__c,
        fmCompressorWarrantyEndDate__c,
        fmExtendedWarrantyEndDate__c
      FROM Asset
      WHERE SerialKey__c = :serialKey
    ];
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
      WHERE
        Product2.Family = :family
        AND Location.Name = :TestDataFactory.VAN_NAME
      LIMIT 1
    ]
    .Id;
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
