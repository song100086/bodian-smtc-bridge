# Bodian Music -> SMTC bridge
#
# Bodian's Windows client (bodian_pc.exe, a Flutter app using media_kit/libmpv) never
# publishes an SMTC media session, so NO SMTC client can see it -- not Windows' own
# media flyout, not Lyricify, not taskbar-lyric tools, not Discord RPC bridges.
#
# This script publishes a real SMTC session in its own process and feeds it what Bodian
# is actually doing. Lyricify Fusion is just one verified consumer; anything that reads
# SMTC gets the same data.
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

# ---- friendly identity ------------------------------------------------------------
# The SMTC session inherits this process's AppUserModelID, so without this the media
# flyout says "powershell.exe" / "unknown app". Must be set before any window exists.
$script:MY_AUMID = "Tencent.BodianMusic.PC"
Add-Type -Language CSharp -TypeDefinition @"
using System.Runtime.InteropServices;
public static class AppId {
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
"@
try { [void][AppId]::SetCurrentProcessExplicitAppUserModelID($script:MY_AUMID) } catch { }

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

  // Media keys are EXTENDED keys: without KEYEVENTF_EXTENDEDKEY (0x0001) Bodian ignores
  // them entirely.
  public static uint MediaKey(ushort vk) {
    INPUT[] ins = new INPUT[2];
    ins[0].type = 1; ins[0].u.ki.wVk = vk; ins[0].u.ki.dwFlags = 0x0001;
    ins[1].type = 1; ins[1].u.ki.wVk = vk; ins[1].u.ki.dwFlags = 0x0001 | 0x0002;
    return SendInput(2, ins, Marshal.SizeOf(typeof(INPUT)));
  }

  [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int AppendFn(IntPtr self, IntPtr item);

  // MediaPlaybackList.Items is a WinRT generic collection (IVector<MediaPlaybackItem>)
  // that PowerShell cannot call Add/Append on (unprojected System.__ComObject). We QI it
  // by IID and call Append through the vtable (index 13).
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
      try { int hr2 = append(p, pItem); return "hr=0x" + hr2.ToString("X8"); }
      finally { Marshal.Release(pItem); }
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
Set-Content -LiteralPath $log -Value ("bridge start " + (Get-Date -Format "HH:mm:ss")) -Encoding UTF8
function Log([string]$m) { try { [System.IO.File]::AppendAllText($log, $m + "`r`n") } catch { } }

# ---- register a friendly display name for our AppUserModelID (HKCU, no admin) ----
# Chinese is built from code points: a PS 5.1 script saved as UTF-8 without BOM would
# decode a Chinese literal as ANSI garbage.
$script:DISPLAY_NAME = [string]([char]0x6CE2 + [char]0x70B9 + [char]0x97F3 + [char]0x4E50)
try {
  $aumidKey = "HKCU:\SOFTWARE\Classes\AppUserModelId\$($script:MY_AUMID)"
  if (-not (Test-Path $aumidKey)) { New-Item -Path $aumidKey -Force | Out-Null }
  Set-ItemProperty -Path $aumidKey -Name "DisplayName" -Value $script:DISPLAY_NAME -ErrorAction SilentlyContinue
  Log ("AUMID display name registered for " + $script:MY_AUMID)
} catch { Log ("AUMID register ERR: " + $_.Exception.Message) }

# ---- Start Menu shortcut carrying our AppUserModelID ------------------------------
# Registering the registry DisplayName alone was NOT enough (the Windows media flyout
# still said "unknown app"). The shell resolves an AUMID to a display name by looking up
# a Start Menu shortcut whose PKEY_AppUserModel_ID matches, so we create one.
Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class ShortcutAumid {
  [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class ShellLinkCoClass { }

  [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IShellLinkW {
    void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cch, IntPtr pfd, int fFlags);
    void GetIDList(out IntPtr ppidl);
    void SetIDList(IntPtr pidl);
    void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cch);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
    void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cch);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
    void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cch);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
    void GetHotkey(out short pwHotkey);
    void SetHotkey(short wHotkey);
    void GetShowCmd(out int piShowCmd);
    void SetShowCmd(int iShowCmd);
    void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cch, out int piIcon);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, int dwReserved);
    void Resolve(IntPtr hwnd, int fFlags);
    void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
  }

  [ComImport, Guid("0000010b-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPersistFile {
    void GetClassID(out Guid pClassID);
    void IsDirty();
    void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
    void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, bool fRemember);
    void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
    void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
  }

  [StructLayout(LayoutKind.Sequential, Pack = 4)]
  struct PROPERTYKEY { public Guid fmtid; public uint pid; }

  [StructLayout(LayoutKind.Explicit)]
  struct PROPVARIANT { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; }

  [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore {
    void GetCount(out uint cProps);
    void GetAt(uint iProp, out PROPERTYKEY pkey);
    void GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
    void SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
    void Commit();
  }

  [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT pv);

  public static string Create(string lnkPath, string target, string arguments, string workingDir, string aumid, string iconPath) {
    object linkObj = null;
    try {
      linkObj = new ShellLinkCoClass();
      var link = (IShellLinkW)linkObj;
      link.SetPath(target);
      if (!string.IsNullOrEmpty(arguments)) link.SetArguments(arguments);
      if (!string.IsNullOrEmpty(workingDir)) link.SetWorkingDirectory(workingDir);
      if (!string.IsNullOrEmpty(iconPath)) link.SetIconLocation(iconPath, 0);

      var store = (IPropertyStore)linkObj;
      var key = new PROPERTYKEY();
      key.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
      key.pid = 5;
      var pv = new PROPVARIANT();
      pv.vt = 31;
      pv.p = Marshal.StringToCoTaskMemUni(aumid);
      try { store.SetValue(ref key, ref pv); store.Commit(); }
      finally { PropVariantClear(ref pv); }

      ((IPersistFile)linkObj).Save(lnkPath, true);
      return "ok";
    } catch (Exception ex) { return "ERR " + ex.Message; }
    finally { if (linkObj != null) { try { Marshal.ReleaseComObject(linkObj); } catch { } } }
  }
}
"@
try {
  $programs = [Environment]::GetFolderPath('Programs')
  $lnkPath = Join-Path $programs ($script:DISPLAY_NAME + ".lnk")
  if (-not (Test-Path $lnkPath)) {
    $vbsPath = Join-Path $PSScriptRoot "bodian-smtc-bridge.vbs"
    $icon = "C:\Program Files (x86)\bodian\bodian_pc.exe"
    $r = [ShortcutAumid]::Create($lnkPath, "wscript.exe", ('"' + $vbsPath + '"'), $PSScriptRoot, $script:MY_AUMID, $icon)
    Log ("start menu shortcut: " + $r)
  } else { Log "start menu shortcut already present" }
} catch { Log ("shortcut ERR: " + $_.Exception.Message) }

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
try { $script:mp.IsLoopingEnabled = $true } catch { }
$script:mp.Volume = 0
try { $script:mp.CommandManager.IsEnabled = $true; Log "CommandManager enabled" } catch { Log ("cm ERR: " + $_.Exception.Message) }
$script:mp.Play()

# ---------- 2) winmm silent loop ----------
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
  Log "winmm silent loop running"
} catch { Log ("winmm audio ERR: " + $_.Exception.Message) }

# ---------- 3) SMTC session ----------
$script:smtc = $script:mp.SystemMediaTransportControls
$script:smtc.IsEnabled = $true
foreach ($p in @("IsPlayEnabled", "IsPauseEnabled", "IsStopEnabled", "IsNextEnabled", "IsPreviousEnabled")) {
  try { $script:smtc.$p = $true } catch { }
}
$script:updater = $script:smtc.DisplayUpdater
$script:updater.Type = [Windows.Media.MediaPlaybackType, Windows.Media, ContentType = WindowsRuntime]::Music
$script:updater.Update()
Log ("smtc ready: " + $script:smtc.GetType().FullName)

# ---------- 4) state ----------
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
$script:lastInject = [DateTime]::MinValue
$script:lastMpState = ""

# ---------- 5) main loop ----------
$script:tick = 0
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 800
$timer.Add_Tick({
  $script:tick++
  try {
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
                  $psi.Arguments = '"' + $script:dlJs + '" "' + $picJpg + '" "' + $cf + '"'
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

    if ($script:curTitle -ne "") {
      try {
        $script:updater.MusicProperties.Title = $script:curTitle
        $script:updater.MusicProperties.Artist = $script:curArtist
        if ($script:curAlbum -ne "") { $script:updater.MusicProperties.AlbumTitle = $script:curAlbum }
        $script:updater.Update()
      } catch { }
    }

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

    $idx = -1
    try { $idx = [int]$script:playlist.CurrentItemIndex } catch { }
    if ($script:lastIdx -ge 0 -and $idx -ne $script:lastIdx) {
      $delta = ($idx - $script:lastIdx + $script:ITEM_COUNT) % $script:ITEM_COUNT
      if (($now - $script:lastInject).TotalMilliseconds -ge 1500) {
        $vk = 0
        if ($delta -eq 1) { $vk = 0xB0 }
        elseif ($delta -eq $script:ITEM_COUNT - 1) { $vk = 0xB1 }
        if ($vk -ne 0) {
          $script:lastInject = $now
          [void][BodianBridge]::MediaKey([uint16]$vk)
          Log ("forwarded media key 0x" + $vk.ToString("X2") + " (idx " + $script:lastIdx + "->" + $idx + ")")
        }
      }
    }
    $script:lastIdx = $idx

    try {
      $mpState = [string]$script:mp.PlaybackSession.PlaybackState
      if ($mpState -ne $script:lastMpState) {
        $bodianPlaying = ($idleMs -lt 2500)
        if (($now - $script:lastInject).TotalMilliseconds -ge 1500) {
          if ($mpState -eq "Paused" -and $bodianPlaying) {
            $script:lastInject = $now
            [void][BodianBridge]::MediaKey([uint16]0xB3)
            Log "forwarded play/pause -> pause (bodian was playing)"
          } elseif ($mpState -eq "Playing" -and $script:lastMpState -eq "Paused" -and -not $bodianPlaying) {
            $script:lastInject = $now
            [void][BodianBridge]::MediaKey([uint16]0xB3)
            Log "forwarded play/pause -> play (bodian was paused)"
          }
        }
        $script:lastMpState = $mpState
      }
    } catch { }

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
