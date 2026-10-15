/**
 * @description CallIntakeController · CallerMatchService 테스트 (정상·불허·벌크)
 *              SOSL은 테스트에서 빈 결과를 돌려주므로 Test.setFixedSearchResults로 후보 Id를 정해 줌
 *              (서비스가 숫자만 비교로 다시 거르므로 후보에 다른 번호가 섞여도 결과는 실제와 같음)
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-15    Edwin     최초 작성 (CTI 가상 착신 시뮬레이터)
 * ----------------------------------------------------------------------------
 * @see CallIntakeController, CallerMatchService
 */
@isTest
private class CallIntakeControllerTest {
  // DESC: devorg 시연 데이터(한빛물류)와 같은 구조 — 대표 번호 1개, 사업장 3곳
  private static final String ACCOUNT_PHONE = '031-600-1000';
  private static final String THREE_ASSET_SITE_PHONE = '010-1111-2001';
  // DESC: 하이픈 없이 저장된 번호 (화면 입력은 하이픈 포함)
  private static final String ONE_ASSET_SITE_PHONE = '01011112002';
  private static final String DUPLICATE_SERIAL_SITE_PHONE = '010-1111-2003';
  private static final String SECONDARY_PHONE = '010-7777-0001';
  private static final String UNKNOWN_PHONE = '010-9999-0000';
  private static final String NO_SERIAL = '#';

  @TestSetup
  static void setupData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.createUser('HG_CallCenter', false);
      TestDataFactory.createUser('HG_Technician', true);
    }
    Account account = TestDataFactory.createAccount();
    account.Phone = ACCOUNT_PHONE;
    update account;

    CustomerSite__c threeAssetSite = TestDataFactory.createSite(account.Id);
    CustomerSite__c oneAssetSite = TestDataFactory.createSite(account.Id);
    CustomerSite__c duplicateSerialSite = TestDataFactory.createSite(
      account.Id
    );
    threeAssetSite.Name = '평택 2창고';
    threeAssetSite.OnSiteContactPhone__c = THREE_ASSET_SITE_PHONE;
    oneAssetSite.Name = '인천 물류센터';
    oneAssetSite.OnSiteContactPhone__c = ONE_ASSET_SITE_PHONE;
    duplicateSerialSite.Name = '서울 본사';
    duplicateSerialSite.OnSiteContactPhone__c = DUPLICATE_SERIAL_SITE_PHONE;
    duplicateSerialSite.SecondaryContactPhone__c = SECONDARY_PHONE;
    update new List<CustomerSite__c>{
      threeAssetSite,
      oneAssetSite,
      duplicateSerialSite
    };

    Date installDate = Date.today().addMonths(-6);
    insert new List<Asset>{
      TestDataFactory.buildAsset(
        account.Id,
        threeAssetSite.Id,
        'TST-CTI-0002',
        installDate,
        false
      ),
      TestDataFactory.buildAsset(
        account.Id,
        threeAssetSite.Id,
        'TST-CTI-0001',
        installDate,
        false
      ),
      TestDataFactory.buildAsset(
        account.Id,
        threeAssetSite.Id,
        'TST-CTI-0015',
        installDate,
        false
      ),
      TestDataFactory.buildAsset(
        account.Id,
        oneAssetSite.Id,
        'TST-CTI-0003',
        installDate,
        false
      ),
      // DESC: 시리얼 끝자리 중복(0099 두 대)은 시연 데이터에 없고 테스트로만 확인
      TestDataFactory.buildAsset(
        account.Id,
        duplicateSerialSite.Id,
        'TST-CTI-A-0099',
        installDate,
        false
      ),
      TestDataFactory.buildAsset(
        account.Id,
        duplicateSerialSite.Id,
        'TST-CTI-B-0099',
        installDate,
        false
      ),
      TestDataFactory.buildAsset(
        account.Id,
        duplicateSerialSite.Id,
        'TST-CTI-0100',
        installDate,
        false
      )
    };
  }

  // 정상: 사업장 1곳 + 시리얼 뒤 4자리 일치 1대 → 장비 확정 (상담원 권한으로)
  @isTest
  static void normalSerialMatchConfirmsAsset() {
    setSearchResults();
    CallerMatchService.MatchResult result;
    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      result = CallIntakeController.matchCaller(THREE_ASSET_SITE_PHONE, '0001');
    }
    Test.stopTest();

    Assert.areEqual(CallerMatchService.OUTCOME_CONFIRMED, result.outcome);
    Assert.areEqual(CallerMatchService.MATCHED_BY_ONSITE, result.matchedBy);
    Assert.areEqual(getAssetId('TST-CTI-0001'), result.assetId);
    Assert.areEqual(getSiteId('평택 2창고'), result.siteId, '사업장 채움');
    Assert.isNotNull(result.accountId, '고객사 채움');
    Assert.areEqual(1, result.serialMatchCount);
    Assert.areEqual(3, result.assets.size(), '다른 장비로 바꿀 수 있게 후보');
    Assert.areEqual(
      3,
      result.sites.size(),
      '고객사의 다른 사업장도 고를 수 있게'
    );
  }

  // 정상: 사업장 1곳 + 시리얼 모름(#) + 장비 1대 → 장비 확정. 하이픈 없이 저장된 번호도 찾음
  @isTest
  static void normalSingleAssetSiteConfirmsAsset() {
    setSearchResults();
    Test.startTest();
    CallerMatchService.MatchResult result = CallIntakeController.matchCaller(
      '010-1111-2002',
      NO_SERIAL
    );
    Test.stopTest();

    Assert.areEqual(CallerMatchService.OUTCOME_CONFIRMED, result.outcome);
    Assert.areEqual(getAssetId('TST-CTI-0003'), result.assetId);
    Assert.isNull(result.serialSuffix, '#은 시리얼 모름');
  }

  // 정상: 사업장 1곳 + 장비 여러 대 + 시리얼 모름 → 장비 후보 3대
  @isTest
  static void normalMultipleAssetsGiveCandidates() {
    setSearchResults();
    Test.startTest();
    CallerMatchService.MatchResult result = CallIntakeController.matchCaller(
      THREE_ASSET_SITE_PHONE,
      NO_SERIAL
    );
    Test.stopTest();

    Assert.areEqual(
      CallerMatchService.OUTCOME_ASSET_CANDIDATES,
      result.outcome
    );
    Assert.isNull(result.assetId, '장비는 비움');
    Assert.areEqual(getSiteId('평택 2창고'), result.siteId);
    Assert.areEqual(3, result.assets.size());
  }

  // 정상: 사업장 1곳 + 시리얼 불일치 → 사업장 장비 전체가 후보 (시리얼로 다른 사업장 장비를 찾지 않음)
  @isTest
  static void normalSerialMismatchShowsSiteAssets() {
    setSearchResults();
    Test.startTest();
    CallerMatchService.MatchResult result = CallIntakeController.matchCaller(
      THREE_ASSET_SITE_PHONE,
      '0003'
    );
    Test.stopTest();

    Assert.areEqual(
      CallerMatchService.OUTCOME_ASSET_CANDIDATES,
      result.outcome
    );
    Assert.areEqual(0, result.serialMatchCount);
    Assert.areEqual(3, result.assets.size());
  }

  // 정상: 고객사 대표 번호 → 사업장 후보 3곳, 시리얼 일치 1대면 사업장·장비 채움
  @isTest
  static void normalAccountPhoneGivesSiteCandidates() {
    setSearchResults();
    Test.startTest();
    CallerMatchService.MatchResult withoutSerial = CallIntakeController.matchCaller(
      ACCOUNT_PHONE,
      NO_SERIAL
    );
    CallerMatchService.MatchResult withSerial = CallIntakeController.matchCaller(
      ACCOUNT_PHONE,
      '0003'
    );
    Test.stopTest();

    Assert.areEqual(
      CallerMatchService.OUTCOME_SITE_CANDIDATES,
      withoutSerial.outcome
    );
    Assert.areEqual(
      CallerMatchService.MATCHED_BY_ACCOUNT,
      withoutSerial.matchedBy
    );
    Assert.isNotNull(withoutSerial.accountId, '고객사 채움');
    Assert.isNull(withoutSerial.siteId, '사업장은 비움');
    Assert.areEqual(3, withoutSerial.sites.size());

    Assert.areEqual(CallerMatchService.OUTCOME_CONFIRMED, withSerial.outcome);
    Assert.areEqual(getSiteId('인천 물류센터'), withSerial.siteId);
    Assert.areEqual(getAssetId('TST-CTI-0003'), withSerial.assetId);
  }

  // 정상: 사업장 후보에서 사업장을 고르면 그 사업장 장비 후보로 갱신
  @isTest
  static void normalSiteSelectionRefreshesAssets() {
    Test.startTest();
    CallerMatchService.AssetChoice threeAssets = CallIntakeController.getAssetCandidates(
      null,
      getSiteId('평택 2창고'),
      null
    );
    CallerMatchService.AssetChoice oneAsset = CallIntakeController.getAssetCandidates(
      null,
      getSiteId('인천 물류센터'),
      null
    );
    List<CallerMatchService.SiteOption> sites = CallIntakeController.getSiteCandidates(
      [SELECT Id FROM Account LIMIT 1].Id
    );
    Test.stopTest();

    Assert.areEqual(3, threeAssets.assets.size());
    Assert.isNull(threeAssets.selectedAssetId);
    Assert.areEqual(getAssetId('TST-CTI-0003'), oneAsset.selectedAssetId);
    Assert.areEqual(3, sites.size());
  }

  // 정상: 미등록 번호 → 발신 번호만, 시리얼 4자리만으로 전체에서 확정하지 않음
  @isTest
  static void normalUnknownNumberFillsNothing() {
    setSearchResults();
    Test.startTest();
    CallerMatchService.MatchResult result = CallIntakeController.matchCaller(
      UNKNOWN_PHONE,
      '0003'
    );
    Test.stopTest();

    Assert.areEqual(CallerMatchService.OUTCOME_NOT_FOUND, result.outcome);
    Assert.areEqual(CallerMatchService.MATCHED_BY_NONE, result.matchedBy);
    Assert.areEqual(UNKNOWN_PHONE, result.callerPhone);
    Assert.isNull(result.assetId, '시리얼만으로 확정하지 않음');
    Assert.isNull(result.accountId);
    Assert.isTrue(result.assets.isEmpty());
  }

  // 정상: 시리얼 끝자리가 같은 장비 2대 → 일치한 2대만 후보 / 보조 연락처로도 찾음
  @isTest
  static void normalDuplicateSerialShowsOnlyMatches() {
    setSearchResults();
    Test.startTest();
    CallerMatchService.MatchResult result = CallIntakeController.matchCaller(
      DUPLICATE_SERIAL_SITE_PHONE,
      '0099'
    );
    CallerMatchService.MatchResult bySecondary = CallIntakeController.matchCaller(
      SECONDARY_PHONE,
      '0100'
    );
    Test.stopTest();

    Assert.areEqual(
      CallerMatchService.OUTCOME_ASSET_CANDIDATES,
      result.outcome
    );
    Assert.areEqual(2, result.serialMatchCount);
    Assert.areEqual(2, result.assets.size(), '일치한 장비만');
    for (CallerMatchService.AssetOption option : result.assets) {
      Assert.isTrue(option.serialMatched);
    }

    Assert.areEqual(
      CallerMatchService.MATCHED_BY_SECONDARY,
      bySecondary.matchedBy
    );
    Assert.areEqual(getAssetId('TST-CTI-0100'), bySecondary.assetId);
  }

  // 정상: 장비 요약 → "이 장비로 접수"는 장비·사업장·고객사가 채워진 상태
  @isTest
  static void normalIntakeForAsset() {
    Test.startTest();
    CallerMatchService.MatchResult result = CallIntakeController.getIntakeForAsset(
      getAssetId('TST-CTI-0015')
    );
    Test.stopTest();

    Assert.areEqual(CallerMatchService.OUTCOME_CONFIRMED, result.outcome);
    Assert.areEqual(getSiteId('평택 2창고'), result.siteId);
    Assert.areEqual(3, result.sites.size(), '사업장도 바꿀 수 있게 후보');
  }

  // 정상: 상담원이 전화 접수 저장 → 경로·발신 번호·증상·기본 제목, 고객사·사업장은 저장 전 Flow가 채움
  @isTest
  static void normalCreateCaseAsCallCenter() {
    Id assetId = getAssetId('TST-CTI-0003');
    CallIntakeController.CaseDraft draft = new CallIntakeController.CaseDraft();
    draft.assetId = assetId;
    draft.symptomType = 'Leak';
    draft.callerPhone = ' 010-1111-2002 ';
    draft.description = '천장에서 물이 떨어짐';

    Id caseId;
    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      Assert.isTrue(CallIntakeController.canCreateCase(), '상담원은 사용 가능');
      caseId = CallIntakeController.createCase(draft);
    }
    Test.stopTest();

    Case saved = [
      SELECT
        Origin,
        CallerPhone__c,
        SymptomType__c,
        Subject,
        Description,
        AccountId,
        CustomerSite__c,
        AssetId
      FROM Case
      WHERE Id = :caseId
    ];
    Assert.areEqual(CallIntakeController.ORIGIN_PHONE, saved.Origin);
    Assert.areEqual('010-1111-2002', saved.CallerPhone__c);
    Assert.areEqual('Leak', saved.SymptomType__c);
    Assert.areEqual(
      CallIntakeController.buildDefaultSubject('Leak'),
      saved.Subject,
      '제목 비우면 기본 제목'
    );
    Assert.isTrue(saved.Subject.contains('누수'), '증상 라벨 사용');
    Assert.areEqual(
      [SELECT Id FROM Account LIMIT 1].Id,
      saved.AccountId,
      'Flow가 장비 기준 고객사 채움'
    );
    Assert.areEqual(getSiteId('인천 물류센터'), saved.CustomerSite__c);
  }

  // 불허: 장비 없이 저장 → 기존 검증 규칙(Asset_Required)이 거부
  @isTest
  static void rejectCreateCaseWithoutAsset() {
    CallIntakeController.CaseDraft draft = new CallIntakeController.CaseDraft();
    draft.symptomType = 'Noise';
    draft.callerPhone = UNKNOWN_PHONE;

    Boolean rejected = false;
    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      try {
        CallIntakeController.createCase(draft);
      } catch (AuraHandledException e) {
        rejected = true;
        Assert.isTrue(
          e.getMessage().contains('장비'),
          '검증 규칙 메시지 전달: ' + e.getMessage()
        );
      }
    }
    Test.stopTest();

    Assert.isTrue(rejected, '장비 없으면 저장 거부');
    Assert.areEqual(0, [SELECT COUNT() FROM Case]);
  }

  // 불허: 기사는 고객 정보 권한이 없어 착신 판정·접수 생성 불가
  @isTest
  static void rejectTechnicianAccess() {
    setSearchResults();
    Boolean matchRejected = false;
    Boolean createRejected = false;
    Boolean canCreate;
    Test.startTest();
    System.runAs(getUser('HG_Technician')) {
      canCreate = CallIntakeController.canCreateCase();
      try {
        CallIntakeController.matchCaller(THREE_ASSET_SITE_PHONE, '0001');
      } catch (AuraHandledException e) {
        matchRejected = true;
        Assert.areEqual(System.Label.MSG_CALL_NO_ACCESS, e.getMessage());
      }
      try {
        CallIntakeController.createCase(new CallIntakeController.CaseDraft());
      } catch (AuraHandledException e) {
        createRejected = true;
      }
    }
    Test.stopTest();

    Assert.isFalse(canCreate, '기사는 사용 불가');
    Assert.isTrue(matchRejected, '판정 거부');
    Assert.isTrue(createRejected, '접수 생성 거부');
  }

  // 벌크: 장비 200대 사업장 → 후보 200대를 한 번에 (쿼리 수 일정)
  @isTest
  static void bulkSiteWith200Assets() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    CustomerSite__c bulkSite = TestDataFactory.createSite(account.Id);
    bulkSite.OnSiteContactPhone__c = '010-2000-0200';
    update bulkSite;
    TestDataFactory.createAssets(account.Id, bulkSite.Id, 'TST-BULK-', 200);
    Test.setFixedSearchResults(new List<Id>{ bulkSite.Id, account.Id });

    Test.startTest();
    CallerMatchService.MatchResult result = CallIntakeController.matchCaller(
      '010-2000-0200',
      NO_SERIAL
    );
    CallerMatchService.AssetChoice choice = CallIntakeController.getAssetCandidates(
      account.Id,
      bulkSite.Id,
      null
    );
    Integer queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(
      CallerMatchService.OUTCOME_ASSET_CANDIDATES,
      result.outcome
    );
    Assert.areEqual(200, result.assets.size());
    Assert.areEqual(200, choice.assets.size());
    Assert.isTrue(queries <= 10, '장비 수와 무관하게 쿼리 몇 번: ' + queries);
  }

  // DESC: 테스트에서 SOSL은 빈 결과 → 모든 사업장·고객사를 후보로 주고 서비스의 번호 비교에 맡김
  private static void setSearchResults() {
    List<Id> ids = new List<Id>();
    for (CustomerSite__c site : [SELECT Id FROM CustomerSite__c]) {
      ids.add(site.Id);
    }
    for (Account account : [SELECT Id FROM Account]) {
      ids.add(account.Id);
    }
    Test.setFixedSearchResults(ids);
  }

  private static User getUser(String permissionSetName) {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :('테스트 ' + permissionSetName)
      LIMIT 1
    ];
  }

  private static Id getAssetId(String serialKey) {
    return [SELECT Id FROM Asset WHERE SerialKey__c = :serialKey].Id;
  }

  private static Id getSiteId(String name) {
    return [SELECT Id FROM CustomerSite__c WHERE Name = :name].Id;
  }
}
