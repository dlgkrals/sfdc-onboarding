/**
 * @description ERP 재고 연동 서비스 — 사용 부품 → ERP 재고 차감 (IF-03), 재고 이동 → ERP (IF-06)
 *              요청: Named Credential HG_ErpMock (키는 External Credential, x-api-key 헤더 merge field)
 *              결과 기록(시스템 모드): 전송 상태·메시지·일시·재시도 횟수·ERP 남은 수량·재고 불일치
 *              - OK → 완료(Synced). ERP 남은 수량 기록, Salesforce 제품 항목 수량과 다르면 불일치 체크 (수량은 고치지 않음)
 *              - 업무 거부(재고 부족·없는 코드 등) → 확인 필요(NeedsReview) — 재시도해도 같은 결과
 *              - 일시적 실패(5xx·401·시간 초과·연결 실패) → 실패(Failed) — 매시 재전송, 상한 초과 시 확인 필요 [RETRY_EXHAUSTED]
 *              메시지 형식: "[코드] 내용" (삭제 규칙이 코드로 판단)
 *              삭제: 허용된 건(ERP 미반영 확실)만 그 수량만큼 Salesforce 재고를 되돌림 (현재 + 삭제 수량, 잠금 후 갱신)
 *              두 오브젝트의 ERP 필드 API 이름이 같아서(ErpSyncStatus__c 등) 전송·결과·재시도 처리는 SObject로 공통 사용
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 5번: 사용 부품 → ERP)
 * 1.1    2026-10-13    Edwin     restoreStockForDeleted 추가 (삭제 시 재고 되돌림, decision-log 11 A안)
 * 1.2    2026-10-13    Edwin     재고 이동 → ERP(IF-06) 추가, 전송·결과·재시도 공통화, 콜아웃과 저장 분리(build*·save)
 * ----------------------------------------------------------------------------
 * @see ErpSyncQueueable, ProductConsumedTriggerHandler, ProductTransferTriggerHandler, erp-mock/src/index.js, docs/interface_definition.md IF-03·IF-06
 */
// DESC: 기사로 실행돼도 재고·위치 필드를 읽고 사용자에게 읽기 전용인 ERP 필드를 써야 하므로 조회·저장 모두 SYSTEM_MODE
public with sharing class ErpInventoryService {
  public static final String STATUS_PENDING = 'Pending';
  public static final String STATUS_SYNCED = 'Synced';
  public static final String STATUS_FAILED = 'Failed';
  public static final String STATUS_NEEDS_REVIEW = 'NeedsReview';
  public static final String CODE_RETRY_EXHAUSTED = 'RETRY_EXHAUSTED';
  public static final String CODE_MISSING = 'MISSING_CODE';

  @TestVisible
  private static final Integer MAX_ITEMS_PER_CALL = 200;
  private static final Integer TIMEOUT_MS = 60000;
  private static final Integer MESSAGE_MAX_LENGTH = 255;
  private static final Integer DEFAULT_MAX_RETRY = 3;
  private static final String CONSUME_ENDPOINT = 'callout:HG_ErpMock/api/stock/consume';
  private static final String TRANSFER_ENDPOINT = 'callout:HG_ErpMock/api/stock/transfer';
  // DESC: ERP 응답 대신 만든 결과(연결 실패·HTTP 오류)를 표시하는 키
  private static final String KEY_STATE = '_state';
  private static final String KEY_MESSAGE = '_message';

  /**
   * @description 테스트에서 트리거가 Queueable을 넣을지 (ERP 테스트만 true. 다른 테스트가 콜아웃에 의존하지 않도록)
   */
  @TestVisible
  private static Boolean enqueueInTests = false;

  /**
   * @description 사용 부품 저장 직후 ERP 전송을 비동기로 예약 (트리거 after insert)
   * @param consumedIds 사용 부품 Id
   */
  public static void enqueueConsumed(Set<Id> consumedIds) {
    enqueue(consumedIds, new Set<Id>());
  }

  /**
   * @description 재고 이동 수령 직후 ERP 전송을 비동기로 예약 (트리거 after insert·update)
   * @param transferIds 재고 이동 Id
   */
  public static void enqueueTransfers(Set<Id> transferIds) {
    enqueue(new Set<Id>(), transferIds);
  }

  private static void enqueue(Set<Id> consumedIds, Set<Id> transferIds) {
    if (
      (consumedIds == null || consumedIds.isEmpty()) &&
      (transferIds == null || transferIds.isEmpty())
    ) {
      return;
    }
    if (Test.isRunningTest() && !enqueueInTests) {
      return;
    }
    // WARN: 이미 Queueable 한도를 다 쓴 트랜잭션이면 대기(Pending)로 남고 재전송 Batch가 보냄
    if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
      System.enqueueJob(new ErpSyncQueueable(consumedIds, transferIds, false));
    }
  }

  /**
   * @description 사용 부품을 ERP로 전송하고 결과를 저장 (콜아웃 → 마지막에 저장 1회)
   * @param consumedIds 사용 부품 Id
   * @param isRetry     재전송이면 true (일시적 실패 시 재시도 횟수 증가·상한 판정)
   * @return 저장한 사용 부품 (테스트·로그용)
   */
  public static List<ProductConsumed> sendConsumed(
    Set<Id> consumedIds,
    Boolean isRetry
  ) {
    List<ProductConsumed> updates = buildConsumedUpdates(consumedIds, isRetry);
    save(updates);
    return updates;
  }

  /**
   * @description 재고 이동을 ERP로 전송하고 결과를 저장 (콜아웃 → 마지막에 저장 1회)
   * @param transferIds 재고 이동 Id
   * @param isRetry     재전송이면 true
   * @return 저장한 재고 이동 (테스트·로그용)
   */
  public static List<ProductTransfer> sendTransfers(
    Set<Id> transferIds,
    Boolean isRetry
  ) {
    List<ProductTransfer> updates = buildTransferUpdates(transferIds, isRetry);
    save(updates);
    return updates;
  }

  /**
   * @description 결과 저장. 저장(DML) 뒤에는 콜아웃을 할 수 없으므로 Queueable은 build*로 모두 보낸 다음 한꺼번에 저장
   *              일부 저장 실패가 나머지를 막지 않도록 allOrNone = false
   * @param updates build*가 만든 결과
   */
  public static void save(List<SObject> updates) {
    if (updates != null && !updates.isEmpty()) {
      Database.update(updates, false, AccessLevel.SYSTEM_MODE);
    }
  }

  /**
   * @description 사용 부품 → ERP 차감 요청을 보내고 저장할 결과를 만듦 (DML 없음)
   * @param consumedIds 사용 부품 Id
   * @param isRetry     재전송이면 true
   * @return 저장할 사용 부품 (Id + ERP 필드)
   */
  public static List<ProductConsumed> buildConsumedUpdates(
    Set<Id> consumedIds,
    Boolean isRetry
  ) {
    List<ProductConsumed> updates = new List<ProductConsumed>();
    if (consumedIds == null || consumedIds.isEmpty()) {
      return updates;
    }
    Datetime attemptedAt = Datetime.now();
    List<ProductConsumed> sendable = new List<ProductConsumed>();
    Map<Id, Decimal> retriesById = new Map<Id, Decimal>();
    List<Map<String, Object>> items = new List<Map<String, Object>>();
    for (ProductConsumed pc : [
      SELECT
        Id,
        QuantityConsumed,
        ErpRetryCount__c,
        ProductItem.QuantityOnHand,
        ProductItem.Location.ErpLocationCode__c,
        Product2.ErpPartCode__c,
        ProductItem.Product2.ErpPartCode__c,
        WorkOrder.WorkOrderNumber
      FROM ProductConsumed
      WHERE Id IN :consumedIds
      WITH SYSTEM_MODE
    ]) {
      retriesById.put(pc.Id, pc.ErpRetryCount__c);
      String locationCode = pc.ProductItem?.Location?.ErpLocationCode__c;
      String partCode = firstNotBlank(
        pc.Product2?.ErpPartCode__c,
        pc.ProductItem?.Product2?.ErpPartCode__c
      );
      if (String.isBlank(locationCode) || String.isBlank(partCode)) {
        // DESC: ERP 위치·부품 코드가 없으면 보내도 거부되므로 바로 확인 필요
        updates.add(
          (ProductConsumed) result(
            pc.Id,
            STATUS_NEEDS_REVIEW,
            '[' + CODE_MISSING + '] ERP 위치 코드 또는 부품 코드가 없습니다.',
            attemptedAt
          )
        );
        continue;
      }
      sendable.add(pc);
      items.add(
        new Map<String, Object>{
          'refId' => pc.Id,
          'locationCode' => locationCode,
          'partCode' => partCode,
          'quantity' => pc.QuantityConsumed,
          'workOrderNumber' => pc.WorkOrder?.WorkOrderNumber
        }
      );
    }

    Map<String, Map<String, Object>> resultsByRefId = post(
      CONSUME_ENDPOINT,
      items
    );
    for (ProductConsumed pc : sendable) {
      Map<String, Object> r = findResult(resultsByRefId, pc.Id);
      SObject updated = interpret(pc.Id, r, attemptedAt, 'ERP 재고 차감 완료');
      if (updated.get('ErpSyncStatus__c') == STATUS_SYNCED) {
        Decimal remaining = toDecimal(r.get('remainingQty'));
        updated.put('ErpRemainingQty__c', remaining);
        // DESC: Salesforce 표준 차감 후 수량과 ERP 남은 수량 비교 (다르면 표시만, 수량은 고치지 않음)
        updated.put(
          'InventoryMismatch__c',
          differs(remaining, pc.ProductItem?.QuantityOnHand)
        );
      }
      updates.add((ProductConsumed) updated);
    }
    applyRetry(updates, retriesById, isRetry);
    return updates;
  }

  /**
   * @description 재고 이동 → ERP 이동 요청을 보내고 저장할 결과를 만듦 (DML 없음)
   *              수량 = 받은 수량(없으면 보낸 수량). 참조 = 재고 이동 번호
   *              불일치 = ERP 출발·도착 남은 수량 중 하나라도 Salesforce 출발 재고·도착 위치의 같은 부품 재고와 다름
   * @param transferIds 재고 이동 Id
   * @param isRetry     재전송이면 true
   * @return 저장할 재고 이동 (Id + ERP 필드)
   */
  public static List<ProductTransfer> buildTransferUpdates(
    Set<Id> transferIds,
    Boolean isRetry
  ) {
    List<ProductTransfer> updates = new List<ProductTransfer>();
    if (transferIds == null || transferIds.isEmpty()) {
      return updates;
    }
    Datetime attemptedAt = Datetime.now();
    List<ProductTransfer> transfers = [
      SELECT
        Id,
        ProductTransferNumber,
        QuantitySent,
        QuantityReceived,
        ErpRetryCount__c,
        Product2Id,
        Product2.ErpPartCode__c,
        DestinationLocationId,
        DestinationLocation.ErpLocationCode__c,
        SourceProductItem.QuantityOnHand,
        SourceProductItem.Product2Id,
        SourceProductItem.Product2.ErpPartCode__c,
        SourceProductItem.Location.ErpLocationCode__c
      FROM ProductTransfer
      WHERE Id IN :transferIds
      WITH SYSTEM_MODE
    ];

    // PERF: 도착 위치 재고(위치 + 부품)를 한 번에 조회해 Map으로
    Set<Id> destinationIds = new Set<Id>();
    Set<Id> productIds = new Set<Id>();
    for (ProductTransfer pt : transfers) {
      destinationIds.add(pt.DestinationLocationId);
      productIds.add(productIdOf(pt));
    }
    Map<String, Decimal> destinationQtyByStockKey = new Map<String, Decimal>();
    for (ProductItem item : [
      SELECT LocationId, Product2Id, QuantityOnHand
      FROM ProductItem
      WHERE LocationId IN :destinationIds AND Product2Id IN :productIds
      WITH SYSTEM_MODE
    ]) {
      destinationQtyByStockKey.put(
        stockKey(item.LocationId, item.Product2Id),
        item.QuantityOnHand
      );
    }

    List<ProductTransfer> sendable = new List<ProductTransfer>();
    Map<Id, Decimal> retriesById = new Map<Id, Decimal>();
    List<Map<String, Object>> items = new List<Map<String, Object>>();
    for (ProductTransfer pt : transfers) {
      retriesById.put(pt.Id, pt.ErpRetryCount__c);
      String fromCode = pt.SourceProductItem?.Location?.ErpLocationCode__c;
      String toCode = pt.DestinationLocation?.ErpLocationCode__c;
      String partCode = firstNotBlank(
        pt.Product2?.ErpPartCode__c,
        pt.SourceProductItem?.Product2?.ErpPartCode__c
      );
      if (
        String.isBlank(fromCode) ||
        String.isBlank(toCode) ||
        String.isBlank(partCode)
      ) {
        updates.add(
          (ProductTransfer) result(
            pt.Id,
            STATUS_NEEDS_REVIEW,
            '[' +
              CODE_MISSING +
              '] ERP 출발·도착 위치 코드 또는 부품 코드가 없습니다.',
            attemptedAt
          )
        );
        continue;
      }
      sendable.add(pt);
      items.add(
        new Map<String, Object>{
          'refId' => pt.Id,
          'fromLocationCode' => fromCode,
          'toLocationCode' => toCode,
          'partCode' => partCode,
          'quantity' => pt.QuantityReceived != null
            ? pt.QuantityReceived
            : pt.QuantitySent,
          'reference' => pt.ProductTransferNumber
        }
      );
    }

    Map<String, Map<String, Object>> resultsByRefId = post(
      TRANSFER_ENDPOINT,
      items
    );
    for (ProductTransfer pt : sendable) {
      Map<String, Object> r = findResult(resultsByRefId, pt.Id);
      SObject updated = interpret(pt.Id, r, attemptedAt, 'ERP 재고 이동 완료');
      if (updated.get('ErpSyncStatus__c') == STATUS_SYNCED) {
        Decimal sourceRemaining = toDecimal(r.get('sourceRemainingQty'));
        Decimal destinationRemaining = toDecimal(
          r.get('destinationRemainingQty')
        );
        updated.put('ErpSourceRemainingQty__c', sourceRemaining);
        updated.put('ErpDestinationRemainingQty__c', destinationRemaining);
        Decimal destinationQty = destinationQtyByStockKey.get(
          stockKey(pt.DestinationLocationId, productIdOf(pt))
        );
        updated.put(
          'InventoryMismatch__c',
          differs(sourceRemaining, pt.SourceProductItem?.QuantityOnHand) ||
          differs(destinationRemaining, destinationQty)
        );
      }
      updates.add((ProductTransfer) updated);
    }
    applyRetry(updates, retriesById, isRetry);
    return updates;
  }

  /**
   * @description 삭제 가능 여부: ERP에 반영되지 않은 것이 확실한 경우만
   *              실패(일시적) · 영구적 실패로 확인 필요 · 아직 전송 대상이 아닌 기존 데이터(상태 없음)는 허용
   *              대기 · 완료 · 재시도 초과(마지막 시간 초과 때 ERP 처리 여부를 알 수 없음)는 불가
   */
  public static Boolean canDelete(ProductConsumed pc) {
    String status = pc.ErpSyncStatus__c;
    if (String.isBlank(status) || status == STATUS_FAILED) {
      return true;
    }
    if (status == STATUS_NEEDS_REVIEW) {
      return pc.ErpSyncMessage__c == null ||
        !pc.ErpSyncMessage__c.startsWith('[' + CODE_RETRY_EXHAUSTED + ']');
    }
    return false;
  }

  /**
   * @description 삭제된 사용 부품 수량만큼 Salesforce 재고(제품 항목)를 되돌림 (decision-log 11, A안)
   *              표준은 삭제해도 보유량을 되돌리지 않으므로 Apex가 보정. 삭제 규칙(canDelete)을 통과한 건 = ERP 미반영이 확실한 건만 들어옴
   *              덮어쓰기가 아니라 "현재 수량 + 삭제한 수량". 동시에 다른 사용·이동이 있어도 값이 꼬이지 않게 FOR UPDATE로 잠금
   * @param deleted 삭제된 사용 부품 (Trigger.old)
   * @return 수량을 고친 제품 항목
   */
  public static List<ProductItem> restoreStockForDeleted(
    List<ProductConsumed> deleted
  ) {
    // DESC: 같은 재고에서 여러 건을 지우면 합쳐서 한 번에 되돌림
    Map<Id, Decimal> restoreQtyByItem = new Map<Id, Decimal>();
    for (ProductConsumed pc : deleted) {
      if (pc.ProductItemId == null || pc.QuantityConsumed == null) {
        continue;
      }
      Decimal current = restoreQtyByItem.containsKey(pc.ProductItemId)
        ? restoreQtyByItem.get(pc.ProductItemId)
        : 0;
      restoreQtyByItem.put(pc.ProductItemId, current + pc.QuantityConsumed);
    }
    if (restoreQtyByItem.isEmpty()) {
      return new List<ProductItem>();
    }
    // WARN: 기사는 차량 재고 소유자지만, 시스템이 계산하는 보정이므로 SYSTEM_MODE로 명시 (API 67 기본 user mode)
    List<ProductItem> items = [
      SELECT Id, QuantityOnHand
      FROM ProductItem
      WHERE Id IN :restoreQtyByItem.keySet()
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    for (ProductItem item : items) {
      item.QuantityOnHand =
        (item.QuantityOnHand == null ? 0 : item.QuantityOnHand) +
        restoreQtyByItem.get(item.Id);
    }
    Database.update(items, true, AccessLevel.SYSTEM_MODE);
    return items;
  }

  // DESC: 200건씩 나눠 POST (200건 = 콜아웃 1번). 묶음이 실패하면 그 묶음 전체에 상태·메시지를 넣은 결과를 만듦
  private static Map<String, Map<String, Object>> post(
    String endpoint,
    List<Map<String, Object>> items
  ) {
    Map<String, Map<String, Object>> resultsByRefId = new Map<String, Map<String, Object>>();
    for (Integer start = 0; start < items.size(); start += MAX_ITEMS_PER_CALL) {
      List<Map<String, Object>> chunk = new List<Map<String, Object>>();
      for (
        Integer i = start;
        i < Math.min(start + MAX_ITEMS_PER_CALL, items.size());
        i++
      ) {
        chunk.add(items[i]);
      }
      resultsByRefId.putAll(postChunk(endpoint, chunk));
    }
    return resultsByRefId;
  }

  private static Map<String, Map<String, Object>> postChunk(
    String endpoint,
    List<Map<String, Object>> chunk
  ) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(endpoint);
    request.setMethod('POST');
    request.setTimeout(TIMEOUT_MS);
    request.setHeader('Content-Type', 'application/json; charset=utf-8');
    request.setBody(
      JSON.serialize(new Map<String, Object>{ 'items' => chunk })
    );

    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (Exception e) {
      // DESC: 시간 초과·연결 실패 → 일시적 실패
      return chunkWith(chunk, STATUS_FAILED, '[CONNECTION] ' + e.getMessage());
    }
    Integer status = response.getStatusCode();
    if (status != 200) {
      // DESC: 400(요청 형식)은 다시 보내도 같으므로 확인 필요, 그 외(401·5xx 등)는 일시적 실패
      return chunkWith(
        chunk,
        status == 400 ? STATUS_NEEDS_REVIEW : STATUS_FAILED,
        '[HTTP_' + status + '] ' + response.getBody()
      );
    }
    Map<String, Map<String, Object>> resultsByRefId = new Map<String, Map<String, Object>>();
    try {
      Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
        response.getBody()
      );
      for (Object raw : (List<Object>) body.get('results')) {
        Map<String, Object> r = (Map<String, Object>) raw;
        resultsByRefId.put((String) r.get('refId'), r);
      }
    } catch (Exception e) {
      return chunkWith(
        chunk,
        STATUS_FAILED,
        '[BAD_RESPONSE] ERP 응답을 읽을 수 없습니다.'
      );
    }
    return resultsByRefId;
  }

  private static Map<String, Map<String, Object>> chunkWith(
    List<Map<String, Object>> chunk,
    String state,
    String message
  ) {
    Map<String, Map<String, Object>> resultsByRefId = new Map<String, Map<String, Object>>();
    for (Map<String, Object> item : chunk) {
      resultsByRefId.put(
        String.valueOf(item.get('refId')),
        new Map<String, Object>{ KEY_STATE => state, KEY_MESSAGE => message }
      );
    }
    return resultsByRefId;
  }

  // DESC: ERP가 15자리 Id로 돌려줘도 찾음
  private static Map<String, Object> findResult(
    Map<String, Map<String, Object>> resultsByRefId,
    Id recordId
  ) {
    Map<String, Object> r = resultsByRefId.get(String.valueOf(recordId));
    return r != null
      ? r
      : resultsByRefId.get(String.valueOf(recordId).left(15));
  }

  // DESC: 결과 1건 → 상태·메시지 (완료일 때 남은 수량 등은 호출한 쪽에서 채움)
  private static SObject interpret(
    Id recordId,
    Map<String, Object> r,
    Datetime attemptedAt,
    String okMessage
  ) {
    if (r == null) {
      return result(
        recordId,
        STATUS_FAILED,
        '[NO_RESULT] ERP 응답에 이 건의 결과가 없습니다.',
        attemptedAt
      );
    }
    if (r.containsKey(KEY_STATE)) {
      return result(
        recordId,
        (String) r.get(KEY_STATE),
        (String) r.get(KEY_MESSAGE),
        attemptedAt
      );
    }
    if ((String) r.get('status') == 'OK') {
      return result(recordId, STATUS_SYNCED, '[OK] ' + okMessage, attemptedAt);
    }
    return result(
      recordId,
      STATUS_NEEDS_REVIEW,
      '[' + r.get('code') + '] ' + r.get('message'),
      attemptedAt
    );
  }

  // DESC: 재전송에서 또 일시적 실패면 횟수 + 1, 상한 도달 시 확인 필요 [RETRY_EXHAUSTED]
  private static void applyRetry(
    List<SObject> updates,
    Map<Id, Decimal> retriesById,
    Boolean isRetry
  ) {
    Integer maxRetry = getMaxRetry();
    for (SObject updated : updates) {
      Decimal previous = retriesById.get(updated.Id);
      Decimal retries = previous == null ? 0 : previous;
      if (isRetry == true && updated.get('ErpSyncStatus__c') == STATUS_FAILED) {
        retries++;
        if (retries >= maxRetry) {
          updated.put('ErpSyncStatus__c', STATUS_NEEDS_REVIEW);
          updated.put(
            'ErpSyncMessage__c',
            truncate(
              '[' +
                CODE_RETRY_EXHAUSTED +
                '] 재시도 ' +
                maxRetry +
                '회 초과. 마지막 오류: ' +
                updated.get('ErpSyncMessage__c')
            )
          );
        }
      }
      updated.put('ErpRetryCount__c', retries);
    }
  }

  private static SObject result(
    Id recordId,
    String status,
    String message,
    Datetime attemptedAt
  ) {
    SObject record = recordId.getSObjectType().newSObject(recordId);
    record.put('ErpSyncStatus__c', status);
    record.put('ErpSyncMessage__c', truncate(message));
    record.put('ErpSyncedAt__c', attemptedAt);
    return record;
  }

  private static Id productIdOf(ProductTransfer pt) {
    return pt.Product2Id != null
      ? pt.Product2Id
      : pt.SourceProductItem?.Product2Id;
  }

  private static String stockKey(Id locationId, Id productId) {
    return locationId + '|' + productId;
  }

  private static String firstNotBlank(String first, String second) {
    return String.isNotBlank(first) ? first : second;
  }

  private static Decimal toDecimal(Object value) {
    return value == null ? null : Decimal.valueOf(String.valueOf(value));
  }

  private static Boolean differs(Decimal erpQty, Decimal salesforceQty) {
    return erpQty != null && salesforceQty != null && erpQty != salesforceQty;
  }

  private static String truncate(String message) {
    return message == null ? null : message.left(MESSAGE_MAX_LENGTH);
  }

  @TestVisible
  private static Integer getMaxRetry() {
    ServiceSetting__mdt setting = ServiceSetting__mdt.getInstance(
      'ErpMaxRetry'
    );
    return setting?.Value__c == null
      ? DEFAULT_MAX_RETRY
      : setting.Value__c.intValue();
  }
}
