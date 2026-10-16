/**
 * @description 출동 승인 요청 Flow 테스트 — 화면 Flow(WorkOrder_Screen_RequestApproval)가 부르는 하위 Flow
 *              WorkOrder_Sub_SubmitApproval(사유·고객 동의 저장 → 승인 프로세스 제출)을 기사 권한으로 실행
 *              화면 Flow는 Apex에서 실행할 수 없어 저장·제출을 하위 Flow로 나눔 (화면 분기는 실제 화면에서 확인)
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-15    Edwin     최초 작성 (피드백 개선 ⑤ 승인 요청 Screen Flow)
 * 1.1    2026-10-16    Edwin     제출 코멘트·ApprovalSummary__c = 승인 요청 요약(이유·부품·사유·동의·메모)
 * ----------------------------------------------------------------------------
 * @see flows/WorkOrder_Sub_SubmitApproval, flows/WorkOrder_Screen_RequestApproval, WorkOrderApprovalTest
 */
@isTest
private class WorkOrderApprovalFlowTest {
  private static final String SUBMIT_FLOW = 'WorkOrder_Sub_SubmitApproval';
  private static final String STATUS_ARRIVED = 'Arrived';
  private static final String STATUS_PENDING = 'PendingApproval';
  private static final String REASON = '압축기 교체, 고객 요청으로 당일 처리';
  private static final String MEMO = '부품 단가 확인 부탁드립니다';

  @TestSetup
  static void setupData() {
    // DESC: 승인자 = 제출자(출동 소유자 = 기사)의 Manager → 기사에게 센터장을 Manager로
    System.runAs(new User(Id = UserInfo.getUserId())) {
      User manager = TestDataFactory.createUser('HG_CenterManager', false);
      User technician = TestDataFactory.createUser('HG_Technician', true);
      technician.ManagerId = manager.Id;
      update technician;
    }
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    List<Asset> assets = TestDataFactory.createAssets(
      account.Id,
      site.Id,
      'TEST-WOF-',
      1
    );
    WorkOrder wo = TestDataFactory.createWorkOrders(
      TestDataFactory.createCases(assets, 1)
    )[0];
    wo.OwnerId = getUser('HG_Technician').Id;
    wo.Status = STATUS_ARRIVED;
    // DESC: 사용 부품 없이 방문비만으로 청구 합계 = 기준 금액 + 1 (고액 유상 → 승인 필요)
    wo.VisitFee__c =
      ServiceSetting__mdt.getInstance('ApprovalAmount').Value__c + 1;
    update wo;
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

  private static WorkOrder getWorkOrder() {
    return [
      SELECT Id, Status, ApprovalRequestReason__c, CustomerConsent__c
      FROM WorkOrder
      LIMIT 1
    ];
  }

  // DESC: 기사 권한으로 하위 Flow 실행 → 결과 변수 { isSubmitted, errorMessage }
  private static Flow.Interview runSubmitFlow(Id workOrderId, Boolean consent) {
    Flow.Interview interview = Flow.Interview.createInterview(
      SUBMIT_FLOW,
      new Map<String, Object>{
        'recordId' => workOrderId,
        'requestReason' => REASON,
        'customerConsent' => consent,
        'submitterComment' => MEMO
      }
    );
    System.runAs(getUser('HG_Technician')) {
      interview.start();
    }
    return interview;
  }

  // 정상: 기사가 사유 + 고객 동의로 요청 → 저장·승인 대기, 승인자 = 센터장(Manager), 메모 = 제출 코멘트
  @isTest
  static void normalSubmittedAsTechnician() {
    Id woId = getWorkOrder().Id;

    Test.startTest();
    Flow.Interview interview = runSubmitFlow(woId, true);
    Test.stopTest();

    Assert.isTrue(
      (Boolean) interview.getVariableValue('isSubmitted'),
      'Flow 결과 = 제출됨: ' + interview.getVariableValue('errorMessage')
    );
    WorkOrder saved = getWorkOrder();
    Assert.areEqual(REASON, saved.ApprovalRequestReason__c, '사유 저장');
    Assert.isTrue(saved.CustomerConsent__c, '고객 동의 저장');
    Assert.areEqual(STATUS_PENDING, saved.Status, '제출 시 승인 대기 상태');

    ProcessInstanceWorkitem item = [
      SELECT ActorId, ProcessInstance.Status
      FROM ProcessInstanceWorkitem
      WHERE ProcessInstance.TargetObjectId = :woId
    ];
    Assert.areEqual(
      getUser('HG_CenterManager').Id,
      item.ActorId,
      '승인자 = 센터장'
    );
    String comment = [
      SELECT Comments
      FROM ProcessInstanceStep
      WHERE ProcessInstance.TargetObjectId = :woId AND StepStatus = 'Started'
    ]
    .Comments;
    // DESC: 제출 코멘트 = 승인 요청 요약(1.1). 사용 부품 없음 → [부품] 줄 없음
    String expected =
      '[승인 필요 이유] 청구 ₩500,001 (기준 ₩500,000 초과)\n' +
      '[사유] ' +
      REASON +
      ' / 고객 동의: 예\n' +
      '[메모] ' +
      MEMO;
    Assert.areEqual(expected, comment, '제출 코멘트 = 요약');
    Assert.areEqual(
      expected,
      [SELECT ApprovalSummary__c FROM WorkOrder WHERE Id = :woId]
      .ApprovalSummary__c,
      '같은 요약을 출동에 저장(메일 템플릿용)'
    );
  }

  // 불허: 기준 초과인데 고객 동의 없음 → 승인 프로세스 진입 조건이 거부, 실패 결과 반환
  // WARN: 저장 되돌림은 화면 Flow의 Roll Back Records 담당(자동 실행 Flow는 롤백 요소 불가) → 하위 Flow 단독 실행에선 사유가 남음
  @isTest
  static void rejectWithoutConsentNotSubmitted() {
    Id woId = getWorkOrder().Id;

    Test.startTest();
    Flow.Interview interview = runSubmitFlow(woId, false);
    Test.stopTest();

    Assert.isFalse((Boolean) interview.getVariableValue('isSubmitted'));
    Assert.isTrue(
      String.isNotBlank((String) interview.getVariableValue('errorMessage')),
      '실패 사유 전달'
    );
    Assert.areEqual(STATUS_ARRIVED, getWorkOrder().Status, '상태 그대로');
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :woId]
    );
  }

  // 불허: 도착 전(Accepted) 출동 → 승인 프로세스 진입 조건이 거부
  @isTest
  static void rejectNotArrived() {
    WorkOrder wo = getWorkOrder();
    wo.Status = 'Accepted';
    update wo;

    Test.startTest();
    Flow.Interview interview = runSubmitFlow(wo.Id, true);
    Test.stopTest();

    Assert.isFalse((Boolean) interview.getVariableValue('isSubmitted'));
    Assert.areEqual('Accepted', getWorkOrder().Status);
  }

  // 정상: 사용 부품이 있으면 부품마다 한 줄([부품] 이름 ×수량 유상·무상 ₩금액), 메모가 없으면 [메모] 줄 없음
  @isTest
  static void normalSummaryHasPartLines() {
    Id woId = getWorkOrder().Id;
    ProductItem item = TestDataFactory.createVanStock(
        TestDataFactory.createProducts(),
        10
      )
      .get('General');
    insert TestDataFactory.buildPart(woId, item.Id);

    Test.startTest();
    Flow.Interview interview = Flow.Interview.createInterview(
      SUBMIT_FLOW,
      new Map<String, Object>{
        'recordId' => woId,
        'requestReason' => REASON,
        'customerConsent' => true,
        'submitterComment' => ''
      }
    );
    System.runAs(getUser('HG_Technician')) {
      interview.start();
    }
    Test.stopTest();

    Assert.isTrue(
      (Boolean) interview.getVariableValue('isSubmitted'),
      '' + interview.getVariableValue('errorMessage')
    );
    String summary = [SELECT ApprovalSummary__c FROM WorkOrder WHERE Id = :woId]
    .ApprovalSummary__c;
    List<String> lines = summary.split('\n');
    Assert.areEqual(
      3,
      lines.size(),
      '이유·부품 1줄·사유 (메모 없음): ' + summary
    );
    Assert.isTrue(lines[0].startsWith('[승인 필요 이유] 청구 ₩'), lines[0]);
    Assert.isTrue(
      lines[1].startsWith('[부품] ') && lines[1].contains(' ×1 '),
      lines[1]
    );
    Assert.isTrue(
      lines[1].contains('유상 ₩') || lines[1].contains('무상 ₩'),
      lines[1]
    );
    Assert.isTrue(lines[2].startsWith('[사유] '), lines[2]);
    Assert.isFalse(summary.contains('[메모]'), '메모 없음');
  }
}
