/**
 * @description 접수 [기사 배정] 서비스 — 출동(WorkOrder)을 만드는 단일 경로
 *              1) load: 배정 화면에 보일 접수 요약과 배정할 수 있는 기사 목록
 *                 (역할 계층 기준: 내 역할 아래 기사 = 우리 센터 기사, 서비스운영팀장(최상위)은 전체)
 *              2) dispatch: 접수의 장비·고객사·사업장·서비스센터를 복사한 출동 생성(소유자 = 기사, 상태 배정)
 *                 + 같은 저장에서 접수 상태를 처리 중(InProgress)으로. 같은 접수에 다시 배정하면 새 출동(회차 + 1)
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-16
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-16    Edwin     최초 작성 (출동 단일 생성 경로, 센터장 출동 생성 권한 제거와 함께)
 * ----------------------------------------------------------------------------
 * @see Case_Screen_DispatchTechnician (화면 Flow, 빠른 작업 Case.HG_DispatchTechnician),
 *      WorkOrder_BeforeSave_FillAsset (다른 경로로 만든 출동의 빈칸 안전망)
 */
// DESC: 센터장은 출동 생성 권한이 없으므로(수정만) 생성·접수 상태 변경은 시스템 모드.
//       대신 관문을 Apex가 직접 지킴 — 사용자 지정 권한 HG_DispatchWorkOrder, 접수가 실행 사용자에게 보이는지(USER_MODE),
//       고른 기사가 실행 사용자의 역할 아래인지
public without sharing class DispatchService {
  public static final String ACTION_LOAD = 'load';
  public static final String ACTION_DISPATCH = 'dispatch';
  @TestVisible
  private static final String PERMISSION_DISPATCH = 'HG_DispatchWorkOrder';
  private static final String TECHNICIAN_PERMISSION_SET = 'HG_Technician';
  private static final Set<String> CLOSED_STATUSES = new Set<String>{
    'Closed',
    'Canceled'
  };
  private static final String CASE_STATUS_IN_PROGRESS = 'InProgress';
  private static final String WORK_ORDER_STATUS_ASSIGNED = 'Assigned';

  /**
   * @description 화면 Flow 입력. action = load | dispatch
   */
  public class DispatchRequest {
    @InvocableVariable(label='동작(load·dispatch)' required=true)
    public String action;
    @InvocableVariable(label='접수 Id' required=true)
    public Id caseId;
    @InvocableVariable(label='기사 Id')
    public Id technicianId;
    @InvocableVariable(label='출동 목적')
    public String purpose;
    @InvocableVariable(label='방문 예정 일시')
    public Datetime plannedStart;
    @InvocableVariable(label='작업 지시')
    public String instruction;
  }

  /**
   * @description 화면 Flow 출력. 실패는 예외 대신 success = false + message로 돌려줌(화면이 안내)
   */
  public class DispatchResult {
    @InvocableVariable(label='성공')
    public Boolean success = false;
    @InvocableVariable(label='안내 문구')
    public String message;
    @InvocableVariable(label='접수 번호')
    public String caseNumber;
    @InvocableVariable(label='장비')
    public String assetName;
    @InvocableVariable(label='사업장')
    public String siteName;
    @InvocableVariable(label='증상')
    public String symptom;
    @InvocableVariable(label='중요도')
    public String priority;
    @InvocableVariable(label='기존 출동 수')
    public Integer workOrderCount = 0;
    @InvocableVariable(label='배정할 수 있는 기사')
    public List<User> technicians = new List<User>();
    @InvocableVariable(label='만든 출동 Id')
    public Id workOrderId;
    @InvocableVariable(label='만든 출동 번호')
    public String workOrderNumber;
  }

  /**
   * @description 화면 Flow 진입점. 요청 순서대로 결과를 돌려줌
   * @param requests load 또는 dispatch 요청 (여러 건 가능)
   * @return 요청과 같은 순서의 결과
   */
  @InvocableMethod(
    label='기사 배정'
    description='접수 요약·배정할 수 있는 기사(load) / 출동 생성·접수 처리 중(dispatch)'
    category='HG'
  )
  public static List<DispatchResult> run(List<DispatchRequest> requests) {
    List<DispatchResult> results = new List<DispatchResult>();
    List<DispatchRequest> dispatchRequests = new List<DispatchRequest>();
    List<DispatchResult> dispatchResults = new List<DispatchResult>();
    for (DispatchRequest req : requests) {
      DispatchResult result = new DispatchResult();
      results.add(result);
      if (req.action == ACTION_DISPATCH) {
        dispatchRequests.add(req);
        dispatchResults.add(result);
      }
    }
    // DESC: 권한이 없으면 접수를 조회하지 않고 안내만(기사는 접수 오브젝트 권한 자체가 없음)
    if (!FeatureManagement.checkPermission(PERMISSION_DISPATCH)) {
      for (DispatchResult result : results) {
        result.message = System.Label.MSG_DISPATCH_NO_PERMISSION;
      }
      return results;
    }
    // DESC: load도 dispatch도 같은 검사(보이는 접수·종결 여부·기사 유무)를 거침
    Map<Id, Case> casesById = loadVisibleCases(requests);
    Map<Id, User> techniciansById = loadAllowedTechnicians();
    Map<Id, Integer> workOrderCountsByCase = countWorkOrders(
      casesById.keySet()
    );

    for (Integer i = 0; i < requests.size(); i++) {
      DispatchRequest req = requests[i];
      DispatchResult result = results[i];
      Case c = casesById.get(req.caseId);
      fillSummary(result, c, workOrderCountsByCase);
      result.message = checkCase(c);
      if (result.message == null && techniciansById.isEmpty()) {
        result.message = System.Label.MSG_DISPATCH_NO_TECHNICIAN;
      }
      if (result.message == null && req.action == ACTION_LOAD) {
        result.success = true;
        result.technicians = techniciansById.values();
      }
    }
    if (!dispatchRequests.isEmpty()) {
      createWorkOrders(
        dispatchRequests,
        dispatchResults,
        casesById,
        techniciansById,
        workOrderCountsByCase
      );
    }
    return results;
  }

  /**
   * @description 실행 사용자에게 보이는 접수만 (USER_MODE로 공유·권한 확인 후 상세는 시스템 모드)
   */
  private static Map<Id, Case> loadVisibleCases(
    List<DispatchRequest> requests
  ) {
    Set<Id> caseIds = new Set<Id>();
    for (DispatchRequest req : requests) {
      caseIds.add(req.caseId);
    }
    caseIds.remove(null);
    Map<Id, Case> visibleById = new Map<Id, Case>();
    try {
      visibleById.putAll(
        [SELECT Id FROM Case WHERE Id IN :caseIds WITH USER_MODE]
      );
    } catch (QueryException e) {
      // DESC: 접수 오브젝트 권한이 없으면 보이는 접수 없음(안내 문구로)
      return new Map<Id, Case>();
    }
    Set<Id> visibleIds = visibleById.keySet();
    return new Map<Id, Case>(
      [
        SELECT
          Id,
          CaseNumber,
          Subject,
          Status,
          Priority,
          SymptomType__c,
          AssetId,
          Asset.Name,
          AccountId,
          CustomerSite__c,
          CustomerSite__r.Name,
          ServiceCenter__c
        FROM Case
        WHERE Id IN :visibleIds
        WITH SYSTEM_MODE
      ]
    );
  }

  /**
   * @description 배정할 수 있는 기사: HG_Technician 권한 집합을 받은 활성 사용자 중
   *              역할이 실행 사용자 역할의 아래(역할 계층)인 사용자. 이름순
   *              역할이 없는 실행 사용자(역할 미지정 관리자)는 전체
   */
  @TestVisible
  private static Map<Id, User> loadAllowedTechnicians() {
    Id myRoleId = UserInfo.getUserRoleId();
    Map<Id, Id> parentByRoleId = new Map<Id, Id>();
    for (UserRole role : [
      SELECT Id, ParentRoleId
      FROM UserRole
      WITH SYSTEM_MODE
    ]) {
      parentByRoleId.put(role.Id, role.ParentRoleId);
    }
    Map<Id, User> techniciansById = new Map<Id, User>();
    for (User u : [
      SELECT Id, Name, UserRoleId
      FROM User
      WHERE
        IsActive = TRUE
        AND Id IN (
          SELECT AssigneeId
          FROM PermissionSetAssignment
          WHERE PermissionSet.Name = :TECHNICIAN_PERMISSION_SET
        )
      WITH SYSTEM_MODE
      ORDER BY Name
    ]) {
      if (
        myRoleId == null || isBelowRole(u.UserRoleId, myRoleId, parentByRoleId)
      ) {
        techniciansById.put(u.Id, u);
      }
    }
    return techniciansById;
  }

  // DESC: 기사 역할에서 위로 올라가며 실행 사용자 역할을 만나면 아래 역할. 자기 역할과 같은 기사는 제외(부하가 아님)
  private static Boolean isBelowRole(
    Id roleId,
    Id ancestorRoleId,
    Map<Id, Id> parentByRoleId
  ) {
    Id current = parentByRoleId.get(roleId);
    Integer guard = 0;
    while (current != null && guard < 50) {
      if (current == ancestorRoleId) {
        return true;
      }
      current = parentByRoleId.get(current);
      guard++;
    }
    return false;
  }

  private static Map<Id, Integer> countWorkOrders(Set<Id> caseIds) {
    Map<Id, Integer> countsByCase = new Map<Id, Integer>();
    for (AggregateResult ar : [
      SELECT CaseId caseId, COUNT(Id) cnt
      FROM WorkOrder
      WHERE CaseId IN :caseIds
      WITH SYSTEM_MODE
      GROUP BY CaseId
    ]) {
      countsByCase.put((Id) ar.get('caseId'), (Integer) ar.get('cnt'));
    }
    return countsByCase;
  }

  private static void fillSummary(
    DispatchResult result,
    Case c,
    Map<Id, Integer> workOrderCountsByCase
  ) {
    if (c == null) {
      return;
    }
    result.caseNumber = c.CaseNumber;
    result.assetName = c.Asset?.Name;
    result.siteName = c.CustomerSite__r?.Name;
    result.symptom = labelOf(Case.SymptomType__c, c.SymptomType__c);
    result.priority = labelOf(Case.Priority, c.Priority);
    Integer count = workOrderCountsByCase.get(c.Id);
    result.workOrderCount = count == null ? 0 : count;
  }

  // DESC: 배정할 수 없으면 안내 문구, 가능하면 null
  private static String checkCase(Case c) {
    if (c == null) {
      return System.Label.MSG_DISPATCH_NO_CASE;
    }
    if (CLOSED_STATUSES.contains(c.Status)) {
      return System.Label.MSG_DISPATCH_CLOSED;
    }
    if (c.AssetId == null) {
      return System.Label.MSG_DISPATCH_NO_ASSET;
    }
    return null;
  }

  /**
   * @description 검사를 통과한 요청만 출동 생성 + 접수 처리 중. 저장 실패 시 전부 되돌리고 같은 문구로 실패 표시
   */
  private static void createWorkOrders(
    List<DispatchRequest> requests,
    List<DispatchResult> results,
    Map<Id, Case> casesById,
    Map<Id, User> techniciansById,
    Map<Id, Integer> workOrderCountsByCase
  ) {
    List<WorkOrder> workOrders = new List<WorkOrder>();
    List<DispatchResult> createdResults = new List<DispatchResult>();
    Map<Id, Case> casesToUpdate = new Map<Id, Case>();
    for (Integer i = 0; i < requests.size(); i++) {
      DispatchRequest req = requests[i];
      DispatchResult result = results[i];
      if (result.message != null) {
        continue;
      }
      if (req.technicianId == null) {
        result.message = System.Label.MSG_DISPATCH_TECH_REQUIRED;
        continue;
      }
      if (!techniciansById.containsKey(req.technicianId)) {
        result.message = System.Label.MSG_DISPATCH_TECH_NOT_ALLOWED;
        continue;
      }
      Case c = casesById.get(req.caseId);
      // DESC: 같은 접수에 다시 배정하면 회차 + 1 (같은 묶음 안의 여러 건도 차례대로)
      Integer current = workOrderCountsByCase.get(c.Id);
      Integer visitNumber = (current == null ? 0 : current) + 1;
      workOrderCountsByCase.put(c.Id, visitNumber);
      result.workOrderCount = visitNumber;
      workOrders.add(
        new WorkOrder(
          CaseId = c.Id,
          AssetId = c.AssetId,
          AccountId = c.AccountId,
          CustomerSite__c = c.CustomerSite__c,
          ServiceCenter__c = c.ServiceCenter__c,
          Subject = c.Subject,
          OwnerId = req.technicianId,
          Status = WORK_ORDER_STATUS_ASSIGNED,
          Purpose__c = req.purpose,
          StartDate = req.plannedStart,
          WorkInstruction__c = req.instruction,
          VisitNumber__c = visitNumber
        )
      );
      createdResults.add(result);
      if (c.Status != CASE_STATUS_IN_PROGRESS) {
        casesToUpdate.put(
          c.Id,
          new Case(Id = c.Id, Status = CASE_STATUS_IN_PROGRESS)
        );
      }
    }
    if (workOrders.isEmpty()) {
      return;
    }
    Savepoint sp = Database.setSavepoint();
    try {
      Database.insert(workOrders, AccessLevel.SYSTEM_MODE);
      Database.update(casesToUpdate.values(), AccessLevel.SYSTEM_MODE);
    } catch (DmlException e) {
      Database.rollback(sp);
      for (DispatchResult result : createdResults) {
        result.message =
          System.Label.MSG_SAVE_ERROR +
          ': ' +
          e.getDmlMessage(0);
      }
      return;
    }
    Map<Id, WorkOrder> savedById = new Map<Id, WorkOrder>(
      [
        SELECT Id, WorkOrderNumber
        FROM WorkOrder
        WHERE Id IN :workOrders
        WITH SYSTEM_MODE
      ]
    );
    for (Integer i = 0; i < workOrders.size(); i++) {
      DispatchResult result = createdResults[i];
      result.success = true;
      result.workOrderId = workOrders[i].Id;
      result.workOrderNumber = savedById.get(workOrders[i].Id).WorkOrderNumber;
      result.message = String.format(
        System.Label.MSG_DISPATCH_DONE,
        new List<Object>{
          result.workOrderNumber,
          techniciansById.get(workOrders[i].OwnerId).Name
        }
      );
    }
  }

  // DESC: 선택 목록 API 이름 → 화면 이름(실행 사용자 언어)
  private static String labelOf(Schema.SObjectField field, String value) {
    if (String.isBlank(value)) {
      return null;
    }
    for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
      if (entry.getValue() == value) {
        return entry.getLabel();
      }
    }
    return value;
  }
}
