using ProxyBridge.TestLab.Ui.Services;
using System.Text.Json;

// No SSH, server commands, product, credentials or shared application storage.
var root=Path.Combine(Path.GetTempPath(),"testlab-apply-checkpoint-"+Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
try
{
    var first=new TrafficApplyCheckpoint(root);
    using(var lease=first.Begin("bundle","target"))
    {
        Assert(first.Pending,"durable before dispatch");
        Throws("TRAFFIC_APPLY_RECHECK_REQUIRED",()=>new TrafficApplyCheckpoint(root).Begin("other","target"));
        Throws("TRAFFIC_OPERATION_ACTIVE",()=>new TrafficApplyCheckpoint(root).ResolveInspection("READY","bundle","target"));
    }
    var restarted=new TrafficApplyCheckpoint(root);
    Assert(restarted.Pending,"unknown survives new controller");
    Throws("TRAFFIC_APPLY_TARGET_RECHECK_REQUIRED",()=>restarted.ResolveInspection("READY","bundle","different-target"));
    Assert(restarted.Pending,"other target cannot resolve uncertainty");
    restarted.ResolveInspection("SETUP_REQUIRED","new-bundle","target");
    Assert(!restarted.Pending,"actual inspection resolves, never resumes");
    using(var lease=restarted.Begin("bundle","target")){lease.Complete("ERROR","TRAFFIC_POST_APPLY_VERIFICATION_FAILED");}
    Assert(!restarted.Pending,"confirmed remote failure differs from lost reply");
    using(var lease=restarted.Begin("bundle","target")){lease.Complete("READY");}
    Assert(!restarted.Pending,"confirmed success resolves");
    var receipts=Directory.GetFiles(Path.Combine(root,"runtime-apply-evidence"),"*.json");
    Assert(receipts.Length==3,"all resolutions retained");
    foreach(var receipt in receipts)
    {
        using var data=JsonDocument.Parse(File.ReadAllBytes(receipt));
        Assert(data.RootElement.GetProperty("pending").GetProperty("outcome").GetString()=="UNKNOWN","prior uncertainty retained");
    }
    File.WriteAllText(Path.Combine(root,"traffic-runtime-apply-pending.json"),"{partial");
    Throws("TRAFFIC_APPLY_TARGET_RECHECK_REQUIRED",()=>restarted.ResolveInspection("READY","bundle","target"));
    Assert(restarted.Pending,"torn target identity cannot be assumed");
    Console.WriteLine("Apply checkpoint persistence, concurrent ownership, target binding and outcome receipts PASS");
}
finally
{
    var resolved=Path.GetFullPath(root);
    if(Path.GetDirectoryName(resolved)!=Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath()))||
       !Path.GetFileName(resolved).StartsWith("testlab-apply-checkpoint-",StringComparison.Ordinal))
        throw new InvalidOperationException("Cleanup target outside fixture directory");
    Directory.Delete(resolved,true);
}

static void Assert(bool condition,string message){if(!condition)throw new InvalidOperationException(message);}
static void Throws(string code,Action action)
{
    try{action();}
    catch(InvalidOperationException error)when(error.Message==code){return;}
    throw new InvalidOperationException("Expected "+code);
}
