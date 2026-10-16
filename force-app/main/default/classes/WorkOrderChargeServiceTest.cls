/**
 * @description WorkOrderChargeService · WorkOrderTriggerHandler · Flow WorkOrder_BeforeSave_FillAsset 테스트
 *              장비·고객사·사업장 누적 청구액 = 방문한 출동(도착·승인 대기·완료)의 총 청구액 합계
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-16
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-16    Edwin     최초 작성 (장비 화면 누적 청구액)
 * 1.1    2026-10-16    Edwin     고객사·사업장 누적 청구액(합계·사업장 변경·벌크·상담원 읽기)
 * 1.2    2026-10-16    Edwin     방문 출동 수(VisitedWorkOrderCount__c) 검증
 * ----------------------------------------------------------------------------
 * @see WorkOrderChargeService, WorkOrderTriggerHandler
 */
@isTest
private class WorkOrderChargeServiceTest {
  private static final String SERIAL_PAID = 'TEST-WOC-PAID';
  private static final String SERIAL_OTHER = 'TEST-WOC-OTHER';
  private static final Decimal FEE = 30000;

  @TestSetup
  static void setupData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.createUser('HG_CallCenter', false);
      TestDataFactory.createUser('HG_Technician', true);
    }
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    // DESC: 보증 미확정 장비는 부품이 유상으로 판정 → 유상 부품비 Roll-Up이 생김
    List<Asset> assets = new List<Asset>{
      TestDataFactory.buildUnverifiedAsset(account.Id, site.Id, SERIAL_PAID),
      TestDataFactory.buildAsset(
        account.Id,
        site.Id,
        SERIAL_OTHER,
        Date.today().addMonths(-6),
        false
      )
    };
    insert assets;
    TestDataFactory.createWorkOrders(TestDataFactory.createCases(assets, 1));
    TestDataFactory.createVanStock(TestDataFactory.createProducts(), 1000);
  }

  private static Id assetId(String serial) {
    return [SELECT Id FROM Asset WHERE SerialKey__c = :serial].Id;
  }

  private static WorkOrder workOrderOf(String serial) {
    return [
      SELECT Id, AssetId, CaseId, Status
      FROM WorkOrder
      WHERE Asset.SerialKey__c = :serial
      LIMIT 1
    ];
  }

  private static Decimal totalOf(String serial) {
    Decimal total = [
      SELECT TotalWorkOrderCharge__c
      FROM Asset
      WHERE SerialKey__c = :serial
    ]
    .TotalWorkOrderCharge__c;
    return total == null ? 0 : total;
  }

  private static Decimal countOf(String serial) {
    Decimal n = [
      SELECT VisitedWorkOrderCount__c
      FROM Asset
      WHERE SerialKey__c = :serial
    ]
    .VisitedWorkOrderCount__c;
    return n == null ? 0 : n;
  }

  private static User getUser(String permissionSetName) {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :('테스트 ' + permissionSetName)
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  // DESC: 상태 전환에 필요한 값(완료 = 도착 일시, 거절 = 거절 사유)을 함께 채움
  private static void moveTo(WorkOrder wo, String status) {
    wo.Status = status;
    wo.VisitFee__c = FEE;
    if (status == 'Completed') {
      wo.ArrivalDateTime__c = Datetime.now().addHours(-1);
    }
    if (status == 'Declined') {
      wo.DeclineReason__c = '일정 불가';
    }
    update wo;
  }

  // 정상: 배정 상태는 합계에서 빠지고, 도착으로 바뀌면(상태 전환) 방문비가 합계에 들어감
  @isTest
  static void normalArrivedCountedAssignedNot() {
    WorkOrder wo = workOrderOf(SERIAL_OTHER);

    Test.startTest();
    moveTo(wo, 'Assigned');
    Decimal whileAssigned = totalOf(SERIAL_OTHER);
    moveTo(wo, 'Arrived');
    Test.stopTest();

    Assert.areEqual(0, whileAssigned, '배정은 방문 전이라 제외');
    Assert.areEqual(FEE, totalOf(SERIAL_OTHER), '도착 = 방문비 합계');
    Assert.areEqual(1, countOf(SERIAL_OTHER), '합산된 출동 1건');
  }

  // 정상: 승인 대기·완료는 포함, 수락·거절은 제외
  @isTest
  static void normalVisitedStatusesOnly() {
    WorkOrder wo = workOrderOf(SERIAL_OTHER);
    Map<String, Decimal> totalsByStatus = new Map<String, Decimal>();

    Test.startTest();
    for (
      String status : new List<String>{
        'Accepted',
        'Arrived',
        'PendingApproval',
        'Completed'
      }
    ) {
      moveTo(wo, status);
      totalsByStatus.put(status, totalOf(SERIAL_OTHER));
    }
    Test.stopTest();

    Assert.areEqual(0, totalsByStatus.get('Accepted'), '수락 제외');
    Assert.areEqual(
      FEE,
      totalsByStatus.get('PendingApproval'),
      '승인 대기 포함'
    );
    Assert.areEqual(FEE, totalsByStatus.get('Completed'), '완료 포함');
  }

  // 불허: 거절된 출동은 방문비가 있어도 합계에 넣지 않음
  @isTest
  static void rejectDeclinedExcluded() {
    WorkOrder wo = workOrderOf(SERIAL_OTHER);

    Test.startTest();
    moveTo(wo, 'Declined');
    Test.stopTest();

    Assert.areEqual(0, totalOf(SERIAL_OTHER));
  }

  // 정상: 사용 부품 추가·삭제 → 유상 부품비 Roll-Up 변경 → 출동 트리거가 불려 장비 합계도 따라감
  @isTest
  static void normalPaidPartRollupFollows() {
    WorkOrder wo = workOrderOf(SERIAL_PAID);
    moveTo(wo, 'Arrived');
    ProductItem general = [
      SELECT Id
      FROM ProductItem
      WHERE Product2.Family = 'General'
      LIMIT 1
    ];

    Test.startTest();
    ProductConsumed part = TestDataFactory.buildPart(wo.Id, general.Id);
    insert part;
    Decimal paid = [SELECT ruPaidPartsTotal__c FROM WorkOrder WHERE Id = :wo.Id]
    .ruPaidPartsTotal__c;
    Decimal afterAdd = totalOf(SERIAL_PAID);
    // DESC: 삭제 규칙 — ERP 전송 실패 건만 삭제 가능
    update new ProductConsumed(Id = part.Id, ErpSyncStatus__c = 'Failed');
    delete part;
    Test.stopTest();

    Assert.isTrue(paid != null && paid > 0, '보증 미확정 장비 부품 = 유상');
    Assert.areEqual(
      FEE + paid,
      afterAdd,
      '부품 추가 후 합계 = 방문비 + 유상 부품비'
    );
    Assert.areEqual(FEE, totalOf(SERIAL_PAID), '부품 삭제 후 방문비만');
  }

  // 정상: 출동의 장비를 바꾸면 이전 장비와 새 장비 둘 다 다시 계산
  @isTest
  static void normalAssetChangeRecalculatesBoth() {
    WorkOrder wo = workOrderOf(SERIAL_OTHER);
    moveTo(wo, 'Arrived');

    Test.startTest();
    update new WorkOrder(Id = wo.Id, AssetId = assetId(SERIAL_PAID));
    Test.stopTest();

    Assert.areEqual(0, totalOf(SERIAL_OTHER), '이전 장비 0');
    Assert.areEqual(FEE, totalOf(SERIAL_PAID), '새 장비에 합계');
  }

  // 정상: 방문한 출동 삭제 → 0, 휴지통 복원 → 다시 합계
  @isTest
  static void normalDeleteAndUndelete() {
    WorkOrder wo = workOrderOf(SERIAL_OTHER);
    moveTo(wo, 'Arrived');

    Test.startTest();
    delete wo;
    Decimal afterDelete = totalOf(SERIAL_OTHER);
    undelete wo;
    Test.stopTest();

    Assert.areEqual(0, afterDelete);
    Assert.areEqual(FEE, totalOf(SERIAL_OTHER));
  }

  // 정상: 장비 없이 접수만으로 출동을 만들면 저장 전 Flow가 접수의 장비를 채움
  @isTest
  static void normalFlowFillsAssetFromCase() {
    Id caseId = workOrderOf(SERIAL_OTHER).CaseId;

    Test.startTest();
    WorkOrder created = new WorkOrder(
      CaseId = caseId,
      Subject = 'Flow 장비 채우기'
    );
    insert created;
    Test.stopTest();

    WorkOrder saved = [
      SELECT AssetId, AccountId, CustomerSite__c, ServiceCenter__c
      FROM WorkOrder
      WHERE Id = :created.Id
    ];
    Case source = [
      SELECT AccountId, CustomerSite__c, ServiceCenter__c
      FROM Case
      WHERE Id = :caseId
    ];
    Assert.areEqual(assetId(SERIAL_OTHER), saved.AssetId, '접수의 장비 복사');
    Assert.areEqual(source.AccountId, saved.AccountId, '고객사 복사');
    Assert.areEqual(
      source.CustomerSite__c,
      saved.CustomerSite__c,
      '사업장 복사'
    );
    Assert.isNotNull(saved.ServiceCenter__c, '서비스센터 복사(공유 규칙 기준)');
    Assert.areEqual(source.ServiceCenter__c, saved.ServiceCenter__c);
  }

  private static Decimal accountTotal() {
    Decimal total = [
      SELECT TotalWorkOrderCharge__c
      FROM Account
      WHERE Name = '테스트 고객사'
      LIMIT 1
    ]
    .TotalWorkOrderCharge__c;
    return total == null ? 0 : total;
  }

  private static Decimal siteTotal(Id siteId) {
    Decimal total = [
      SELECT TotalWorkOrderCharge__c
      FROM CustomerSite__c
      WHERE Id = :siteId
    ]
    .TotalWorkOrderCharge__c;
    return total == null ? 0 : total;
  }

  // 정상: 고객사·사업장 누적 청구액 = 그 아래 장비들의 방문 출동 합계 (장비 2대 · 출동 2건)
  @isTest
  static void normalAccountAndSiteTotalsFollow() {
    WorkOrder paidWo = workOrderOf(SERIAL_PAID);
    WorkOrder otherWo = workOrderOf(SERIAL_OTHER);
    Id siteId = [SELECT CustomerSite__c FROM WorkOrder WHERE Id = :otherWo.Id]
    .CustomerSite__c;

    Test.startTest();
    moveTo(paidWo, 'Arrived');
    moveTo(otherWo, 'Arrived');
    Decimal accountAfterArrive = accountTotal();
    moveTo(otherWo, 'Declined');
    Test.stopTest();

    Assert.areEqual(FEE * 2, accountAfterArrive, '고객사 = 출동 2건 합계');
    Assert.areEqual(
      1,
      [
        SELECT VisitedWorkOrderCount__c
        FROM Account
        WHERE Name = '테스트 고객사'
        LIMIT 1
      ]
      .VisitedWorkOrderCount__c,
      '거절 후 고객사 방문 출동 1건'
    );
    Assert.areEqual(FEE, accountTotal(), '거절된 출동은 고객사 합계에서 빠짐');
    Assert.areEqual(FEE, siteTotal(siteId), '사업장도 같은 기준');
  }

  // 정상: 출동의 사업장을 바꾸면 이전 사업장과 새 사업장 둘 다 다시 계산
  @isTest
  static void normalSiteChangeRecalculatesBoth() {
    WorkOrder wo = workOrderOf(SERIAL_OTHER);
    moveTo(wo, 'Arrived');
    WorkOrder saved = [
      SELECT AccountId, CustomerSite__c
      FROM WorkOrder
      WHERE Id = :wo.Id
    ];
    CustomerSite__c otherSite = TestDataFactory.createSite(saved.AccountId);

    Test.startTest();
    update new WorkOrder(Id = wo.Id, CustomerSite__c = otherSite.Id);
    Test.stopTest();

    Assert.areEqual(0, siteTotal(saved.CustomerSite__c), '이전 사업장 0');
    Assert.areEqual(FEE, siteTotal(otherSite.Id), '새 사업장에 합계');
    Assert.areEqual(FEE, accountTotal(), '고객사는 그대로');
  }

  // 불허: 트리거 스위치를 끄면 다시 계산하지 않음 (데이터 이관 때)
  @isTest
  static void rejectSwitchOffSkipsRecalculation() {
    WorkOrder wo = workOrderOf(SERIAL_OTHER);
    TriggerHandler.activeOverridesByObject.put('WorkOrder', false);

    Test.startTest();
    moveTo(wo, 'Arrived');
    Test.stopTest();

    Assert.areEqual(0, totalOf(SERIAL_OTHER));
  }

  // 불허: 묶는 필드가 조회 필드가 아니면 거부 (고객사·사업장 확장용 메서드의 입력 검사)
  @isTest
  static void rejectNonReferenceGroupField() {
    Boolean rejected = false;
    Test.startTest();
    try {
      WorkOrderChargeService.recalculateTotals(
        new Set<Id>{ assetId(SERIAL_OTHER) },
        WorkOrder.Subject,
        Asset.TotalWorkOrderCharge__c
      );
    } catch (IllegalArgumentException e) {
      rejected = true;
    }
    Test.stopTest();

    Assert.isTrue(rejected);
  }

  // 정상: 상담원은 누적 청구액을 읽을 수 있고, 기사는 장비 권한이 없어 읽지 못함 (USER_MODE)
  @isTest
  static void normalCallCenterReadsTechnicianCannot() {
    WorkOrder wo = workOrderOf(SERIAL_OTHER);
    moveTo(wo, 'Arrived');
    Id targetId = assetId(SERIAL_OTHER);
    Decimal seenByCallCenter;
    Decimal accountSeenByCallCenter;
    Boolean technicianBlocked = false;

    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      seenByCallCenter = [
        SELECT TotalWorkOrderCharge__c
        FROM Asset
        WHERE Id = :targetId
        WITH USER_MODE
      ]
      .TotalWorkOrderCharge__c;
      accountSeenByCallCenter = [
        SELECT TotalWorkOrderCharge__c
        FROM Account
        WHERE Name = '테스트 고객사'
        WITH USER_MODE
        LIMIT 1
      ]
      .TotalWorkOrderCharge__c;
    }
    System.runAs(getUser('HG_Technician')) {
      try {
        List<Asset> rows = [
          SELECT TotalWorkOrderCharge__c
          FROM Asset
          WHERE Id = :targetId
          WITH USER_MODE
        ];
      } catch (QueryException e) {
        technicianBlocked = true;
      }
    }
    Test.stopTest();

    Assert.areEqual(FEE, seenByCallCenter, '상담원 읽기');
    Assert.areEqual(
      FEE,
      accountSeenByCallCenter,
      '상담원 고객사 누적 청구액 읽기'
    );
    Assert.isTrue(technicianBlocked, '기사는 장비 권한 없음');
  }

  // 벌크: 방문한 출동 200건을 한 번에 저장 → 합계 정확, 조회 몇 번
  @isTest
  static void bulk200VisitedWorkOrders() {
    Id caseId = workOrderOf(SERIAL_OTHER).CaseId;
    Id targetId = assetId(SERIAL_OTHER);
    List<WorkOrder> workOrders = new List<WorkOrder>();
    for (Integer i = 0; i < 200; i++) {
      workOrders.add(
        new WorkOrder(
          CaseId = caseId,
          AssetId = targetId,
          Subject = '벌크 ' + i,
          Status = 'Arrived',
          VisitFee__c = 1000
        )
      );
    }

    Test.startTest();
    insert workOrders;
    Integer queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(200 * 1000, totalOf(SERIAL_OTHER));
    Assert.areEqual(200, countOf(SERIAL_OTHER), '방문 출동 200건');
    Assert.areEqual(200 * 1000, accountTotal(), '고객사 합계도 같은 묶음에서');
    Assert.isTrue(queries < 20, '200건이어도 조회 몇 번: ' + queries);
  }
}
