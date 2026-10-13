/**
 * @description CustomerSiteAddressService · AddressSearchController.saveSiteAddress 테스트
 *              상담원은 센터를 직접 못 고치지만 주소 저장 시 매핑 센터가 시스템 모드로 반영되는지
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성
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

  // 정상: 상담원에게 서비스센터 편집 권한은 없음 (직접 변경 시도 → 거부, 센터 그대로)
  @isTest
  static void normalCallCenterCannotEditCenterDirectly() {
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

  // 정상: 매핑에 없는 행정구역 코드 → 주소만 저장, 센터는 그대로
  @isTest
  static void normalCallCenterUnmappedKeepsCenter() {
    CustomerSite__c site = getSite();
    CustomerSiteAddressService.SiteAddress address = uijeongbu(null);
    address.adminDistrictCode = '9911010100';
    String saved;

    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      saved = AddressSearchController.saveSiteAddress(site.Id, address);
    }
    Test.stopTest();

    Assert.isNull(saved, '센터 변경 없음');
    Assert.areEqual('GyeonggiSouth', getSite().ServiceCenter__c, '센터 그대로');
    Assert.areEqual(
      '9911010100',
      getSite().AdminDistrictCode__c,
      '주소는 저장'
    );
  }

  // 정상: 센터장은 매핑(경기북부)과 다른 센터(경기남부)를 골라 저장할 수 있음
  @isTest
  static void normalCenterManagerChoosesCenter() {
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

    Assert.areEqual('GyeonggiSouth', saved, '센터장이 고른 값');
    Assert.areEqual(
      'GyeonggiSouth',
      getSite().ServiceCenter__c,
      '센터장 선택 유지'
    );
    Assert.areEqual(
      UIJEONGBU_CODE,
      getSite().AdminDistrictCode__c,
      '주소는 의정부'
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
    Assert.isNull(getSite().AdminDistrictCode__c, '변경 없음');
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
}
