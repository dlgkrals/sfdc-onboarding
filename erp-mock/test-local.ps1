# ERP Mock 로컬 검증 (wrangler dev --local 실행 중일 때). 키는 로컬 전용 테스트 키
param([string]$Base = 'http://127.0.0.1:8787', [string]$Key = 'local-test-key')
$h = @{ 'x-api-key' = $Key }
function Post($path, $body) {
  try { Invoke-RestMethod -Method Post -Uri "$Base$path" -Headers $h -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 6 -Compress))) }
  catch { "HTTP $($_.Exception.Response.StatusCode.value__)" }
}
for ($i = 0; $i -lt 40; $i++) { try { $hl = Invoke-RestMethod "$Base/health"; break } catch { Start-Sleep -Milliseconds 500 } }
"1 health: $($hl.status)"
try { Invoke-RestMethod "$Base/api/stock" | Out-Null; '2 no key: (unexpected OK)' } catch { "2 no key: HTTP $($_.Exception.Response.StatusCode.value__)" }
$seed = Post '/api/admin/seed' @{ reset = $true; locations = @(@{ code = 'WH-GS-001'; name = '경기남부 창고'; type = 'WAREHOUSE' }, @{ code = 'VAN-GS-001'; name = '최민호 차량'; type = 'VAN' }); stock = @(@{ locationCode = 'WH-GS-001'; partCode = 'CMP-404-50'; quantity = 10; unit = 'Each' }, @{ locationCode = 'VAN-GS-001'; partCode = 'CMP-404-50'; quantity = 1; unit = 'Each' }, @{ locationCode = 'VAN-GS-001'; partCode = 'RFG-404A'; quantity = 17.5; unit = 'kg' }) }
"3 seed: locations=$($seed.locations) stock=$($seed.stock)"
$c = Post '/api/stock/consume' @{ items = @(@{ refId = 'PC-1'; locationCode = 'VAN-GS-001'; partCode = 'RFG-404A'; quantity = 2.5; workOrderNumber = 'WO-0001' }, @{ refId = 'PC-2'; locationCode = 'VAN-GS-001'; partCode = 'CMP-404-50'; quantity = 5 }, @{ refId = 'PC-3'; locationCode = 'VAN-XX'; partCode = 'CMP-404-50'; quantity = 1 }, @{ refId = 'PC-4'; locationCode = 'VAN-GS-001'; partCode = 'NOPE'; quantity = 1 }) }
'4 consume: ' + (($c.results | % { "$($_.refId)=$($_.status)/$($_.code)/$($_.remainingQty)$($_.unit)" }) -join '  ')
$d = Post '/api/stock/consume' @{ items = @(@{ refId = 'PC-1'; locationCode = 'VAN-GS-001'; partCode = 'RFG-404A'; quantity = 2.5 }) }
"5 duplicate PC-1: $($d.results[0].status) remaining=$($d.results[0].remainingQty) duplicate=$($d.results[0].duplicate)"
$t = Post '/api/stock/transfer' @{ items = @(@{ refId = 'PT-1'; fromLocationCode = 'WH-GS-001'; toLocationCode = 'VAN-GS-001'; partCode = 'CMP-404-50'; quantity = 2; reference = 'TR-0001' }, @{ refId = 'PT-2'; fromLocationCode = 'WH-GS-001'; toLocationCode = 'VAN-GS-001'; partCode = 'CMP-404-50'; quantity = 99 }) }
'6 transfer: ' + (($t.results | % { "$($_.refId)=$($_.status)/$($_.code) src=$($_.sourceRemainingQty) dst=$($_.destinationRemainingQty) unit=$($_.unit)" }) -join '  ')
$s = Invoke-RestMethod "$Base/api/stock" -Headers $h
'7 stock: ' + (($s.items | % { "$($_.locationCode)|$($_.partCode)=$($_.quantity)$($_.unit)" }) -join '  ')
Post '/api/admin/maintenance' @{ on = $true } | Out-Null
"8 maintenance on, consume: " + (Post '/api/stock/consume' @{ items = @(@{ refId = 'PC-9'; locationCode = 'VAN-GS-001'; partCode = 'RFG-404A'; quantity = 1 }) })
Post '/api/admin/maintenance' @{ on = $false } | Out-Null
"9 bad body: " + (Post '/api/stock/consume' @{ nothing = 1 })
$page = Invoke-WebRequest "$Base/" -UseBasicParsing
"10 page: HTTP $($page.StatusCode) length=$($page.Content.Length) hasHistory=$($page.Content.Contains('사용 차감')) hasUnitLabel=$($page.Content.Contains('17.5 kg') -or $page.Content.Contains('15 kg'))"
