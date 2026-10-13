/**
 * @description 테스트 데이터 생성 공통 클래스 (고객사·사업장·장비·접수·출동·부품·재고·사용 부품·테스트 사용자)
 *              build* 는 insert 하지 않고 돌려줌, create* 는 insert 까지 함
 *              모든 값은 org의 Validation Rule을 통과하도록 맞춤 (사업자번호 10자리, 청구 이메일, 사업장 센터, 장비 판매 경로·설치일 근거 등)
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-12
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-12    Edwin     최초 작성 (D6 실습: 테스트 데이터 공통화)
 * ----------------------------------------------------------------------------
 * @see CaseTriggerHandlerTest, CaseStatsServiceTest, WarrantyServiceTest, AssetRepeatFailureBatchTest
 */
@isTest
public class TestDataFactory {
  public static final String STATUS_NEW = 'New';
  public static final String VAN_NAME = '테스트 차량';
  private static final String PROFILE_MINIMUM_ACCESS = 'Minimum Access - Salesforce';
  private static final String PSL_FIELD_SERVICE = 'FieldServiceStandardPsl';

  // DESC: 법인 고객사 (Individual이 아니면 사업자번호·청구 이메일 필수)
  public static Account createAccount() {
    Account account = new Account(
      Name = '테스트 고객사',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Corporation')
        .getRecordTypeId(),
      BusinessRegistrationNumber__c = '1234567890',
      BillingContactEmail__c = 'billing@example.com'
    );
    insert account;
    return account;
  }

  // DESC: 사무실 용도 → 저장 전 Flow가 접수를 긴급으로 바꾸지 않음 (긴급 메일 Flow 미실행)
  public static CustomerSite__c createSite(Id accountId) {
    CustomerSite__c site = new CustomerSite__c(
      Name = '테스트 사업장',
      Account__c = accountId,
      ServiceCenter__c = 'GyeonggiSouth',
      UsageType__c = 'Office'
    );
    insert site;
    return site;
  }

  // DESC: 직판 · 시운전 보고서 근거 · 설치일 기준 보증 장비
  public static Asset buildAsset(
    Id accountId,
    Id siteId,
    String serialKey,
    Date installDate,
    Boolean hasExtendedWarranty
  ) {
    return new Asset(
      Name = '테스트 장비 ' + serialKey,
      SerialKey__c = serialKey,
      AccountId = accountId,
      CustomerSite__c = siteId,
      Status = 'Installed',
      SalesChannel__c = 'Direct',
      InstallationDateSource__c = 'CommissioningReport',
      InstallDate = installDate,
      WarrantyBasis__c = 'InstallationDate',
      HasExtendedWarranty__c = hasExtendedWarranty
    );
  }

  // DESC: 설치일 근거 미확인 + 보증 기준 없음 → 보증 시작일 미확정 장비
  public static Asset buildUnverifiedAsset(
    Id accountId,
    Id siteId,
    String serialKey
  ) {
    return new Asset(
      Name = '보증 미확정 장비',
      SerialKey__c = serialKey,
      AccountId = accountId,
      CustomerSite__c = siteId,
      Status = 'Installed',
      SalesChannel__c = 'Direct',
      InstallationDateSource__c = 'Unverified'
    );
  }

  // DESC: 설치 6개월 된 장비 count대 (시리얼 = prefix + 번호)
  public static List<Asset> createAssets(
    Id accountId,
    Id siteId,
    String serialPrefix,
    Integer count
  ) {
    List<Asset> assets = new List<Asset>();
    for (Integer i = 0; i < count; i++) {
      assets.add(
        buildAsset(
          accountId,
          siteId,
          serialPrefix + i,
          Date.today().addMonths(-6),
          false
        )
      );
    }
    insert assets;
    return assets;
  }

  public static Case buildCase(Id assetId, Integer seq) {
    return new Case(
      AssetId = assetId,
      Subject = '테스트 접수 ' + seq,
      Status = STATUS_NEW,
      Origin = 'Phone'
    );
  }

  // DESC: 장비마다 접수 casesPerAsset건
  public static List<Case> createCases(
    List<Asset> assets,
    Integer casesPerAsset
  ) {
    List<Case> cases = new List<Case>();
    Integer seq = 0;
    for (Asset asset : assets) {
      for (Integer i = 0; i < casesPerAsset; i++) {
        cases.add(buildCase(asset.Id, seq++));
      }
    }
    insert cases;
    return cases;
  }

  // DESC: 접수마다 출동 1건 (출동은 접수에서 만들어야 함: Validation Rule Case_Required)
  public static List<WorkOrder> createWorkOrders(List<Case> cases) {
    List<WorkOrder> workOrders = new List<WorkOrder>();
    for (Case c : cases) {
      workOrders.add(
        new WorkOrder(
          CaseId = c.Id,
          AssetId = c.AssetId,
          Subject = c.Subject,
          Status = 'Assigned'
        )
      );
    }
    insert workOrders;
    return workOrders;
  }

  // DESC: 압축기·일반 부품 각 1종. 결과 Map 키 = Family
  public static Map<String, Product2> createProducts() {
    Map<String, Product2> productsByFamily = new Map<String, Product2>{
      'Compressor' => new Product2(
        Name = '테스트 압축기',
        Family = 'Compressor',
        ErpPartCode__c = 'TEST-CMP',
        ErpUnitPrice__c = 500000,
        IsActive = true
      ),
      'General' => new Product2(
        Name = '테스트 일반 부품',
        Family = 'General',
        ErpPartCode__c = 'TEST-GEN',
        ErpUnitPrice__c = 20000,
        IsActive = true
      )
    };
    insert productsByFamily.values();
    return productsByFamily;
  }

  // DESC: 테스트 차량(재고 위치) + 부품마다 재고. 결과 Map 키 = Family
  public static Map<String, ProductItem> createVanStock(
    Map<String, Product2> productsByFamily,
    Decimal quantity
  ) {
    Schema.Location van = new Schema.Location(
      Name = VAN_NAME,
      LocationType = 'Van',
      IsInventoryLocation = true
    );
    insert van;
    Map<String, ProductItem> itemsByFamily = new Map<String, ProductItem>();
    for (String family : productsByFamily.keySet()) {
      itemsByFamily.put(
        family,
        new ProductItem(
          LocationId = van.Id,
          Product2Id = productsByFamily.get(family).Id,
          QuantityOnHand = quantity
        )
      );
    }
    insert itemsByFamily.values();
    return itemsByFamily;
  }

  // DESC: ProductItemId 방식 사용 부품 (표준 가격표 비활성). 수량 1
  public static ProductConsumed buildPart(Id workOrderId, Id productItemId) {
    return new ProductConsumed(
      WorkOrderId = workOrderId,
      ProductItemId = productItemId,
      QuantityConsumed = 1
    );
  }

  /**
   * @description 최소 권한 프로필 + 권한 집합 사용자 (System.runAs 용)
   *              WARN: 사용자·권한 집합 배정은 설정 오브젝트라 일반 데이터와 같은 트랜잭션에 넣으면 Mixed DML 오류
   *                    → 호출하는 쪽에서 System.runAs(현재 사용자) 블록 안에서 부를 것
   * @param permissionSetName HG_CallCenter / HG_CenterManager / HG_Technician 등
   * @param withFieldService  출동·사용 부품을 다루면 Field Service 권한 집합 라이선스도 배정
   */
  public static User createUser(
    String permissionSetName,
    Boolean withFieldService
  ) {
    String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User user = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = :PROFILE_MINIMUM_ACCESS]
      .Id,
      LastName = '테스트 ' + permissionSetName,
      Alias = 'hgt' + unique.left(5),
      Email = 'hg.test' + unique + '@example.com',
      Username = 'hg.test' + unique + '@hangyeol-as.test',
      TimeZoneSidKey = 'Asia/Seoul',
      LocaleSidKey = 'ko_KR',
      LanguageLocaleKey = 'ko',
      EmailEncodingKey = 'UTF-8'
    );
    insert user;

    if (withFieldService) {
      insert new PermissionSetLicenseAssign(
        AssigneeId = user.Id,
        PermissionSetLicenseId = [
          SELECT Id
          FROM PermissionSetLicense
          WHERE DeveloperName = :PSL_FIELD_SERVICE
        ]
        .Id
      );
    }
    insert new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = :permissionSetName
      ]
      .Id
    );
    return user;
  }
}
