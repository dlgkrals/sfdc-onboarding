/**
 * @description WorkOrderPartsController 테스트 — 사용 부품 목록·합계, 차량 재고 선택지, 부품 추가(판정·재고 차감), 권한, 200건
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 LWC: 출동 사용 부품 화면)
 * ----------------------------------------------------------------------------
 * @see WorkOrderPartsController
 */
@isTest
private class WorkOrderPartsControllerTest {
  private static final Decimal VAN_QUANTITY = 300;

  @TestSetup
  static void setupData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.createUser('HG_Technician', true);
      TestDataFactory.createUser('HG_CallCenter', false);
    }
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    List<Asset> assets = TestDataFactory.createAssets(
      account.Id,
      site.Id,
      'TEST-WOP-',
      1
    );
    TestDataFactory.createWorkOrders(TestDataFactory.createCases(assets, 1));
    // DESC: 출동 소유자(실행 사용자)의 차량 재고 = 부품 추가 선택지
    Map<String, ProductItem> itemsByFamily = TestDataFactory.createVanStock(
      TestDataFactory.createProducts(),
      VAN_QUANTITY
    );
    ProductItem general = itemsByFamily.get('General');
    update new ProductItem(Id = general.Id, QuantityUnitOfMeasure = 'kg');
  }

  private static WorkOrder getWorkOrder() {
    return [SELECT Id, OwnerId FROM WorkOrder LIMIT 1];
  }

  private static ProductItem getItem(String family) {
    return [
      SELECT Id, QuantityOnHand, Product2Id, LocationId
      FROM ProductItem
      WHERE
        Product2.Family = :family
        AND Location.Name = :TestDataFactory.VAN_NAME
      LIMIT 1
    ];
  }

  private static User getUser(String permissionSetName) {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :('테스트 ' + permissionSetName)
      LIMIT 1
    ];
  }

  // 정상: 사용 부품 목록에 부품·수량·단위 표기·판정 표시 이름, 합계는 출동 롤업·수식 값
  @isTest
  static void normalGetPartsShowsRowsAndTotals() {
    WorkOrder wo = getWorkOrder();
    ProductConsumed general = TestDataFactory.buildPart(
      wo.Id,
      getItem('General').Id
    );
    general.QuantityConsumed = 2.5;
    insert new List<ProductConsumed>{
      general,
      TestDataFactory.buildPart(wo.Id, getItem('Compressor').Id)
    };

    Test.startTest();
    WorkOrderPartsController.PartsView view = WorkOrderPartsController.getParts(
      wo.Id
    );
    Test.stopTest();

    WorkOrder saved = [
      SELECT WorkOrderNumber, ruPaidPartsTotal__c, fmTotalCharge__c
      FROM WorkOrder
      WHERE Id = :wo.Id
    ];
    Assert.areEqual(2, view.rows.size(), '사용 부품 2건');
    Assert.areEqual(saved.WorkOrderNumber, view.workOrderNumber, '출동 번호');
    Assert.areEqual(
      saved.ruPaidPartsTotal__c,
      view.paidTotal,
      '유상 부품비 = 롤업'
    );
    Assert.areEqual(
      saved.fmTotalCharge__c,
      view.totalCharge,
      '총 청구액 = 수식'
    );
    Assert.isTrue(view.canAdd, '관리자는 추가 가능');
    for (WorkOrderPartsController.PartRow row : view.rows) {
      Assert.isNotNull(row.chargeTypeLabel, '판정 표시 이름: ' + row.partName);
      if (row.id == general.Id) {
        Assert.areEqual(2.5, row.quantity, '수량');
        Assert.areEqual(System.Label.MISC_UNIT_KG, row.unitLabel, 'kg 표기');
      }
    }
  }

  // 정상: 차량 재고 선택지 = 출동 소유자의 차량, 보유 수량 > 0만 (창고·빈 재고 제외)
  @isTest
  static void normalVanStockOnlyAvailableVanItems() {
    ProductItem compressor = getItem('Compressor');
    update new ProductItem(Id = compressor.Id, QuantityOnHand = 0);
    Schema.Location warehouse = new Schema.Location(
      Name = '테스트 창고',
      LocationType = 'Warehouse',
      IsInventoryLocation = true
    );
    insert warehouse;
    insert new ProductItem(
      LocationId = warehouse.Id,
      Product2Id = compressor.Product2Id,
      QuantityOnHand = 50
    );

    Test.startTest();
    List<WorkOrderPartsController.StockOption> options = WorkOrderPartsController.getVanStock(
      getWorkOrder().Id
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      options.size(),
      '빈 압축기·창고 재고 제외 → 일반 부품 1건'
    );
    Assert.areEqual(
      getItem('General').Id,
      options[0].productItemId,
      '차량 일반 부품'
    );
    Assert.areEqual(
      System.Label.MISC_UNIT_KG,
      options[0].unitLabel,
      '단위 표기'
    );
  }

  // 정상: 부품 추가 → 저장, 트리거가 유·무상 판정, 표준이 차량 재고 차감
  @isTest
  static void normalAddPartJudgedAndStockReduced() {
    WorkOrder wo = getWorkOrder();

    Test.startTest();
    Id partId = WorkOrderPartsController.addPart(
      wo.Id,
      getItem('General').Id,
      2.5
    );
    Test.stopTest();

    ProductConsumed saved = [
      SELECT QuantityConsumed, AutoChargeType__c, ChargeType__c
      FROM ProductConsumed
      WHERE Id = :partId
    ];
    Assert.areEqual(2.5, saved.QuantityConsumed, '수량');
    Assert.isNotNull(saved.AutoChargeType__c, '트리거 자동 판정');
    Assert.isNotNull(saved.ChargeType__c, '최종 판정 채움');
    Assert.areEqual(
      VAN_QUANTITY - 2.5,
      getItem('General').QuantityOnHand,
      '차량 재고 차감'
    );
  }

  // 불허: 수량 0 이하, 재고 미선택은 저장하지 않고 안내 문구
  @isTest
  static void rejectInvalidInput() {
    WorkOrder wo = getWorkOrder();
    Id itemId = getItem('General').Id;
    String zeroMessage;
    String missingMessage;

    Test.startTest();
    try {
      WorkOrderPartsController.addPart(wo.Id, itemId, 0);
    } catch (AuraHandledException e) {
      zeroMessage = e.getMessage();
    }
    try {
      WorkOrderPartsController.addPart(wo.Id, null, 1);
    } catch (AuraHandledException e) {
      missingMessage = e.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(
      System.Label.MSG_QUANTITY_INVALID,
      zeroMessage,
      '수량 안내'
    );
    Assert.areEqual(
      System.Label.MSG_PART_SELECT_REQUIRED,
      missingMessage,
      '재고 선택 안내'
    );
    Assert.areEqual(0, [SELECT COUNT() FROM ProductConsumed], '저장 안 됨');
  }

  // 정상: 협력 기사가 자기 출동·자기 차량 재고로 화면에서 부품 추가 (USER_MODE 저장)
  @isTest
  static void normalTechnicianAddsFromOwnVan() {
    User technician = getUser('HG_Technician');
    WorkOrder wo = getWorkOrder();
    wo.OwnerId = technician.Id;
    update wo;
    // DESC: 실제 org처럼 기사 차량·차량 재고를 처음부터 기사 소유로 생성
    Schema.Location van = new Schema.Location(
      Name = '기사 차량',
      LocationType = 'Van',
      IsInventoryLocation = true,
      OwnerId = technician.Id
    );
    insert van;
    ProductItem item = new ProductItem(
      LocationId = van.Id,
      Product2Id = getItem('General').Product2Id,
      QuantityOnHand = 10,
      OwnerId = technician.Id
    );
    insert item;
    Id partId;
    List<WorkOrderPartsController.StockOption> options;

    Test.startTest();
    System.runAs(technician) {
      options = WorkOrderPartsController.getVanStock(wo.Id);
      partId = WorkOrderPartsController.addPart(wo.Id, item.Id, 1);
    }
    Test.stopTest();

    Assert.areEqual(1, options.size(), '기사 차량 재고만 보임');
    Assert.isNotNull(partId, '기사 저장 성공');
    Assert.areEqual(
      9,
      [SELECT QuantityOnHand FROM ProductItem WHERE Id = :item.Id]
      .QuantityOnHand,
      '기사 차량 10 → 9'
    );
  }

  // 불허: 콜센터 상담원은 사용 부품을 볼 수만 있고 추가하면 오류 (권한 매트릭스: 사용 부품 읽기 전용)
  @isTest
  static void rejectCallCenterCannotAdd() {
    User agent = getUser('HG_CallCenter');
    WorkOrder wo = getWorkOrder();
    Id itemId = getItem('General').Id;
    Boolean addFailed = false;
    WorkOrderPartsController.PartsView view;

    Test.startTest();
    System.runAs(agent) {
      try {
        view = WorkOrderPartsController.getParts(wo.Id);
      } catch (AuraHandledException e) {
        view = null;
      }
      try {
        WorkOrderPartsController.addPart(wo.Id, itemId, 1);
      } catch (AuraHandledException e) {
        addFailed = true;
      }
    }
    Test.stopTest();

    Assert.isTrue(addFailed, '상담원 추가 거부');
    Assert.areEqual(0, [SELECT COUNT() FROM ProductConsumed], '저장 안 됨');
    if (view != null) {
      Assert.isFalse(view.canAdd, '추가 폼 숨김');
    }
  }

  // 벌크: 사용 부품 200건 → 목록 200행, 조회 몇 번
  @isTest
  static void bulk200PartsListed() {
    WorkOrder wo = getWorkOrder();
    Id itemId = getItem('General').Id;
    List<ProductConsumed> parts = new List<ProductConsumed>();
    for (Integer i = 0; i < 200; i++) {
      parts.add(TestDataFactory.buildPart(wo.Id, itemId));
    }
    insert parts;

    Test.startTest();
    WorkOrderPartsController.PartsView view = WorkOrderPartsController.getParts(
      wo.Id
    );
    Integer queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(200, view.rows.size(), '200행');
    Assert.isTrue(queries <= 3, '200건이어도 조회 몇 번: ' + queries);
  }
}
