$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq "IAsyncOperation``1" })[0]
function Await($WinRtTask, $ResultType) {
  $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
  $netTask = $asTask.Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
  $netTask.Result
}
$mgrType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$propsType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType = WindowsRuntime]
$mgr = Await ($mgrType::RequestAsync()) $mgrType
$cur = $mgr.GetCurrentSession()
if ($cur -eq $null) { "currentSession = NULL (no active session)" }
else {
  "currentSession AUMID = " + $cur.SourceAppUserModelId
  try { $info = Await ($cur.TryGetMediaPropertiesAsync()) $propsType; "  title='" + $info.Title + "' artist='" + $info.Artist + "'" } catch { "  props ERR " + $_.Exception.Message }
  try { $pb = $cur.GetPlaybackInfo(); "  status = " + $pb.PlaybackStatus } catch { "  pb ERR " + $_.Exception.Message }
  try { $tl = $cur.GetTimelineProperties(); "  pos = " + [math]::Round($tl.Position.TotalSeconds, 2) + " end = " + [math]::Round($tl.EndTime.TotalSeconds, 2) } catch { "  tl ERR " + $_.Exception.Message }
}
