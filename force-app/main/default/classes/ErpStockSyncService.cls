/**
 * @description ERP → Salesforce 재고 역방향 동기화 (IF-02)
 *              ERP 이력 중 "마지막으로 가져온 번호(ErpSyncState__c.LastMovementId__c) 이후"를 한 쪽(최대 200건)씩 가져와
 *              ERP에서만 생긴 입고(RECEIPT)·조정(ADJUST)만 변동량만큼 Salesforce 재고에 반영
 *              - Salesforce가 보낸 사용 차감·재고 이동(origin SALESFORCE)과 초기 적재(SEED)는 건너뜀 (이미 Salesforce에 있음)
 *              - 재고 원칙: ERP 값으로 덮어쓰지 않음. "현재 수량 + 변동량", 재고 조회 시 FOR UPDATE 잠금
 *              - 위치+부품 재고가 없으면 새로 만듦 (소유자 = 위치 소유자, 차량이면 기사)
 *              - 한 쪽의 반영·기록·이력 번호 저장은 한 트랜잭션 → 모두 되거나 모두 안 됨 (같은 변동은 한 번만)
 *              - 통신 실패(연결·HTTP 오류): 예외 → 이력 번호를 올리지 않음 → 다음 실행에서 다시
 *              - 데이터 문제(없는 위치·부품 코드, 음수가 되는 조정): 다시 해도 같은 결과 → 오류로 기록하고 건너뜀
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 IF-02 역방향)
 * ----------------------------------------------------------------------------
 * @see ErpStockSyncBatch, ErpStockSyncSchedulable, erp-mock/src/index.js getMovements, docs/interface_definition.md IF-02
 */
// DESC: 예약 작업(관리자)으로 돌지만 시스템이 계산하는 반영이므로 조회·저장 모두 SYSTEM_MODE 명시 (API 67 기본 user mode)
public with sharing class ErpStockSyncService {
  public static final String ORIGIN_ERP = 'ERP';
  public static final String TYPE_RECEIPT = 'RECEIPT';
  public static final String TYPE_ADJUST = 'ADJUST';
  public static final String RESULT_APPLIED = 'Applied';
  public static final String RESULT_ERROR = 'Error';
  public static final String CODE_UNKNOWN = 'UNKNOWN_CODE';
  public static final String CODE_NEGATIVE = 'NEGATIVE_STOCK';

  @TestVisible
  private static final Integer PAGE_SIZE = 200;
  private static final Integer TIMEOUT_MS = 60000;
  private static final String MOVEMENTS_ENDPOINT = 'callout:HG_ErpMock/api/movements';
  private static final Map<String, String> UOM_BY_ERP_UNIT = new Map<String, String>{
    'Each' => 'Each',
    'kg' => 'kg'
  };

  /**
   * @description 한 번 실행 결과 (Batch 로그·미리 보기 출력용)
   */
  public class SyncResult {
    public Long fromId;
    public Long lastId;
    public Long latestId;
    public Boolean hasMore = false;
    public Integer fetched = 0;
    public Integer erpChanges = 0;
    public Integer applied = 0;
    public Integer errors = 0;
    public Integer skipped = 0;
    public Integer createdItems = 0;
  }

  public class ErpSyncException extends Exception {
  }

  // DESC: ERP 이력 한 건 (API 응답 items[])
  private class Movement {
    Long id;
    String type;
    String origin;
    String locationCode;
    String partCode;
    Decimal quantityChange;
    String unit;
    String reference;
    Datetime createdAt;
  }

  /**
   * @description 마지막 ERP 이력 번호 (없으면 null = 아직 기준점을 정하지 않음)
   */
  public static Long getLastMovementId() {
    Decimal value = ErpSyncState__c.getOrgDefaults()?.LastMovementId__c;
    return value == null ? null : value.longValue();
  }

  /**
   * @description 이력 번호 저장 (기준점 스크립트·동기화에서 사용)
   */
  public static void saveLastMovementId(Long movementId) {
    ErpSyncState__c state = ErpSyncState__c.getOrgDefaults();
    if (state == null) {
      state = new ErpSyncState__c();
    }
    if (state.SetupOwnerId == null) {
      state.SetupOwnerId = UserInfo.getOrganizationId();
    }
    state.LastMovementId__c = movementId;
    Database.upsert(state, true, AccessLevel.SYSTEM_MODE);
  }

  /**
   * @description 다음 한 쪽을 가져와 반영 (콜아웃 → 반영·기록·이력 번호를 한 번에 저장)
   * @return 실행 결과. 기준점이 없으면 아무것도 하지 않음
   */
  public static SyncResult syncNextPage() {
    SyncResult result = new SyncResult();
    Long after = getLastMovementId();
    if (after == null) {
      // WARN: 기준점 없이 0부터 가져오면 초기 적재·과거 이력까지 반영될 수 있음 → 기준점 스크립트 먼저
      throw new ErpSyncException(
        '[NO_BASELINE] 기준 이력 번호가 없습니다. d7_erp_inbound_baseline.apex를 먼저 실행하세요.'
      );
    }
    Map<String, Object> body = fetch(after);
    List<Movement> movements = parse(body, result, after);
    List<Movement> erpChanges = new List<Movement>();
    for (Movement m : movements) {
      if (
        m.origin == ORIGIN_ERP &&
        (m.type == TYPE_RECEIPT ||
        m.type == TYPE_ADJUST)
      ) {
        erpChanges.add(m);
      } else {
        result.skipped++;
      }
    }
    result.erpChanges = erpChanges.size();
    // DESC: 콜아웃은 끝났으므로 여기부터 저장. 하나라도 실패하면 이 쪽 전체를 되돌리고 이력 번호도 그대로
    Savepoint sp = Database.setSavepoint();
    try {
      apply(erpChanges, result);
      if (result.lastId > after) {
        saveLastMovementId(result.lastId);
      }
    } catch (Exception e) {
      Database.rollback(sp);
      throw new ErpSyncException('[SAVE_FAILED] ' + e.getMessage());
    }
    return result;
  }

  /**
   * @description 미리 보기: 반영하지 않고 가져올 변동 건수만 셈 (실제 org 첫 실행 전 확인용, 최대 10쪽)
   */
  public static SyncResult preview() {
    SyncResult total = new SyncResult();
    Long after = getLastMovementId();
    total.fromId = after;
    Long cursor = after == null ? 0 : after;
    for (Integer page = 0; page < 10; page++) {
      SyncResult one = new SyncResult();
      List<Movement> movements = parse(fetch(cursor), one, cursor);
      total.latestId = one.latestId;
      total.fetched += one.fetched;
      for (Movement m : movements) {
        if (
          m.origin == ORIGIN_ERP &&
          (m.type == TYPE_RECEIPT ||
          m.type == TYPE_ADJUST)
        ) {
          total.erpChanges++;
        } else {
          total.skipped++;
        }
      }
      total.lastId = one.lastId;
      total.hasMore = one.hasMore;
      cursor = one.lastId;
      if (!one.hasMore) {
        break;
      }
    }
    return total;
  }

  /**
   * @description ERP의 가장 최근 이력 번호 (기준점 스크립트용)
   */
  public static Long fetchLatestId() {
    Map<String, Object> body = fetch(0, 1);
    return toLong(body.get('latestId'));
  }

  private static Map<String, Object> fetch(Long after) {
    return fetch(after, PAGE_SIZE);
  }

  private static Map<String, Object> fetch(Long after, Integer limitRows) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(
      MOVEMENTS_ENDPOINT + '?after=' + after + '&limit=' + limitRows
    );
    request.setMethod('GET');
    request.setTimeout(TIMEOUT_MS);
    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (Exception e) {
      throw new ErpSyncException('[CONNECTION] ' + e.getMessage());
    }
    if (response.getStatusCode() != 200) {
      throw new ErpSyncException(
        '[HTTP_' + response.getStatusCode() + '] ' + response.getBody()
      );
    }
    try {
      return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
    } catch (Exception e) {
      throw new ErpSyncException('[BAD_RESPONSE] ERP 응답을 읽을 수 없습니다.');
    }
  }

  private static List<Movement> parse(
    Map<String, Object> body,
    SyncResult result,
    Long after
  ) {
    List<Movement> movements = new List<Movement>();
    List<Object> items = body.get('items') == null
      ? new List<Object>()
      : (List<Object>) body.get('items');
    for (Object raw : items) {
      Map<String, Object> item = (Map<String, Object>) raw;
      Movement m = new Movement();
      m.id = toLong(item.get('id'));
      m.type = (String) item.get('type');
      m.origin = (String) item.get('origin');
      m.locationCode = (String) item.get('locationCode');
      m.partCode = (String) item.get('partCode');
      m.quantityChange = item.get('quantityChange') == null
        ? 0
        : Decimal.valueOf(String.valueOf(item.get('quantityChange')));
      m.unit = (String) item.get('unit');
      m.reference = (String) item.get('reference');
      String createdAt = (String) item.get('createdAt');
      m.createdAt = String.isBlank(createdAt)
        ? null
        : (Datetime) JSON.deserialize('"' + createdAt + '"', Datetime.class);
      movements.add(m);
    }
    result.fromId = after;
    result.fetched = movements.size();
    result.lastId = body.get('lastId') == null
      ? after
      : toLong(body.get('lastId'));
    result.hasMore = body.get('hasMore') == true;
    result.latestId = toLong(body.get('latestId'));
    return movements;
  }

  // DESC: 반영 + 기록. 루프 안 SOQL/DML 없이 코드 → Id Map, 재고 잠금 조회 1회, 저장은 마지막에 한 번씩
  private static void apply(List<Movement> changes, SyncResult result) {
    if (changes.isEmpty()) {
      return;
    }
    Set<String> locationCodes = new Set<String>();
    Set<String> partCodes = new Set<String>();
    for (Movement m : changes) {
      locationCodes.add(m.locationCode);
      partCodes.add(m.partCode);
    }
    Map<String, Schema.Location> locationsByCode = new Map<String, Schema.Location>();
    for (Schema.Location loc : [
      SELECT Id, OwnerId, ErpLocationCode__c
      FROM Location
      WHERE ErpLocationCode__c IN :locationCodes
      WITH SYSTEM_MODE
    ]) {
      locationsByCode.put(loc.ErpLocationCode__c, loc);
    }
    Map<String, Id> productIdByCode = new Map<String, Id>();
    for (Product2 product : [
      SELECT Id, ErpPartCode__c
      FROM Product2
      WHERE ErpPartCode__c IN :partCodes
      WITH SYSTEM_MODE
    ]) {
      productIdByCode.put(product.ErpPartCode__c, product.Id);
    }
    Set<Id> locationIds = new Set<Id>();
    for (Schema.Location loc : locationsByCode.values()) {
      locationIds.add(loc.Id);
    }
    // WARN: 같은 재고를 동시에 사용·이동·동기화해도 값이 꼬이지 않게 잠금
    Map<String, ProductItem> itemsByKey = new Map<String, ProductItem>();
    for (ProductItem item : [
      SELECT Id, LocationId, Product2Id, QuantityOnHand
      FROM ProductItem
      WHERE
        LocationId IN :locationIds
        AND Product2Id IN :productIdByCode.values()
      WITH SYSTEM_MODE
      FOR UPDATE
    ]) {
      itemsByKey.put(item.LocationId + '|' + item.Product2Id, item);
    }

    Map<String, ProductItem> newItemsByKey = new Map<String, ProductItem>();
    Map<Id, ProductItem> changedItemsById = new Map<Id, ProductItem>();
    List<ErpInboundLog__c> logs = new List<ErpInboundLog__c>();
    for (Movement m : changes) {
      ErpInboundLog__c log = newLog(m);
      logs.add(log);
      Schema.Location loc = locationsByCode.get(m.locationCode);
      Id productId = productIdByCode.get(m.partCode);
      if (loc == null || productId == null) {
        markError(
          log,
          CODE_UNKNOWN,
          'Salesforce에 없는 ' +
            (loc == null ? '위치 코드' : '부품 코드') +
            '입니다.'
        );
        continue;
      }
      String key = loc.Id + '|' + productId;
      ProductItem item = itemsByKey.containsKey(key)
        ? itemsByKey.get(key)
        : newItemsByKey.get(key);
      Decimal current = item == null ||
        item.QuantityOnHand == null
        ? 0
        : item.QuantityOnHand;
      Decimal next = current + m.quantityChange;
      if (next < 0) {
        markError(
          log,
          CODE_NEGATIVE,
          '반영하면 Salesforce 재고가 0 미만(' +
            next +
            ')이 됩니다. 재고를 확인하세요.'
        );
        continue;
      }
      if (item == null) {
        // DESC: Salesforce에 없던 위치+부품 재고 → 새로 만듦 (같은 쪽 안에서 다시 나오면 이어서 누적)
        item = new ProductItem(
          LocationId = loc.Id,
          Product2Id = productId,
          OwnerId = loc.OwnerId,
          QuantityUnitOfMeasure = UOM_BY_ERP_UNIT.get(m.unit)
        );
        newItemsByKey.put(key, item);
        result.createdItems++;
      } else if (item.Id != null) {
        changedItemsById.put(item.Id, item);
      }
      item.QuantityOnHand = next;
      log.Result__c = RESULT_APPLIED;
      log.QuantityAfter__c = next;
      log.Message__c = '[OK] ' + current + ' → ' + next;
      result.applied++;
    }
    for (ErpInboundLog__c log : logs) {
      if (log.Result__c == RESULT_ERROR) {
        result.errors++;
      }
    }
    // DESC: 하나라도 실패하면 예외 → 이 쪽 전체가 취소되고 이력 번호도 그대로 (다음 실행에서 다시)
    Database.insert(newItemsByKey.values(), true, AccessLevel.SYSTEM_MODE);
    Database.update(changedItemsById.values(), true, AccessLevel.SYSTEM_MODE);
    // DESC: MovementId__c 고유 → 같은 변동이 두 번 들어오면 저장이 거부돼 이중 반영되지 않음
    Database.insert(logs, true, AccessLevel.SYSTEM_MODE);
  }

  private static ErpInboundLog__c newLog(Movement m) {
    return new ErpInboundLog__c(
      MovementId__c = m.id,
      MovementType__c = m.type,
      LocationCode__c = m.locationCode,
      PartCode__c = m.partCode,
      QuantityChange__c = m.quantityChange,
      MovementAt__c = m.createdAt
    );
  }

  private static void markError(
    ErpInboundLog__c log,
    String code,
    String message
  ) {
    log.Result__c = RESULT_ERROR;
    log.Message__c = ('[' + code + '] ' + message).left(255);
  }

  private static Long toLong(Object value) {
    return value == null
      ? null
      : Decimal.valueOf(String.valueOf(value)).longValue();
  }
}
