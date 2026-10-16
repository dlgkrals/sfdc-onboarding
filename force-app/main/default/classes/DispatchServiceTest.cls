/**
 * @description DispatchService 테스트 — 접수 [기사 배정]
 *              센터장은 우리 센터(역할 아래) 기사만 고를 수 있고, 출동은 접수 값을 복사해 기사 소유로 생성, 접수는 처리 중
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-16
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-16    Edwin     최초 작성 (출동 단일 생성 경로)
 * 1.1    2026-10-16    Edwin     출장비 기준값 검증
 * ----------------------------------------------------------------------------
 * @see DispatchService
 */
@isTest
private class DispatchServiceTest {
  private static final String SERIAL = 'TEST-DSP-0001';
  private static final String ROLE_MANAGER = 'HG_GyeonggiSouthCenterManager';
  private static final String ROLE_TECHNICIAN = 'HG_GyeonggiSouthTechnician';
  private static final String ROLE_OTHER_TECHNICIAN = 'HG_SeoulTechnician';
  private static final String NAME_TECHNICIAN = '테스트 우리센터 기사';
  private static final String NAME_OTHER_TECHNICIAN = '테스트 다른센터 기사';
  private static final String QUEUE_CENTER = 'HG_GyeonggiSouthCases';

  @TestSetup
  static void setupData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Map<String, Id> roleIdsByName = new Map<String, Id>();
      for (UserRole role : [
        SELECT Id, DeveloperName
        FROM UserRole
        WHERE DeveloperName LIKE 'HG_%'
      ]) {
        roleIdsByName.put(role.DeveloperName, role.Id);
      }
      User manager = TestDataFactory.createUser('HG_CenterManager', true);
      User technician = TestDataFactory.createUser('HG_Technician', true);
      User otherTechnician = TestDataFactory.createUser('HG_Technician', true);
      User callCenter = TestDataFactory.createUser('HG_CallCenter', false);
      manager.UserRoleId = roleIdsByName.get(ROLE_MANAGER);
      technician.UserRoleId = roleIdsByName.get(ROLE_TECHNICIAN);
      technician.LastName = NAME_TECHNICIAN;
      technician.ManagerId = manager.Id;
      otherTechnician.UserRoleId = roleIdsByName.get(ROLE_OTHER_TECHNICIAN);
      otherTechnician.LastName = NAME_OTHER_TECHNICIAN;
      update new List<User>{ manager, technician, otherTechnician, callCenter };
    }
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    List<Asset> assets = new List<Asset>{
      TestDataFactory.buildAsset(
        account.Id,
        site.Id,
        SERIAL,
        Date.today().addMonths(-6),
        false
      )
    };
    insert assets;
    assignToCenterQueue(TestDataFactory.createCases(assets, 1));
  }

  // DESC: 운영과 같이 접수 소유자 = 센터 Queue(구성원 = 센터장 역할) → 센터장이 접수를 봄
  private static void assignToCenterQueue(List<Case> cases) {
    Id queueId = [
      SELECT Id
      FROM Group
      WHERE Type = 'Queue' AND DeveloperName = :QUEUE_CENTER
    ]
    .Id;
    for (Case c : cases) {
      c.OwnerId = queueId;
    }
    update cases;
  }

  private static User userWith(String permissionSetName) {
    return [
      SELECT Id
      FROM User
      WHERE
        LastName LIKE '테스트%'
        AND Id IN (
          SELECT AssigneeId
          FROM PermissionSetAssignment
          WHERE PermissionSet.Name = :permissionSetName
        )
      LIMIT 1
    ];
  }

  private static User technicianNamed(String lastName) {
    return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
  }

  private static Case theCase() {
    return [
      SELECT
        Id,
        Status,
        AssetId,
        AccountId,
        CustomerSite__c,
        ServiceCenter__c,
        Subject
      FROM Case
      WHERE Asset.SerialKey__c = :SERIAL
      LIMIT 1
    ];
  }

  private static DispatchService.DispatchRequest request(
    String action,
    Id caseId,
    Id technicianId
  ) {
    DispatchService.DispatchRequest req = new DispatchService.DispatchRequest();
    req.action = action;
    req.caseId = caseId;
    req.technicianId = technicianId;
    req.purpose = 'Repair';
    req.plannedStart = Datetime.now().addDays(1);
    req.instruction = '압축기 점검';
    return req;
  }

  private static DispatchService.DispatchResult runOne(
    DispatchService.DispatchRequest req
  ) {
    return DispatchService.run(
      new List<DispatchService.DispatchRequest>{ req }
    )[0];
  }

  private static Set<Id> idsOf(List<User> users) {
    return new Map<Id, User>(users).keySet();
  }

  @isTest
  static void normalLoadShowsSummaryAndOwnCenterTechnicians() {
    Case c = theCase();
    Id ownTechId = technicianNamed(NAME_TECHNICIAN).Id;
    Id otherTechId = technicianNamed(NAME_OTHER_TECHNICIAN).Id;
    DispatchService.DispatchResult result;
    Test.startTest();
    System.runAs(userWith('HG_CenterManager')) {
      result = runOne(request(DispatchService.ACTION_LOAD, c.Id, null));
    }
    Test.stopTest();

    Assert.isTrue(result.success, '' + result.message);
    Assert.isNotNull(result.caseNumber);
    Assert.isNotNull(result.assetName, '장비 이름 표시');
    Assert.isNotNull(result.siteName, '사업장 이름 표시');
    Assert.areEqual(0, result.workOrderCount);
    Set<Id> technicianIds = idsOf(result.technicians);
    Assert.isTrue(technicianIds.contains(ownTechId), '우리 센터 기사는 보임');
    Assert.isFalse(
      technicianIds.contains(otherTechId),
      '다른 센터 기사는 안 보임'
    );
  }

  @isTest
  static void normalDispatchCreatesWorkOrderAndMovesCase() {
    Case c = theCase();
    Id techId = technicianNamed(NAME_TECHNICIAN).Id;
    DispatchService.DispatchResult result;
    Test.startTest();
    System.runAs(userWith('HG_CenterManager')) {
      result = runOne(request(DispatchService.ACTION_DISPATCH, c.Id, techId));
    }
    Test.stopTest();

    Assert.isTrue(result.success, '' + result.message);
    WorkOrder wo = [
      SELECT
        Id,
        WorkOrderNumber,
        CaseId,
        AssetId,
        AccountId,
        CustomerSite__c,
        ServiceCenter__c,
        Subject,
        OwnerId,
        Status,
        Purpose__c,
        StartDate,
        WorkInstruction__c,
        VisitNumber__c,
        VisitFee__c
      FROM WorkOrder
      WHERE Id = :result.workOrderId
    ];
    Assert.areEqual(wo.WorkOrderNumber, result.workOrderNumber);
    Assert.areEqual(c.AssetId, wo.AssetId);
    Assert.areEqual(c.AccountId, wo.AccountId);
    Assert.areEqual(c.CustomerSite__c, wo.CustomerSite__c);
    Assert.areEqual(c.ServiceCenter__c, wo.ServiceCenter__c);
    Assert.isNotNull(wo.ServiceCenter__c, '센터장 공유 기준 서비스센터');
    Assert.areEqual(c.Subject, wo.Subject);
    Assert.areEqual(techId, wo.OwnerId, '소유자 = 기사');
    Assert.areEqual('Assigned', wo.Status);
    Assert.areEqual('Repair', wo.Purpose__c);
    Assert.isNotNull(wo.StartDate);
    Assert.areEqual('압축기 점검', wo.WorkInstruction__c);
    Assert.areEqual(1, wo.VisitNumber__c);
    Assert.areEqual(
      ServiceSetting__mdt.getInstance('VisitFee').Value__c,
      wo.VisitFee__c,
      '출장비 = ServiceSetting VisitFee(실습 중 발견한 빈 출장비 결함)'
    );
    Assert.areEqual('InProgress', theCase().Status, '접수는 처리 중');
  }

  @isTest
  static void normalRedispatchSameCaseCreatesNextVisit() {
    Case c = theCase();
    Id techId = technicianNamed(NAME_TECHNICIAN).Id;
    DispatchService.DispatchResult second;
    DispatchService.DispatchResult reload;
    Test.startTest();
    System.runAs(userWith('HG_CenterManager')) {
      runOne(request(DispatchService.ACTION_DISPATCH, c.Id, techId));
      second = runOne(request(DispatchService.ACTION_DISPATCH, c.Id, techId));
      reload = runOne(request(DispatchService.ACTION_LOAD, c.Id, null));
    }
    Test.stopTest();

    Assert.isTrue(second.success, '' + second.message);
    Assert.areEqual(
      2,
      [SELECT VisitNumber__c FROM WorkOrder WHERE Id = :second.workOrderId]
      .VisitNumber__c
    );
    Assert.areEqual(2, reload.workOrderCount, '화면에 기존 출동 수 안내');
    Assert.areEqual('InProgress', theCase().Status);
  }

  @isTest
  static void rejectClosedOrCanceledCaseGuidanceOnly() {
    Case c = theCase();
    c.Status = 'Canceled';
    c.CancelReason__c = '고객 요청';
    update c;
    Id techId = technicianNamed(NAME_TECHNICIAN).Id;
    DispatchService.DispatchResult load;
    DispatchService.DispatchResult dispatch;
    Test.startTest();
    System.runAs(userWith('HG_CenterManager')) {
      load = runOne(request(DispatchService.ACTION_LOAD, c.Id, null));
      dispatch = runOne(request(DispatchService.ACTION_DISPATCH, c.Id, techId));
    }
    Test.stopTest();

    Assert.isFalse(load.success);
    Assert.areEqual(System.Label.MSG_DISPATCH_CLOSED, load.message);
    Assert.isTrue(load.technicians.isEmpty(), '안내만, 기사 목록 없음');
    Assert.isFalse(dispatch.success);
    Assert.areEqual(System.Label.MSG_DISPATCH_CLOSED, dispatch.message);
    Assert.areEqual(0, [SELECT COUNT() FROM WorkOrder WHERE CaseId = :c.Id]);
  }

  @isTest
  static void rejectOtherCenterTechnician() {
    Case c = theCase();
    Id otherTechId = technicianNamed(NAME_OTHER_TECHNICIAN).Id;
    DispatchService.DispatchResult result;
    Test.startTest();
    System.runAs(userWith('HG_CenterManager')) {
      result = runOne(
        request(DispatchService.ACTION_DISPATCH, c.Id, otherTechId)
      );
    }
    Test.stopTest();

    Assert.isFalse(result.success);
    Assert.areEqual(System.Label.MSG_DISPATCH_TECH_NOT_ALLOWED, result.message);
    Assert.areEqual(0, [SELECT COUNT() FROM WorkOrder WHERE CaseId = :c.Id]);
    Assert.areEqual('New', theCase().Status, '접수 상태 그대로');
  }

  @isTest
  static void rejectTechnicianRequired() {
    Case c = theCase();
    DispatchService.DispatchResult result;
    Test.startTest();
    System.runAs(userWith('HG_CenterManager')) {
      result = runOne(request(DispatchService.ACTION_DISPATCH, c.Id, null));
    }
    Test.stopTest();

    Assert.isFalse(result.success);
    Assert.areEqual(System.Label.MSG_DISPATCH_TECH_REQUIRED, result.message);
  }

  @isTest
  static void rejectTechnicianAndCallCenterCannotDispatch() {
    Case c = theCase();
    Id techId = technicianNamed(NAME_TECHNICIAN).Id;
    DispatchService.DispatchResult byTechnician;
    DispatchService.DispatchResult byCallCenter;
    Test.startTest();
    System.runAs(technicianNamed(NAME_TECHNICIAN)) {
      byTechnician = runOne(
        request(DispatchService.ACTION_DISPATCH, c.Id, techId)
      );
    }
    System.runAs(userWith('HG_CallCenter')) {
      byCallCenter = runOne(
        request(DispatchService.ACTION_DISPATCH, c.Id, techId)
      );
    }
    Test.stopTest();

    Assert.areEqual(
      System.Label.MSG_DISPATCH_NO_PERMISSION,
      byTechnician.message
    );
    Assert.areEqual(
      System.Label.MSG_DISPATCH_NO_PERMISSION,
      byCallCenter.message
    );
    Assert.areEqual(0, [SELECT COUNT() FROM WorkOrder WHERE CaseId = :c.Id]);
  }

  @isTest
  static void rejectCenterManagerCannotCreateWorkOrderDirectly() {
    Case c = theCase();
    Id techId = technicianNamed(NAME_TECHNICIAN).Id;
    Boolean blocked = false;
    Test.startTest();
    System.runAs(userWith('HG_CenterManager')) {
      try {
        Database.insert(
          new WorkOrder(CaseId = c.Id, OwnerId = techId, Status = 'Assigned'),
          AccessLevel.USER_MODE
        );
      } catch (Exception e) {
        blocked = true;
      }
    }
    Test.stopTest();

    Assert.isTrue(blocked, '센터장은 출동 생성 권한 없음 — [기사 배정]으로만');
  }

  @isTest
  static void bulk200DispatchRequests() {
    Asset asset = [SELECT Id FROM Asset WHERE SerialKey__c = :SERIAL];
    List<Case> cases = TestDataFactory.createCases(
      new List<Asset>{ asset },
      199
    );
    assignToCenterQueue(cases);
    cases.add(theCase());
    Id techId = technicianNamed(NAME_TECHNICIAN).Id;
    List<DispatchService.DispatchRequest> requests = new List<DispatchService.DispatchRequest>();
    for (Case c : cases) {
      requests.add(request(DispatchService.ACTION_DISPATCH, c.Id, techId));
    }
    List<DispatchService.DispatchResult> results;
    Test.startTest();
    System.runAs(userWith('HG_CenterManager')) {
      results = DispatchService.run(requests);
    }
    Test.stopTest();

    Assert.areEqual(200, results.size());
    for (DispatchService.DispatchResult result : results) {
      Assert.isTrue(result.success, '' + result.message);
    }
    Assert.areEqual(
      200,
      [SELECT COUNT() FROM WorkOrder WHERE OwnerId = :techId]
    );
    Assert.areEqual(
      200,
      [SELECT COUNT() FROM Case WHERE Status = 'InProgress']
    );
  }
}
