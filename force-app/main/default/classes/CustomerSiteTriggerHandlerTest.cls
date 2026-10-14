/**
 * @description CustomerSiteTriggerHandler 테스트 — 사업장 서비스센터 완전 자동 지정 (D8)
 *              등록·수정 시 매핑 센터 자동, 주소 검색 없이 저장·매핑 없는 주소·센터 직접 변경 거부, 200건
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-14
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-14    Edwin     최초 작성 (D8 서비스센터 완전 자동)
 * ----------------------------------------------------------------------------
 * @see CustomerSiteTriggerHandler, CustomerSiteAddressService
 */
@isTest
private class CustomerSiteTriggerHandlerTest {
  private static final String UIJEONGBU_CODE = '4115010100';
  private static final String SEOUL_CODE = '1111010100';

  @TestSetup
  static void setupData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.createUser('HG_CallCenter', false);
      TestDataFactory.createUser('HG_CenterManager', false);
    }
    TestDataFactory.createAccount();
  }

  private static User getUser(String permissionSet) {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :('테스트 ' + permissionSet)
      LIMIT 1
    ];
  }

  private static CustomerSite__c buildSite(String code) {
    return new CustomerSite__c(
      Name = '테스트 사업장 ' + code,
      Account__c = [SELECT Id FROM Account LIMIT 1]
      .Id,
      RoadAddress__c = '테스트 도로명 1',
      AdminDistrictCode__c = code
    );
  }

  private static String centerOf(Id siteId) {
    return [SELECT ServiceCenter__c FROM CustomerSite__c WHERE Id = :siteId]
    .ServiceCenter__c;
  }

  // 정상: 상담원 등록 → 매핑 센터 자동 (의정부 → 경기북부)
  @isTest
  static void normalCallCenterRegistersWithAutoCenter() {
    CustomerSite__c site = buildSite(UIJEONGBU_CODE);

    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      Database.insert(site, true, AccessLevel.USER_MODE);
    }
    Test.stopTest();

    Assert.areEqual(
      'GyeonggiNorth',
      centerOf(site.Id),
      '상담원 등록 자동 지정'
    );
  }

  // 정상: 센터장도 고르지 않음 — 등록 시 매핑 센터 (서울 → 서울센터). 센터장은 V1.1상 생성 권한이 없어 관리자로 생성 후 센터장이 주소 수정
  @isTest
  static void normalCenterManagerAddressChangeReassigns() {
    CustomerSite__c site = buildSite(SEOUL_CODE);
    insert site;

    Test.startTest();
    System.runAs(getUser('HG_CenterManager')) {
      Database.update(
        new CustomerSite__c(
          Id = site.Id,
          RoadAddress__c = '경기도 의정부시 시민로 1',
          AdminDistrictCode__c = UIJEONGBU_CODE
        ),
        true,
        AccessLevel.USER_MODE
      );
    }
    Test.stopTest();

    Assert.areEqual(
      'GyeonggiNorth',
      centerOf(site.Id),
      '주소를 바꾸면 센터도 매핑대로'
    );
  }

  // 불허: 주소 검색 없이 등록(행정구역 코드 없음) → "주소 검색으로 주소를 선택해 주세요"
  @isTest
  static void rejectInsertWithoutAddressSearch() {
    Database.SaveResult result = Database.insert(buildSite(null), false);

    Assert.isFalse(result.isSuccess(), '거부');
    Assert.areEqual(
      System.Label.MSG_ADDRESS_SEARCH_REQUIRED,
      result.getErrors()[0].getMessage(),
      '안내 문구'
    );
  }

  // 불허: 주소 검색 결과 필드(도로명주소)를 손으로 바꿈(행정구역 코드 그대로) → 거부
  @isTest
  static void rejectManualAddressEdit() {
    CustomerSite__c site = buildSite(SEOUL_CODE);
    insert site;

    Database.SaveResult result = Database.update(
      new CustomerSite__c(Id = site.Id, RoadAddress__c = '손으로 고친 주소'),
      false
    );

    Assert.isFalse(result.isSuccess(), '거부');
    Assert.areEqual(
      System.Label.MSG_ADDRESS_SEARCH_REQUIRED,
      result.getErrors()[0].getMessage(),
      '안내 문구'
    );
  }

  // 정상: 상세주소는 센터와 무관해 자유롭게 고칠 수 있음
  @isTest
  static void normalDetailAddressEditAllowed() {
    CustomerSite__c site = buildSite(SEOUL_CODE);
    insert site;

    Database.SaveResult result = Database.update(
      new CustomerSite__c(Id = site.Id, DetailAddress__c = '3층 기계실'),
      false
    );

    Assert.isTrue(result.isSuccess(), '상세주소 수정 허용');
    Assert.areEqual('Seoul', centerOf(site.Id), '센터 그대로');
  }

  // 불허: 매핑 없는 행정구역 코드 → "관리자에게 매핑 추가를 요청하세요"
  @isTest
  static void rejectUnmappedDistrict() {
    Database.SaveResult result = Database.insert(
      buildSite('9911010100'),
      false
    );

    Assert.isFalse(result.isSuccess(), '거부');
    Assert.areEqual(
      System.Label.MSG_CENTER_NO_MAPPING,
      result.getErrors()[0].getMessage(),
      '안내 문구'
    );
  }

  // 불허: 센터장이 센터를 직접 바꾸려 함 → 필드 읽기 전용으로 거부 (센터장 수동 변경 없앰)
  @isTest
  static void rejectCenterManagerEditsCenterDirectly() {
    CustomerSite__c site = buildSite(SEOUL_CODE);
    insert site;
    Boolean failed = false;

    Test.startTest();
    System.runAs(getUser('HG_CenterManager')) {
      try {
        Database.update(
          new CustomerSite__c(Id = site.Id, ServiceCenter__c = 'GyeonggiSouth'),
          true,
          AccessLevel.USER_MODE
        );
      } catch (Exception e) {
        failed = true;
      }
    }
    Test.stopTest();

    Assert.isTrue(failed, '센터장 직접 변경 거부');
    Assert.areEqual('Seoul', centerOf(site.Id), '센터 그대로');
  }

  // 불허: 필드 권한과 무관한 경로(관리자·시스템)로 센터만 다른 값으로 바꿔도 트리거가 거부
  @isTest
  static void rejectSystemDirectCenterChange() {
    CustomerSite__c site = buildSite(SEOUL_CODE);
    insert site;

    Database.SaveResult result = Database.update(
      new CustomerSite__c(Id = site.Id, ServiceCenter__c = 'GyeonggiSouth'),
      false,
      AccessLevel.SYSTEM_MODE
    );

    Assert.isFalse(result.isSuccess(), '거부');
    Assert.areEqual(
      System.Label.MSG_CENTER_AUTO_ONLY,
      result.getErrors()[0].getMessage(),
      '안내 문구'
    );
  }

  // 벌크: 사업장 200건 한 번에 등록 → 모두 매핑 센터, 매핑 조회는 캐시라 SOQL 거의 없음
  @isTest
  static void bulk200SitesAutoCenter() {
    // PERF: 고객사 조회는 1번, 복제로 200건
    CustomerSite__c seoul = buildSite(SEOUL_CODE);
    CustomerSite__c uijeongbu = buildSite(UIJEONGBU_CODE);
    List<CustomerSite__c> sites = new List<CustomerSite__c>();
    for (Integer i = 0; i < 200; i++) {
      sites.add(Math.mod(i, 2) == 0 ? seoul.clone() : uijeongbu.clone());
    }

    Test.startTest();
    insert sites;
    Integer queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(
      100,
      [SELECT COUNT() FROM CustomerSite__c WHERE ServiceCenter__c = 'Seoul'],
      '서울 100'
    );
    Assert.areEqual(
      100,
      [
        SELECT COUNT()
        FROM CustomerSite__c
        WHERE ServiceCenter__c = 'GyeonggiNorth'
      ],
      '경기북부 100'
    );
    Assert.isTrue(queries <= 5, '200건이어도 조회 몇 번: ' + queries);
  }
}
