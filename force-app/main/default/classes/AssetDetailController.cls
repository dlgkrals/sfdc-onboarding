/**
 * @description 장비 상세 화면(SC-04 assetDetail · assetRecentCases) 컨트롤러 — 장비의 최근 접수 목록
 *              기본 정보·보증은 화면이 LDS로 직접 읽으므로 여기서는 최근 접수만 제공
 * @layer       Controller
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 실습: LWC 상세 화면)
 * ----------------------------------------------------------------------------
 * @see assetRecentCases (LWC), docs/d6_screen_design.md SC-04
 */
// DESC: 화면은 실행 사용자 권한대로 → with sharing + 조회 USER_MODE (사용자가 볼 수 있는 접수만)
public with sharing class AssetDetailController {
  // DESC: 접수 전 확인용이라 최근 5건이면 충분 (전체 이력은 표준 관련 목록 "모두 보기")
  public static final Integer RECENT_CASE_LIMIT = 5;

  /**
   * @description 장비의 최근 접수 5건과 전체 접수 수
   * @param assetId 장비 Id
   * @return 최근 접수 행 + 전체 건수 ("모두 보기" 표시 여부 판단용)
   */
  @AuraEnabled(cacheable=true)
  public static RecentCases getRecentCases(Id assetId) {
    RecentCases result = new RecentCases();
    if (assetId == null) {
      return result;
    }
    try {
      result.totalCount = [
        SELECT COUNT()
        FROM Case
        WHERE AssetId = :assetId
        WITH USER_MODE
      ];
      for (Case c : [
        SELECT
          Id,
          CaseNumber,
          CreatedDate,
          toLabel(SymptomType__c),
          toLabel(Status),
          RepeatFailure__c,
          toLabel(ServiceCenter__c)
        FROM Case
        WHERE AssetId = :assetId
        WITH USER_MODE
        ORDER BY CreatedDate DESC
        LIMIT :RECENT_CASE_LIMIT
      ]) {
        result.rows.add(new CaseRow(c));
      }
      return result;
    } catch (Exception e) {
      AuraHandledException ex = new AuraHandledException(e.getMessage());
      ex.setMessage(e.getMessage());
      throw ex;
    }
  }

  /**
   * @description 최근 접수 목록 + 전체 건수
   */
  public class RecentCases {
    @AuraEnabled
    public List<CaseRow> rows = new List<CaseRow>();
    @AuraEnabled
    public Integer totalCount = 0;
  }

  /**
   * @description 최근 접수 한 행
   */
  public class CaseRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String caseNumber;
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public String symptom;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean repeatFailure;
    @AuraEnabled
    public String serviceCenter;

    CaseRow(Case c) {
      this.id = c.Id;
      this.caseNumber = c.CaseNumber;
      this.createdDate = c.CreatedDate;
      this.symptom = c.SymptomType__c;
      this.status = c.Status;
      this.repeatFailure = c.RepeatFailure__c;
      this.serviceCenter = c.ServiceCenter__c;
    }
  }
}
