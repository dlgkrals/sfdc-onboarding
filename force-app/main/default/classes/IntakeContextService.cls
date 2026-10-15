/**
 * @description 접수 작성 팝업의 오른쪽 정보 — 고객사 카드·사업장 카드, 고른 장비의 진행 중 접수(BR-11 중복 경고)
 *              화면 표시용이라 실행 사용자 권한대로 조회 (USER_MODE, 공유는 호출한 컨트롤러를 따름)
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-15    Edwin     최초 작성 (피드백 개선 ① 카드, ③ 중복 접수 경고)
 * ----------------------------------------------------------------------------
 * @see CallIntakeController, caseIntakeModal · intakeContextCards (LWC), docs/d6_screen_design.md SC-08
 */
public inherited sharing class IntakeContextService {
  // DESC: 진행 중 = 종결·취소가 아닌 접수 (완료 Completed도 포함 — 상태를 같이 보여 주고 상담원이 판단)
  @TestVisible
  private static final Set<String> CLOSED_STATUSES = new Set<String>{
    'Closed',
    'Canceled'
  };
  // DESC: 긴급 용도 — 저장 전 Flow(Case_BeforeSave_FillFromAsset)의 긴급 판단과 같은 값
  @TestVisible
  private static final Set<String> URGENT_USAGE_TYPES = new Set<String>{
    'ColdStorage',
    'ServerRoom'
  };
  @TestVisible
  private static final Integer OPEN_CASE_LIMIT = 5;

  /**
   * @description 고객사·사업장 카드. 둘 다 없으면 빈 결과
   * @param accountId 고른 고객사 (없으면 사업장의 고객사)
   * @param siteId    고른 사업장 (없으면 사업장 카드 없음)
   */
  public static ContextCards getCards(Id accountId, Id siteId) {
    ContextCards cards = new ContextCards();
    if (siteId != null) {
      cards.site = buildSiteCard(siteId);
      if (accountId == null && cards.site != null) {
        accountId = cards.site.accountId;
      }
    }
    if (accountId != null) {
      cards.account = buildAccountCard(accountId);
    }
    return cards;
  }

  /**
   * @description 장비의 진행 중 접수 (최근 5건 + 전체 건수)
   */
  public static OpenCases getOpenCases(Id assetId) {
    OpenCases result = new OpenCases();
    if (assetId == null) {
      return result;
    }
    result.totalCount = [
      SELECT COUNT()
      FROM Case
      WHERE AssetId = :assetId AND Status NOT IN :CLOSED_STATUSES
      WITH USER_MODE
    ];
    if (result.totalCount == 0) {
      return result;
    }
    Map<String, String> statusLabels = picklistLabels(
      Case.Status.getDescribe()
    );
    for (Case c : [
      SELECT Id, CaseNumber, Status, Subject, CreatedDate
      FROM Case
      WHERE AssetId = :assetId AND Status NOT IN :CLOSED_STATUSES
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT :OPEN_CASE_LIMIT
    ]) {
      result.cases.add(new OpenCase(c, statusLabels.get(c.Status)));
    }
    return result;
  }

  private static AccountCard buildAccountCard(Id accountId) {
    List<Account> accounts = [
      SELECT Id, Name, Phone, AccountStatus__c, RecordType.Name, ruSiteCount__c
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (accounts.isEmpty()) {
      return null;
    }
    Account account = accounts[0];
    AccountCard card = new AccountCard();
    card.id = account.Id;
    card.name = account.Name;
    card.customerType = account.RecordType?.Name;
    card.phone = account.Phone;
    card.status = account.AccountStatus__c;
    card.statusLabel = picklistLabels(
        Schema.SObjectType.Account.fields.AccountStatus__c
      )
      .get(account.AccountStatus__c);
    card.siteCount = account.ruSiteCount__c == null
      ? 0
      : account.ruSiteCount__c.intValue();
    card.assetCount = [
      SELECT COUNT()
      FROM Asset
      WHERE AccountId = :accountId
      WITH USER_MODE
    ];
    return card;
  }

  private static SiteCard buildSiteCard(Id siteId) {
    List<CustomerSite__c> sites = [
      SELECT
        Id,
        Name,
        Account__c,
        fmFullAddress__c,
        ServiceCenter__c,
        OnSiteContactName__c,
        OnSiteContactPhone__c,
        SecondaryContactPhone__c,
        UsageType__c
      FROM CustomerSite__c
      WHERE Id = :siteId
      WITH USER_MODE
      LIMIT 1
    ];
    if (sites.isEmpty()) {
      return null;
    }
    CustomerSite__c site = sites[0];
    SiteCard card = new SiteCard();
    card.id = site.Id;
    card.name = site.Name;
    card.accountId = site.Account__c;
    card.address = site.fmFullAddress__c;
    card.serviceCenter = picklistLabels(
        CustomerSite__c.ServiceCenter__c.getDescribe()
      )
      .get(site.ServiceCenter__c);
    card.onSiteContactName = site.OnSiteContactName__c;
    card.onSiteContactPhone = site.OnSiteContactPhone__c;
    card.secondaryContactPhone = site.SecondaryContactPhone__c;
    card.usageType = site.UsageType__c;
    card.usageLabel = picklistLabels(CustomerSite__c.UsageType__c.getDescribe())
      .get(site.UsageType__c);
    card.isUrgentUsage = URGENT_USAGE_TYPES.contains(site.UsageType__c);
    card.assetCount = [
      SELECT COUNT()
      FROM Asset
      WHERE CustomerSite__c = :siteId
      WITH USER_MODE
    ];
    card.openCaseCount = [
      SELECT COUNT()
      FROM Case
      WHERE CustomerSite__c = :siteId AND Status NOT IN :CLOSED_STATUSES
      WITH USER_MODE
    ];
    return card;
  }

  // DESC: picklist API 이름 → 화면 라벨 (사용자 언어)
  private static Map<String, String> picklistLabels(
    Schema.DescribeFieldResult field
  ) {
    Map<String, String> labelsByValue = new Map<String, String>();
    for (Schema.PicklistEntry entry : field.getPicklistValues()) {
      labelsByValue.put(entry.getValue(), entry.getLabel());
    }
    return labelsByValue;
  }

  public class ContextCards {
    @AuraEnabled
    public AccountCard account;
    @AuraEnabled
    public SiteCard site;
  }

  public class AccountCard {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String customerType;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String statusLabel;
    @AuraEnabled
    public Integer siteCount;
    @AuraEnabled
    public Integer assetCount;
  }

  public class SiteCard {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String address;
    @AuraEnabled
    public String serviceCenter;
    @AuraEnabled
    public String onSiteContactName;
    @AuraEnabled
    public String onSiteContactPhone;
    @AuraEnabled
    public String secondaryContactPhone;
    @AuraEnabled
    public String usageType;
    @AuraEnabled
    public String usageLabel;
    @AuraEnabled
    public Boolean isUrgentUsage = false;
    @AuraEnabled
    public Integer assetCount;
    @AuraEnabled
    public Integer openCaseCount;
  }

  public class OpenCases {
    @AuraEnabled
    public Integer totalCount = 0;
    @AuraEnabled
    public List<OpenCase> cases = new List<OpenCase>();
  }

  public class OpenCase {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String caseNumber;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String statusLabel;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public Datetime createdDate;

    OpenCase(Case c, String statusLabel) {
      this.id = c.Id;
      this.caseNumber = c.CaseNumber;
      this.status = c.Status;
      this.statusLabel = String.isBlank(statusLabel) ? c.Status : statusLabel;
      this.subject = c.Subject;
      this.createdDate = c.CreatedDate;
    }
  }
}
