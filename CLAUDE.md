# ReplayCam

iOS 相機 App，以延遲畫面為主畫面，讓使用者可以「看到幾秒前的自己」，並儲存最近一段時間的影片片段。

## 專案結構

```
ReplayCam/
├── ReplayCam.xcodeproj/       # Xcode 專案設定
└── ReplayCam/
    ├── ReplayCamApp.swift      # App 入口點
    ├── RootView.swift          # 根視圖（導向 HomeView）
    ├── HomeView.swift          # 首頁：相機入口、片段庫、設定卡片
    ├── ContentView.swift       # 相機拍攝畫面（延遲預覽 + 即時小視窗）
    ├── CameraManager.swift     # 相機邏輯、緩衝區管理、儲存觸發
    ├── FrameBuffer.swift       # Thread-safe 滾動緩衝區
    ├── TimestampedFrame.swift  # 幀資料 model
    ├── VideoExporter.swift     # 非同步影片匯出
    ├── ClipStore.swift         # 片段檔案管理 + 最愛清單
    ├── LibraryView.swift       # 片段庫（ClipCell、ShareSheet）
    ├── DateLibraryView.swift   # 依日期分組的片段庫（含 DayDetailView）
    ├── PlayerView.swift        # 影片播放器（縮圖 scrubber、速度選擇、匯出）
    ├── SettingsView.swift      # 設定頁（預設延遲、儲存空間、版本資訊）
    ├── UIImage+Video.swift     # resize / toPixelBuffer extensions
    ├── Info.plist              # App 設定
    └── Assets.xcassets/        # 圖示與顏色資源（含 tiss_pattern）
```

## 核心功能

- **延遲畫面**：主畫面顯示 N 秒前的鏡頭畫面（可選 1–30 秒，預設可在設定調整）
- **即時小視窗**：拍攝畫面右下角顯示當下即時畫面
- **循環緩衝區**：最多保留 35 秒的畫面，以 JPEG 壓縮（quality 0.6）儲存在記憶體
- **儲存影片**：可選擇儲存最近一段時間，匯出為 1080×1920 H.264 MP4 存到 App 片段庫
- **片段庫**：依日期分組瀏覽、縮圖方格（支援 pinch 調整欄數）、最愛標記
- **播放器**：縮圖 scrubber 拖曳定位、¼× / ½× / 1× 速度切換、最愛、中文匯出分享

## 主要類別與架構

### 導航流程

```
ReplayCamApp → RootView → HomeView
                              ├── ContentView（相機拍攝，fullScreenCover）
                              ├── DateLibraryView（片段庫，NavigationLink）
                              │     └── DayDetailView → PlayerView
                              └── SettingsView（NavigationLink）
```

### `HomeView`
- 首頁卡片式 UI，品牌漸層背景（深海軍藍 + tiss_pattern 紋理）
- 相機大卡片 + 片段庫、設定次要卡片
- `@ObservedObject var store: ClipStore` — 顯示片段數量

### `ContentView` (相機拍攝畫面)
- `@StateObject var camera: CameraManager`
- `selectedDelay: Double` — 目前選擇的延遲秒數
- `showSaveOptions: Bool` — 控制儲存長度的 confirmationDialog
- 拆成多個 private computed var：`delayedBackground`、`realtimePreview`、`controlPanel`、`delayPicker`、`bufferStatus`、`saveButton`

### `CameraManager` (`@MainActor` NSObject + ObservableObject)

| 屬性 | 說明 |
|------|------|
| `realtimeImage` | 即時畫面縮圖 |
| `delayedImage` | 延遲畫面縮圖 |
| `bufferFrameCount` | 緩衝區目前幀數 |
| `bufferDuration` | 緩衝區涵蓋秒數 |
| `isSaving` | 是否正在匯出影片 |
| `isRunning` | 相機是否啟動中 |
| `showSuccess` | 儲存成功提示旗標 |

**主要方法：**
- `checkPermissions()` — 請求相機授權，成功後呼叫 `setupCamera()`
- `setupCamera()` — 在 `sessionQueue` 建立 `AVCaptureSession`（後置鏡頭，high preset，直向，強制 30fps）
- `setDelay(_:)` — 更新 `delaySeconds`（nonisolated unsafe）
- `saveRecentFrames(duration:)` — 從緩衝區取幀，用 `Task.detached` 呼叫 `VideoExporter`，存到 ClipStore
- `captureOutput(...)` — `nonisolated`，在 `frameQueue` 接收幀，寫入 `FrameBuffer`，限速更新 UI

**效能設計：**
- `CIContext` 建立一次、重複使用（避免每幀重建）
- 即時畫面 UI 更新限速 15fps，延遲畫面限速 25fps
- 錄製幀率強制鎖 30fps（防止新款 iPhone 自動跳 60fps 造成 CPU 雙倍負擔）
- 緩衝區上限 35 秒，設有 1200 幀的提前清理門檻
- 每 300 幀（約 10 秒）flush GPU/CPU cache 防止記憶體累積

### `FrameBuffer`
- `NSLock` 保護內部陣列，可安全從任意 thread 讀寫
- `append(_:)` — 加幀並清除過期資料
- `findFrame(nearTimestamp:tolerance:)` — 找最近目標時間的幀
- `frames(since:)` — 取出指定時間之後的所有幀（供匯出用）

### `VideoExporter`
- `export(frames:) async throws -> URL` — 用 `requestMediaDataWhenReady` 非同步匯出 MP4（1080×1920，30fps，5Mbps H.264）至暫存目錄
- `moveToClipsDirectory(from:) throws -> URL` — 將暫存檔移入 ClipStore 管理目錄
- `saveToPhotoLibrary(url:) async throws` — 用 `PHPhotoLibrary` async API 儲存到相簿
- 匯出時每幀用 `autoreleasepool` 控制記憶體

### `ClipStore` (`@MainActor` ObservableObject, singleton)
- 管理 `Documents/ReplayCamClips/` 目錄下的 `.mp4` 檔案
- `clips: [SavedClip]` — 依建立日期降序排列
- `favoriteIDs: Set<String>` — 最愛清單，持久化到 `UserDefaults`
- `refresh()` — 背景重新掃描目錄
- `delete(_:)` — 刪除檔案並從清單移除
- `toggleFavorite(_:)` / `isFavorite(_:)` — 最愛管理

### `PlayerView`
- `@StateObject var model: PlayerModel` — 包裝 `AVPlayer`，管理播放狀態、時間、縮圖
- 縮圖 scrubber（30 格縮圖，拖曳時顯示預覽氣泡）
- 速度選擇：¼× / ½× / 1×
- 最愛按鈕（連動 ClipStore）
- 匯出：自訂 `VideoShareSheet`（`UIActivityViewController`），排除「拷貝」，以中文「儲存影片」取代系統 Save Video

### `DateLibraryView` / `DayDetailView`
- 依日期分組，顯示每日片段數與總時長
- `DayDetailView`：方格縮圖，支援 pinch 手勢調整欄數（2–5 欄）、多選刪除模式
- 縮圖以 `AVAssetImageGenerator` 非同步產生，letterbox 填滿方形格子

### `SettingsView`
- 品牌漸層背景（與 HomeView 一致）+ tiss_pattern 紋理
- 預設延遲 Slider（1–30 秒，AppStorage 持久化）
- 儲存空間顯示（片段數、MB 用量）
- 清除所有片段（需確認）
- App 版本 / 建置號

### `UIImage+Video`
- `resized(to:)` — 縮圖（一般用途）
- `resizedFit(maxDimension:)` — 按長邊縮放
- `resizedExact(to:)` — scale=1 精確尺寸（匯出用）
- `toPixelBuffer()` — 轉成 `CVPixelBuffer`（32BGRA，匯出用）

## 權限（已設定在 project.pbxproj 的 build settings）
- `NSCameraUsageDescription`
- `NSPhotoLibraryAddUsageDescription`
- `NSPhotoLibraryUsageDescription`

## Git 分支

| 分支 | 說明 |
|------|------|
| `main` | 原始版本（單一 ContentView.swift，含 CameraManager） |
| `refactor/clean-architecture` | 重構版本（多檔案、片段庫、播放器、設定頁） |

## 重構變更紀錄（refactor/clean-architecture）

- **拆分檔案**：將原本單一 `ContentView.swift` 拆成多個獨立檔案
- **修正 thread safety**：`FrameBuffer` 用 `NSLock` 保護，修正 `frameQueue` 與 `MainActor` 之間的 data race
- **`CIContext` 重用**：原本每幀都建一個新 `CIContext`，改為初始化時建立一次
- **非同步匯出**：`VideoExporter` 改用 `requestMediaDataWhenReady` + async/await
- **片段庫**：新增 `ClipStore`、`DateLibraryView`、`DayDetailView`，支援日期分組、多選刪除、最愛
- **播放器**：新增 `PlayerView`，含縮圖 scrubber、速度控制、自訂中文匯出分享
- **品牌視覺**：HomeView、SettingsView 套用 TISS 漸層背景 + tiss_pattern
- **Swift 6 concurrency**：`CameraManager` 標記 `@MainActor`，`captureOutput` 標記 `nonisolated`
