# ReplayCam

iOS 相機 App，以延遲畫面為主畫面，讓使用者可以「看到幾秒前的自己」，並儲存最近一段時間的影片片段。

## 專案結構

```
ReplayCam/
├── ReplayCam.xcodeproj/       # Xcode 專案設定
└── ReplayCam/
    ├── ReplayCamApp.swift      # App 入口點
    ├── ContentView.swift       # 主 UI + CameraManager 邏輯
    ├── Info.plist              # App 設定（相機/相簿權限）
    └── Assets.xcassets/        # 圖示與顏色資源
```

## 核心功能

- **延遲畫面**：主畫面顯示 N 秒前的鏡頭畫面（可選 1/3/5/10/15/30 秒）
- **即時小視窗**：右下角顯示當下即時畫面（200×150pt）
- **循環緩衝區**：最多保留 30 秒的畫面，以 JPEG 壓縮（quality 0.6）儲存在記憶體
- **儲存影片**：可選擇儲存最近 5/10/15/30 秒，匯出為 1080×1920 H.264 MP4 存到相簿

## 主要類別與架構

### `ContentView` (SwiftUI View)
- `@StateObject var cameraManager: CameraManager`
- `selectedDelay: Double` — 目前選擇的延遲秒數
- `showSaveOptions: Bool` — 控制儲存長度的 confirmationDialog

### `CameraManager` (NSObject + ObservableObject)
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
- `saveRecentFrames(duration:)` — 從緩衝區取幀，在背景 thread 呼叫 `exportVideo`
- `exportVideo(frames:duration:)` — 用 `AVAssetWriter` 匯出 MP4（1080×1920，30fps，5Mbps）

**效能設計：**
- 即時畫面 UI 更新限速 15fps，延遲畫面限速 25fps
- 緩衝區超過 30 秒的舊幀自動清除
- 匯出時每幀用 `autoreleasepool` 避免記憶體爆炸

### UIImage extensions
- `resized(to:)` — 縮圖（一般用途）
- `resizedExact(to:)` — scale=1 精確尺寸（匯出用）
- `toPixelBuffer()` — 轉成 `CVPixelBuffer`（32BGRA，匯出用）

## 所需權限（需加入 Info.plist）
- `NSCameraUsageDescription` — 相機
- `NSPhotoLibraryAddUsageDescription` — 寫入相簿

> 目前 Info.plist 尚未包含這兩個 key，執行時會 crash。需補上。

## 備註
- `ContentView.swift` 頂部有一大段舊版程式碼被 `/* ... */` 包起來（舊版有「開始/停止錄影」按鈕），現行版本改為「儲存最近 N 秒」的設計。
