/**
 * @description 출동 승인 프로세스(WorkOrder.HG_WorkOrderApproval) 진입 조건과 승인 기준액(ServiceSetting ApprovalAmount)이 같은지 검증
 *              승인 진입 조건은 $CustomMetadata를 쓰는 수식을 참조할 수 없어(플랫폼 제약) 기준액이 숫자 500000으로 들어 있음
 *              → Custom Metadata 값과 값 + 1 경계로 실제 승인 요청을 보내, 한쪽만 바꾸면 이 테스트가 실패하게 함
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-15    Edwin     최초 작성 (승인 진입 조건 A안: 숫자 + 테스트로 일치 검증)
 * ----------------------------------------------------------------------------
 * @see approvalProcesses/WorkOrder.HG_WorkOrderApproval, WorkOrder.fmNeedsApproval__c, docs/decision-log.md
 */
@isTest
private class WorkOrderApprovalTest {
  private static final String STATUS_ARRIVED = 'Arrived';

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
      'TEST-WOA-',
      1
    );
    WorkOrder wo = TestDataFactory.createWorkOrders(
      TestDataFactory.createCases(assets, 1)
    )[0];
    wo.OwnerId = getTechnician().Id;
    wo.Status = STATUS_ARRIVED;
    wo.ApprovalRequestReason__c = '테스트 승인 요청';
    update wo;
  }

  private static User getTechnician() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = '테스트 HG_Technician'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  private static Decimal approvalAmount() {
    return ServiceSetting__mdt.getInstance('ApprovalAmount').Value__c;
  }

  // DESC: 사용 부품 없이 방문비만으로 총 청구액을 맞춤(총 청구액 = 방문비 + 유상 부품비)
  private static Id prepare(Decimal totalCharge, Boolean consent) {
    WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];
    wo.VisitFee__c = totalCharge;
    wo.CustomerConsent__c = consent;
    update wo;
    WorkOrder saved = [
      SELECT fmTotalCharge__c, fmNeedsApproval__c
      FROM WorkOrder
      WHERE Id = :wo.Id
    ];
    Assert.areEqual(totalCharge, saved.fmTotalCharge__c, '총 청구액 준비');
    return wo.Id;
  }

  // DESC: 기사로 승인 요청. 진입 조건에 안 맞으면 플랫폼이 예외 → 거부로 봄
  private static Boolean submit(Id workOrderId) {
    Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
    request.setObjectId(workOrderId);
    request.setComments('테스트 승인 요청');
    try {
      Approval.ProcessResult result;
      System.runAs(getTechnician()) {
        result = Approval.process(request);
      }
      return result.isSuccess();
    } catch (Exception e) {
      return false;
    }
  }

  // 불허(경계): 총 청구액 = 기준액(초과 아님), 예외 무상 없음 → 승인 대상 아님. fmNeedsApproval__c도 거짓
  @isTest
  static void rejectAtThresholdNotSubmitted() {
    Id woId = prepare(approvalAmount(), true);

    Test.startTest();
    Boolean submitted = submit(woId);
    Test.stopTest();

    Assert.isFalse(
      [SELECT fmNeedsApproval__c FROM WorkOrder WHERE Id = :woId]
      .fmNeedsApproval__c,
      '수식: 기준액과 같으면 승인 불필요'
    );
    Assert.isFalse(
      submitted,
      '승인 진입 조건도 기준액과 같으면 대상 아님 — 실패하면 승인 프로세스의 숫자와 ServiceSetting ApprovalAmount가 어긋난 것'
    );
  }

  // 정상(경계): 기준액 + 1 + 고객 동의 → 승인 요청됨. fmNeedsApproval__c도 참
  @isTest
  static void normalOverThresholdWithConsentSubmitted() {
    Id woId = prepare(approvalAmount() + 1, true);

    Test.startTest();
    Boolean submitted = submit(woId);
    Test.stopTest();

    Assert.isTrue(
      [SELECT fmNeedsApproval__c FROM WorkOrder WHERE Id = :woId]
      .fmNeedsApproval__c,
      '수식: 기준액 초과면 승인 필요'
    );
    Assert.isTrue(
      submitted,
      '승인 진입 조건도 기준액 초과면 대상 — 실패하면 승인 프로세스의 숫자와 ServiceSetting ApprovalAmount가 어긋난 것'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM ProcessInstance
        WHERE TargetObjectId = :woId AND Status = 'Pending'
      ],
      '승인 대기 1건'
    );
  }

  // 불허: 기준액 + 1인데 고객 동의 없음 → 승인 요청 불가(고액 유상은 동의가 있어야 요청)
  @isTest
  static void rejectOverThresholdWithoutConsent() {
    Id woId = prepare(approvalAmount() + 1, false);

    Test.startTest();
    Boolean submitted = submit(woId);
    Test.stopTest();

    Assert.isFalse(submitted, '고객 동의 없으면 승인 요청 불가');
  }
}
