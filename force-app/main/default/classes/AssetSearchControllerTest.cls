/**
 * @description AssetSearchController 테스트 (정상·불허·벌크)
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 실습: LWC 목록 화면 컨트롤러)
 * ----------------------------------------------------------------------------
 * @see AssetSearchController
 */
@isTest
private class AssetSearchControllerTest {
  private static final String SERIAL_PREFIX = 'TEST-SRCH-';

  @TestSetup
  static void setupData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.createUser('HG_CallCenter', false);
      TestDataFactory.createUser('HG_Technician', true);
    }
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    List<Asset> assets = TestDataFactory.createAssets(
      account.Id,
      site.Id,
      SERIAL_PREFIX,
      3
    );
    // DESC: 최근 접수일 0번 = 어제, 1번 = 열흘 전, 2번 = 없음. 0번만 반복 고장 장비
    //       집계 필드는 사용자에게 읽기 전용이라 테스트 데이터 준비도 시스템 모드로
    assets[0].LastCaseDate__c = Date.today().addDays(-1);
    assets[0].RecentCaseCount__c = 3;
    assets[0].RepeatFailure__c = true;
    assets[1].LastCaseDate__c = Date.today().addDays(-10);
    assets[1].RecentCaseCount__c = 1;
    Database.update(assets, AccessLevel.SYSTEM_MODE);
  }

  // 정상: 기본 정렬은 최근 접수일 내림차순, 접수 없는 장비는 맨 뒤
  @isTest
  static void normalDefaultSortRecentFirstNullsLast() {
    Test.startTest();
    AssetSearchController.AssetPage page = AssetSearchController.searchAssets(
      null,
      false,
      null,
      null,
      1
    );
    Test.stopTest();

    Assert.areEqual(3, page.totalCount, '전체 장비 수');
    Assert.areEqual(1, page.pageNumber, '첫 페이지');
    Assert.areEqual(
      SERIAL_PREFIX + '0',
      page.rows[0].serialKey,
      '어제 접수가 맨 위'
    );
    Assert.areEqual(
      SERIAL_PREFIX + '1',
      page.rows[1].serialKey,
      '열흘 전이 두 번째'
    );
    Assert.areEqual(
      SERIAL_PREFIX + '2',
      page.rows[2].serialKey,
      '접수 없는 장비는 맨 뒤'
    );
    Assert.isTrue(page.rows[0].repeatFailure, '반복 고장 장비 표시값 전달');
    Assert.areEqual(
      '테스트 고객사',
      page.rows[0].accountName,
      '고객사명 평탄화'
    );
    Assert.areEqual('테스트 사업장', page.rows[0].siteName, '사업장명 평탄화');
  }

  // 정상: 오름차순으로 바꿔도 값이 없는 장비는 맨 뒤
  @isTest
  static void normalAscendingKeepsNullsLast() {
    Test.startTest();
    AssetSearchController.AssetPage page = AssetSearchController.searchAssets(
      null,
      false,
      'lastCaseDate',
      'asc',
      1
    );
    Test.stopTest();

    Assert.areEqual(
      SERIAL_PREFIX + '1',
      page.rows[0].serialKey,
      '오래된 접수가 맨 위'
    );
    Assert.areEqual(
      SERIAL_PREFIX + '2',
      page.rows[2].serialKey,
      '접수 없는 장비는 여전히 맨 뒤'
    );
  }

  // 정상: 고객사·사업장·시리얼 일부로 검색
  @isTest
  static void normalSearchByAccountSiteSerial() {
    Test.startTest();
    Integer bySerial = AssetSearchController.searchAssets(
        SERIAL_PREFIX + '1',
        false,
        null,
        null,
        1
      )
      .totalCount;
    Integer bySite = AssetSearchController.searchAssets(
        '사업장',
        false,
        null,
        null,
        1
      )
      .totalCount;
    Integer byAccount = AssetSearchController.searchAssets(
        '테스트 고객',
        false,
        null,
        null,
        1
      )
      .totalCount;
    Integer noMatch = AssetSearchController.searchAssets(
        '없는장비',
        false,
        null,
        null,
        1
      )
      .totalCount;
    Test.stopTest();

    Assert.areEqual(1, bySerial, '시리얼 일부');
    Assert.areEqual(3, bySite, '사업장명 일부');
    Assert.areEqual(3, byAccount, '고객사명 일부');
    Assert.areEqual(0, noMatch, '일치 없음');
  }

  // 정상: "반복 고장 장비만" 필터
  @isTest
  static void normalRepeatOnlyFilter() {
    Test.startTest();
    AssetSearchController.AssetPage page = AssetSearchController.searchAssets(
      null,
      true,
      null,
      null,
      1
    );
    Test.stopTest();

    Assert.areEqual(1, page.totalCount, '반복 고장 장비 1대');
    Assert.areEqual(
      SERIAL_PREFIX + '0',
      page.rows[0].serialKey,
      '반복 고장 장비'
    );
  }

  // 정상: 상담원 사용자로 실행 (화면 실제 사용자)
  @isTest
  static void normalCallCenterUserSearches() {
    User callCenter = [
      SELECT Id
      FROM User
      WHERE LastName = '테스트 HG_CallCenter'
      LIMIT 1
    ];
    AssetSearchController.AssetPage page;

    Test.startTest();
    System.runAs(callCenter) {
      page = AssetSearchController.searchAssets(
        SERIAL_PREFIX,
        false,
        null,
        null,
        1
      );
    }
    Test.stopTest();

    Assert.areEqual(3, page.totalCount, '상담원은 장비를 검색할 수 있음');
  }

  // 불허: 허용 목록에 없는 정렬값(인젝션 시도)·1글자 검색어·범위 밖 페이지는 기본값으로 처리
  @isTest
  static void rejectInvalidInputsFallBackToDefaults() {
    Test.startTest();
    AssetSearchController.AssetPage injected = AssetSearchController.searchAssets(
      null,
      false,
      'Name DESC; DELETE',
      'sideways',
      1
    );
    AssetSearchController.AssetPage oneChar = AssetSearchController.searchAssets(
      '테',
      false,
      null,
      null,
      1
    );
    AssetSearchController.AssetPage tooFar = AssetSearchController.searchAssets(
      null,
      false,
      null,
      null,
      99
    );
    AssetSearchController.AssetPage negative = AssetSearchController.searchAssets(
      null,
      false,
      null,
      null,
      -5
    );
    Test.stopTest();

    Assert.areEqual(
      SERIAL_PREFIX + '0',
      injected.rows[0].serialKey,
      '허용되지 않은 정렬 → 최근 접수일 내림차순'
    );
    Assert.areEqual(3, oneChar.totalCount, '1글자는 검색 조건 없이 전체');
    Assert.areEqual(
      1,
      tooFar.pageNumber,
      '마지막 페이지를 넘으면 마지막 페이지로'
    );
    Assert.areEqual(1, negative.pageNumber, '1보다 작으면 첫 페이지');
  }

  // 불허: 장비 권한이 없는 협력 기사는 조회 불가 → 화면에 표시할 오류
  @isTest
  static void rejectTechnicianWithoutAssetAccess() {
    User technician = [
      SELECT Id
      FROM User
      WHERE LastName = '테스트 HG_Technician'
      LIMIT 1
    ];
    AuraHandledException caught;

    Test.startTest();
    System.runAs(technician) {
      try {
        AssetSearchController.searchAssets(null, false, null, null, 1);
      } catch (AuraHandledException e) {
        caught = e;
      }
    }
    Test.stopTest();

    Assert.isNotNull(caught, '기사는 장비 목록을 볼 수 없음');
    Assert.isFalse(
      String.isBlank(caught.getMessage()),
      '화면에 보일 오류 메시지'
    );
  }

  // 벌크: 장비 203대 → 20건씩, 마지막 페이지 3건
  @isTest
  static void bulkPagingOver200Assets() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    CustomerSite__c site = [SELECT Id FROM CustomerSite__c LIMIT 1];
    TestDataFactory.createAssets(account.Id, site.Id, 'TEST-BULK-', 200);

    Test.startTest();
    AssetSearchController.AssetPage first = AssetSearchController.searchAssets(
      null,
      false,
      'serialKey',
      'asc',
      1
    );
    AssetSearchController.AssetPage last = AssetSearchController.searchAssets(
      null,
      false,
      'serialKey',
      'asc',
      11
    );
    Test.stopTest();

    Assert.areEqual(203, first.totalCount, '전체 203대');
    Assert.areEqual(
      AssetSearchController.PAGE_SIZE,
      first.rows.size(),
      '한 페이지 20건'
    );
    Assert.areEqual(11, last.pageNumber, '11쪽');
    Assert.areEqual(3, last.rows.size(), '마지막 페이지 3건');
  }
}
