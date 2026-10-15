/**
 * @description 가상 착신 시뮬레이터 · 접수 작성 팝업 · 장비 요약 팝업 컨트롤러
 *              판정 결과 조회(발신자 찾기 + 장비 확정), 사업장·장비 후보 조회, 전화 접수 생성
 *              실제 CTI(Service Cloud Voice·Open CTI)가 아니라 착신 정보를 상담원이 직접 넣는 시뮬레이터
 * @layer       Controller
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-15    Edwin     최초 작성 (CTI 가상 착신 시뮬레이터)
 * 1.1    2026-10-15    Edwin     제목 기본값 "{증상} · {사업장} · {시리얼}" (피드백 개선 ②)
 * 1.2    2026-10-15    Edwin     고객사·사업장 카드, 진행 중 접수 조회 (피드백 개선 ①③, IntakeContextService)
 * ----------------------------------------------------------------------------
 * @see CallerMatchService, callSimulator · caseIntakeModal · assetSummaryModal (LWC)
 */
// DESC: 화면은 실행 사용자 권한대로 → with sharing + 조회·DML USER_MODE
public with sharing class CallIntakeController {
  @TestVisible
  private static final String ORIGIN_PHONE = 'Phone';
  @TestVisible
  private static final String SUBJECT_SEPARATOR = ' · ';

  /**
   * @description 접수 작성 가능 여부 (패널 표시·"이 장비로 접수" 버튼 표시용)
   *              클래스 접근이 없는 사용자(기사·센터장)는 호출 자체가 실패 → 화면은 "사용 불가"로 처리
   */
  @AuraEnabled(cacheable=true)
  public static Boolean canCreateCase() {
    return hasIntakeAccess();
  }

  /**
   * @description 착신 → 발신자 찾기 + 장비 확정 판정
   * @param callerPhone  발신 번호
   * @param serialSuffix 시리얼 뒤 4자리 (# = 모름)
   */
  @AuraEnabled
  public static CallerMatchService.MatchResult matchCaller(
    String callerPhone,
    String serialSuffix
  ) {
    requireAccess();
    try {
      return CallerMatchService.match(callerPhone, serialSuffix);
    } catch (Exception e) {
      throw newAuraException(e.getMessage());
    }
  }

  /**
   * @description 장비 하나로 접수 작성 팝업 채우기 (장비 요약 → "이 장비로 접수")
   */
  @AuraEnabled
  public static CallerMatchService.MatchResult getIntakeForAsset(Id assetId) {
    requireAccess();
    try {
      return CallerMatchService.forAsset(assetId);
    } catch (Exception e) {
      throw newAuraException(e.getMessage());
    }
  }

  /**
   * @description 고객사의 사업장 후보
   */
  @AuraEnabled
  public static List<CallerMatchService.SiteOption> getSiteCandidates(
    Id accountId
  ) {
    requireAccess();
    try {
      return CallerMatchService.getSites(accountId);
    } catch (Exception e) {
      throw newAuraException(e.getMessage());
    }
  }

  /**
   * @description 사업장(없으면 고객사)의 장비 후보 + 확정할 장비
   */
  @AuraEnabled
  public static CallerMatchService.AssetChoice getAssetCandidates(
    Id accountId,
    Id siteId,
    String serialSuffix
  ) {
    requireAccess();
    try {
      return CallerMatchService.getAssets(accountId, siteId, serialSuffix);
    } catch (Exception e) {
      throw newAuraException(e.getMessage());
    }
  }

  /**
   * @description 접수 작성 팝업 오른쪽 고객사·사업장 카드 (고객사·사업장을 바꿀 때마다)
   */
  @AuraEnabled
  public static IntakeContextService.ContextCards getContextCards(
    Id accountId,
    Id siteId
  ) {
    requireAccess();
    try {
      return IntakeContextService.getCards(accountId, siteId);
    } catch (Exception e) {
      throw newAuraException(e.getMessage());
    }
  }

  /**
   * @description 고른 장비의 진행 중 접수 (BR-11 중복 접수 경고, 저장은 막지 않음)
   */
  @AuraEnabled
  public static IntakeContextService.OpenCases getOpenCases(Id assetId) {
    requireAccess();
    try {
      return IntakeContextService.getOpenCases(assetId);
    } catch (Exception e) {
      throw newAuraException(e.getMessage());
    }
  }

  /**
   * @description 전화 접수 생성. 고객사·사업장·센터·긴급도는 저장 전 Flow가 장비를 보고 채움
   *              팝업에서 고른 고객사·사업장은 장비를 좁히는 데만 썼으므로 저장하지 않음
   *              장비가 없으면 기존 검증 규칙 Asset_Required가 거부
   * @param draft 장비·증상·제목·설명·발신 번호
   * @return 새 접수 Id
   */
  @AuraEnabled
  public static Id createCase(CaseDraft draft) {
    requireAccess();
    if (draft == null) {
      throw newAuraException(System.Label.MSG_SAVE_ERROR);
    }
    Case newCase = new Case(
      AssetId = draft.assetId,
      Origin = ORIGIN_PHONE,
      CallerPhone__c = String.isBlank(draft.callerPhone)
        ? null
        : draft.callerPhone.trim(),
      SymptomType__c = String.isBlank(draft.symptomType)
        ? null
        : draft.symptomType,
      Subject = String.isBlank(draft.subject)
        ? buildDefaultSubject(draft.symptomType, draft.assetId)
        : draft.subject.trim(),
      Description = draft.description
    );
    // DESC: 표준 새 접수 화면과 같게 활성 할당 규칙 적용 (레이아웃 기본값 runAssignmentRulesDefault = true) → 센터 Queue 소유
    Database.DMLOptions options = new Database.DMLOptions();
    options.assignmentRuleHeader.useDefaultRule = true;
    newCase.setOptions(options);
    try {
      Database.insert(newCase, AccessLevel.USER_MODE);
      return newCase.Id;
    } catch (DmlException e) {
      // DESC: 검증 규칙 메시지(예: Asset_Required)만 화면에 보여 줌
      throw newAuraException(e.getDmlMessage(0));
    } catch (Exception e) {
      throw newAuraException(e.getMessage());
    }
  }

  // DESC: 제목 기본값 "{증상} · {사업장} · {시리얼}" — 빈 값은 건너뜀, 모두 비면 "전화 접수" (화면 caseIntakeModal과 같은 규칙)
  @TestVisible
  private static String buildDefaultSubject(String symptomType, Id assetId) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(symptomType)) {
      for (
        Schema.PicklistEntry entry : Case.SymptomType__c.getDescribe()
          .getPicklistValues()
      ) {
        if (entry.getValue() == symptomType) {
          parts.add(entry.getLabel());
        }
      }
    }
    if (assetId != null) {
      List<Asset> assets = [
        SELECT SerialKey__c, CustomerSite__r.Name
        FROM Asset
        WHERE Id = :assetId
        WITH USER_MODE
        LIMIT 1
      ];
      if (!assets.isEmpty()) {
        addIfPresent(parts, assets[0].CustomerSite__r?.Name);
        addIfPresent(parts, assets[0].SerialKey__c);
      }
    }
    return parts.isEmpty()
      ? System.Label.LABEL_CALL_SUBJECT_PLAIN
      : String.join(parts, SUBJECT_SEPARATOR);
  }

  private static void addIfPresent(List<String> parts, String value) {
    if (String.isNotBlank(value)) {
      parts.add(value);
    }
  }

  // DESC: 접수 생성 + 고객 정보(사업장·장비) 조회가 모두 되는 사용자만 (상담원·관리자)
  private static Boolean hasIntakeAccess() {
    return Schema.SObjectType.Case.isCreateable() &&
      Schema.SObjectType.CustomerSite__c.isAccessible() &&
      Schema.SObjectType.Asset.isAccessible();
  }

  private static void requireAccess() {
    if (!hasIntakeAccess()) {
      throw newAuraException(System.Label.MSG_CALL_NO_ACCESS);
    }
  }

  private static AuraHandledException newAuraException(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }

  /**
   * @description 접수 작성 팝업에서 저장하는 값
   */
  public class CaseDraft {
    @AuraEnabled
    public Id assetId { get; set; }
    @AuraEnabled
    public String symptomType { get; set; }
    @AuraEnabled
    public String subject { get; set; }
    @AuraEnabled
    public String description { get; set; }
    @AuraEnabled
    public String callerPhone { get; set; }
  }
}
