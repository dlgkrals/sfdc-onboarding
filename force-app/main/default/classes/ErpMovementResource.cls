/**
 * @description ERP → Salesforce 재고 변동 푸시 입구 (IF-02 Push, Apex REST)
 *              POST /services/apexrest/hg/erp/movements  { "movements": [ { id, type, origin, locationCode, partCode, quantityChange, unit, reference, createdAt } ] }
 *              - 호출자: ERP Mock(Cloudflare Workers), OAuth 2.0 Client Credentials → 연동 전용 사용자(외부 클라이언트 앱 Run As)
 *              - 연동 사용자에게는 이 클래스 실행 권한만. 재고·기록 저장은 ErpStockSyncService가 SYSTEM_MODE로 처리
 *              - 반영 규칙은 가져오기(Pull)와 같음: ERP 출처 입고·조정만 변동량만큼, 없는 재고는 생성, 이미 기록된 이력 번호는 건너뜀
 *              - 받은 변동은 재고 수량만 조정(사용 부품·재고 이동을 만들지 않음) → ERP 전송 트리거가 다시 돌지 않음
 *              - 요청 전체가 잘못되면 400, 저장 실패는 500(ERP는 재시도하지 않음 → 매시 가져오기가 다시 가져옴)
 *              - 건별 형식 오류는 INVALID로 응답만 하고 기록·반영하지 않음
 * @layer       Controller
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-15    Edwin     최초 작성 (IF-02 Pull → Push + Pull)
 * 1.1    2026-10-15    Edwin     without sharing (연동 사용자가 위치를 못 찾던 결함)
 * 1.2    2026-10-19    Edwin     ERP 통신 기록(ErpCallLogger): 받은 본문·돌려준 본문·상태·처리 시간 (Authorization 헤더는 기록 안 함)
 * ----------------------------------------------------------------------------
 * @see ErpStockSyncService.applyPushed, erp-mock/src/index.js, docs/interface_definition.md IF-02
 */
// WARN: without sharing — 연동 사용자는 레코드를 소유하지 않고 위치·재고 공유도 없음. SYSTEM_MODE만으로는 공유가 풀리지 않아
//       위치를 못 찾았음(2026-10-15 실제 호출). 접근은 이 클래스 실행 권한(HG_ErpIntegration)과 입력 검증으로 제한
@RestResource(urlMapping='/hg/erp/movements')
global without sharing class ErpMovementResource {
  @TestVisible
  private static final Integer MAX_MOVEMENTS = 200;
  @TestVisible
  private static final Integer MAX_BODY_BYTES = 1000000;
  private static final Integer MAX_CODE_LENGTH = 40;
  private static final Integer MAX_REFERENCE_LENGTH = 255;
  private static final Decimal MAX_ABS_QUANTITY = 1000000;
  private static final Long MAX_ID = 999999999999L;
  private static final Set<String> TYPES = new Set<String>{
    'CONSUME',
    'TRANSFER_OUT',
    'TRANSFER_IN',
    'SEED',
    'RECEIPT',
    'ADJUST'
  };
  private static final Set<String> ORIGINS = new Set<String>{
    'SALESFORCE',
    'ERP',
    'SEED'
  };
  private static final Set<String> UNITS = new Set<String>{ 'Each', 'kg' };
  private static final Pattern CODE_PATTERN = Pattern.compile(
    '^[A-Za-z0-9_\\-]+$'
  );
  @TestVisible
  private static final String RESULT_INVALID = 'INVALID';

  // DESC: 요청 전체를 받을 수 없는 경우(형식·건수) → 400
  private class BadRequestException extends Exception {
  }

  // DESC: 통신 기록용 (respond에서 한 줄로 남김)
  private static Long startedAt;
  private static List<String> movementIds = new List<String>();

  @HttpPost
  global static void receive() {
    startedAt = System.currentTimeMillis();
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json; charset=utf-8');
    List<Object> items;
    try {
      items = readMovements(RestContext.request);
    } catch (BadRequestException e) {
      respond(res, 400, errorBody('BAD_REQUEST', e.getMessage()));
      return;
    }

    // DESC: 건별 검증 → 통과한 것만 반영. 응답은 요청 순서대로
    List<Object> slots = new List<Object>();
    List<ErpStockSyncService.Movement> valid = new List<ErpStockSyncService.Movement>();
    for (Integer i = 0; i < items.size(); i++) {
      if (items[i] instanceof Map<String, Object>) {
        movementIds.add(
          String.valueOf(((Map<String, Object>) items[i]).get('id'))
        );
      }
      Object parsed = toMovement(items[i], i);
      slots.add(parsed);
      if (parsed instanceof ErpStockSyncService.Movement) {
        valid.add((ErpStockSyncService.Movement) parsed);
      }
    }

    List<ErpStockSyncService.PushItemResult> applied;
    try {
      applied = ErpStockSyncService.applyPushed(valid);
    } catch (Exception e) {
      // WARN: 저장 실패(동시에 같은 변동이 들어와 고유키 충돌 등) → 전부 되돌림. 매시 가져오기가 다시 가져옴
      respond(res, 500, errorBody('SAVE_FAILED', e.getMessage()));
      return;
    }

    Map<String, Integer> counts = new Map<String, Integer>{
      ErpStockSyncService.PUSH_APPLIED => 0,
      ErpStockSyncService.PUSH_DUPLICATE => 0,
      ErpStockSyncService.PUSH_SKIPPED => 0,
      ErpStockSyncService.PUSH_ERROR => 0,
      RESULT_INVALID => 0
    };
    List<ErpStockSyncService.PushItemResult> results = new List<ErpStockSyncService.PushItemResult>();
    Integer next = 0;
    for (Object slot : slots) {
      ErpStockSyncService.PushItemResult r = slot instanceof ErpStockSyncService.Movement
        ? applied[next++]
        : (ErpStockSyncService.PushItemResult) slot;
      results.add(r);
      counts.put(r.result, counts.get(r.result) + 1);
    }
    respond(
      res,
      200,
      new Map<String, Object>{
        'received' => items.size(),
        'applied' => counts.get(ErpStockSyncService.PUSH_APPLIED),
        'duplicates' => counts.get(ErpStockSyncService.PUSH_DUPLICATE),
        'skipped' => counts.get(ErpStockSyncService.PUSH_SKIPPED),
        'errors' => counts.get(ErpStockSyncService.PUSH_ERROR),
        'invalid' => counts.get(RESULT_INVALID),
        'results' => results
      }
    );
  }

  // DESC: 본문 크기 → JSON → movements 배열 → 건수(1~200)
  private static List<Object> readMovements(RestRequest req) {
    Blob body = req?.requestBody;
    if (body == null || body.size() == 0) {
      throw new BadRequestException('요청 본문이 비어 있습니다.');
    }
    if (body.size() > MAX_BODY_BYTES) {
      throw new BadRequestException(
        '요청 본문이 너무 큽니다(최대 ' + MAX_BODY_BYTES + '바이트).'
      );
    }
    Object root;
    try {
      root = JSON.deserializeUntyped(body.toString());
    } catch (Exception e) {
      throw new BadRequestException('JSON 형식이 아닙니다.');
    }
    if (!(root instanceof Map<String, Object>)) {
      throw new BadRequestException('본문은 JSON 객체여야 합니다.');
    }
    Object raw = ((Map<String, Object>) root).get('movements');
    if (!(raw instanceof List<Object>)) {
      throw new BadRequestException('movements 배열이 필요합니다.');
    }
    List<Object> items = (List<Object>) raw;
    if (items.isEmpty()) {
      throw new BadRequestException('movements가 비어 있습니다.');
    }
    if (items.size() > MAX_MOVEMENTS) {
      throw new BadRequestException(
        'movements는 한 번에 최대 ' +
          MAX_MOVEMENTS +
          '건입니다(받은 ' +
          items.size() +
          '건).'
      );
    }
    return items;
  }

  // DESC: 한 건 검증. 통과하면 Movement, 아니면 INVALID 결과(필드 이름을 메시지에)
  @TestVisible
  private static Object toMovement(Object raw, Integer index) {
    if (!(raw instanceof Map<String, Object>)) {
      return invalid(null, index, '항목이 객체가 아닙니다.');
    }
    Map<String, Object> item = (Map<String, Object>) raw;
    Long id = toWholeNumber(item.get('id'));
    if (id == null || id <= 0 || id > MAX_ID) {
      return invalid(null, index, 'id는 1 이상의 정수여야 합니다.');
    }
    String type = asString(item.get('type'));
    if (!TYPES.contains(type)) {
      return invalid(id, index, 'type 값이 올바르지 않습니다.');
    }
    String origin = asString(item.get('origin'));
    if (!ORIGINS.contains(origin)) {
      return invalid(id, index, 'origin 값이 올바르지 않습니다.');
    }
    String locationCode = asString(item.get('locationCode'));
    if (!isCode(locationCode)) {
      return invalid(id, index, 'locationCode 형식이 올바르지 않습니다.');
    }
    String partCode = asString(item.get('partCode'));
    if (!isCode(partCode)) {
      return invalid(id, index, 'partCode 형식이 올바르지 않습니다.');
    }
    Decimal quantity = toDecimal(item.get('quantityChange'));
    if (
      quantity == null ||
      quantity == 0 ||
      quantity.abs() > MAX_ABS_QUANTITY ||
      quantity.scale() > 2
    ) {
      return invalid(
        id,
        index,
        'quantityChange는 0이 아닌 숫자(소수 둘째 자리까지, 절댓값 ' +
          MAX_ABS_QUANTITY +
          ' 이하)여야 합니다.'
      );
    }
    Object rawUnit = item.get('unit');
    String unit = asString(rawUnit);
    if (rawUnit != null && !UNITS.contains(unit)) {
      return invalid(id, index, 'unit은 Each 또는 kg이어야 합니다.');
    }
    Object rawReference = item.get('reference');
    String reference = asString(rawReference);
    if (
      rawReference != null &&
      (reference == null ||
      reference.length() > MAX_REFERENCE_LENGTH)
    ) {
      return invalid(
        id,
        index,
        'reference는 ' + MAX_REFERENCE_LENGTH + '자 이하 문자열이어야 합니다.'
      );
    }
    Datetime createdAt;
    Object rawCreated = item.get('createdAt');
    if (rawCreated != null) {
      try {
        createdAt = (Datetime) JSON.deserialize(
          '"' + asString(rawCreated) + '"',
          Datetime.class
        );
      } catch (Exception e) {
        return invalid(id, index, 'createdAt은 ISO 8601 일시여야 합니다.');
      }
    }
    ErpStockSyncService.Movement m = new ErpStockSyncService.Movement();
    m.id = id;
    m.type = type;
    m.origin = origin;
    m.locationCode = locationCode;
    m.partCode = partCode;
    m.quantityChange = quantity;
    m.unit = unit;
    m.reference = reference;
    m.createdAt = createdAt;
    return m;
  }

  private static ErpStockSyncService.PushItemResult invalid(
    Long id,
    Integer index,
    String message
  ) {
    return new ErpStockSyncService.PushItemResult(
      id,
      RESULT_INVALID,
      'INVALID_FIELD',
      'movements[' + index + ']: ' + message
    );
  }

  private static String asString(Object value) {
    return value instanceof String ? (String) value : null;
  }

  private static Boolean isCode(String value) {
    return String.isNotBlank(value) &&
      value.length() <= MAX_CODE_LENGTH &&
      CODE_PATTERN.matcher(value).matches();
  }

  // DESC: JSON 숫자만 받음(문자열 숫자는 거부). 정수 id는 소수부가 없어야 함
  private static Decimal toDecimal(Object value) {
    if (
      value instanceof Integer ||
      value instanceof Long ||
      value instanceof Decimal ||
      value instanceof Double
    ) {
      return Decimal.valueOf(String.valueOf(value));
    }
    return null;
  }

  private static Long toWholeNumber(Object value) {
    Decimal d = toDecimal(value);
    if (d == null || d != d.setScale(0, RoundingMode.DOWN)) {
      return null;
    }
    return d.longValue();
  }

  private static Map<String, Object> errorBody(String code, String message) {
    return new Map<String, Object>{
      'error' => new Map<String, Object>{ 'code' => code, 'message' => message }
    };
  }

  private static void respond(RestResponse res, Integer status, Object body) {
    res.statusCode = status;
    res.responseBody = Blob.valueOf(JSON.serialize(body, true));
    logCall(status, body, res.responseBody.toString());
  }

  // DESC: 받기(푸시) 통신 기록 1줄. 요청 본문만(헤더의 토큰 없음). 기록 실패는 응답에 영향 없음
  private static void logCall(
    Integer status,
    Object body,
    String responseText
  ) {
    try {
      ErpCallLogger.Entry log = new ErpCallLogger.Entry();
      log.direction = ErpCallLogger.DIRECTION_PUSH;
      log.interfaceCode = 'IF-02-P';
      log.endpoint = '/services/apexrest/hg/erp/movements';
      log.method = 'POST';
      RestRequest req = RestContext.request;
      log.requestBody = req != null &&
        req.requestBody != null
        ? req.requestBody.toString()
        : null;
      log.responseBody = responseText;
      log.statusCode = status;
      log.durationMs = startedAt == null
        ? null
        : System.currentTimeMillis() - startedAt;
      log.itemCount = movementIds.size();
      log.refIds.addAll(movementIds);
      Map<String, Object> m = (Map<String, Object>) body;
      if (status != 200) {
        log.result = ErpCallLogger.RESULT_FAILED;
        Map<String, Object> error = (Map<String, Object>) m.get('error');
        log.errorMessage = error == null
          ? null
          : '[' + error.get('code') + '] ' + error.get('message');
      } else {
        Integer problems =
          (Integer) m.get('errors') + (Integer) m.get('invalid');
        log.result = problems == 0
          ? ErpCallLogger.RESULT_SUCCESS
          : ErpCallLogger.RESULT_REJECTED;
        log.errorMessage = problems == 0
          ? null
          : '오류 ' + m.get('errors') + ' · 형식 오류 ' + m.get('invalid');
      }
      ErpCallLogger.add(log);
      ErpCallLogger.flush();
    } catch (Exception e) {
      System.debug(LoggingLevel.WARN, '푸시 통신 기록 실패: ' + e.getMessage());
    }
  }
}
