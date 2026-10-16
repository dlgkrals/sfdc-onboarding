/**
 * @description CaseWorkOrderStatsService · WorkOrderTriggerHandler 1.2 · 검증 규칙 Case.OpenWorkOrders_BlockClose 테스트
 *              접수별 열린·완료 출동 수, 처리 중 → 완료 자동, 완료 → 처리 중 재오픈, 열린 출동이 있으면 완료·종결 불가(BR-18)
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-16
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-16    Edwin     최초 작성 (접수 자동 완료·종결 대기)
 * ----------------------------------------------------------------------------
 * @see CaseWorkOrderStatsService, WorkOrderTriggerHandler
 */
@isTest
private class CaseWorkOrderStatsServiceTest {
  private static final String SERIAL = 'TEST-CWS-0001';

  @TestSetup
  static void setupData() {
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    insert TestDataFactory.buildAsset(
      account.Id,
      site.Id,
      SERIAL,
      Date.today().addMonths(-6),
      false
    );
  }

  private static Asset theAsset() {
    return [SELECT Id FROM Asset WHERE SerialKey__c = :SERIAL];
  }

  // DESC: 처리 중 접수 n건 + 접수마다 배정 출동 1건
  private static List<Case> createInProgressCasesWithWorkOrder(Integer n) {
    List<Case> cases = TestDataFactory.createCases(
      new List<Asset>{ theAsset() },
      n
    );
    for (Case c : cases) {
      c.Status = 'InProgress';
    }
    update cases;
    TestDataFactory.createWorkOrders(cases);
    return cases;
  }

  private static void complete(List<WorkOrder> workOrders) {
    for (WorkOrder wo : workOrders) {
      wo.Status = 'Completed';
      wo.ArrivalDateTime__c = Datetime.now().addHours(-1);
    }
    update workOrders;
  }

  private static Case reload(Id caseId) {
    return [
      SELECT Status, OpenWorkOrderCount__c, CompletedWorkOrderCount__c
      FROM Case
      WHERE Id = :caseId
    ];
  }

  // 정상: 출동이 생기면 열린 1, 마지막 출동이 완료되면 접수 자동 완료(열린 0·완료 1)
  @isTest
  static void normalAutoCompleteWhenLastWorkOrderCompleted() {
    Case c = createInProgressCasesWithWorkOrder(1)[0];
    Case beforeDone = reload(c.Id);

    Test.startTest();
    complete([SELECT Id FROM WorkOrder WHERE CaseId = :c.Id]);
    Test.stopTest();

    Assert.areEqual(1, beforeDone.OpenWorkOrderCount__c, '열린 출동 1');
    Case saved = reload(c.Id);
    Assert.areEqual('Completed', saved.Status, '자동 완료');
    Assert.areEqual(0, saved.OpenWorkOrderCount__c);
    Assert.areEqual(1, saved.CompletedWorkOrderCount__c);
  }

  // 정상: 완료 접수에 출동이 다시 생기면 처리 중(재방문·재배정)
  @isTest
  static void normalReopenWhenNewWorkOrder() {
    Case c = createInProgressCasesWithWorkOrder(1)[0];
    complete([SELECT Id FROM WorkOrder WHERE CaseId = :c.Id]);

    Test.startTest();
    insert new WorkOrder(
      CaseId = c.Id,
      Subject = '재방문',
      Status = 'Assigned'
    );
    Test.stopTest();

    Case saved = reload(c.Id);
    Assert.areEqual('InProgress', saved.Status, '다시 처리 중');
    Assert.areEqual(1, saved.OpenWorkOrderCount__c);
    Assert.areEqual(1, saved.CompletedWorkOrderCount__c);
  }

  // 불허: 접수 상태(접수 = New)는 자동으로 바꾸지 않음 — 처리 중일 때만
  @isTest
  static void rejectNewCaseNotAutoCompleted() {
    Case c = TestDataFactory.createCases(new List<Asset>{ theAsset() }, 1)[0];
    TestDataFactory.createWorkOrders(new List<Case>{ c });

    Test.startTest();
    complete([SELECT Id FROM WorkOrder WHERE CaseId = :c.Id]);
    Test.stopTest();

    Case saved = reload(c.Id);
    Assert.areEqual('New', saved.Status, '접수 상태 그대로');
    Assert.areEqual(1, saved.CompletedWorkOrderCount__c, '집계는 갱신');
  }

  // 불허(BR-18): 열린 출동이 있으면 사용자(상담원)가 완료·종결로 바꿀 수 없음
  // DESC: 테스트 실행 관리자는 검증 우회 권한(HG_BypassValidation)이 있어 상담원으로 실행, 접수 소유자 = 상담원
  @isTest
  static void rejectCloseWithOpenWorkOrder() {
    User agent;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      agent = TestDataFactory.createUser('HG_CallCenter', false);
    }
    Case c = createInProgressCasesWithWorkOrder(1)[0];
    update new Case(Id = c.Id, OwnerId = agent.Id);
    String message;

    Test.startTest();
    System.runAs(agent) {
      try {
        update new Case(Id = c.Id, Status = 'Completed');
      } catch (DmlException e) {
        message = e.getDmlMessage(0);
      }
    }
    Test.stopTest();

    Assert.isNotNull(message, '거부');
    Assert.isTrue(message.contains('열린 출동'), message);
    Assert.areEqual('InProgress', reload(c.Id).Status);
  }

  // 벌크: 접수 200건의 출동을 한 번에 완료 → 200건 모두 자동 완료, 조회 몇 번
  @isTest
  static void bulk200AutoComplete() {
    List<Case> cases = createInProgressCasesWithWorkOrder(200);
    List<WorkOrder> workOrders = [
      SELECT Id
      FROM WorkOrder
      WHERE CaseId IN :cases
    ];

    Test.startTest();
    complete(workOrders);
    Integer queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(
      200,
      [SELECT COUNT() FROM Case WHERE Id IN :cases AND Status = 'Completed']
    );
    Assert.isTrue(queries < 40, '200건이어도 조회 몇 번: ' + queries);
  }
}
