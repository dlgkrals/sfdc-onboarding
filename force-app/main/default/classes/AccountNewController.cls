/**
 * @description 고객사 "새로 만들기" 재정의 화면(accountNew) 컨트롤러 — 고른 레코드 유형의 API 이름
 *              LDS getObjectInfo의 recordTypeInfos에는 표시 이름만 있고 API 이름(DeveloperName)이 없어
 *              "개인이면 사업자번호 숨김" 같은 유형별 규칙을 표시 이름(번역·변경 가능)에 의존하지 않게 함
 * @layer       Controller
 * @author      Edwin
 * @date        2026-10-14
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-14    Edwin     최초 작성 (D8 고객사·사업장 새로 만들기 재정의)
 * ----------------------------------------------------------------------------
 * @see accountNew (LWC), accountNewOverride (Aura)
 */
// DESC: 화면은 실행 사용자 권한대로 → with sharing + USER_MODE
public with sharing class AccountNewController {
  /**
   * @description 고객사 레코드 유형 API 이름 (Individual · SoleProprietor · Corporation · Dealer)
   * @param recordTypeId 레코드 유형 Id (null이면 null)
   * @return API 이름, 고객사 유형이 아니거나 없으면 null
   */
  @AuraEnabled(cacheable=true)
  public static String getRecordTypeDeveloperName(Id recordTypeId) {
    if (recordTypeId == null) {
      return null;
    }
    List<RecordType> types = [
      SELECT DeveloperName
      FROM RecordType
      WHERE Id = :recordTypeId AND SobjectType = 'Account'
      WITH USER_MODE
    ];
    return types.isEmpty() ? null : types[0].DeveloperName;
  }
}
