/**
 * @description AssetDetailController 테스트 (정상·불허·벌크)
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 실습: LWC 상세 화면 컨트롤러)
 * ----------------------------------------------------------------------------
 * @see AssetDetailController
 */
@isTest
private class AssetDetailControllerTest {
  @TestSetup
  static void setupData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.createUser('HG_Technician', true);
    }
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    TestDataFactory.createAssets(account.Id, site.Id, 'TEST-DTL-', 2);
  }

  // 정상: 접수 6건 → 최근 5건만 최신순, 전체 6건 ("모두 보기" 표시 기준)
  @isTest
  static void normalReturnsLatestFiveNewestFirst() {
    Asset asset = getAsset(0);
    List<Case> cases = TestDataFactory.createCases(new List<Asset>{ asset }, 6);
    // DESC: 생성일을 하루씩 다르게 해서 정렬을 확인 (0번이 가장 오래됨)
    for (Integer i = 0; i < cases.size(); i++) {
      Test.setCreatedDate(cases[i].Id, Datetime.now().addDays(i - 10));
    }

    Test.startTest();
    AssetDetailController.RecentCases result = AssetDetailController.getRecentCases(
      asset.Id
    );
    Test.stopTest();

    Assert.areEqual(6, result.totalCount, '전체 접수 수');
    Assert.areEqual(
      AssetDetailController.RECENT_CASE_LIMIT,
      result.rows.size(),
      '최근 5건만'
    );
    Assert.areEqual(cases[5].Id, result.rows[0].id, '가장 최근 접수가 맨 위');
    Assert.areEqual(cases[1].Id, result.rows[4].id, '가장 오래된 0번은 제외');
    Assert.isNotNull(result.rows[0].status, '상태(표시 라벨) 전달');
  }

  // 정상: 접수 없는 장비·Id 없음 → 빈 목록 (오류 아님)
  @isTest
  static void normalNoCasesReturnsEmpty() {
    Test.startTest();
    AssetDetailController.RecentCases none = AssetDetailController.getRecentCases(
      getAsset(1).Id
    );
    AssetDetailController.RecentCases nullId = AssetDetailController.getRecentCases(
      null
    );
    Test.stopTest();

    Assert.areEqual(0, none.totalCount, '접수 없음');
    Assert.isTrue(none.rows.isEmpty(), '행 없음');
    Assert.areEqual(0, nullId.totalCount, 'Id 없음은 빈 결과');
  }

  // 정상: 다른 장비의 접수는 섞이지 않음
  @isTest
  static void normalOnlyThisAssetCases() {
    TestDataFactory.createCases(new List<Asset>{ getAsset(0) }, 2);
    TestDataFactory.createCases(new List<Asset>{ getAsset(1) }, 3);

    Test.startTest();
    AssetDetailController.RecentCases result = AssetDetailController.getRecentCases(
      getAsset(1).Id
    );
    Test.stopTest();

    Assert.areEqual(3, result.totalCount, '1번 장비 접수만');
  }

  // 불허: 접수 권한이 없는 협력 기사 → 화면에 표시할 오류
  @isTest
  static void rejectTechnicianWithoutCaseAccess() {
    Asset asset = getAsset(0);
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
        AssetDetailController.getRecentCases(asset.Id);
      } catch (AuraHandledException e) {
        caught = e;
      }
    }
    Test.stopTest();

    Assert.isNotNull(caught, '기사는 접수 목록을 볼 수 없음');
  }

  // 벌크: 접수 200건 장비 → 5건만 반환, 전체 200
  @isTest
  static void bulkTwoHundredCasesReturnsFive() {
    Asset asset = getAsset(0);
    TestDataFactory.createCases(new List<Asset>{ asset }, 200);

    Test.startTest();
    AssetDetailController.RecentCases result = AssetDetailController.getRecentCases(
      asset.Id
    );
    Integer soql = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(200, result.totalCount, '전체 200건');
    Assert.areEqual(5, result.rows.size(), '5건만');
    Assert.areEqual(2, soql, '건수와 상관없이 조회 2회');
  }

  private static Asset getAsset(Integer index) {
    return [SELECT Id FROM Asset WHERE SerialKey__c = :('TEST-DTL-' + index)];
  }
}
