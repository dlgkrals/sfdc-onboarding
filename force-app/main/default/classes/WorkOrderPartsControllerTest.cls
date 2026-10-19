/**
 * @description WorkOrderPartsController 테스트 — 사용 부품 목록·합계, 차량 재고 선택지, 부품 추가(판정·재고 차감), 권한, 200건
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 LWC: 출동 사용 부품 화면)
 * 1.1    2026-10-14    Edwin     빈 재고 비활성·저장 거부, 기사 runAs 자기 차량만·빈 재고 거부 (D8 화면 개선)
 * 1.2    2026-10-14    Edwin     남은 수량 초과 거부(불허)·정확히 남은 수량 허용(경계)
 * 1.3    2026-10-15    Edwin     커버리지 보강: 출동 없이·다른 Id로 호출 시 빈 결과
 * 1.4    2026-10-19    Edwin     판정 변경(사유 필수)·삭제(ERP 미반영 건만)·잠김(승인 대기·완료) — 기사 runAs
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

  // 정상: 차량 재고 선택지 = 출동 소유자의 차량 재고 (창고 제외), 남은 수량 0도 보이되 고를 수 없음(available=false)
  @isTest
  static void normalVanStockIncludesEmptyAsUnavailable() {
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

    Assert.areEqual(2, options.size(), '차량 재고 2건 (창고 재고 제외)');
    for (WorkOrderPartsController.StockOption option : options) {
      Assert.areEqual(
        TestDataFactory.VAN_NAME,
        option.locationName,
        '위치 = 차량'
      );
      if (option.productItemId == compressor.Id) {
        Assert.isFalse(option.available, '남은 수량 0 → 고를 수 없음');
      } else {
        Assert.isTrue(option.available, '일반 부품은 고를 수 있음');
        Assert.areEqual(
          System.Label.MISC_UNIT_KG,
          option.unitLabel,
          '단위 표기'
        );
      }
    }
  }

  // 불허: 남은 수량 0인 재고로는 저장하지 않음 (화면 비활성을 우회해도 서버에서 거부)
  @isTest
  static void rejectEmptyStockNotSaved() {
    ProductItem compressor = getItem('Compressor');
    update new ProductItem(Id = compressor.Id, QuantityOnHand = 0);
    String message;

    Test.startTest();
    try {
      WorkOrderPartsController.addPart(getWorkOrder().Id, compressor.Id, 1);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(System.Label.MSG_STOCK_EMPTY, message, '안내 문구');
    Assert.areEqual(0, [SELECT COUNT() FROM ProductConsumed], '저장 안 됨');
  }

  // 불허: 남은 수량보다 많이 쓰면 거부 — "차량 재고가 부족합니다(남은 n단위)…"
  @isTest
  static void rejectOverRemainingQuantity() {
    String message;

    Test.startTest();
    try {
      WorkOrderPartsController.addPart(
        getWorkOrder().Id,
        getItem('General').Id,
        VAN_QUANTITY + 0.5
      );
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(
      String.format(
        System.Label.MSG_STOCK_SHORT,
        new List<String>{
          String.valueOf(VAN_QUANTITY.intValue()),
          System.Label.MISC_UNIT_KG
        }
      ),
      message,
      '안내 문구 (남은 300kg)'
    );
    Assert.areEqual(0, [SELECT COUNT() FROM ProductConsumed], '저장 안 됨');
    Assert.areEqual(
      VAN_QUANTITY,
      getItem('General').QuantityOnHand,
      '재고 그대로'
    );
  }

  // 정상(경계): 정확히 남은 수량만큼은 허용 → 차량 재고 0
  @isTest
  static void normalExactRemainingQuantityAllowed() {
    Test.startTest();
    Id partId = WorkOrderPartsController.addPart(
      getWorkOrder().Id,
      getItem('General').Id,
      VAN_QUANTITY
    );
    Test.stopTest();

    Assert.isNotNull(partId, '저장됨');
    Assert.areEqual(0, getItem('General').QuantityOnHand, '남은 수량 0');
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

  // 불허: 출동 없이(또는 출동이 아닌 Id로) 부르면 빈 결과 — 화면이 레코드 페이지 밖에서 열린 경우
  @isTest
  static void rejectMissingWorkOrderReturnsEmpty() {
    Id notWorkOrderId = [SELECT Id FROM Case LIMIT 1].Id;

    Test.startTest();
    WorkOrderPartsController.PartsView emptyView = WorkOrderPartsController.getParts(
      null
    );
    List<WorkOrderPartsController.StockOption> noIdStock = WorkOrderPartsController.getVanStock(
      null
    );
    List<WorkOrderPartsController.StockOption> otherIdStock = WorkOrderPartsController.getVanStock(
      notWorkOrderId
    );
    Test.stopTest();

    Assert.isTrue(emptyView.rows.isEmpty());
    Assert.isTrue(noIdStock.isEmpty());
    Assert.isTrue(otherIdStock.isEmpty(), '출동을 못 찾으면 빈 목록');
  }

  // 정상: 협력 기사(최민호와 같은 권한 집합 HG_Technician) runAs — 자기 출동에서 자기 차량 재고만 보이고(다른 사람 차량 제외),
  //       빈 재고는 비활성, 남은 재고로 저장 성공·차감, 빈 재고로 저장은 거부 (USER_MODE 조회·저장)
  @isTest
  static void normalTechnicianAddsFromOwnVan() {
    User technician = getUser('HG_Technician');
    WorkOrder wo = getWorkOrder();
    wo.OwnerId = technician.Id;
    update wo;
    // DESC: 실제 org처럼 기사 차량·차량 재고를 처음부터 기사 소유로 생성. setup의 차량(관리자 소유)은 다른 사람 차량 역할
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
    ProductItem empty = new ProductItem(
      LocationId = van.Id,
      Product2Id = getItem('Compressor').Product2Id,
      QuantityOnHand = 0,
      OwnerId = technician.Id
    );
    insert new List<ProductItem>{ item, empty };
    Id partId;
    String emptyMessage;
    List<WorkOrderPartsController.StockOption> options;

    Test.startTest();
    System.runAs(technician) {
      options = WorkOrderPartsController.getVanStock(wo.Id);
      partId = WorkOrderPartsController.addPart(wo.Id, item.Id, 1);
      try {
        WorkOrderPartsController.addPart(wo.Id, empty.Id, 1);
      } catch (AuraHandledException e) {
        emptyMessage = e.getMessage();
      }
    }
    Test.stopTest();

    Assert.areEqual(
      2,
      options.size(),
      '기사 차량 재고 2건만 (다른 사람 차량 제외)'
    );
    for (WorkOrderPartsController.StockOption option : options) {
      Assert.areEqual('기사 차량', option.locationName, '자기 차량');
      Assert.areEqual(
        option.productItemId == item.Id,
        option.available,
        '빈 재고만 비활성'
      );
    }
    Assert.isNotNull(partId, '기사 저장 성공');
    Assert.areEqual(
      System.Label.MSG_STOCK_EMPTY,
      emptyMessage,
      '빈 재고 저장 거부'
    );
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

  // DESC: 기사 소유 출동 + 기사 차량 재고 + 사용 부품 1건 (실제 org처럼 차량·재고는 기사 소유)
  private static ProductConsumed createTechnicianPart(User technician) {
    WorkOrder wo = getWorkOrder();
    wo.OwnerId = technician.Id;
    update wo;
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
    ProductConsumed pc = new ProductConsumed(
      WorkOrderId = wo.Id,
      ProductItemId = item.Id,
      QuantityConsumed = 1
    );
    insert pc;
    return [
      SELECT Id, WorkOrderId, ProductItemId, AutoChargeType__c, ChargeType__c
      FROM ProductConsumed
      WHERE Id = :pc.Id
    ];
  }

  private static String otherChargeOf(String chargeType) {
    return chargeType == 'Paid' ? 'Free' : 'Paid';
  }

  // 정상: 기사가 최종 판정을 자동 판정과 다르게 + 변경 사유 → 저장, 목록에 사유·자동 판정이 보이고 수정 가능
  @isTest
  static void normalTechnicianChangesChargeWithReason() {
    User technician = getUser('HG_Technician');
    ProductConsumed pc = createTechnicianPart(technician);
    String target = otherChargeOf(pc.AutoChargeType__c);
    WorkOrderPartsController.PartsView before;
    WorkOrderPartsController.PartsView after;

    Test.startTest();
    System.runAs(technician) {
      before = WorkOrderPartsController.getParts(pc.WorkOrderId);
      WorkOrderPartsController.updateChargeType(
        pc.Id,
        target,
        '장기 거래처 예외'
      );
      after = WorkOrderPartsController.getParts(pc.WorkOrderId);
    }
    Test.stopTest();

    Assert.isTrue(before.canEdit, '기사 판정 변경 가능');
    Assert.isFalse(before.locked, '진행 중 출동은 잠기지 않음');
    Assert.areEqual(2, before.chargeOptions.size(), '유상·무상 선택지');
    ProductConsumed saved = [
      SELECT ChargeType__c, OverrideReason__c
      FROM ProductConsumed
      WHERE Id = :pc.Id
    ];
    Assert.areEqual(target, saved.ChargeType__c);
    Assert.areEqual('장기 거래처 예외', saved.OverrideReason__c);
    Assert.areEqual(target, after.rows[0].chargeType);
    Assert.areEqual('장기 거래처 예외', after.rows[0].overrideReason);
    Assert.areEqual(pc.AutoChargeType__c, after.rows[0].autoChargeType);
  }

  // 불허: 자동 판정과 다르게 바꾸면서 사유가 없으면 검증 규칙(OverrideReason_Required) 문구로 거부, 값은 그대로
  @isTest
  static void rejectChangeWithoutReason() {
    User technician = getUser('HG_Technician');
    ProductConsumed pc = createTechnicianPart(technician);
    String message;

    Test.startTest();
    System.runAs(technician) {
      try {
        WorkOrderPartsController.updateChargeType(
          pc.Id,
          otherChargeOf(pc.AutoChargeType__c),
          '  '
        );
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
    }
    Test.stopTest();

    Assert.isNotNull(message, '사유 없이 변경 거부');
    Assert.areEqual(
      pc.ChargeType__c,
      [SELECT ChargeType__c FROM ProductConsumed WHERE Id = :pc.Id]
      .ChargeType__c,
      '판정 그대로'
    );
  }

  // 불허: 승인 대기·완료 출동은 잠김 — 목록은 잠김 안내, 추가·판정 변경·삭제 모두 거부
  @isTest
  static void rejectLockedWhenPendingApprovalOrCompleted() {
    User technician = getUser('HG_Technician');
    ProductConsumed pc = createTechnicianPart(technician);
    update new ProductConsumed(Id = pc.Id, ErpSyncStatus__c = 'Failed');
    update new WorkOrder(Id = pc.WorkOrderId, Status = 'PendingApproval');
    WorkOrderPartsController.PartsView pendingView;
    WorkOrderPartsController.PartsView completedView;
    String changeMessage;
    String deleteMessage;
    String addMessage;
    String completedMessage;

    Test.startTest();
    System.runAs(technician) {
      pendingView = WorkOrderPartsController.getParts(pc.WorkOrderId);
      try {
        WorkOrderPartsController.updateChargeType(pc.Id, 'Free', '사유');
      } catch (AuraHandledException e) {
        changeMessage = e.getMessage();
      }
      try {
        WorkOrderPartsController.deletePart(pc.Id);
      } catch (AuraHandledException e) {
        deleteMessage = e.getMessage();
      }
      try {
        WorkOrderPartsController.addPart(pc.WorkOrderId, pc.ProductItemId, 1);
      } catch (AuraHandledException e) {
        addMessage = e.getMessage();
      }
    }
    update new WorkOrder(
      Id = pc.WorkOrderId,
      Status = 'Completed',
      ArrivalDateTime__c = Datetime.now().addHours(-1)
    );
    System.runAs(technician) {
      completedView = WorkOrderPartsController.getParts(pc.WorkOrderId);
      try {
        WorkOrderPartsController.updateChargeType(pc.Id, 'Free', '사유');
      } catch (AuraHandledException e) {
        completedMessage = e.getMessage();
      }
    }
    Test.stopTest();

    Assert.isTrue(pendingView.locked);
    Assert.isFalse(pendingView.canAdd, '부품 추가 숨김');
    Assert.isFalse(pendingView.canEdit, '판정 변경 숨김');
    Assert.isFalse(pendingView.rows[0].canDelete, '삭제 숨김');
    Assert.areEqual(
      System.Label.MSG_PART_LOCKED_APPROVAL,
      pendingView.lockMessage
    );
    Assert.areEqual(System.Label.MSG_PART_LOCKED_APPROVAL, changeMessage);
    Assert.areEqual(System.Label.MSG_PART_LOCKED_APPROVAL, deleteMessage);
    Assert.areEqual(System.Label.MSG_PART_LOCKED_APPROVAL, addMessage);
    Assert.areEqual(
      System.Label.MSG_PART_LOCKED_COMPLETED,
      completedView.lockMessage
    );
    Assert.areEqual(System.Label.MSG_PART_LOCKED_COMPLETED, completedMessage);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM ProductConsumed WHERE Id = :pc.Id],
      '삭제 안 됨'
    );
  }

  // 정상·불허: ERP 실패 건은 기사가 삭제, ERP 완료 건은 삭제 버튼 없음·서버도 거부
  @isTest
  static void normalDeleteFailedPartRejectSynced() {
    User technician = getUser('HG_Technician');
    ProductConsumed failed = createTechnicianPart(technician);
    update new ProductConsumed(Id = failed.Id, ErpSyncStatus__c = 'Failed');
    ProductConsumed synced = new ProductConsumed(
      WorkOrderId = failed.WorkOrderId,
      ProductItemId = failed.ProductItemId,
      QuantityConsumed = 1
    );
    insert synced;
    update new ProductConsumed(Id = synced.Id, ErpSyncStatus__c = 'Synced');
    WorkOrderPartsController.PartsView view;
    String syncedMessage;

    Test.startTest();
    System.runAs(technician) {
      view = WorkOrderPartsController.getParts(failed.WorkOrderId);
      WorkOrderPartsController.deletePart(failed.Id);
      try {
        WorkOrderPartsController.deletePart(synced.Id);
      } catch (AuraHandledException e) {
        syncedMessage = e.getMessage();
      }
    }
    Test.stopTest();

    for (WorkOrderPartsController.PartRow row : view.rows) {
      Assert.areEqual(
        row.id == failed.Id,
        row.canDelete,
        '실패 건만 삭제 가능'
      );
    }
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM ProductConsumed WHERE Id = :failed.Id],
      '실패 건 삭제'
    );
    Assert.areEqual(System.Label.MSG_ERP_DELETE_BLOCKED, syncedMessage);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM ProductConsumed WHERE Id = :synced.Id],
      '완료 건 유지'
    );
  }
}
