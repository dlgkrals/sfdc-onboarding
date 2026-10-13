/**
 * @description ERP 재고 연동 서비스 — 사용 부품 → ERP 재고 차감 (IF-03)
 *              요청: Named Credential HG_ErpMock (키는 External Credential, x-api-key 헤더 merge field)
 *              결과 기록(시스템 모드): 전송 상태·메시지·일시·재시도 횟수·ERP 남은 수량·재고 불일치
 *              - OK → 완료(Synced). ERP 남은 수량 기록, Salesforce 제품 항목 수량과 다르면 불일치 체크 (수량은 고치지 않음)
 *              - 업무 거부(재고 부족·없는 코드 등) → 확인 필요(NeedsReview) — 재시도해도 같은 결과
 *              - 일시적 실패(5xx·401·시간 초과·연결 실패) → 실패(Failed) — 매시 재전송, 상한 초과 시 확인 필요 [RETRY_EXHAUSTED]
 *              메시지 형식: "[코드] 내용" (삭제 규칙이 코드로 판단)
 *              삭제: 허용된 건(ERP 미반영 확실)만 그 수량만큼 Salesforce 재고를 되돌림 (현재 + 삭제 수량, 잠금 후 갱신)
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 5번: 사용 부품 → ERP)
 * 1.1    2026-10-13    Edwin     restoreStockForDeleted 추가 (삭제 시 재고 되돌림, decision-log 11 A안)
 * ----------------------------------------------------------------------------
 * @see ErpSyncQueueable, ProductConsumedTriggerHandler, erp-mock/src/index.js, docs/interface_definition.md IF-03
 */
// DESC: 기사로 실행돼도 접수·장비·재고 필드를 읽고 사용자에게 읽기 전용인 ERP 필드를 써야 하므로 조회·저장 모두 SYSTEM_MODE
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
    if (consumedIds == null || consumedIds.isEmpty()) {
      return;
    }
    if (Test.isRunningTest() && !enqueueInTests) {
      return;
    }
    // WARN: 이미 Queueable 한도를 다 쓴 트랜잭션이면 대기(Pending)로 남고 재전송 Batch가 보냄
    if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
      System.enqueueJob(new ErpSyncQueueable(consumedIds, false));
    }
  }

  /**
   * @description 사용 부품을 ERP로 전송하고 결과를 기록 (Queueable·재전송 Batch에서 호출, 콜아웃 → 마지막에 저장 1회)
   * @param consumedIds 사용 부품 Id
   * @param isRetry     재전송이면 true (일시적 실패 시 재시도 횟수 증가·상한 판정)
   * @return 저장한 사용 부품 (테스트·로그용)
   */
  public static List<ProductConsumed> sendConsumed(
    Set<Id> consumedIds,
    Boolean isRetry
  ) {
    List<ProductConsumed> toUpdate = new List<ProductConsumed>();
    if (consumedIds == null || consumedIds.isEmpty()) {
      return toUpdate;
    }
    Integer maxRetry = getMaxRetry();
    Datetime attemptedAt = Datetime.now();

    List<ProductConsumed> sendable = new List<ProductConsumed>();
    Map<Id, ProductConsumed> sourcesById = new Map<Id, ProductConsumed>();
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
      sourcesById.put(pc.Id, pc);
      if (String.isBlank(locationCode(pc)) || String.isBlank(partCode(pc))) {
        // DESC: ERP 위치·부품 코드가 없으면 보내도 거부되므로 바로 확인 필요
        toUpdate.add(
          result(
            pc.Id,
            STATUS_NEEDS_REVIEW,
            '[' + CODE_MISSING + '] ERP 위치 코드 또는 부품 코드가 없습니다.',
            attemptedAt
          )
        );
      } else {
        sendable.add(pc);
      }
    }

    // PERF: 200건씩 한 번에 (사용 부품 200건 = 콜아웃 1번). 콜아웃을 모두 끝낸 뒤 저장
    for (
      Integer start = 0; start < sendable.size(); start += MAX_ITEMS_PER_CALL
    ) {
      List<ProductConsumed> chunk = new List<ProductConsumed>();
      for (
        Integer i = start;
        i < Math.min(start + MAX_ITEMS_PER_CALL, sendable.size());
        i++
      ) {
        chunk.add(sendable[i]);
      }
      toUpdate.addAll(sendChunk(chunk, attemptedAt));
    }

    for (ProductConsumed updated : toUpdate) {
      ProductConsumed source = sourcesById.get(updated.Id);
      Decimal previousRetries = source.ErpRetryCount__c == null
        ? 0
        : source.ErpRetryCount__c;
      updated.ErpRetryCount__c = previousRetries;
      if (isRetry && updated.ErpSyncStatus__c == STATUS_FAILED) {
        updated.ErpRetryCount__c = previousRetries + 1;
        if (updated.ErpRetryCount__c >= maxRetry) {
          updated.ErpSyncStatus__c = STATUS_NEEDS_REVIEW;
          updated.ErpSyncMessage__c = truncate(
            '[' +
              CODE_RETRY_EXHAUSTED +
              '] 재시도 ' +
              maxRetry +
              '회 초과. 마지막 오류: ' +
              updated.ErpSyncMessage__c
          );
        }
      }
    }
    // DESC: 일부 저장 실패가 나머지를 막지 않도록 allOrNone = false
    Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
    return toUpdate;
  }

  private static List<ProductConsumed> sendChunk(
    List<ProductConsumed> chunk,
    Datetime attemptedAt
  ) {
    List<Map<String, Object>> items = new List<Map<String, Object>>();
    for (ProductConsumed pc : chunk) {
      items.add(
        new Map<String, Object>{
          'refId' => pc.Id,
          'locationCode' => locationCode(pc),
          'partCode' => partCode(pc),
          'quantity' => pc.QuantityConsumed,
          'workOrderNumber' => pc.WorkOrder?.WorkOrderNumber
        }
      );
    }
    HttpRequest request = new HttpRequest();
    request.setEndpoint(CONSUME_ENDPOINT);
    request.setMethod('POST');
    request.setTimeout(TIMEOUT_MS);
    request.setHeader('Content-Type', 'application/json; charset=utf-8');
    request.setBody(
      JSON.serialize(new Map<String, Object>{ 'items' => items })
    );

    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (Exception e) {
      // DESC: 시간 초과·연결 실패 → 일시적 실패
      return allWith(
        chunk,
        STATUS_FAILED,
        '[CONNECTION] ' + e.getMessage(),
        attemptedAt
      );
    }
    Integer status = response.getStatusCode();
    if (status != 200) {
      // DESC: 400(요청 형식)은 다시 보내도 같으므로 확인 필요, 그 외(401·5xx 등)는 일시적 실패
      String state = status == 400 ? STATUS_NEEDS_REVIEW : STATUS_FAILED;
      return allWith(
        chunk,
        state,
        '[HTTP_' + status + '] ' + response.getBody(),
        attemptedAt
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
      return allWith(
        chunk,
        STATUS_FAILED,
        '[BAD_RESPONSE] ERP 응답을 읽을 수 없습니다.',
        attemptedAt
      );
    }

    List<ProductConsumed> updates = new List<ProductConsumed>();
    for (ProductConsumed pc : chunk) {
      Map<String, Object> r = resultsByRefId.get(String.valueOf(pc.Id));
      if (r == null) {
        r = resultsByRefId.get(String.valueOf(pc.Id).left(15));
      }
      if (r == null) {
        updates.add(
          result(
            pc.Id,
            STATUS_FAILED,
            '[NO_RESULT] ERP 응답에 이 사용 부품 결과가 없습니다.',
            attemptedAt
          )
        );
        continue;
      }
      if ((String) r.get('status') == 'OK') {
        Decimal remaining = r.get('remainingQty') == null
          ? null
          : Decimal.valueOf(String.valueOf(r.get('remainingQty')));
        ProductConsumed ok = result(
          pc.Id,
          STATUS_SYNCED,
          '[OK] ERP 재고 차감 완료',
          attemptedAt
        );
        ok.ErpRemainingQty__c = remaining;
        // DESC: Salesforce 표준 차감 후 수량과 ERP 남은 수량 비교 (다르면 표시만, 수량은 고치지 않음)
        ok.InventoryMismatch__c =
          remaining != null &&
          pc.ProductItem?.QuantityOnHand != null &&
          remaining != pc.ProductItem.QuantityOnHand;
        updates.add(ok);
      } else {
        updates.add(
          result(
            pc.Id,
            STATUS_NEEDS_REVIEW,
            '[' + r.get('code') + '] ' + r.get('message'),
            attemptedAt
          )
        );
      }
    }
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

  private static String locationCode(ProductConsumed pc) {
    return pc.ProductItem?.Location?.ErpLocationCode__c;
  }

  private static String partCode(ProductConsumed pc) {
    return String.isNotBlank(pc.Product2?.ErpPartCode__c)
      ? pc.Product2.ErpPartCode__c
      : pc.ProductItem?.Product2?.ErpPartCode__c;
  }

  private static List<ProductConsumed> allWith(
    List<ProductConsumed> chunk,
    String status,
    String message,
    Datetime attemptedAt
  ) {
    List<ProductConsumed> updates = new List<ProductConsumed>();
    for (ProductConsumed pc : chunk) {
      updates.add(result(pc.Id, status, message, attemptedAt));
    }
    return updates;
  }

  private static ProductConsumed result(
    Id id,
    String status,
    String message,
    Datetime attemptedAt
  ) {
    return new ProductConsumed(
      Id = id,
      ErpSyncStatus__c = status,
      ErpSyncMessage__c = truncate(message),
      ErpSyncedAt__c = attemptedAt
    );
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
