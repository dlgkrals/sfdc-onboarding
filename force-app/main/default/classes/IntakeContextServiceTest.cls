/**
 * @description IntakeContextService 테스트 — 접수 작성 팝업 고객사·사업장 카드, 진행 중 접수(BR-11 중복 경고)
 *              상담원 권한(System.runAs)으로 컨트롤러를 거쳐 호출 (USER_MODE 조회가 실제 권한으로 되는지)
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-15    Edwin     최초 작성 (피드백 개선 ① 카드, ③ 중복 접수 경고)
 * ----------------------------------------------------------------------------
 * @see IntakeContextService, CallIntakeController
 */
@isTest
private class IntakeContextServiceTest {
  private static final String ACCOUNT_PHONE = '031-600-1000';
  private static final String ONSITE_PHONE = '010-1111-2001';
  private static final String SECONDARY_PHONE = '010-7777-0001';
  // DESC: 진행 중 7건(New 5·InProgress 1·Completed 1) + 종결 1·취소 1 → 진행 중 7, 표시 5
  private static final Integer OPEN_NEW_COUNT = 5;

  @TestSetup
  static void setupData() {
    // DESC: 접수 공유 규칙은 공개 그룹 HG_CallCenter 대상 → 운영처럼 상담원을 그룹에 넣음 (접수 만들기 전에)
    System.runAs(new User(Id = UserInfo.getUserId())) {
      User callCenter = TestDataFactory.createUser('HG_CallCenter', false);
      TestDataFactory.createUser('HG_Technician', true);
      insert new GroupMember(
        GroupId = [
          SELECT Id
          FROM Group
          WHERE DeveloperName = 'HG_CallCenter' AND Type = 'Regular'
        ]
        .Id,
        UserOrGroupId = callCenter.Id
      );
    }
    Account account = TestDataFactory.createAccount();
    account.Phone = ACCOUNT_PHONE;
    account.AccountStatus__c = 'PaymentWarning';
    update account;

    CustomerSite__c coldSite = TestDataFactory.createSite(account.Id);
    coldSite.Name = '평택 냉동창고';
    coldSite.UsageType__c = 'ColdStorage';
    coldSite.OnSiteContactName__c = '박현장';
    coldSite.OnSiteContactPhone__c = ONSITE_PHONE;
    coldSite.SecondaryContactPhone__c = SECONDARY_PHONE;
    update coldSite;
    TestDataFactory.createSite(account.Id);

    List<Asset> assets = TestDataFactory.createAssets(
      account.Id,
      coldSite.Id,
      'TST-CTX-',
      2
    );
    List<Case> cases = TestDataFactory.createCases(
      new List<Asset>{ assets[0] },
      OPEN_NEW_COUNT + 4
    );
    cases[OPEN_NEW_COUNT].Status = 'InProgress';
    cases[OPEN_NEW_COUNT + 1].Status = 'Completed';
    cases[OPEN_NEW_COUNT + 2].Status = 'Closed';
    cases[OPEN_NEW_COUNT + 3].Status = 'Canceled';
    cases[OPEN_NEW_COUNT + 3].CancelReason__c = '고객 요청으로 취소';
    update cases;
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

  private static CustomerSite__c getColdSite() {
    return [
      SELECT Id, Account__c
      FROM CustomerSite__c
      WHERE Name = '평택 냉동창고'
      LIMIT 1
    ];
  }

  private static Id getAssetId(Integer index) {
    return [
      SELECT Id
      FROM Asset
      WHERE CustomerSite__c = :getColdSite().Id
      ORDER BY SerialKey__c
    ][index]
    .Id;
  }

  // 정상: 고객사·사업장 카드 — 거래 상태(미수 주의)·용도 긴급·장비 수·진행 중 접수 수 (상담원)
  @isTest
  static void normalCardsAsCallCenter() {
    CustomerSite__c site = getColdSite();
    IntakeContextService.ContextCards cards;
    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      cards = CallIntakeController.getContextCards(site.Account__c, site.Id);
    }
    Test.stopTest();

    IntakeContextService.AccountCard account = cards.account;
    Assert.areEqual('테스트 고객사', account.name);
    Assert.areEqual(ACCOUNT_PHONE, account.phone);
    Assert.areEqual('PaymentWarning', account.status);
    Assert.isNotNull(account.statusLabel, '거래 상태 라벨');
    Assert.isNotNull(account.customerType, '고객 유형 = 레코드 유형');
    Assert.areEqual(2, account.siteCount);
    Assert.areEqual(2, account.assetCount);

    IntakeContextService.SiteCard siteCard = cards.site;
    Assert.areEqual('평택 냉동창고', siteCard.name);
    Assert.isTrue(siteCard.isUrgentUsage, '냉동창고 = 긴급 용도');
    Assert.areEqual('박현장', siteCard.onSiteContactName);
    Assert.areEqual(ONSITE_PHONE, siteCard.onSiteContactPhone);
    Assert.areEqual(SECONDARY_PHONE, siteCard.secondaryContactPhone);
    Assert.isNotNull(siteCard.serviceCenter, '센터는 트리거가 자동 지정');
    Assert.areEqual(2, siteCard.assetCount);
    Assert.areEqual(
      OPEN_NEW_COUNT + 2,
      siteCard.openCaseCount,
      '종결·취소 제외, 완료 포함'
    );
  }

  // 정상: 사업장만 넘겨도 그 사업장의 고객사 카드까지 / 둘 다 없으면 빈 카드
  @isTest
  static void normalCardsFromSiteOnly() {
    CustomerSite__c site = getColdSite();
    IntakeContextService.ContextCards fromSite;
    IntakeContextService.ContextCards empty;
    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      fromSite = CallIntakeController.getContextCards(null, site.Id);
      empty = CallIntakeController.getContextCards(null, null);
    }
    Test.stopTest();

    Assert.areEqual(site.Account__c, fromSite.account.id);
    Assert.isNull(empty.account);
    Assert.isNull(empty.site);
  }

  // 벌크(표시 상한): 진행 중 7건 → 전체 7, 최근 5건만, 상태 라벨 포함 / 접수 없는 장비는 0건
  @isTest
  static void bulkOpenCasesLimitedToFive() {
    IntakeContextService.OpenCases withCases;
    IntakeContextService.OpenCases noCases;
    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      withCases = CallIntakeController.getOpenCases(getAssetId(0));
      noCases = CallIntakeController.getOpenCases(getAssetId(1));
    }
    Test.stopTest();

    Assert.areEqual(OPEN_NEW_COUNT + 2, withCases.totalCount);
    Assert.areEqual(
      IntakeContextService.OPEN_CASE_LIMIT,
      withCases.cases.size()
    );
    for (IntakeContextService.OpenCase openCase : withCases.cases) {
      Assert.isFalse(
        IntakeContextService.CLOSED_STATUSES.contains(openCase.status),
        '종결·취소 접수는 경고에 없음'
      );
      Assert.isNotNull(openCase.statusLabel);
      Assert.isNotNull(openCase.caseNumber);
    }
    Assert.areEqual(0, noCases.totalCount);
    Assert.isTrue(noCases.cases.isEmpty());
  }

  // 불허: 기사(고객사·사업장·장비·접수 권한 없음) → 카드·진행 중 접수 모두 거부
  @isTest
  static void rejectTechnician() {
    CustomerSite__c site = getColdSite();
    Id assetId = getAssetId(0);
    Integer rejected = 0;
    Test.startTest();
    System.runAs(getUser('HG_Technician')) {
      try {
        CallIntakeController.getContextCards(site.Account__c, site.Id);
      } catch (AuraHandledException e) {
        rejected++;
      }
      try {
        CallIntakeController.getOpenCases(assetId);
      } catch (AuraHandledException e) {
        rejected++;
      }
    }
    Test.stopTest();

    Assert.areEqual(2, rejected, '기사는 둘 다 거부');
  }
}
