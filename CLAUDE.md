# ReplayCam

iOS 相機 App，以延遲畫面為主畫面，讓使用者可以「看到幾秒前的自己」，並儲存最近一段時間的影片片段。

## 專案結構

```
ReplayCam/
├── ReplayCam.xcodeproj/       # Xcode 專案設定
└── ReplayCam/
    ├── ReplayCamApp.swift      # App 入口點
    ├── ContentView.swift       # SwiftUI 主畫面（純 View）
    ├── CameraManager.swift     # 相機邏輯、緩衝區管理、儲存觸發
    ├── FrameBuffer.swift       # Thread-safe 滾動緩衝區
    ├── TimestampedFrame.swift  # 幀資料 model
    ├── VideoExporter.swift     # 非同步影片匯出 + 相簿儲存
    ├── UIImage+Video.swift     # resize / toPixelBuffer extensions
    ├── Info.plist              # App 設定
    └── Assets.xcassets/        # 圖示與顏色資源
```

## 核心功能

- **延遲畫面**：主畫面顯示 N 秒前的鏡頭畫面（可選 1/3/5/10/15/30 秒）
- **即時小視窗**：右下角顯示當下即時畫面（200×150pt）
- **循環緩衝區**：最多保留 35 秒的畫面，以 JPEG 壓縮（quality 0.6）儲存在記憶體
- **儲存影片**：可選擇儲存最近 5/10/15/30 秒，匯出為 1080×1920 H.264 MP4 存到相簿

## 主要類別與架構

### `ContentView` (SwiftUI View)
- `@StateObject var camera: CameraManager`
- `selectedDelay: Double` — 目前選擇的延遲秒數
- `showSaveOptions: Bool` — 控制儲存長度的 confirmationDialog
- 拆成多個 private computed var：`delayedBackground`、`realtimePreview`、`controlPanel`、`delayPicker`、`bufferStatus`、`saveButton`

### `CameraManager` (`@MainActor` NSObject + ObservableObject)

| 屬性 | 說明 |
|------|------|
| `realtimeImage` | 即時畫面（縮圖 200×150） |
| `delayedImage` | 延遲畫面（縮圖 540×960） |
| `bufferFrameCount` | 緩衝區目前幀數 |
| `bufferDuration` | 緩衝區涵蓋秒數 |
| `isSaving` | 是否正在匯出影片 |

**主要方法：**
- `checkPermissions()` — 請求相機授權，成功後呼叫 `setupCamera()`
- `setupCamera()` — 在 `sessionQueue` 建立 `AVCaptureSession`（後置鏡頭，high preset，直向）
- `saveRecentFrames(duration:)` — 從緩衝區取幀，用 `Task.detached` 呼叫 `VideoExporter`
- `captureOutput(...)` — `nonisolated`，在 `frameQueue` 接收幀，寫入 `FrameBuffer`，限速更新 UI

**效能設計：**
- `CIContext` 建立一次、重複使用（避免每幀重建）
- 即時畫面 UI 更新限速 15fps，延遲畫面限速 25fps
- 緩衝區上限 35 秒（超出的舊幀自動清除，並設有 1200 幀的提前清理門檻）

### `FrameBuffer`
- `NSLock` 保護內部陣列，可安全從任意 thread 讀寫
- `append(_:)` — 加幀並清除過期資料
- `findFrame(nearTimestamp:tolerance:)` — 找最近目標時間的幀
- `frames(since:)` — 取出指定時間之後的所有幀（供匯出用）

### `VideoExporter`
- `export(frames:) async throws -> URL` — 用 `requestMediaDataWhenReady` 非同步匯出 MP4（1080×1920，30fps，5Mbps H.264）
- `saveToPhotoLibrary(url:) async throws` — 用 `PHPhotoLibrary` async API 儲存到相簿
- 匯出時每幀用 `autoreleasepool` 控制記憶體

### `UIImage+Video`
- `resized(to:)` — 縮圖（一般用途）
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
| `refactor/clean-architecture` | 重構版本（拆分成多個檔案，修正 thread safety，async export） |

## 重構變更紀錄（refactor/clean-architecture）

- **拆分檔案**：將原本 1293 行的 `ContentView.swift` 拆成 6 個獨立檔案
- **修正 thread safety**：`FrameBuffer` 用 `NSLock` 保護，修正原本在 `frameQueue` 與 `MainActor` 之間的 data race
- **`CIContext` 重用**：原本每幀都建一個新 `CIContext`，改為在 `CameraManager` 初始化時建立一次
- **非同步匯出**：`VideoExporter` 改用 `requestMediaDataWhenReady` + async/await，取代原本的 `Thread.sleep` 迴圈
- **移除死碼**：刪掉 548 行被 `/* */` 包住的舊版程式碼
- **Swift 6 concurrency**：`CameraManager` 標記為 `@MainActor`，`captureOutput` 標記為 `nonisolated`，跨 thread 存取的屬性用 `nonisolated(unsafe)` 明確標示
