Set-StrictMode -Version Latest

function Get-KdBootSessionEvidence {
    # Read-only observations. Do not infer a reboot from a changing CIM estimate.
    $event=Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Kernel-General';Id=12} -MaxEvents 1 -ErrorAction Stop
    [xml]$xml=$event.ToXml()
    $ns=[Xml.XmlNamespaceManager]::new($xml.NameTable)
    $ns.AddNamespace('e','http://schemas.microsoft.com/win/2004/08/events/event')
    $start=$xml.SelectSingleNode('/e:Event/e:EventData/e:Data[@Name="StartTime"]',$ns)
    if (-not $start) {throw 'KD_BOOT_START_TIME_MISSING'}
    $bootId=(Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name BootId -ErrorAction Stop).BootId
    $cim=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop
    $result=[ordered]@{
        method='kernel-general-12-and-prefetch-bootid-v1'
        identity=[ordered]@{
            computer=[string]$xml.Event.System.Computer
            provider=[string]$xml.Event.System.Provider.Name
            event_id=[int]$xml.Event.System.EventID
            event_record_id=[long]$xml.Event.System.EventRecordID
            event_time_utc=([DateTimeOffset]::Parse([string]$xml.Event.System.TimeCreated.SystemTime)).ToUniversalTime().ToString('o')
            start_time_utc=([DateTimeOffset]::Parse($start.InnerText)).ToUniversalTime().ToString('o')
            prefetch_boot_id=[long]$bootId
        }
        event_xml=$event.ToXml()
        observed_at_utc=[DateTime]::UtcNow.ToString('o')
        cim_boot_estimate_utc=([DateTimeOffset](([DateTime]$cim.LastBootUpTime).ToUniversalTime())).ToString('o')
        cryptographic_boot_identity=$false
    }
    Assert-KdBootSessionEvidence -Expected $result -Actual $result
    return $result
}

function Assert-KdBootSessionEvidence {
    param($Expected,$Actual)
    $fields=@('computer','provider','event_id','event_record_id','event_time_utc','start_time_utc','prefetch_boot_id')
    foreach ($record in @($Expected,$Actual)) {
        if ($record.method -cne 'kernel-general-12-and-prefetch-bootid-v1' -or $record.cryptographic_boot_identity -or
            $record.identity.provider -cne 'Microsoft-Windows-Kernel-General' -or $record.identity.event_id -ne 12 -or
            $record.identity.event_record_id -le 0 -or $record.identity.prefetch_boot_id -lt 0 -or -not $record.identity.computer) {throw 'KD_BOOT_EVIDENCE_INVALID'}
        [xml]$raw=$record.event_xml
        $ns=[Xml.XmlNamespaceManager]::new($raw.NameTable)
        $ns.AddNamespace('e','http://schemas.microsoft.com/win/2004/08/events/event')
        $start=$raw.SelectSingleNode('/e:Event/e:EventData/e:Data[@Name="StartTime"]',$ns)
        if (-not $start -or [string]$raw.Event.System.Computer -cne $record.identity.computer -or
            [string]$raw.Event.System.Provider.Name -cne $record.identity.provider -or
            [int]$raw.Event.System.EventID -ne 12 -or [long]$raw.Event.System.EventRecordID -ne $record.identity.event_record_id -or
            ([DateTimeOffset]::Parse([string]$raw.Event.System.TimeCreated.SystemTime)).ToUniversalTime().ToString('o') -cne $record.identity.event_time_utc -or
            ([DateTimeOffset]::Parse($start.InnerText)).ToUniversalTime().ToString('o') -cne $record.identity.start_time_utc) {throw 'KD_BOOT_EVENT_XML_DIFFERS'}
    }
    foreach ($field in $fields) {
        if ([string]$Expected.identity.$field -cne [string]$Actual.identity.$field) {throw ('KD_BOOT_SESSION_CHANGED_OR_EVIDENCE_UNAVAILABLE: '+$field)}
    }
    # observed_at and CIM estimate are diagnostic values, never session keys.
}

Export-ModuleMember -Function Get-KdBootSessionEvidence,Assert-KdBootSessionEvidence
