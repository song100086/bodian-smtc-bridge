# 波点音乐 SMTC 桥接：诊断与实现记录
鏁寸悊鏃堕棿锛?026-10-03
鐩爣锛氳 Lyricify Fusion锛圠yricify Lite锛夊湪鎾斁娉㈢偣闊充箰鏃舵樉绀哄悓姝ユ瓕璇嶃€?
---

## 涓€銆佺粨璁猴紙鏍瑰洜锛?
1. Lyricify Fusion **鍙€氳繃 Windows SMTC锛堢郴缁熷獟浣撲紶杈撴帶浠讹級璇诲彇鎾斁鐘舵€?*銆?   瀹樻柟鏂囨。鍘熻瘽锛?"鎵€鏈夋帴鍏?SMTC 鐨勫簲鐢ㄥ潎鏀寔 Lyricify Fusion"*锛涙娴嬩笉鍒版椂鐨勫師鍥犲氨鏄?   *"浣犱娇鐢ㄧ殑杞欢鍙兘骞朵笉鏀寔 SMTC锛屾垨鏄病鏈夋纭厤缃?SMTC"*銆?
2. **娉㈢偣闊充箰妗岄潰瀹㈡埛绔?1.1.7 浠庝笉鍙戝竷 SMTC 浼氳瘽**锛坄bodian_pc.exe`锛孎lutter 搴旂敤锛屽唴宓?   `media_kit` + `libmpv-2.dll`锛岃鍦?`C:\Program Files (x86)\bodian`锛夈€?   瀹炴祴锛氭挱鏀炬椂鎸夐煶閲忛敭/鎵撳紑闊抽噺寮圭獥锛屽獟浣撴帶浠堕噷**娌℃湁**娉㈢偣锛涙灇涓剧郴缁?SMTC 浼氳瘽涓?0 涓€?
3. 鍥犳锛?*Fusion 閲屼换浣曡缃兘鏃犳硶瑙ｅ喅**锛岃繖涓嶆槸閰嶇疆闂锛岃€屾槸娉㈢偣娌′笂鎶ユ暟鎹€?
---

## 浜屻€佸凡楠岃瘉鐨勪簨瀹烇紙鍏ㄩ儴鏈満瀹炴祴锛?
### 2.1 褰撳墠鎾斁鏇茬洰 鈫?songDB.db锛堢畝鍗曞彲闈狅紝鏃犻渶鏉冮檺锛?
```sql
SELECT ord, id, json, time FROM hist_song ORDER BY ord DESC LIMIT 1;
```

- 鏁版嵁搴擄細`%LOCALAPPDATA%\cn.wenyu.bodian\bodian_pc\database\songDB.db`
- `json` 瀛楁鍚?`name / artist / album / duration / albumPic120` 绛?- 姣忚疆杞锛宍ord` 鍙樺寲鍗冲垏姝?- 瀹炴祴寰楀埌锛歚The Loser` / `verzache` / `131s`锛屼笌娉㈢偣鐣岄潰涓€鑷?- 鈿狅笍 娉ㄦ剰锛?*鍗曟洸寰幆鏃?`ord` 鍜?`time` 閮戒笉鏇存柊**锛屾墍浠ヤ笉鑳介潬瀹冪畻杩涘害
  锛堝疄娴?`time` 鍋滃湪 09:26锛岃€屽疄闄呭凡鎾簡 27 鍒嗛挓锛?
### 2.2 绮剧‘鎾斁杩涘害 鈫?璇?bodian_pc 杩涚▼鍐呭瓨锛堝惈鏆傚仠/鎷栧姩锛?
鎸囬拡閾撅紙`media_kit` 鐨?libmpv锛夛細

```
media_kit_native_event_loop.dll 鍩哄潃 + 0xA1D8   -> myHead
[myHead]                                        -> firstNode
[firstNode + 0x10]                              -> mpv_handle  (鍓?4 瀛楄妭搴斾负 "main")
[mpv_handle + 0x48]                             -> MPContext
MPContext + 0x328  (double, 绉?                 -> mpv time-pos
```

- 鏉冮檺锛歚OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION)`锛?*鏅€氱敤鎴峰嵆鍙?*锛堝疄娴嬫垚鍔燂級
- 瀹炴祴锛堝悓涓€浼氳瘽杩炵画閲囨牱锛?.5s 闂撮殧锛夛細
  - 鎾斁涓細`0.000 鈫?0.821 鈫?2.391 鈫?鈥?鈫?93.305`锛屾瘡 1.5s 绋冲畾 +1.56s
  - 鏆傚仠锛歚11.675` 杩炵画澶氭涓嶅彉
  - 鎷栧姩锛歚31.510 鈫?63.502`锛堣烦浜嗙害 32s锛?- 缁撹锛歚MPContext + 0x328` 灏辨槸鍑嗙‘鐨?time-pos锛屾殏鍋?seek 鍏ㄩ儴鍙瘑鍒?- 鍙傝€冨疄鐜帮細寮€婧愰」鐩?[BodianTaskbarLyric](https://github.com/weiwei221206/BodianTaskbarLyric)
  鐢ㄧ殑灏辨槸鍚屼竴濂楀師鐞嗭紙`src/Core/MpvMemoryReader.cs`銆乣src/Core/BodianEngine.cs`锛?
### 2.3 娉㈢偣鑷甫姝岃瘝缂撳瓨锛堝彲绂荤嚎鍙栨瓕璇嶏級

`%LOCALAPPDATA%\cn.wenyu.bodian\bodian_pc\cache\lyric\<姝屾洸ID>.lrc`
锛堟枃浠跺悕涓?hist_song 閲岀殑 `id`锛屽疄娴?`382292595.lrc` 涓庡綋鍓嶆洸鐩搴旓級

### 2.4 浼€?SMTC 浼氳瘽鏄彲琛岀殑锛堝叧閿?API 缁嗚妭锛岃俯鍧戣褰曪級

| 椤圭洰 | 鍊?/ 鍋氭硶 |
|---|---|
| interop 鎺ュ彛 | `ISystemMediaTransportControlsInterop`锛孖ID **`ddb0472d-c911-4a1f-86d9-dc3d71a95f5a`** |
| 鈿狅笍 鏄撻敊 | 涓嶆槸 `ddb0472e-f826-...`锛堥偅鏄彟涓€涓帴鍙ｏ紝QI 浼氳繑鍥?`E_NOINTERFACE`锛?|
| SMTC 鎺ュ彛 | `ISystemMediaTransportControls`锛孖ID `99fa3ff4-1742-42a6-902e-087d41f965ec` |
| 鑾峰彇 factory | `RoGetActivationFactory("Windows.Media.SystemMediaTransportControls", interopIID)` |
| 鍙栦細璇?| `GetForWindow(hwnd, riid, out smtc)` 鈥斺€?**vtable 绱㈠紩 6**锛圛Unknown 3 + IInspectable 3锛?|
| 鍧?1 | 鐢?`InterfaceIsIUnknown` 澹版槑鎺ュ彛鏃讹紝蹇呴』鏄惧紡鍐欏嚭 IInspectable 鐨?3 涓柟娉曪紝鍚﹀垯绱㈠紩閿欎綅 鈫?璁块棶鍐茬獊 |
| 鍧?2 | `Marshal.GetTypedObjectForIUnknown` 鎷掔粷 WinRT 绫诲瀷锛涙敼鐢?**PowerShell 鐨?`[Windows.Media.SystemMediaTransportControls]$comObj` 杞崲**锛堟垚鍔燂級 |
| 鍧?3 | 浼氳瘽闇€瑕?*绐楀彛 + 娑堟伅娉?*锛圵inForms `Application.Run`锛夋墠绋冲畾娉ㄥ唽 |
| 鍙缃?| `IsEnabled`銆乣PlaybackStatus`銆乣DisplayUpdater`锛圱itle/Artist/Album锛夈€乣UpdateTimelineProperties` |

瀹炴祴缁撴灉锛?*浼€犳垚鍔?*锛孡yricify 鍒楄〃閲屽嚭鐜颁簡杩欎釜浼氳瘽锛堟樉绀轰负 `F0DC299D809B9700`锛夈€?
---

## 涓夈€佹垚鍝佷笌瀹夎锛堚渽 宸茶濂藉苟楠岃瘉锛?
| 鏂囦欢 | 璇存槑 |
|---|---|
| `bodian-smtc-bridge.ps1` | 涓昏剼鏈細璇?`songDB.db` 鎷挎洸鐩?+ 璇诲唴瀛樻嬁杩涘害 鈫?涓婃姤 SMTC 浼氳瘽锛堝惈鍗曞疄渚嬩繚鎶わ級 |
| `bodian-smtc-bridge.cmd` | 鍙屽嚮鍚姩鍣紙闅愯棌绐楀彛鍚庡彴杩愯锛?|
| `verify_session.ps1` | 璇婃柇宸ュ叿锛氭煡璇㈢郴缁熷綋鍓嶆挱鏀炬簮 |
| `bodian_test.html` | 锛堝巻鍙诧級濯掍綋浼氳瘽娴嬭瘯椤碉紝楠岃瘉 Chromium 浼氳瘽鏃剁敤杩?|

**宸插畨瑁呭埌锛堝紑鏈鸿嚜鍚敤鐨勫氨鏄繖浠藉壇鏈級**锛歚%LOCALAPPDATA%\BodianSmtcBridge\`

**寮€鏈鸿嚜鍚?*锛歚%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Bodian SMTC Bridge.lnk`

### 鎵嬪姩鎺у埗
- **鍚姩**锛氬弻鍑?`%LOCALAPPDATA%\BodianSmtcBridge\bodian-smtc-bridge.cmd`
- **鍋滄**锛氫换鍔＄鐞嗗櫒閲岀粨鏉熼偅涓?`powershell.exe`锛堟ˉ鎺ヨ繘绋嬶級锛屾垨鎵ц涓嬮潰杩欐鎸夌獥鍙ｆ爣棰樼簿纭畾浣嶏細
  ```powershell
  Add-Type -Namespace W -Name U -MemberDefinition '[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);'
  $h = [W.U]::FindWindow($null, 'Bodian SMTC Bridge')
  if ($h -ne [IntPtr]::Zero) { $p = 0; [void][W.U]::GetWindowThreadProcessId($h, [ref]$p); Stop-Process -Id $p -Force }
  ```
- **鏃ュ織**锛歚%TEMP%\bodian_bridge.log`
- 閲嶅鍚姩鏃犲壇浣滅敤锛氳剼鏈紑澶存湁鍏ㄥ眬浜掓枼浣?`Global\BodianSmtcBridge`锛岀浜屼釜瀹炰緥浼氱洿鎺ラ€€鍑?
杩愯瑕佹眰锛歐indows PowerShell 5.1 + `-STA`锛堝惎鍔ㄥ櫒宸插甫璇ュ弬鏁帮級锛?*涓嶈**鐢?PowerShell 7銆?
### 缁存姢鎻愰啋
娉㈢偣瀹㈡埛绔崌绾у悗锛岀 2.2 鑺傜殑鍐呭瓨鍋忕Щ锛坄+0xA1D8`銆乣+0x328`锛夊彲鑳藉彉鍖栵紝
琛ㄧ幇涓烘瓕璇嶄笉鍐嶈窡闅忔垨杩涘害鍋滃湪 0 闄勮繎锛涘眾鏃堕噸鏂板畾浣嶅亸绉诲嵆鍙紙绗?2.2 鑺傜殑鎸囬拡閾炬槸鍏ュ彛锛夈€?
---

## 鍥涖€佸叧閿獊鐮达細浼氳瘽濡備綍鎴愪负銆屽綋鍓嶆挱鏀炬簮銆嶏紙鉁?宸茶В鍐筹級

**Fusion 瑕佺殑涓嶆槸"涓€涓?SMTC 浼氳瘽"锛岃€屾槸绯荤粺鐨勩€屽綋鍓嶆挱鏀炬簮銆嶏紙current session锛夈€?*
Windows 鍙负**鐪熸鍦ㄦ覆鏌撻煶棰?*鐨勪細璇濇縺娲诲畠銆?
澶辫触鐨勫皾璇曪紙閮介獙璇佽繃锛夛細
1. 鐢?`ISystemMediaTransportControlsInterop.GetForWindow` 鐩存帴寤轰細璇?鈫?浼氳瘽鑳借 Fusion
   鐪嬭锛堝垪琛ㄩ噷鏈夊畠锛夛紝浣?`GetCurrentSession()` 鎭掍负 NULL锛孎usion 鎶ャ€屾棤鍙敤鎾斁婧愩€?2. 缁欎笂闈㈣繖涓細璇濆崟鐙厤 `SoundPlayer` 闈欓煶闊抽 鈫?浠嶉潪 current
3. `MediaPlayer` 鐩存帴鎾斁闈欓煶 wav 鈫?`PlaybackState` 鎭掍负 `None`锛堝獟浣撶绾夸笉鍚姩锛?
**鏈夋晥鍋氭硶锛堜袱涓绱犵己涓€涓嶅彲锛夛細**

1. **鐢?`MediaPlayer` 褰撳鍣紝鎷垮畠鍐呴儴鐨?SMTC 瀵硅薄**锛岃€屼笉鏄敤 interop 鐩存帴寤轰細璇濓細

   ```powershell
   $mp = [Activator]::CreateInstance(
       [Windows.Media.Playback.MediaPlayer, Windows.Media, ContentType = WindowsRuntime])
   $mp.CommandManager.IsEnabled = $false       # 绂佹绯荤粺鑷姩鎺ョ
   $smtc = $mp.SystemMediaTransportControls    # 杩欎釜浼氳瘽鏄郴缁熻鍙殑"鍚堟硶"瀵硅薄
   $smtc.IsEnabled = $true
   # 涔嬪悗鐓у父璁剧疆 PlaybackStatus / DisplayUpdater / UpdateTimelineProperties
   ```

   MediaPlayer 鍐呴儴浼氬垱寤哄悎娉曠殑 SMTC 鍘熺敓瀵硅薄锛岃€屼笖**涓嶉渶瑕佺湡鐨勭敤瀹冩挱鏀惧獟浣?*
   锛堝畠鐨?`PlaybackSession.PlaybackState` 淇濇寔 `None` 涔熸病鍏崇郴锛夈€?
2. **鍚岃繘绋嬫寔缁覆鏌撻煶棰?*锛歚SoundPlayer` 寰幆鎾斁涓€娈?60 绉掑叏 0 閲囨牱鐨?wav
   锛堝畬鍏ㄦ棤澹帮紝浣嗚杩涚▼鏈夌湡瀹為煶棰戞祦锛夈€傝繖涓€姝ヨ绯荤粺鎶婅浼氳瘽璁や綔 active銆?
鍔犱笂杩欎袱鐐瑰悗锛宍GetCurrentSession()` 绔嬪嵆杩斿洖鎴戜滑鐨勪細璇濓紝鏁版嵁鍏ㄩ儴姝ｇ‘锛?
```
currentSession AUMID = powershell.exe
  title='The Loser' artist='verzache'
  status = Playing   pos = 105.8  end = 131     # 娉㈢偣瀹為檯 106.63s锛岄殢 tick 鍒锋柊
```

琛ュ厖瑕佹眰锛氬繀椤荤敤 **Windows PowerShell 5.1 + `-STA`**锛屽苟涓旇鏈夌獥鍙ｅ拰娑堟伅娉?锛圵inForms `Application.Run`锛夛紝鍚﹀垯浼氳瘽涓嶇ǔ瀹氥€?
---

## 鍥涚偣浜斻€佹挱鏀炬帶鍒舵寜閽細涓嶅彲鐢紙宸插叧闂級

> 鈿狅笍 **鏈妭缁撹宸茶銆屽洓鐐瑰崄銆嶅彇浠?*锛歷2 宸茬粡鐢?> 銆孧ediaPlayer + 闈欓煶鎾斁鍒楄〃 + CommandManager 杞銆嶆妸 Fusion/濯掍綋闈㈡澘鐨?> 涓嬩竴棣?涓婁竴棣?鎾斁鏆傚仠鎸夐挳鎺ラ€氫簡銆傛湰鑺備繚鐣欎綔涓烘帓鏌ヨ繃绋嬭褰曘€?
浼氳瘽鍙互鏄剧ず鎾斁鎺у埗鎸夐挳锛屼絾**鎸変笉鍔ㄦ尝鐐?*鈥斺€斿師鍥犲拰灏濊瘯璁板綍锛?
- 娉㈢偣涓嶆彁渚涗换浣曞閮ㄦ帶鍒舵帴鍙ｏ紱瀹冪殑 `media_key_detector_windows_plugin.dll` 鍙敤浜?*妫€娴?*濯掍綋閿€?- 鎸夐挳杞彂闇€瑕佽闃?SMTC 鐨?`ButtonPressed` 浜嬩欢锛屼笁鏉¤矾閮藉け璐ワ細
  1. **PowerShell 璁㈤槄**锛氬洖璋冨湪闈?PowerShell 绾跨▼涓婃墽琛岋紝PS 鑴氭湰鍧楁棤娉曡繍琛?     锛堝疄娴嬶細`TrySkipNextAsync()` 杩斿洖 True锛屼絾浜嬩欢澶勭悊鍣ㄤ竴娆￠兘娌¤璋冪敤锛?  2. **鍙嶅皠鍔ㄦ€佹敞鍐?*锛氳绯荤粺鎷掔粷鈥斺€?"Adding or removing event handlers dynamically
     is not supported on WinRT events"*
  3. **缂栬瘧 C# 瀹夸富**锛堢紪璇戞湡缁戝畾浜嬩欢锛夛細闇€瑕?.NET Framework 鍙傝€冪▼搴忛泦锛團acades锛?     鎴?CsWinRT 鎶曞奖鍖?`Microsoft.Windows.SDK.NET.dll`锛?*鏈満閮芥病鏈?*锛屼笖缃戠粶鍙楅檺瑁呬笉浜?NuGet
- 鈿狅笍 **閲嶈**锛歚IsPlayEnabled` / `IsPauseEnabled` **蹇呴』淇濇寔 `true`**銆傚疄娴嬪叏閮ㄥ叧闂悗锛?  Windows 涓嶅啀鎶婅浼氳瘽褰撲綔"娲诲姩鐨勫獟浣撴簮"锛宍GetCurrentSession()` 鍙樺洖 NULL锛?  Fusion 浼氬交搴曞け鍘绘挱鏀炬簮銆傜洰鍓嶅彧鍏抽棴浜?`Next/Previous/Stop`銆?
**閭ｆ€庝箞鍒囨瓕**锛氱洿鎺ョ敤閿洏鐨勫獟浣撻敭锛堚彮 / 鈴?/ 鎾斁鏆傚仠锛夆€斺€斿疄娴嬫湁鏁?鉁呫€?涔熷彲浠ョ敤 PowerToys 閿洏绠＄悊鍣ㄦ妸浠绘剰蹇嵎閿槧灏勬垚濯掍綋閿紝鍚屾牱鏈夋晥锛堝凡楠岃瘉锛夈€?
> 椤哄甫婢勬竻涓€涓潙锛氬獟浣撻敭灞炰簬**鎵╁睍閿?*锛岀敤 `SendInput`/`keybd_event` 鍙戦€佹椂**蹇呴』甯?> `KEYEVENTF_EXTENDEDKEY (0x0001)`**锛屽惁鍒欐尝鐐逛細蹇界暐銆傝繖瑙ｉ噴浜嗘棭鏈?鍚堟垚閿棤鏁?鐨勫亣璞°€?
## 鍥涚偣鍏€佷笓杈戝皝闈紙鉁?宸插疄鐜帮級

- **鏁版嵁鏉ユ簮**锛歚songDB.db` 鐨?`json` 瀛楁閲岃嚜甯﹀皝闈㈠湴鍧€ `albumPic120` / `albumPic`锛堥叿鎴?CDN锛?- **鏍煎紡**锛氶叿鎴戠粰鐨勬槸 `.webp`锛學indows shell 鐨勭缉鐣ュ浘绠＄嚎涓嶈锛涙妸鎵╁睍鍚嶆崲鎴?`.jpg`
  鍚屼竴鍦板潃灏辫兘鎷垮埌 `image/jpeg`锛堝疄娴嬩袱绉嶉兘杩斿洖 200锛?- **鍏抽敭鐨勫潙**锛氭湰鏈?**.NET/schannel 鐨?HTTPS 鏄潖鐨?*
  锛坄curl` 鎶?`SEC_E_NO_CREDENTIALS`銆乣Invoke-WebRequest` 鎶?鍩虹杩炴帴宸茬粡鍏抽棴"锛夛紝
  鎵€浠?**SMTC 鑷繁涓嬭浇涓嶅埌灏侀潰**銆傝В娉曪細妗ユ帴鐢?**node**锛圤penSSL锛屼笉璧?schannel锛夋妸鍥?  涓嬭浇鍒?`%TEMP%\bodian_cover_<姝屾洸ID>.jpg`锛屽啀浜ょ粰 SMTC鈥斺€?
  | 浜ょ粰 SMTC 鐨勬柟寮?| 缁撴灉 |
  |---|---|
  | `CreateFromUri(https://鈥?` | 鉂?绯荤粺 TLS 鍧忥紝涓嬩笉涓嬫潵 |
  | `CreateFromUri(file://鈥?` | 鉂?闈欓粯蹇界暐 |
  | **`CreateFromFile(StorageFile)`** | 鉁?**鐢熸晥**锛堥渶瑕?`GetFileFromPathAsync` + 寮傛绛夊緟锛?|

- 涓嬭浇鍣細`cover_dl.js`锛坣ode锛夛紝鍏堝啓 `.part` 鍐嶉噸鍛藉悕锛岄伩鍏嶆ˉ鎺ヨ鍒板崐寮犲浘
- 缂撳瓨锛氬悓涓€棣栨瓕鍐嶆鎾斁鐩存帴澶嶇敤鏈湴鏂囦欢锛屼笉鍐嶈仈缃?
## 鍥涚偣涓冦€侀潤榛樿繍琛岋紙娌℃湁绐楀彛锛?
涓や釜鍦版柟浼氬啋鍑烘帶鍒跺彴绐楀彛锛岄兘宸插鐞嗭細

1. **鍒囨瓕鏃?*锛氬皝闈㈢敱 node 涓嬭浇銆俙[Process]::Start(鏂囦欢鍚? 鍙傛暟)` 杩欑閲嶈浇浼氬脊鍑?   鎺у埗鍙扮獥鍙ｏ紝蹇呴』鏀圭敤 `ProcessStartInfo` 骞惰缃?   `UseShellExecute = false` + **`CreateNoWindow = true`**锛堝啀鍔?`WindowStyle = Hidden`锛?2. **鍚姩鏃?*锛歚.cmd` 鍚姩鍣ㄦ€讳細闂嚭/鐣欎笅涓€涓帶鍒跺彴绐楀彛銆傛敼鐢?**VBScript 鍚姩鍣?*
   `bodian-smtc-bridge.vbs`锛坄WScript.Shell.Run(cmd, 0, False)`锛岀獥鍙ｆā寮?0 = 瀹屽叏闅愯棌锛夛紝
   寮€鏈鸿嚜鍚殑蹇嵎鏂瑰紡鎸囧悜 `wscript.exe` + 璇?vbs

鐜板湪鎵嬪姩鍚姩鏂瑰紡鏄?*鍙屽嚮 `bodian-smtc-bridge.vbs`**锛坄.cmd` 鍙槸杞皟瀹冿紝浠嶄細闂竴涓嬶級銆?
## 鍥涚偣鍏€佽ˉ鍏咃細涓轰粈涔堛€孧ediaPlayer + 鎾斁鍒楄〃 + 妫€娴嬫挱鏀惧彉鍖栥€嶄篃璧颁笉閫?
鎬濊矾锛堝緢鍚堢悊锛夛細璁?MediaPlayer 鎺ョ SMTC 鎸夐挳锛坄CommandManager.IsEnabled = true`锛夛紝
杞妫€娴嬫挱鏀惧垪琛ㄦ槸鍚﹀墠杩涳紝浠ユ鍒ゆ柇鐢ㄦ埛鎸変簡 next锛屽啀杞彂濯掍綋閿粰娉㈢偣銆?
瀹炴祴缁撹锛?*鍓嶆彁涓嶆垚绔嬨€?*

- 鍙楅檺娌欑閲岋細`PlaybackState` 鎭掍负 `None`
- **姝ｅ父妗岄潰鐜**锛堢敤鎴锋墜鍔ㄨ繍琛?`cmd_mgr_selftest.ps1`锛岃窇浜?45 绉掞級锛氬悓鏍?`state=None`锛?  `MediaOpened` / `MediaFailed` 閮戒笉瑙﹀彂锛屾渶缁?`sawPlaying=False`
- 鎾斁鍣ㄦ棦鐒朵粠鏈繘鍏ユ挱鏀剧姸鎬?鈫?`CommandManager` 涓嶄細鍝嶅簲鎸夐挳 鈫?鎾斁鍒楄〃涓嶄細鍓嶈繘
  鈫?**娌℃湁浠讳綍銆屾挱鏀惧彉鍖栥€嶅彲渚涙娴?*
- 闄勫甫锛歅owerShell 璋?WinRT 闆嗗悎涔熶細澶辫触锛坄Items.Add` 鈫?`System.__ComObject` 娌℃湁 `Add`锛?
**鏍规湰鍘熷洜**锛氭尝鐐硅兘鍑哄０锛屾槸鍥犱负瀹冭嚜甯?mpv锛堣嚜宸辫В鐮侊紝涓嶈蛋绯荤粺濯掍綋鏍堬級锛涜€?WinRT
MediaPlayer 渚濊禆 Windows 鐨?Media Foundation / 闊抽鏍堬紝鍦ㄨ繖鍙版満鍣ㄤ笂灏辨槸璧蜂笉鏉ャ€?
> 鑷鑴氭湰淇濈暀鍦ㄥ伐浣滃尯锛坄cmd_mgr_selftest.ps1` / `.cmd`锛夈€傛崲鏈哄櫒銆佹垨淇浜嗙郴缁熷獟浣撶粍浠?> 涔嬪悗鍙互鍐嶈窇涓€娆★細鍙鍑虹幇 `sawPlaying=True` + `POSITION RESET`锛岃繖鏉¤矾灏辨椿浜嗭紝
> 閭ｆ椂鍐嶆妸鎸夐挳杞彂鎺ヤ笂鍗冲彲銆?
## 鍥涚偣涔濄€丮ediaPlayer 鎵撲笉寮€鏂囦欢鐨勭湡姝ｅ師鍥狅紙宸茬粫杩囷級

瀹炴祴鍥涚缁?MediaPlayer 鍠傚獟浣撶殑鏂瑰紡锛?
| 鏂瑰紡 | 缁撴灉 |
|---|---|
| `CreateFromUri("file:///C:/Windows/Media/鈥?)` | 鉂?`PlaybackState=None`锛圵PF 鐗堟姤 `0xC00D11D2`銆屾棤娉曡闂枃浠躲€嶏級 |
| `CreateFromUri("file:///鈥?TEMP%鈥?)` | 鉂?鍚屾牱澶辫触 |
| **`CreateFromStorageFile(StorageFile)`** | 鉁?**`Playing`** |
| **`CreateFromStream(InMemoryRandomAccessStream)`** | 鉁?**`Playing`** |

鎵€浠ラ棶棰?*涓嶆槸** Media Foundation 鎹熷潖锛屼篃**涓嶆槸**闊抽璁惧闂锛堟敞鍐岃〃閲屽涓?`state=1` 鐨勬椿璺冩覆鏌撹澶囥€乣Audiosrv` / `Audiodg` 閮芥甯革級锛岃€屾槸 **`file://` URI
閭ｆ潯 scheme handler 璺緞鍧忎簡**鈥斺€旀墍鏈変綅缃兘澶辫触锛屼笌鏂囦欢璺緞銆佹潈闄愩€佹矙绠辨棤鍏炽€?鐢?`StorageFile` 鎴栧唴瀛樻祦鍗冲彲瀹屽叏缁曡繃銆?
> 鎰忎箟锛?*MediaPlayer 鏈韩瀹屽叏鍙敤**銆傝繖鏄瘎浼般€岀敤 CommandManager 妫€娴嬫寜閽€嶆柟妗堢殑鍏抽敭鍓嶆彁锛?> 鐜板湪鍙墿銆屽線 `MediaPlaybackList` 閲屽姞椤广€嶈繖涓€涓己鍙ｏ紙PowerShell 璋冧笉鍔ㄦ硾鍨嬫姇褰遍泦鍚堬級銆?
## 鍥涚偣鍗併€佹挱鏀炬帶鍒舵寜閽細鉁?宸插疄鐜帮紙v2锛?
**鎬濊矾**锛堢敤鎴锋彁鍑虹殑鏂瑰悜锛夛細璁?MediaPlayer 鑷繁鎺ョ鎸夐挳 鈫?鎾斁鍒楄〃浼氶殢涔嬪墠杩?鈫?杞妫€娴嬪埌鍙樺寲 鈫?杞彂濯掍綋閿粰娉㈢偣銆傚叏閮ㄨ绱犲涓嬶細

1. **MediaPlayer 鎾竴涓?4 椤归潤闊虫挱鏀惧垪琛?*
   - 鍏抽敭 1锛?*鐢?`MediaSource.CreateFromStream(InMemoryRandomAccessStream)`**锛?     鍗抽煶棰戞暟鎹湪鍐呭瓨閲岀幇閫犮€傚洜涓烘湰鏈?`CreateFromUri("file:///鈥?)` 鏄潖鐨?     锛坄0xC00D11D2`锛夛紝鑰?`CreateFromStream` / `CreateFromStorageFile` 姝ｅ父
   - 鍏抽敭 2锛?*4 椤?*锛堜笉鏄?1 椤癸級鎵嶈兘鐢ㄧ储寮曞彉鍖栨柟鍚戝尯鍒嗐€屼笅涓€棣?涓婁竴棣栥€?2. **鍚敤 `CommandManager.IsEnabled = true`**锛岃瀹冩帴绠?SMTC 鎸夐挳鈥斺€?   杩欐牱**涓嶉渶瑕佽闃呬换浣?WinRT 浜嬩欢**锛圥owerShell 璁㈤槄涓嶄簡锛?3. **杞 `MediaPlaybackList.CurrentItemIndex`** 妫€娴嬫寜閽細
   - `delta == 1` 鈫?涓嬩竴棣?鈫?鍙?`VK_MEDIA_NEXT_TRACK (0xB0)`
   - `delta == 3` 鈫?涓婁竴棣?鈫?鍙?`VK_MEDIA_PREV_TRACK (0xB1)`
   - 鎾斁鍣ㄤ笉澶勪簬 Playing锛堣鏄庢寜浜嗘挱鏀?鏆傚仠锛夆啋 鍙?`VK_MEDIA_PLAY_PAUSE (0xB3)` 骞舵仮澶嶆挱鏀?4. **闃叉姈 1.5s**锛氬拷鐣ユ垜浠嚜宸辨敞鍏ョ殑鎸夐敭鍥炲０

**涓や釜韪╁潙**锛?- **鎾斁鍒楄〃鍔犱笉杩涢」**锛歚Items` 鏄硾鍨嬪疄渚嬪寲鐨?`System.__ComObject`锛?  `Add`/`Append` 鍦?PowerShell 閲岄兘璋冧笉鍔ㄣ€傝В娉曪細鎸?IID
  **`e1504f46-c4a6-5a29-8fc9-a934d12d7242`**锛? `IVector<MediaPlaybackItem>`锛?  鐢?`IInspectable::GetIids` 鎺㈡祴寰楀埌锛塓I 鍚庯紝鐩存帴璋冪敤 vtable **绱㈠紩 13** 鐨?`Append`
- **`CommandManager` 浼氳鐩栨垜浠缃殑鍏冩暟鎹?*锛坱itle 琚竻绌猴級鈫?瑙ｆ硶锛?*姣忎釜 tick 閲嶆柊
  鍐欏叆 Title/Artist/Album**锛堝疄娴嬭兘绋崇ǔ鍘嬩綇锛涘皝闈㈠彧鍦ㄥ垏姝屾椂璁剧疆涓€娆★級

**涓庨敭鐩樺獟浣撻敭涓嶅啿绐?*锛氭尝鐐圭敤閿洏閽╁瓙浼樺厛鍚冩帀鐗╃悊濯掍綋閿紝绯荤粺灏变笉鍐嶆妸瀹冨垎鍙戠粰鎴戜滑鐨?浼氳瘽锛屾墍浠?*鎸夐敭鐩樺彧鍒囦竴棣?*锛堝疄娴嬬‘璁わ級锛涜€?Fusion 鐨勬寜閽蛋 SMTC 鍗忚锛屽彧鏈夋垜浠敹寰楀埌銆?锛堝獟浣撻敭鍙戦€佸繀椤诲甫 `KEYEVENTF_EXTENDEDKEY`锛屽惁鍒欐尝鐐瑰拷鐣ャ€傦級

## 浜斻€佸悗缁彲閫夎矾绾?
### A. 鐢ㄦ湰鏈?.NET SDK 缂栦竴涓湡姝ｇ殑瀹夸富锛堟柊鍙戠幇锛屽€煎緱浼樺厛锛?`C:\宸ヤ綔鍖篭dotnet-sdk\dotnet.exe`锛?*SDK 8.0.400**锛屽畬鏁村彲鐢級銆?鐢?C# 鍐欏涓诲彲浠ョ洿鎺ョ敤 `Windows.Media.Playback.MediaPlayer`锛堥煶棰戝ぉ鐒朵笌浼氳瘽鍏宠仈锛屽繀鐒舵垚涓?current锛夛紝
姣?PowerShell 缁?WinRT 绋冲緱澶氾紱鏁版嵁浠嶇敤绗簩鑺傞偅濂楋紙鏁版嵁搴?+ 鍐呭瓨锛夈€?
### B. Edge/Chromium 瀹夸富锛堟渶鍙兘閫氬埌 Fusion锛岄獙璇佹垚鏈渶浣庯級
Chromium 鐨勫獟浣撲細璇濊嚜甯﹂煶棰戙€佸繀鐒舵垚涓?current锛孎usion 瀹樻柟鏀寔 Chrome/Edge銆?姝ラ锛氱敤 Edge 鎵撳紑 `bodian_test.html` 鈫?鍦?Lyricify 璁剧疆閲?*鍚敤 Microsoft Edge / Google Chrome 鏀寔**
锛堥粯璁ゆ槸鍏抽棴鐨勶級鈫?鐪嬫槸鍚﹀嚭姝岃瘝銆傛垚鍔熺殑璇濇妸閲囬泦鍣ㄦ帴鍒伴〉闈笂鍗冲彲鍏ㄨ嚜鍔ㄣ€?
### C. BodianTaskbarLyric锛堟垚鍝侊紝纭畾鑳界敤锛?涓撲负娉㈢偣鍋氱殑浠诲姟鏍忔瓕璇嶏紝鍘熺悊涓庢湰鏂囨。涓€鑷淬€備笅杞藉嵆鐢細
https://github.com/weiwei221206/BodianTaskbarLyric/releases
浠ｄ环锛氭瓕璇嶅湪浠诲姟鏍忥紝涓嶆槸 Fusion 鐨勭晫闈€?
### D. 鎹㈡挱鏀炬簮锛堥浂寮€鍙戯級
姹芥按闊充箰锛團usion 鏀寔"瀹岀編"锛? QQ 闊充箰锛堟彃浠跺悗瀹岀編锛? 缃戞槗浜戯紙闇€鎻掍欢锛夈€?
### E. PotPlayer
鍦?Fusion 鏀寔鍒楄〃閲岋紙"鏃堕棿杞村畬缇庯紱鏇茬洰淇℃伅鍙栧喅浜庡叿浣撴枃浠跺悕"锛夛紝
浣?*鏀句笉浜嗘尝鐐圭殑鍦ㄧ嚎鏇插簱**锛堥叿鎴戞簮 mflac/mgg/zp 鍔犲瘑鏍煎紡 + 鎺堟潈锛夛紝
鍙兘褰?瀹夸富"锛屼笖瀹冪殑鍏冩暟鎹潵鑷枃浠躲€佹棤娉曞姩鎬佹敞鍏?鈫?涓嶅 B 骞插噣銆?
---

## 鍏€佺幆澧冨蹇?
- 娉㈢偣锛歚C:\Program Files (x86)\bodian\bodian_pc.exe`锛岃繘绋嬪悕 `bodian_pc`锛岀増鏈?1.1.7
  鏁版嵁鐩綍锛歚%LOCALAPPDATA%\cn.wenyu.bodian\bodian_pc`
- Lyricify锛歋tore 鍖?`63265WXRIW.193470E81A0DE`锛堣繘绋嬪悕 `Lyricify Lite`锛岀増鏈?1.3.1.0 = Fusion锛夛紝
  鍙︽湁 `63265WXRIW.Lyricify` 4.4.0.0
- .NET SDK 8.0.400锛歚C:\宸ヤ綔鍖篭dotnet-sdk\dotnet.exe`
- PowerShell锛?.1锛坄C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe`锛? pwsh 7
- 鏈満鍛戒护琛?HTTPS 涓嶅彲鐢細`curl: schannel AcquireCredentialsHandle failed SEC_E_NO_CREDENTIALS`锛?  GitHub 鐩磋繛鏃堕€氭椂涓嶉€氥€傚彲鐢?DSH 鐨勭綉椤垫姄鍙栭€氶亾锛坄read_url`锛夎 GitHub API / raw锛堥棿姝囧彲鐢級
- 鍙楅檺娌欑浼氭嫤锛欵dge 鍚姩銆侀儴鍒?WMI 鏌ヨ锛坄Get-CimInstance` 鎷掔粷璁块棶锛?
## 涓冦€佸彲鐩存帴澶嶇敤鐨勫叧閿唬鐮?
**璇诲綋鍓嶆洸鐩紙SQLite锛屽彧璇伙級**
```
sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY=1, NULL)
SELECT ord, id, json, time FROM hist_song ORDER BY ord DESC LIMIT 1;
```
闇€瑕?`SetDllDirectory("C:\Program Files (x86)\bodian")` 鎵嶈兘鍔犺浇瀹冭嚜甯︾殑 `sqlite3.dll`銆?
**璇昏繘搴︼紙瑙?2.2 鎸囬拡閾撅級**

**浼€?SMTC 浼氳瘽锛堣 2.4锛?*

**鍒ゆ柇鎾斁/鏆傚仠锛堝疄娴嬫湁鏁堢殑瀹瑰樊锛?*
- 姣?800ms 閲囨牱涓€娆?time-pos锛涗笌涓婃宸€?> 0.05s 瑙嗕负"鏈夎繘灞?骞惰褰曟椂闂?- 杩炵画 **2.5 绉?*鏃犺繘灞?鈫?`Paused`锛屽惁鍒?`Playing`
- 瀹瑰樊澶皬浼氭姈鍔紙鍋跺彂璇诲け璐ヤ細琚鍒や负鏆傚仠锛夛紝2.5s 瀹炴祴绋冲畾

