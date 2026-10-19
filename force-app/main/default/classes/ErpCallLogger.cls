/**
 * @description ERP 통신 기록(ErpCallLog__c) — 호출 1번 = 1줄, 요청·응답 JSON 원문
 *              - 보내기(IF-03·06): ErpInventoryService.postChunk가 남기고 save()가 저장
 *              - 받기 푸시(IF-02-P): ErpMovementResource.respond가 남기고 저장
 *              - 가져오기(IF-02-R): ErpStockSyncService.fetch가 남기고 syncNextPage가 저장(0건 호출도)
 *              - 콜아웃 뒤에만 저장할 수 있으므로 메모리에 모았다가 flush()로 한 번에 저장
 *              - 기록은 부가 기능: 만들기·저장 중 오류는 삼키고 본 처리를 막지 않음(Database.insert allOrNone=false + try/catch)
 *              - 헤더(API 키·토큰)는 받지도 저장하지도 않음. 본문만
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-19
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-19    Edwin     최초 작성 (모의 발표 피드백: ERP 통신 기록)
 * ----------------------------------------------------------------------------
 * @see ErpInventoryService, ErpMovementResource, ErpStockSyncService, ErpCallLog__c
 */
// DESC: 기록 저장은 시스템 동작(기사·연동 사용자에게 이 오브젝트 권한 없음) → 저장은 SYSTEM_MODE, 공유는 호출한 쪽을 따름
public inherited sharing class ErpCallLogger {
  public static final String DIRECTION_OUTBOUND = 'Outbound';
  public static final String DIRECTION_PUSH = 'InboundPush';
  public static final String DIRECTION_PULL = 'InboundPull';
  public static final String RESULT_SUCCESS = 'Success';
  public static final String RESULT_REJECTED = 'Rejected';
  public static final String RESULT_FAILED = 'Failed';
  @TestVisible
  private static final Integer BODY_MAX = 131072;
  private static final Integer REF_MAX = 32768;
  private static final Integer TEXT_MAX = 255;

  private static List<ErpCallLog__c> pending = new List<ErpCallLog__c>();

  /**
   * @description 호출 한 번의 기록
   */
  public class Entry {
    public String direction;
    public String interfaceCode;
    public String endpoint;
    public String method;
    public String requestBody;
    public String responseBody;
    public Integer statusCode;
    public Long durationMs;
    public Integer itemCount;
    public String result;
    public String errorMessage;
    public List<String> relatedNumbers = new List<String>();
    public List<String> refIds = new List<String>();
  }

  /**
   * @description 기록을 메모리에 모음 (저장은 flush)
   * @param e 호출 기록
   */
  public static void add(Entry e) {
    try {
      Boolean truncated = false;
      String request = clip(e.requestBody, BODY_MAX);
      String response = clip(e.responseBody, BODY_MAX);
      truncated =
        (e.requestBody != null && request.length() < e.requestBody.length()) ||
        (e.responseBody != null &&
        response.length() < e.responseBody.length());
      pending.add(
        new ErpCallLog__c(
          Direction__c = e.direction,
          Interface__c = e.interfaceCode,
          Source__c = sourceOf(e.direction),
          Endpoint__c = e.endpoint == null ? null : e.endpoint.left(TEXT_MAX),
          HttpMethod__c = e.method,
          RequestBody__c = request,
          ResponseBody__c = response,
          Truncated__c = truncated,
          StatusCode__c = e.statusCode,
          DurationMs__c = e.durationMs,
          ItemCount__c = e.itemCount,
          Result__c = e.result,
          ErrorMessage__c = e.errorMessage == null
            ? null
            : e.errorMessage.left(TEXT_MAX),
          RelatedNumbers__c = joinUnique(e.relatedNumbers, TEXT_MAX),
          RefIds__c = joinUnique(e.refIds, REF_MAX)
        )
      );
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.WARN,
        'ERP 통신 기록 만들기 실패: ' + ex.getMessage()
      );
    }
  }

  /**
   * @description 모은 기록 저장 — 콜아웃이 모두 끝난 뒤에 부를 것. 실패해도 예외를 던지지 않음
   */
  public static void flush() {
    if (pending.isEmpty()) {
      return;
    }
    List<ErpCallLog__c> logs = pending;
    pending = new List<ErpCallLog__c>();
    try {
      Database.insert(logs, false, AccessLevel.SYSTEM_MODE);
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.WARN,
        'ERP 통신 기록 저장 실패: ' + ex.getMessage()
      );
    }
  }

  @TestVisible
  private static Integer pendingCount() {
    return pending.size();
  }

  // DESC: 실행 위치는 실행 문맥으로 판단 (호출하는 쪽이 넘기지 않아도 되게)
  private static String sourceOf(String direction) {
    if (direction == DIRECTION_PUSH) {
      return 'ApexRest';
    }
    if (System.isQueueable()) {
      return 'Queueable';
    }
    if (System.isBatch()) {
      return direction == DIRECTION_OUTBOUND ? 'RetryBatch' : 'PullBatch';
    }
    return 'Manual';
  }

  // DESC: 한도를 넘으면 자르고 끝에 원래 길이를 표시
  @TestVisible
  private static String clip(String body, Integer max) {
    if (body == null || body.length() <= max) {
      return body;
    }
    String mark = '\n…(잘림, 원래 ' + body.length() + '자)';
    return body.left(max - mark.length()) + mark;
  }

  private static String joinUnique(List<String> values, Integer max) {
    if (values == null || values.isEmpty()) {
      return null;
    }
    List<String> unique = new List<String>();
    for (String value : new Set<String>(values)) {
      if (String.isNotBlank(value)) {
        unique.add(value);
      }
    }
    if (unique.isEmpty()) {
      return null;
    }
    String joined = String.join(unique, ', ');
    return joined.length() <= max ? joined : joined.left(max - 1) + '…';
  }
}
