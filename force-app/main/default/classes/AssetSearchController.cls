/**
 * @description 장비 검색 목록 화면(SC-01 assetSearch) 컨트롤러
 *              고객사명·사업장명·시리얼 검색, "반복 고장 장비만" 필터, 서버 정렬, 20건 페이징
 *              기본 정렬: 최근 접수일 내림차순, 접수 없는 장비는 맨 뒤 (D6 화면 설계 결정)
 * @layer       Controller
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 실습: LWC 목록 화면)
 * ----------------------------------------------------------------------------
 * @see assetSearch (LWC), docs/d6_screen_design.md SC-01
 */
// DESC: 화면은 실행 사용자 권한대로 보여야 하므로 with sharing + 조회 USER_MODE (API 67.0 기본도 user mode지만 명시)
public with sharing class AssetSearchController {
  public static final Integer PAGE_SIZE = 20;
  // DESC: SOQL OFFSET 최대값. 넘는 페이지는 마지막 가능 페이지로 맞춤 (장비 수가 늘면 키셋 페이징으로 전환)
  private static final Integer MAX_OFFSET = 2000;
  private static final Integer MIN_SEARCH_LENGTH = 2;
  private static final String DEFAULT_SORT_FIELD = 'lastCaseDate';
  private static final String DIRECTION_ASC = 'asc';

  // DESC: 화면 열 이름 → SOQL 필드. 이 목록에 있는 필드로만 정렬 (SOQL 인젝션 방어)
  private static final Map<String, String> SORT_FIELDS_BY_COLUMN = new Map<String, String>{
    'serialKey' => 'SerialKey__c',
    'accountName' => 'Account.Name',
    'warrantyStatus' => 'fmWarrantyStatus__c',
    'lastCaseDate' => 'LastCaseDate__c',
    'recentCaseCount' => 'RecentCaseCount__c'
  };

  /**
   * @description 장비 검색 (한 페이지)
   * @param searchKey     고객사명·사업장명·시리얼 일부. 2글자 미만이면 검색 조건 없이 전체
   * @param repeatOnly    true면 반복 고장 장비만
   * @param sortField     화면 열 이름 (SORT_FIELDS_BY_COLUMN 키). 없거나 허용되지 않으면 최근 접수일
   * @param sortDirection asc / desc (그 외는 desc)
   * @param pageNumber    1부터
   * @return 해당 페이지 행 + 전체 건수
   */
  @AuraEnabled(cacheable=true)
  public static AssetPage searchAssets(
    String searchKey,
    Boolean repeatOnly,
    String sortField,
    String sortDirection,
    Integer pageNumber
  ) {
    try {
      Map<String, Object> bindsByName = new Map<String, Object>();
      String whereClause = buildWhere(searchKey, repeatOnly, bindsByName);

      Integer totalCount = Database.countQueryWithBinds(
        'SELECT COUNT() FROM Asset' + whereClause,
        bindsByName,
        AccessLevel.USER_MODE
      );

      Integer page = normalizePage(pageNumber, totalCount);
      bindsByName.put('pageSize', PAGE_SIZE);
      bindsByName.put('offsetRows', (page - 1) * PAGE_SIZE);

      String query =
        'SELECT Id, Name, SerialKey__c, Product2.Name, Account.Name, CustomerSite__r.Name, ' +
        'toLabel(CustomerSite__r.ServiceCenter__c), fmWarrantyStatus__c, LastCaseDate__c, ' +
        'RecentCaseCount__c, RepeatFailure__c FROM Asset' +
        whereClause +
        buildOrderBy(sortField, sortDirection) +
        ' LIMIT :pageSize OFFSET :offsetRows';

      AssetPage result = new AssetPage();
      result.totalCount = totalCount;
      result.pageNumber = page;
      result.pageSize = PAGE_SIZE;
      for (
        Asset asset : (List<Asset>) Database.queryWithBinds(
          query,
          bindsByName,
          AccessLevel.USER_MODE
        )
      ) {
        result.rows.add(new AssetRow(asset));
      }
      return result;
    } catch (Exception e) {
      // WARN: 권한 없는 사용자(기사 등)는 USER_MODE 조회에서 예외 → 화면에는 읽을 수 있는 메시지로
      throw newAuraException(e.getMessage());
    }
  }

  private static String buildWhere(
    String searchKey,
    Boolean repeatOnly,
    Map<String, Object> bindsByName
  ) {
    List<String> conditions = new List<String>();
    String key = String.isBlank(searchKey) ? '' : searchKey.trim();
    if (key.length() >= MIN_SEARCH_LENGTH) {
      // DESC: 사용자 입력은 바인드 변수로만 SOQL에 들어감 (쿼리 문자열에 붙이지 않음)
      bindsByName.put('searchKey', '%' + key + '%');
      conditions.add(
        '(Account.Name LIKE :searchKey OR CustomerSite__r.Name LIKE :searchKey OR SerialKey__c LIKE :searchKey)'
      );
    }
    if (repeatOnly == true) {
      conditions.add('RepeatFailure__c = TRUE');
    }
    return conditions.isEmpty()
      ? ''
      : ' WHERE ' + String.join(conditions, ' AND ');
  }

  private static String buildOrderBy(String sortField, String sortDirection) {
    String field = SORT_FIELDS_BY_COLUMN.containsKey(sortField)
      ? SORT_FIELDS_BY_COLUMN.get(sortField)
      : SORT_FIELDS_BY_COLUMN.get(DEFAULT_SORT_FIELD);
    String direction = DIRECTION_ASC.equalsIgnoreCase(sortDirection)
      ? 'ASC'
      : 'DESC';
    // DESC: 값이 빈 장비(접수 없음 등)는 방향과 상관없이 맨 뒤, 같은 값은 시리얼 순
    return ' ORDER BY ' +
      field +
      ' ' +
      direction +
      ' NULLS LAST, SerialKey__c ASC';
  }

  // DESC: 1보다 작으면 1, 마지막 페이지·OFFSET 상한을 넘으면 갈 수 있는 마지막 페이지로
  private static Integer normalizePage(Integer pageNumber, Integer totalCount) {
    Integer page = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
    Integer lastPage = Math.max(
      1,
      ((Decimal) totalCount / PAGE_SIZE)
        .round(System.RoundingMode.CEILING)
        .intValue()
    );
    Integer lastReachablePage = MAX_OFFSET / PAGE_SIZE + 1;
    return Math.min(page, Math.min(lastPage, lastReachablePage));
  }

  private static AuraHandledException newAuraException(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }

  /**
   * @description 검색 결과 한 페이지
   */
  public class AssetPage {
    @AuraEnabled
    public List<AssetRow> rows = new List<AssetRow>();
    @AuraEnabled
    public Integer totalCount;
    @AuraEnabled
    public Integer pageNumber;
    @AuraEnabled
    public Integer pageSize;
  }

  /**
   * @description 목록 한 행 (lightning-datatable은 평평한 필드만 표시하므로 관계 필드를 풀어서 담음)
   */
  public class AssetRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String serialKey;
    @AuraEnabled
    public String model;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String siteName;
    @AuraEnabled
    public String serviceCenter;
    @AuraEnabled
    public String warrantyStatus;
    @AuraEnabled
    public Date lastCaseDate;
    @AuraEnabled
    public Decimal recentCaseCount;
    @AuraEnabled
    public Boolean repeatFailure;

    AssetRow(Asset asset) {
      this.id = asset.Id;
      this.serialKey = asset.SerialKey__c;
      this.model = asset.Product2 != null ? asset.Product2.Name : asset.Name;
      this.accountName = asset.Account?.Name;
      this.siteName = asset.CustomerSite__r?.Name;
      this.serviceCenter = asset.CustomerSite__r?.ServiceCenter__c;
      this.warrantyStatus = asset.fmWarrantyStatus__c;
      this.lastCaseDate = asset.LastCaseDate__c;
      this.recentCaseCount = asset.RecentCaseCount__c;
      this.repeatFailure = asset.RepeatFailure__c;
    }
  }
}
