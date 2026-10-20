$ErrorActionPreference='Stop'
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../modules/TargetAcceptNative.psm1') -Raw
$code=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
if (-not $code) {throw 'TCP_TABLE_SOURCE_NOT_FOUND'}
$checks=@'
public static class PBTableChecks {
    static string mode; static int calls;
    static uint Query(IntPtr p, ref int n, bool order, int af, int cls, uint reserved) {
        calls++;
        if(p==IntPtr.Zero) { n=mode=="oversize"?17000000:28; return 122; }
        if(mode=="unstable" || (mode=="retry" && calls==2)) {n+=24;return 122;}
        if(mode=="error") return 5;
        // Simulate 200 rows appearing after the initial size query.
        int required=28+200*24;
        if(n<required) {n=required;return 122;}
        if(mode=="invalid-size") {n++;return 0;}
        n=28;
        Marshal.WriteInt32(p,mode=="invalid-count"?2:1);
        Marshal.WriteInt32(p,4,3);Marshal.WriteInt32(p,8,0x0100007f);
        Marshal.WriteByte(p,12,0xa4);Marshal.WriteByte(p,13,0xd9);
        Marshal.WriteInt32(p,16,0x0100007f);
        Marshal.WriteByte(p,20,0x84);Marshal.WriteByte(p,21,0xda);
        Marshal.WriteInt32(p,24,1234);return 0;
    }
    public static void Check(string test,string error,int expectedCalls) {
        mode=test;calls=0;
        try {
            var rows=PBTargetTcpTable.ReadWith(Query);
            if(error!="") throw new Exception("EXPECTED_FAILURE_"+test);
            if(rows.Length!=1 || rows[0].Pid!=1234 || rows[0].State!=3 ||
                rows[0].LocalAddress!="127.0.0.1" || rows[0].RemoteAddress!="127.0.0.1" ||
                rows[0].LocalPort!=42201 || rows[0].RemotePort!=34010) throw new Exception("ROW_INVALID");
        } catch(Exception e) {
            if(error=="" || e.Message.IndexOf(error,StringComparison.Ordinal)<0) throw;
        }
        if(calls!=expectedCalls) throw new Exception("QUERY_BOUND_DIFFERS_"+test);
    }
}
'@
Add-Type -TypeDefinition ($code+[Environment]::NewLine+$checks)
[PBTableChecks]::Check('growth','',2)
[PBTableChecks]::Check('retry','',3)
[PBTableChecks]::Check('unstable','TCP_TABLE_UNSTABLE',5)
[PBTableChecks]::Check('oversize','TCP_TABLE_SIZE_INVALID',1)
[PBTableChecks]::Check('invalid-count','TCP_TABLE_LAYOUT_INVALID',2)
[PBTableChecks]::Check('invalid-size','TCP_TABLE_SIZE_INVALID',2)
[PBTableChecks]::Check('error','Access is denied',2)
Write-Output 'TARGET_TCP_TABLE_CHECKS_PASSED: 7; no product or traffic'
