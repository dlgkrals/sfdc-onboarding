/**
 * @description LWC 공통 유틸 — 여러 형태의 오류 객체에서 사람이 읽을 메시지만 뽑음
 *              (Apex AuraHandledException, LDS 오류, JS 오류, 배열 모두 처리. LWC Recipes의 reduceErrors 방식)
 * @layer       LWC (공통)
 * @author      Edwin
 * @date        2026-10-13
 * @see assetSearch, assetDetail, assetRecentCases
 */

/**
 * @param {Object|Object[]} errors 오류 하나 또는 배열
 * @return {String[]} 메시지 목록 (빈 값 제외)
 */
export function reduceErrors(errors) {
  const list = Array.isArray(errors) ? errors : [errors];
  return (
    list
      .filter((error) => !!error)
      .map((error) => {
        // DESC: LDS 레코드 오류 (body 배열)
        if (Array.isArray(error.body)) {
          return error.body.map((e) => e.message);
        }
        // DESC: LDS 페이지·필드 오류
        if (error.body?.output?.errors?.length) {
          return error.body.output.errors.map((e) => e.message);
        }
        // DESC: Apex 오류 (AuraHandledException 등)
        if (error.body && typeof error.body.message === "string") {
          return error.body.message;
        }
        // DESC: JS 오류
        if (typeof error.message === "string") {
          return error.message;
        }
        return error.statusText;
      })
      // DESC: 중첩 배열을 펴고 빈 값 제거
      .reduce((all, item) => all.concat(item), [])
      .filter((message) => !!message)
  );
}
