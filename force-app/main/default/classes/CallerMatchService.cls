/**
 * @description 가상 착신(CTI 시뮬레이터) 발신자 찾기 + 장비 확정 판정
 *              발신 번호 → 사업장 현장 담당자 번호 → 사업장 보조 연락처 → 고객사 대표 번호 순으로 찾고,
 *              찾은 사업장·고객사 안에서만 시리얼 뒤 4자리로 장비를 좁힘 (시리얼만으로 전체에서 확정하지 않음)
 *              팝업 규칙: 1건 → 채움, 여러 건 → 후보, 없음 → 검색
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-15    Edwin     최초 작성 (CTI 가상 착신 시뮬레이터)
 * 1.1    2026-10-15    Edwin     모델 없는 장비 = "모델 미지정" (피드백 개선 ④)
 * ----------------------------------------------------------------------------
 * @see CallIntakeController, callSimulator · caseIntakeModal (LWC)
 */
// DESC: 화면(상담원)이 볼 수 있는 고객 정보만 찾아야 하므로 시스템 계산 서비스와 달리 조회 모두 USER_MODE
//       (권한 없는 사용자는 조회 단계에서 예외 → 컨트롤러가 화면 메시지로 바꿈)
public inherited sharing class CallerMatchService {
  public static final String MATCHED_BY_ONSITE = 'ONSITE';
  public static final String MATCHED_BY_SECONDARY = 'SECONDARY';
  public static final String MATCHED_BY_ACCOUNT = 'ACCOUNT';
  public static final String MATCHED_BY_NONE = 'NONE';

  public static final String OUTCOME_CONFIRMED = 'CONFIRMED';
  public static final String OUTCOME_ASSET_CANDIDATES = 'ASSET_CANDIDATES';
  public static final String OUTCOME_SITE_CANDIDATES = 'SITE_CANDIDATES';
  public static final String OUTCOME_ACCOUNT_CANDIDATES = 'ACCOUNT_CANDIDATES';
  public static final String OUTCOME_NOT_FOUND = 'NOT_FOUND';

  // DESC: 국번 없는 7자리(지역 번호 생략)보다 짧으면 번호로 보지 않음
  private static final Integer MIN_PHONE_DIGITS = 7;
  private static final Integer SERIAL_SUFFIX_LENGTH = 4;
  // DESC: SOSL 오브젝트별 반환 상한 · 후보 목록 상한 (한 사업장 장비 수백 대까지 한 번에 표시)
  private static final Integer SEARCH_LIMIT = 200;
  private static final Integer CANDIDATE_LIMIT = 500;

  /**
   * @description 발신자 찾기 + 장비 확정 판정
   * @param callerPhone  발신 번호 (하이픈·공백 무관)
   * @param serialSuffix 시리얼 뒤 4자리 (# 또는 빈 값 = 모름)
   * @return 판정 결과 (채울 값 + 후보 목록)
   */
  public static MatchResult match(String callerPhone, String serialSuffix) {
    MatchResult result = new MatchResult();
    result.callerPhone = String.isBlank(callerPhone) ? '' : callerPhone.trim();
    result.serialSuffix = normalizeSuffix(serialSuffix);

    String digits = toDigits(callerPhone);
    if (digits.length() < MIN_PHONE_DIGITS) {
      return result;
    }

    // DESC: SOSL PHONE FIELDS는 저장 형식(하이픈 유무·공백)과 무관하게 찾음 (2026-10-15 devorg 확인)
    //       어느 필드가 일치했는지는 숫자만 비교해서 다시 가름 (우선순위 판단 + 부분 일치 제외)
    List<List<SObject>> found = [
      FIND :digits
      IN PHONE FIELDS
      RETURNING
        CustomerSite__c(
          Id,
          Name,
          Account__c,
          Account__r.Name,
          OnSiteContactPhone__c,
          SecondaryContactPhone__c
          ORDER BY Name
          LIMIT :SEARCH_LIMIT
        ),
        Account(Id, Name, Phone ORDER BY Name LIMIT :SEARCH_LIMIT)
      WITH USER_MODE
    ];

    List<CustomerSite__c> onSiteMatches = new List<CustomerSite__c>();
    List<CustomerSite__c> secondaryMatches = new List<CustomerSite__c>();
    for (CustomerSite__c site : (List<CustomerSite__c>) found[0]) {
      if (toDigits(site.OnSiteContactPhone__c) == digits) {
        onSiteMatches.add(site);
      } else if (toDigits(site.SecondaryContactPhone__c) == digits) {
        secondaryMatches.add(site);
      }
    }
    List<Account> accountMatches = new List<Account>();
    for (Account account : (List<Account>) found[1]) {
      if (toDigits(account.Phone) == digits) {
        accountMatches.add(account);
      }
    }

    if (!onSiteMatches.isEmpty()) {
      result.matchedBy = MATCHED_BY_ONSITE;
      resolveBySites(result, onSiteMatches);
    } else if (!secondaryMatches.isEmpty()) {
      result.matchedBy = MATCHED_BY_SECONDARY;
      resolveBySites(result, secondaryMatches);
    } else if (!accountMatches.isEmpty()) {
      result.matchedBy = MATCHED_BY_ACCOUNT;
      resolveByAccounts(result, accountMatches);
    }
    fillChoices(result);
    return result;
  }

  /**
   * @description 장비 하나로 접수 작성 팝업을 채울 값 (장비 검색 → 장비 요약 → "이 장비로 접수")
   * @param assetId 장비 Id
   * @return 장비·사업장·고객사가 채워진 결과 (+ 바꿀 수 있도록 후보 목록)
   */
  public static MatchResult forAsset(Id assetId) {
    MatchResult result = new MatchResult();
    List<Asset> assets = [
      SELECT
        Id,
        Name,
        SerialKey__c,
        Product2.Name,
        AccountId,
        Account.Name,
        CustomerSite__c,
        CustomerSite__r.Name
      FROM Asset
      WHERE Id = :assetId
      WITH USER_MODE
    ];
    if (!assets.isEmpty()) {
      confirmAsset(result, assets[0]);
      fillChoices(result);
    }
    return result;
  }

  /**
   * @description 고객사의 사업장 후보 (팝업에서 고객사를 고르거나 바꿨을 때)
   */
  public static List<SiteOption> getSites(Id accountId) {
    List<SiteOption> options = new List<SiteOption>();
    if (accountId == null) {
      return options;
    }
    for (CustomerSite__c site : querySites(new Set<Id>{ accountId })) {
      options.add(new SiteOption(site));
    }
    return options;
  }

  /**
   * @description 사업장(없으면 고객사) 안의 장비 후보 + 확정할 장비
   *              시리얼 일치 1대 → 그 장비 선택 / 2대 이상 → 일치한 장비만 / 없음 → 전부, 1대뿐이면 선택
   */
  public static AssetChoice getAssets(
    Id accountId,
    Id siteId,
    String serialSuffix
  ) {
    List<Asset> scope = new List<Asset>();
    if (siteId != null) {
      scope = queryAssetsBySites(new Set<Id>{ siteId });
    } else if (accountId != null) {
      scope = queryAssetsByAccounts(new Set<Id>{ accountId });
    }
    return chooseAsset(scope, normalizeSuffix(serialSuffix));
  }

  // DESC: 같은 번호의 사업장이 1곳이면 그 사업장 장비로, 여러 곳이면 그 사업장들 장비 중 시리얼 일치 1대일 때만 확정
  private static void resolveBySites(
    MatchResult result,
    List<CustomerSite__c> sites
  ) {
    Set<Id> siteIds = new Set<Id>();
    Set<Id> accountIds = new Set<Id>();
    for (CustomerSite__c site : sites) {
      siteIds.add(site.Id);
      accountIds.add(site.Account__c);
      result.sites.add(new SiteOption(site));
    }
    if (accountIds.size() == 1) {
      result.accountId = sites[0].Account__c;
      result.accountName = sites[0].Account__r?.Name;
    }
    if (sites.size() == 1) {
      result.siteId = sites[0].Id;
      result.siteName = sites[0].Name;
    }

    AssetChoice choice = chooseAsset(
      queryAssetsBySites(siteIds),
      result.serialSuffix
    );
    applyChoice(result, choice, sites.size() == 1);
  }

  // DESC: 대표 번호는 고객사만 알려 줌 → 그 고객사 장비 중 시리얼 일치 1대면 사업장·장비까지 채움, 아니면 사업장 후보
  private static void resolveByAccounts(
    MatchResult result,
    List<Account> accounts
  ) {
    Set<Id> accountIds = new Set<Id>();
    for (Account account : accounts) {
      accountIds.add(account.Id);
      result.accounts.add(new Option(account.Id, account.Name));
    }
    if (accounts.size() == 1) {
      result.accountId = accounts[0].Id;
      result.accountName = accounts[0].Name;
    }

    List<Asset> accountAssets = queryAssetsByAccounts(accountIds);
    AssetChoice serialChoice = chooseAsset(accountAssets, result.serialSuffix);
    if (serialChoice.serialMatchCount > 0) {
      applyChoice(result, serialChoice, false);
      return;
    }
    if (accounts.size() > 1) {
      result.outcome = OUTCOME_ACCOUNT_CANDIDATES;
      return;
    }

    List<CustomerSite__c> sites = querySites(accountIds);
    for (CustomerSite__c site : sites) {
      result.sites.add(new SiteOption(site));
    }
    if (sites.size() > 1) {
      result.outcome = OUTCOME_SITE_CANDIDATES;
      return;
    }
    // DESC: 사업장이 1곳이면 그 사업장으로 (1건 → 채움), 사업장 없는 고객사면 고객사 장비 전체로
    List<Asset> scope = accountAssets;
    if (sites.size() == 1) {
      result.siteId = sites[0].Id;
      result.siteName = sites[0].Name;
      scope = new List<Asset>();
      for (Asset asset : accountAssets) {
        if (asset.CustomerSite__c == sites[0].Id) {
          scope.add(asset);
        }
      }
    }
    applyChoice(result, chooseAsset(scope, result.serialSuffix), true);
  }

  // DESC: 장비 선택 결과를 판정 결과에 반영. singleScope = 범위가 사업장 1곳(또는 고객사 1곳의 전체)인지
  private static void applyChoice(
    MatchResult result,
    AssetChoice choice,
    Boolean singleScope
  ) {
    result.serialMatchCount = choice.serialMatchCount;
    if (choice.selected != null) {
      confirmAsset(result, choice.selected);
      return;
    }
    if (choice.serialMatchCount > 1 || singleScope) {
      result.assets = choice.assets;
      result.outcome = OUTCOME_ASSET_CANDIDATES;
      fillScopeFromCandidates(result, choice.assets);
      return;
    }
    result.outcome = OUTCOME_SITE_CANDIDATES;
  }

  // DESC: 후보 장비가 모두 같은 사업장·고객사면 그 값도 채움 (시리얼 다중 일치가 한 사업장 안일 때)
  private static void fillScopeFromCandidates(
    MatchResult result,
    List<AssetOption> candidates
  ) {
    Set<Id> siteIds = new Set<Id>();
    Set<Id> accountIds = new Set<Id>();
    for (AssetOption candidate : candidates) {
      siteIds.add(candidate.siteId);
      accountIds.add(candidate.accountId);
    }
    if (result.accountId == null && accountIds.size() == 1) {
      result.accountId = candidates[0].accountId;
      result.accountName = candidates[0].accountName;
    }
    if (result.siteId == null && siteIds.size() == 1) {
      result.siteId = candidates[0].siteId;
      result.siteName = candidates[0].siteName;
    }
  }

  private static void confirmAsset(MatchResult result, Asset asset) {
    result.outcome = OUTCOME_CONFIRMED;
    result.assetId = asset.Id;
    result.assetLabel = new AssetOption(asset, null).label;
    result.accountId = asset.AccountId;
    result.accountName = asset.Account?.Name;
    result.siteId = asset.CustomerSite__c;
    result.siteName = asset.CustomerSite__r?.Name;
  }

  // DESC: 팝업에서 바로 다른 사업장·장비로 바꿀 수 있게 후보 목록을 채움
  //       자동 판정은 찾은 사업장 안에서만 했지만, 상담원이 고르는 목록은 고객사의 사업장 전체
  //       (사업장 후보 판정이면 찾은 사업장만 보여 줌)
  private static void fillChoices(MatchResult result) {
    if (result.accountId != null && result.outcome != OUTCOME_SITE_CANDIDATES) {
      result.sites = getSites(result.accountId);
    }
    if (result.siteId != null && result.assets.isEmpty()) {
      result.assets = chooseAsset(
          queryAssetsBySites(new Set<Id>{ result.siteId }),
          null
        )
        .assets;
    }
  }

  private static AssetChoice chooseAsset(List<Asset> scope, String suffix) {
    AssetChoice choice = new AssetChoice();
    List<Asset> serialMatches = new List<Asset>();
    if (suffix != null) {
      for (Asset asset : scope) {
        if (asset.SerialKey__c != null && asset.SerialKey__c.endsWith(suffix)) {
          serialMatches.add(asset);
        }
      }
    }
    choice.serialMatchCount = serialMatches.size();
    List<Asset> shown = serialMatches.isEmpty() ? scope : serialMatches;
    for (Asset asset : shown) {
      choice.assets.add(new AssetOption(asset, suffix));
    }
    if (shown.size() == 1) {
      choice.selected = shown[0];
      choice.selectedAssetId = shown[0].Id;
    }
    return choice;
  }

  private static List<CustomerSite__c> querySites(Set<Id> accountIds) {
    return [
      SELECT Id, Name, Account__c, Account__r.Name
      FROM CustomerSite__c
      WHERE Account__c IN :accountIds
      WITH USER_MODE
      ORDER BY Name
      LIMIT :CANDIDATE_LIMIT
    ];
  }

  private static List<Asset> queryAssetsBySites(Set<Id> siteIds) {
    return [
      SELECT
        Id,
        Name,
        SerialKey__c,
        Product2.Name,
        AccountId,
        Account.Name,
        CustomerSite__c,
        CustomerSite__r.Name
      FROM Asset
      WHERE CustomerSite__c IN :siteIds
      WITH USER_MODE
      ORDER BY SerialKey__c
      LIMIT :CANDIDATE_LIMIT
    ];
  }

  private static List<Asset> queryAssetsByAccounts(Set<Id> accountIds) {
    return [
      SELECT
        Id,
        Name,
        SerialKey__c,
        Product2.Name,
        AccountId,
        Account.Name,
        CustomerSite__c,
        CustomerSite__r.Name
      FROM Asset
      WHERE AccountId IN :accountIds
      WITH USER_MODE
      ORDER BY SerialKey__c
      LIMIT :CANDIDATE_LIMIT
    ];
  }

  @TestVisible
  private static String toDigits(String value) {
    return String.isBlank(value) ? '' : value.replaceAll('[^0-9]', '');
  }

  // DESC: 숫자 4자리일 때만 시리얼 조건으로 씀 (#·빈 값·자릿수 다름 = 모름)
  @TestVisible
  private static String normalizeSuffix(String value) {
    String digits = toDigits(value);
    return digits.length() == SERIAL_SUFFIX_LENGTH ? digits : null;
  }

  /**
   * @description 판정 결과. outcome·matchedBy 값은 위 상수
   */
  public class MatchResult {
    @AuraEnabled
    public String outcome = OUTCOME_NOT_FOUND;
    @AuraEnabled
    public String matchedBy = MATCHED_BY_NONE;
    @AuraEnabled
    public String callerPhone;
    @AuraEnabled
    public String serialSuffix;
    @AuraEnabled
    public Integer serialMatchCount = 0;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Id siteId;
    @AuraEnabled
    public String siteName;
    @AuraEnabled
    public Id assetId;
    @AuraEnabled
    public String assetLabel;
    @AuraEnabled
    public List<Option> accounts = new List<Option>();
    @AuraEnabled
    public List<SiteOption> sites = new List<SiteOption>();
    @AuraEnabled
    public List<AssetOption> assets = new List<AssetOption>();
  }

  /**
   * @description 장비 후보 + 확정된 장비 (1대뿐이거나 시리얼 일치 1대)
   */
  public class AssetChoice {
    @AuraEnabled
    public List<AssetOption> assets = new List<AssetOption>();
    @AuraEnabled
    public Id selectedAssetId;
    @AuraEnabled
    public Integer serialMatchCount = 0;
    public Asset selected;
  }

  // DESC: 후보 클래스는 상속 없이 각자 id·label을 가짐 (@AuraEnabled 직렬화에서 부모 필드 누락 방지)

  /**
   * @description 고객사 후보 한 줄
   */
  public class Option {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String label;

    public Option(Id id, String label) {
      this.id = id;
      this.label = label;
    }
  }

  /**
   * @description 사업장 후보 한 줄 (번호가 여러 고객사에 걸칠 수 있어 고객사도 담음)
   */
  public class SiteOption {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;

    public SiteOption(CustomerSite__c site) {
      this.id = site.Id;
      this.label = site.Name;
      this.accountId = site.Account__c;
      this.accountName = site.Account__r?.Name;
    }
  }

  /**
   * @description 장비 후보 한 줄
   */
  public class AssetOption {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String serialKey;
    @AuraEnabled
    public String model;
    @AuraEnabled
    public Id siteId;
    @AuraEnabled
    public String siteName;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Boolean serialMatched = false;

    public AssetOption(Asset asset, String suffix) {
      this.id = asset.Id;
      this.serialKey = asset.SerialKey__c;
      // DESC: 모델 없는 장비는 "모델 미지정" (예전에는 장비 이름을 대신 보여 줘 모델처럼 보였음)
      this.model = asset.Product2 != null
        ? asset.Product2.Name
        : System.Label.LABEL_MODEL_UNSPECIFIED;
      this.siteId = asset.CustomerSite__c;
      this.siteName = asset.CustomerSite__r?.Name;
      this.accountId = asset.AccountId;
      this.accountName = asset.Account?.Name;
      this.serialMatched =
        suffix != null &&
        asset.SerialKey__c != null &&
        asset.SerialKey__c.endsWith(suffix);
      this.label = this.serialKey + ' · ' + this.model;
    }
  }
}
