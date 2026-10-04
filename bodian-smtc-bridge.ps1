# Bodian Music -> SMTC bridge (v2)
#
# Bodian's Windows client (bodian_pc.exe, a Flutter app using media_kit/libmpv)
# never publishes an SMTC media session, so NO SMTC client can see it -- not Windows'
# own media flyout, not Lyricify, not taskbar-lyric tools, not Discord RPC bridges.
#
# This script publishes a real SMTC session in its own process and feeds it what
# Bodian is actually doing. Lyricify Fusion is just one verified consumer; anything
# that reads SMTC gets the same data.
#
# How it works:
#   1. A WinRT MediaPlayer plays a 4-item playlist of SILENT in-memory wavs.
#      Playing real audio is what makes Windows treat this session as the active
#      media source; using a playlist (not a single item) is what lets us observe
#      media-control button presses.
#   2. CommandManager is enabled, so MediaPlayer itself handles the SMTC transport
#      buttons (Next/Previous/Play/Pause) -- we do NOT need to subscribe any WinRT
#      event (which PowerShell cannot do).
#   3. When a button is pressed, the playlist advances: CurrentItemIndex changes and
#      the position resets. We poll that and forward the press to Bodian as a
#      synthetic media key (Bodian listens to media keys).
#   4. The session is fed with what Bodian is actually doing:
#        - track metadata <- songDB.db (table hist_song, newest row)
#        - position       <- mpv time-pos read from bodian_pc process memory
#      Because CommandManager owns the session, it overwrites our metadata, so we
#      re-assert Title/Artist/Album on every tick.
#
# Run with Windows PowerShell 5.1 (STA), NOT PowerShell 7.

$ErrorActionPreference = "Continue"

# single instance guard: a second copy would create a duplicate SMTC session
$script:bridgeMutex = New-Object System.Threading.Mutex($false, "Global\BodianSmtcBridge")
if (-not $script:bridgeMutex.WaitOne(0)) {
  Write-Output "Bodian SMTC bridge is already running; exiting."
  exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Runtime.WindowsRuntime

Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class BodianBridge {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool SetDllDirectory(string path);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(int access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out IntPtr read);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);

  [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
  [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_prepare16_v2(IntPtr db, [MarshalAs(UnmanagedType.LPWStr)] string sql, int nByte, out IntPtr stmt, IntPtr tail);
  [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
  [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern long sqlite3_column_int64(IntPtr stmt, int i);
  [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text16(IntPtr stmt, int i);
  [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
  [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_close_v2(IntPtr db);
  [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_busy_timeout(IntPtr db, int ms);

  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public InputUnion u; }
  [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

  // Media keys are EXTENDED keys: without KEYEVENTF_EXTENDEDKEY (0x0001) Bodian
  // ignores them entirely.
  public static uint MediaKey(ushort vk) {
    INPUT[] ins = new INPUT[2];
    ins[0].type = 1; ins[0].u.ki.wVk = vk; ins[0].u.ki.dwFlags = 0x0001;
    ins[1].type = 1; ins[1].u.ki.wVk = vk; ins[1].u.ki.dwFlags = 0x0001 | 0x0002;
    return SendInput(2, ins, Marshal.SizeOf(typeof(INPUT)));
  }

  [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int AppendFn(IntPtr self, IntPtr item);

  // MediaPlaybackList.Items is a WinRT generic collection (IVector<MediaPlaybackItem>)
  // which PowerShell cannot call Add/Append on (unprojected System.__ComObject).
  // We QI it by IID and call Append through the vtable (index 13). The IID below was
  // determined empirically by probing the object's IInspectable::GetIids list.
  public static string PlaylistAppend(object items, object item) {
    IntPtr p = IntPtr.Zero;
    try {
      Guid iid = new Guid("e1504f46-c4a6-5a29-8fc9-a934d12d7242");
      IntPtr pUnk = Marshal.GetIUnknownForObject(items);
      int hr = Marshal.QueryInterface(pUnk, ref iid, out p);
      Marshal.Release(pUnk);
      if (hr != 0) return "QI hr=0x" + hr.ToString("X8");
      IntPtr vtbl = Marshal.ReadIntPtr(p);
      var append = (AppendFn)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(vtbl, 13 * IntPtr.Size), typeof(AppendFn));
      IntPtr pItem = Marshal.GetIUnknownForObject(item);
      try {
        int hr2 = append(p, pItem);
        return "hr=0x" + hr2.ToString("X8");
      } finally { Marshal.Release(pItem); }
    } catch (Exception ex) { return "EX " + ex.Message; }
    finally { if (p != IntPtr.Zero) { try { Marshal.Release(p); } catch { } } }
  }

  static BodianBridge() {
    try { SetDllDirectory(@"C:\Program Files (x86)\bodian"); } catch { }
  }

  static string PtrToStr(IntPtr p) { return p == IntPtr.Zero ? "" : Marshal.PtrToStringUni(p); }

  // returns "ord\u0001id\u0001json\u0001time", or null when unavailable
  public static string QueryLatestSong(string dbPath) {
    IntPtr db = IntPtr.Zero, stmt = IntPtr.Zero;
    try {
      byte[] path = Encoding.UTF8.GetBytes(dbPath + "\0");
      if (sqlite3_open_v2(path, out db, 1, IntPtr.Zero) != 0) return null;
      sqlite3_busy_timeout(db, 400);
      if (sqlite3_prepare16_v2(db, "SELECT ord, id, json, time FROM hist_song ORDER BY ord DESC LIMIT 1;", -1, out stmt, IntPtr.Zero) != 0) return null;
      if (sqlite3_step(stmt) != 100) return null;
      long ord = sqlite3_column_int64(stmt, 0);
      long id = sqlite3_column_int64(stmt, 1);
      string json = PtrToStr(sqlite3_column_text16(stmt, 2));
      string time = PtrToStr(sqlite3_column_text16(stmt, 3));
      return ord + "\u0001" + id + "\u0001" + json + "\u0001" + time;
    } catch { return null; }
    finally {
      if (stmt != IntPtr.Zero) sqlite3_finalize(stmt);
      if (db != IntPtr.Zero) sqlite3_close_v2(db);
    }
  }

  public static bool IsBodianRunning() {
    try { return Process.GetProcessesByName("bodian_pc").Length > 0; } catch { return false; }
  }

  // mpv time-pos in seconds, or -1 when unavailable
  public static double GetTimePos() {
    try {
      var procs = Process.GetProcessesByName("bodian_pc");
      if (procs.Length == 0) return -1.0;
      var p = procs[0];
      IntPtr eventLoop = IntPtr.Zero;
      try {
        foreach (ProcessModule m in p.Modules)
          if (m.ModuleName.ToLowerInvariant().Contains("media_kit_native_event_loop")) eventLoop = m.BaseAddress;
      } catch { return -1.0; }
      if (eventLoop == IntPtr.Zero) return -1.0;
      IntPtr h = OpenProcess(0x10 | 0x400, false, p.Id);
      if (h == IntPtr.Zero) return -1.0;
      try {
        long myHead = ReadI64(h, eventLoop.ToInt64() + 0xA1D8);
        long firstNode = myHead != 0 ? ReadI64(h, myHead) : 0;
        long mpvHandle = (firstNode != 0 && firstNode != myHead) ? ReadI64(h, firstNode + 0x10) : 0;
        long mpctx = IsPtr(mpvHandle) ? ReadI64(h, mpvHandle + 0x48) : 0;
        if (!IsPtr(mpctx)) return -1.0;
        double pos = ReadDouble(h, mpctx + 0x328);
        if (double.IsNaN(pos) || double.IsInfinity(pos) || pos < 0 || pos > 86400) return -1.0;
        return pos;
      } finally { CloseHandle(h); }
    } catch { return -1.0; }
  }

  static long ReadI64(IntPtr h, long a) { byte[] b = new byte[8]; IntPtr br; return (ReadProcessMemory(h, new IntPtr(a), b, 8, out br) && br.ToInt32() == 8) ? BitConverter.ToInt64(b, 0) : 0; }
  static double ReadDouble(IntPtr h, long a) { byte[] b = new byte[8]; IntPtr br; return (ReadProcessMemory(h, new IntPtr(a), b, 8, out br) && br.ToInt32() == 8) ? BitConverter.ToDouble(b, 0) : double.NaN; }
  static bool IsPtr(long v) { ulong u = unchecked((ulong)v); return u >= 0x10000UL && u < 0x0000800000000000UL; }
}
"@

$log = Join-Path $env:TEMP "bodian_bridge.log"
Set-Content -LiteralPath $log -Value ("bridge v2 start " + (Get-Date -Format "HH:mm:ss")) -Encoding UTF8
function Log([string]$m) { try { [System.IO.File]::AppendAllText($log, $m + "`r`n") } catch { } }

# helper to await a WinRT IAsyncOperation from PowerShell 5.1
$script:asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function Await($WinRtTask, $ResultType) {
  $asTask = $script:asTaskGeneric.MakeGenericMethod($ResultType)
  $netTask = $asTask.Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
  $netTask.Result
}

$script:ITEM_COUNT = 4

# build a silent wav entirely in memory -> MediaSource
function NewSilentSource([int]$seconds, [int]$rate) {
  $n = $rate * $seconds
  $ms = New-Object System.IO.MemoryStream
  $bw = New-Object System.IO.BinaryWriter($ms)
  $a = [System.Text.Encoding]::ASCII
  $bw.Write($a.GetBytes("RIFF")); $bw.Write([int](36 + $n)); $bw.Write($a.GetBytes("WAVE"))
  $bw.Write($a.GetBytes("fmt ")); $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1)
  $bw.Write([int]$rate); $bw.Write([int]$rate); $bw.Write([int16]1); $bw.Write([int16]8)
  $bw.Write($a.GetBytes("data")); $bw.Write([int]$n); $bw.Write((New-Object byte[] $n))
  $bw.Flush()
  $bytes = $ms.ToArray()
  $memType = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
  $dwType = [Windows.Storage.Streams.DataWriter, Windows.Storage.Streams, ContentType = WindowsRuntime]
  $srcType = [Windows.Media.Core.MediaSource, Windows.Media.Core, ContentType = WindowsRuntime]
  $mem = [Activator]::CreateInstance($memType)
  $dw = [Activator]::CreateInstance($dwType, $mem)
  $dw.WriteBytes($bytes)
  [void](Await ($dw.StoreAsync()) ([uint32]))
  [void]$dw.DetachStream()
  $mem.Seek(0)
  return $srcType::CreateFromStream($mem, "audio/wav")
}

# ---------- 1) MediaPlayer playing a silent playlist ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Bodian SMTC Bridge"
$form.ShowInTaskbar = $false
$form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
$form.Show()

$mpType = [Windows.Media.Playback.MediaPlayer, Windows.Media, ContentType = WindowsRuntime]
$listType = [Windows.Media.Playback.MediaPlaybackList, Windows.Media, ContentType = WindowsRuntime]
$itemType = [Windows.Media.Playback.MediaPlaybackItem, Windows.Media, ContentType = WindowsRuntime]
$script:mp = [Activator]::CreateInstance($mpType)
$script:playlist = [Activator]::CreateInstance($listType)
for ($i = 0; $i -lt $script:ITEM_COUNT; $i++) {
  try {
    $src = NewSilentSource 3600 8000
    $it = [Activator]::CreateInstance($itemType, $src)
    Log ("playlist append: " + [BodianBridge]::PlaylistAppend($script:playlist.Items, $it))
  } catch { Log ("playlist item ERR: " + $_.Exception.Message) }
}
$script:mp.Source = $script:playlist
# MediaPlaybackList has no IsLoopingEnabled; looping is handled by MediaPlayer.IsLoopingEnabled
try { $script:mp.IsLoopingEnabled = $true } catch { }
$script:mp.Volume = 0
try { $script:mp.CommandManager.IsEnabled = $true; Log "CommandManager enabled" } catch { Log ("cm ERR: " + $_.Exception.Message) }
$script:mp.Play()

# ---------- 1b) winmm silent loop ----------
# Keeps this process "rendering audio" even while the MediaPlayer below is left paused
# by the user, so the SMTC session stays the current media source.
$silentWav = Join-Path $env:TEMP "bodian_silence_60s.wav"
try {
  $sr = 8000; $n = $sr * 60
  $fs = [System.IO.File]::Create($silentWav)
  $bw = New-Object System.IO.BinaryWriter($fs)
  $a = [System.Text.Encoding]::ASCII
  $bw.Write($a.GetBytes("RIFF")); $bw.Write([int](36 + $n)); $bw.Write($a.GetBytes("WAVE"))
  $bw.Write($a.GetBytes("fmt ")); $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1)
  $bw.Write([int]$sr); $bw.Write([int]$sr); $bw.Write([int16]1); $bw.Write([int16]8)
  $bw.Write($a.GetBytes("data")); $bw.Write([int]$n); $bw.Write((New-Object byte[] $n))
  $bw.Close(); $fs.Close()
  $script:player = New-Object System.Media.SoundPlayer
  $script:player.SoundLocation = $silentWav
  $script:player.Load()
  $script:player.PlayLooping()
  Log "winmm silent loop running (session stays alive while paused)"
} catch { Log ("winmm audio ERR: " + $_.Exception.Message) }

# ---------- 2) SMTC session ----------
$script:smtc = $script:mp.SystemMediaTransportControls
$script:smtc.IsEnabled = $true
# IsPlayEnabled/IsPauseEnabled MUST stay true: Windows only treats a session as an
# active media source if it claims playback capability.
foreach ($p in @("IsPlayEnabled", "IsPauseEnabled", "IsStopEnabled", "IsNextEnabled", "IsPreviousEnabled")) {
  try { $script:smtc.$p = $true } catch { }
}
$script:updater = $script:smtc.DisplayUpdater
$script:updater.Type = [Windows.Media.MediaPlaybackType, Windows.Media, ContentType = WindowsRuntime]::Music
$script:updater.Update()
Log ("smtc ready: " + $script:smtc.GetType().FullName)

# ---------- 3) state ----------
$script:form = $form
$script:dbPath = Join-Path $env:LOCALAPPDATA "cn.wenyu.bodian\bodian_pc\database\songDB.db"
$script:lastOrd = -1
$script:curDuration = 0
$script:curTitle = ""
$script:curArtist = ""
$script:curAlbum = ""
$script:coverFile = ""
$script:coverApplied = $true
$script:nodePath = "C:\Program Files\nodejs\node.exe"
$script:dlJs = Join-Path $PSScriptRoot "cover_dl.js"
$script:lastPos = -1.0
$script:lastPosChange = [DateTime]::Now
$script:status = [Windows.Media.MediaPlaybackStatus, Windows.Media, ContentType = WindowsRuntime]::Stopped
$script:lastIdx = -1
$script:lastLoggedIdx = -999
$script:lastInject = [DateTime]::MinValue
$script:lastMpState = ""
$script:ignoreNextPlaying = $false

# ---------- 4) main loop ----------
$script:tick = 0
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 800
$timer.Add_Tick({
  $script:tick++
  try {
    # ---- current track from Bodian's own database ----
    $row = [BodianBridge]::QueryLatestSong($script:dbPath)
    if ($row) {
      $f = $row.Split([char]1)
      if ($f.Length -ge 4) {
        $ord = 0
        [void][int]::TryParse($f[0], [ref]$ord)
        if ($ord -ne $script:lastOrd) {
          $script:lastOrd = $ord
          $j = $null
          try { $j = $f[2] | ConvertFrom-Json } catch { }
          if ($j) {
            $script:curTitle = [string]$j.name
            $script:curArtist = [string]$j.artist
            $script:curAlbum = if ($j.album) { [string]$j.album } else { "" }
            $script:curDuration = [int]$j.duration
            $script:updater.MusicProperties.Title = $script:curTitle
            $script:updater.MusicProperties.Artist = $script:curArtist
            if ($script:curAlbum -ne "") { $script:updater.MusicProperties.AlbumTitle = $script:curAlbum }
            # album art: node downloads it (this machine's system TLS is broken) and we
            # hand SMTC the local file via CreateFromFile
            $pic = ""
            if ($j.albumPic120) { $pic = [string]$j.albumPic120 }
            elseif ($j.albumPic) { $pic = [string]$j.albumPic }
            $script:coverFile = ""
            $script:coverApplied = $true
            if ($pic) {
              $picJpg = $pic -replace '\.webp', '.jpg'
              $cf = Join-Path $env:TEMP ("bodian_cover_" + [string]$j.id + ".jpg")
              $script:coverFile = $cf
              if (Test-Path $cf) {
                $script:coverApplied = $false
              } else {
                try {
                  $psi = New-Object System.Diagnostics.ProcessStartInfo
                  $psi.FileName = $script:nodePath
                  $psi.Arguments = "`"$script:dlJs`" `"$picJpg`" `"$cf`""
                  $psi.UseShellExecute = $false
                  $psi.CreateNoWindow = $true
                  $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                  [void][System.Diagnostics.Process]::Start($psi)
                  $script:coverApplied = $false
                  Log ("cover dl started: " + $cf)
                } catch { Log ("cover dl ERR: " + $_.Exception.Message) }
              }
            }
            $script:updater.Update()
            Log ("track: " + $script:curTitle + " - " + $script:curArtist + " (" + $script:curDuration + "s)")
          }
        }
      }
    }

    # ---- position / play state from mpv time-pos ----
    $pos = [BodianBridge]::GetTimePos()
    $now = [DateTime]::Now
    if ($pos -ge 0) {
      if ($script:lastPos -lt 0 -or [Math]::Abs($pos - $script:lastPos) -gt 0.05) {
        $script:lastPos = $pos
        $script:lastPosChange = $now
      }
    }
    $idleMs = ($now - $script:lastPosChange).TotalMilliseconds
    if (-not [BodianBridge]::IsBodianRunning()) {
      $newStatus = [Windows.Media.MediaPlaybackStatus, Windows.Media, ContentType = WindowsRuntime]::Paused
    } elseif ($idleMs -lt 2500) {
      $newStatus = [Windows.Media.MediaPlaybackStatus, Windows.Media, ContentType = WindowsRuntime]::Playing
    } else {
      $newStatus = [Windows.Media.MediaPlaybackStatus, Windows.Media, ContentType = WindowsRuntime]::Paused
    }
    if ([int]$newStatus -ne [int]$script:status) {
      $script:status = $newStatus
      $script:smtc.PlaybackStatus = $newStatus
      Log ("status " + [int]$newStatus)
    }

    # ---- fight back for our metadata (CommandManager overwrites it) ----
    if ($script:curTitle -ne "") {
      try {
        $script:updater.MusicProperties.Title = $script:curTitle
        $script:updater.MusicProperties.Artist = $script:curArtist
        if ($script:curAlbum -ne "") { $script:updater.MusicProperties.AlbumTitle = $script:curAlbum }
        $script:updater.Update()
      } catch { }
    }

    # ---- timeline so lyrics follow exactly ----
    if ($pos -ge 0 -and $script:curDuration -gt 0) {
      $tlType = [Windows.Media.SystemMediaTransportControlsTimelineProperties, Windows.Media, ContentType = WindowsRuntime]
      $tl = [Activator]::CreateInstance($tlType)
      $tl.StartTime = [TimeSpan]::Zero
      $tl.EndTime = [TimeSpan]::FromSeconds([double]$script:curDuration)
      $tl.Position = [TimeSpan]::FromSeconds([double]$pos)
      $tl.MinSeekTime = [TimeSpan]::Zero
      $tl.MaxSeekTime = [TimeSpan]::FromSeconds([double]$script:curDuration)
      $script:smtc.UpdateTimelineProperties($tl)
    }

    # ---- detect transport-button presses via playlist index change ----
    $idx = -1
    try { $idx = [int]$script:playlist.CurrentItemIndex } catch { Log ("idx read ERR: " + $_.Exception.Message) }
    if ($script:lastIdx -ge 0 -and $idx -ne $script:lastIdx) {
      $delta = ($idx - $script:lastIdx + $script:ITEM_COUNT) % $script:ITEM_COUNT
      # ignore changes caused by our own injected key echoing back
      if (($now - $script:lastInject).TotalMilliseconds -ge 1500) {
        $vk = 0
        if ($delta -eq 1) { $vk = 0xB0 }                        # Next
        elseif ($delta -eq $script:ITEM_COUNT - 1) { $vk = 0xB1 }  # Previous
        if ($vk -ne 0) {
          $script:lastInject = $now
          [void][BodianBridge]::MediaKey([uint16]$vk)
          Log ("forwarded media key 0x" + $vk.ToString("X2") + " (idx " + $script:lastIdx + "->" + $idx + ")")
        }
      }
    }
    $script:lastIdx = $idx    # always remember, including the very first sample

    # ---- play / pause ----
    # CommandManager applies the user's play/pause to our player, so we detect it as a
    # state change. To avoid ever flipping Bodian's state the wrong way, we only forward
    # when Bodian is actually in the OPPOSITE state; our own resume is flagged and ignored.
    try {
      $mpState = [string]$script:mp.PlaybackSession.PlaybackState
      if ($mpState -ne $script:lastMpState) {
        $bodianPlaying = ($idleMs -lt 2500)
        if (($now - $script:lastInject).TotalMilliseconds -ge 1500) {
          if ($mpState -eq "Paused" -and $bodianPlaying) {
            $script:lastInject = $now
            [void][BodianBridge]::MediaKey([uint16]0xB3)   # VK_MEDIA_PLAY_PAUSE
            Log "forwarded play/pause -> pause (bodian was playing)"
          } elseif ($mpState -eq "Playing" -and $script:lastMpState -eq "Paused" -and -not $bodianPlaying) {
            $script:lastInject = $now
            [void][BodianBridge]::MediaKey([uint16]0xB3)   # VK_MEDIA_PLAY_PAUSE
            Log "forwarded play/pause -> play (bodian was paused)"
          }
        }
        $script:lastMpState = $mpState
      }
      # NOTE: no auto-resume here on purpose. The user's pause must stick, otherwise a
      # later press of Play would not change the state and could never be detected.
      # The winmm loop above keeps the session current meanwhile.
    } catch { }

    # ---- apply downloaded album art ----
    if (-not $script:coverApplied -and $script:coverFile -ne "" -and (Test-Path $script:coverFile)) {
      try {
        $sfType = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
        $sf = Await ($sfType::GetFileFromPathAsync($script:coverFile)) $sfType
        $rarType = [Windows.Storage.Streams.RandomAccessStreamReference, Windows.Storage.Streams, ContentType = WindowsRuntime]
        $script:updater.Thumbnail = $rarType::CreateFromFile($sf)
        $script:updater.Update()
        $script:coverApplied = $true
        Log ("cover applied: " + $script:coverFile)
      } catch {
        Log ("cover apply ERR: " + $_.Exception.Message)
        $script:coverApplied = $true
      }
    }
  } catch {
    Log ("tick err: " + $_.Exception.Message)
  }
})
$timer.Start()
[System.Windows.Forms.Application]::Run($form)
try { $script:mp.Dispose() } catch { }
Log "stopped"
