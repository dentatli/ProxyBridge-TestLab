namespace ProxyBridge.TestLab.Ui.Services;

public enum RunContinuationAction
{
    Continue,
    RecoverOnce,
    SafetyStop
}

public static class RunContinuationPolicy
{
    public static RunContinuationAction Decide(string status, bool independent, bool recoveryAttempted, bool sharedStateClean)
    {
        if (!sharedStateClean || status == "CONTAMINATED") return RunContinuationAction.SafetyStop;
        if (status is "FAIL_HARNESS" or "FAIL_INFRASTRUCTURE")
            return recoveryAttempted ? RunContinuationAction.SafetyStop : RunContinuationAction.RecoverOnce;
        if (status == "HOLD_AMBIGUOUS" && !independent) return RunContinuationAction.SafetyStop;
        return RunContinuationAction.Continue;
    }
}
