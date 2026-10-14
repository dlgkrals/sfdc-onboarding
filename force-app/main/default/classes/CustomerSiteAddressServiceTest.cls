/**
 * @description CustomerSiteAddressService · AddressSearchController.saveSiteAddress 테스트
 *              누구든 주소를 저장하면 서비스센터는 매핑으로 자동 지정(트리거), 매핑 없는 주소는 거부
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성
 * 1.1    2026-10-14    Edwin     기사 생성 거부 (D8 새로 만들기 재정의)
 * 1.2    2026-10-14    Edwin     센터 완전 자동: 센터장도 매핑 센터, 매핑 없는 주소 거부, 상담원 새 사업장 자동 지정
 * ----------------------------------------------------------------------------
 * @see CustomerSiteAddressService
 */
@isTest
private class CustomerSiteAddressServiceTest {
  private static final String UIJEONGBU_CODE = '4115010100';

  @TestSetup
  static void setupData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.createUser('HG_CallCenter', false);
      TestDataFactory.createUser('HG_CenterManager', false);
      TestDataFactory.createUser('HG_Technician', true);
    }
    Account account = TestDataFactory.createAccount();
    // DESC: TestDataFactory 사업장은 경기남부·인천센터
    TestDataFactory.createSite(account.Id);
  }

  private static User getUser(String permissionSet) {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :('테스트 ' + permissionSet)
      LIMIT 1
    ];
  }

  private static CustomerSite__c getSite() {
    return [
      SELECT
        Id,
        ServiceCenter__c,
        RoadAddress__c,
        RoadAddressNote__c,
        DetailAddress__c,
        PostalCode__c,
        Sido__c,
        Sigungu__c,
        AdminDistrictCode__c
      FROM CustomerSite__c
      LIMIT 1
    ];
  }

  private static CustomerSiteAddressService.SiteAddress uijeongbu(
    String requestedCenter
  ) {
    CustomerSiteAddressService.SiteAddress a = new CustomerSiteAddressService.SiteAddress();
    a.roadAddress = '경기도 의정부시 시민로 1';
    a.roadAddressNote = '(의정부동)';
    a.detailAddress = ' 2층 ';
    a.postalCode = '11622';
    a.sido = '경기도';
    a.sigungu = '의정부시';
    a.adminDistrictCode = UIJEONGBU_CODE;
    a.serviceCenter = requestedCenter;
    return a;
  }

  // 정상: 상담원이 의정부 주소 저장 → 화면이 보낸 센터(서울)는 무시하고 매핑(경기북부)을 시스템 모드로 반영
  @isTest
  static void normalCallCenterGetsMappedCenter() {
    CustomerSite__c site = getSite();
    String saved;

    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      saved = AddressSearchController.saveSiteAddress(
        site.Id,
        uijeongbu('Seoul')
      );
    }
    Test.stopTest();

    CustomerSite__c after = getSite();
    Assert.areEqual('GyeonggiNorth', saved, '반환값 = 매핑 센터');
    Assert.areEqual(
      'GyeonggiNorth',
      after.ServiceCenter__c,
      '상담원 저장에도 센터 자동 반영'
    );
    Assert.areEqual(
      '경기도 의정부시 시민로 1',
      after.RoadAddress__c,
      '도로명주소'
    );
    Assert.areEqual('(의정부동)', after.RoadAddressNote__c, '참고항목');
    Assert.areEqual('2층', after.DetailAddress__c, '상세주소 공백 제거');
    Assert.areEqual('11622', after.PostalCode__c, '우편번호');
    Assert.areEqual(
      UIJEONGBU_CODE,
      after.AdminDistrictCode__c,
      '행정구역 코드'
    );
  }

  // 불허: 상담원은 서비스센터를 직접 바꿀 수 없음 (필드 읽기 전용 → 거부, 센터 그대로)
  @isTest
  static void rejectCallCenterEditsCenterDirectly() {
    CustomerSite__c site = getSite();
    Exception caught;

    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      try {
        Database.update(
          new CustomerSite__c(Id = site.Id, ServiceCenter__c = 'Seoul'),
          AccessLevel.USER_MODE
        );
      } catch (Exception e) {
        caught = e;
      }
    }
    Test.stopTest();

    Assert.isNotNull(caught, '상담원은 서비스센터를 직접 바꿀 수 없음');
    Assert.areEqual('GyeonggiSouth', getSite().ServiceCenter__c, '센터 그대로');
  }

  // 불허: 매핑에 없는 행정구역 코드 → 저장 거부 ("관리자에게 매핑 추가 요청"), 주소·센터 그대로
  @isTest
  static void rejectUnmappedAddress() {
    CustomerSite__c site = getSite();
    CustomerSiteAddressService.SiteAddress address = uijeongbu(null);
    address.adminDistrictCode = '9911010100';
    AuraHandledException caught;

    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      try {
        AddressSearchController.saveSiteAddress(site.Id, address);
      } catch (AuraHandledException e) {
        caught = e;
      }
    }
    Test.stopTest();

    Assert.isNotNull(caught, '매핑 없는 주소 거부');
    Assert.isTrue(
      caught.getMessage().contains(System.Label.MSG_CENTER_NO_MAPPING),
      '메시지: ' + caught.getMessage()
    );
    Assert.areEqual('GyeonggiSouth', getSite().ServiceCenter__c, '센터 그대로');
    Assert.areEqual(
      TestDataFactory.PYEONGTAEK_DISTRICT_CODE,
      getSite().AdminDistrictCode__c,
      '주소도 그대로'
    );
  }

  // 정상: 센터장이 화면에서 다른 센터(경기남부)를 보내도 무시 → 주소 매핑(경기북부)으로 자동 지정
  @isTest
  static void normalCenterManagerGetsMappedCenter() {
    CustomerSite__c site = getSite();
    String saved;

    Test.startTest();
    System.runAs(getUser('HG_CenterManager')) {
      saved = AddressSearchController.saveSiteAddress(
        site.Id,
        uijeongbu('GyeonggiSouth')
      );
    }
    Test.stopTest();

    Assert.areEqual('GyeonggiNorth', saved, '매핑 센터');
    Assert.areEqual(
      'GyeonggiNorth',
      getSite().ServiceCenter__c,
      '센터장도 자동 지정'
    );
  }

  // 불허: 사업장 권한이 없는 협력 기사 → 화면에 표시할 오류, 변경 없음
  @isTest
  static void rejectTechnicianWithoutSiteAccess() {
    CustomerSite__c site = getSite();
    AuraHandledException caught;

    Test.startTest();
    System.runAs(getUser('HG_Technician')) {
      try {
        AddressSearchController.saveSiteAddress(site.Id, uijeongbu(null));
      } catch (AuraHandledException e) {
        caught = e;
      }
    }
    Test.stopTest();

    Assert.isNotNull(caught, '기사는 사업장 주소를 저장할 수 없음');
    Assert.areEqual(
      TestDataFactory.PYEONGTAEK_DISTRICT_CODE,
      getSite().AdminDistrictCode__c,
      '변경 없음'
    );
    Assert.areEqual('GyeonggiSouth', getSite().ServiceCenter__c, '센터 그대로');
  }

  // 불허: 주소 없이 저장 요청 → 오류
  @isTest
  static void rejectMissingAddress() {
    AuraHandledException caught;

    Test.startTest();
    try {
      AddressSearchController.saveSiteAddress(
        getSite().Id,
        new CustomerSiteAddressService.SiteAddress()
      );
    } catch (AuraHandledException e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(caught, '주소 없으면 거부');
  }

  // 정상: 사업장 등록 화면 경로 — 상담원이 주소 검색 결과(행정구역 코드)와 함께 새 사업장 저장 → 센터 자동 지정(경기북부)
  @isTest
  static void normalCallCenterNewSiteGetsMappedCenter() {
    Id accountId = [SELECT Id FROM Account LIMIT 1].Id;
    CustomerSite__c created = new CustomerSite__c(
      Name = '상담원 등록 사업장',
      Account__c = accountId,
      RoadAddress__c = '경기도 의정부시 시민로 1',
      AdminDistrictCode__c = UIJEONGBU_CODE
    );

    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      Database.insert(created, true, AccessLevel.USER_MODE);
    }
    Test.stopTest();

    Assert.areEqual(
      'GyeonggiNorth',
      [SELECT ServiceCenter__c FROM CustomerSite__c WHERE Id = :created.Id]
      .ServiceCenter__c,
      '새 사업장 센터 자동 지정'
    );
  }

  // 불허: 협력 기사는 사업장을 만들 수 없음 (사업장 오브젝트 권한 없음 → 새로 만들기 화면도 쓸 수 없음)
  @isTest
  static void rejectTechnicianCannotCreateSite() {
    Id accountId = [SELECT Id FROM Account LIMIT 1].Id;
    Boolean failed = false;

    Test.startTest();
    System.runAs(getUser('HG_Technician')) {
      try {
        Database.insert(
          new CustomerSite__c(Name = '기사 등록 시도', Account__c = accountId),
          true,
          AccessLevel.USER_MODE
        );
      } catch (Exception e) {
        failed = true;
      }
    }
    Test.stopTest();

    Assert.isTrue(failed, '기사 생성 거부');
  }
}
