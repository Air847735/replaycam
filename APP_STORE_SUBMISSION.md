# ReplayCam — App Store 上架指南

> 從準備到正式上線的完整流程，依序執行。

---

## 第一階段：帳號與憑證準備

### 1. Apple Developer Program
- 確認已加入 [Apple Developer Program](https://developer.apple.com/programs/)（年費 $99 USD）
- 登入 [developer.apple.com](https://developer.apple.com) 確認帳號狀態為 **Active**

### 2. 憑證與 Provisioning Profile
在 Xcode → Settings → Accounts 登入 Apple ID，然後：

```
Xcode → 點選專案 → Signing & Capabilities
  ✅ Automatically manage signing（勾選）
  Team → 選擇你的開發者帳號
  Bundle Identifier → 設定唯一 ID，例如 com.yourname.replaycam
```

> 若是個人帳號：Bundle ID 建議用反向域名格式，一旦上傳不可更改。

---

## 第二階段：App 資訊設定

### 3. Info.plist 權限說明文字
審核員會檢查每個權限的用途說明是否清楚。確認以下三項都有填：

| Key | 建議文字 |
|-----|---------|
| `NSCameraUsageDescription` | 需要相機權限以錄製延遲回放影片 |
| `NSPhotoLibraryAddUsageDescription` | 需要相簿權限以儲存錄製的影片 |
| `NSPhotoLibraryUsageDescription` | 需要相簿權限以瀏覽和管理已儲存的影片 |

### 4. 版本號與 Build 號
```
Xcode → 專案 → General
  Version：1.0.0（對外顯示，每次提審可保持相同）
  Build：1（每次上傳 TestFlight / 提審都要遞增，不可重複）
```

### 5. App Icons
需提供 **1024×1024 px** 的 App Icon（無圓角，PNG，無透明）：
- 放入 `Assets.xcassets/AppIcon`
- Xcode 會自動產生各尺寸

---

## 第三階段：App Store Connect 設定

前往 [appstoreconnect.apple.com](https://appstoreconnect.apple.com)

### 6. 建立 App
```
我的 App → + → 新增 App
  平台：iOS
  名稱：ReplayCam（上架後顯示在 App Store 的名稱）
  語言：繁體中文（或英文）
  Bundle ID：選擇第 2 步設定的 ID
  SKU：自訂唯一編號，例如 REPLAYCAM001（內部用，不公開）
```

### 7. App 資訊填寫

#### 基本資訊
| 欄位 | 建議填寫 |
|------|---------|
| 副標題（選填） | 動作延遲回放分析 |
| 分類 | 主：體育；次：工具程式 |
| 內容分級 | 4+（無不當內容） |
| 版權 | © 2025 你的姓名 |

#### 描述（最多 4000 字）
```
ReplayCam 讓你即時看到幾秒前的自己。

設定 1 到 30 秒的延遲，鏡頭會顯示你指定秒數之前的動作畫面，
讓你不需要教練也能即時分析揮棒、投球、舞步或任何重複動作。

主要功能：
• 可調式延遲：1 秒到 30 秒，精確到 1 秒
• 即時小視窗：同時看到當下與延遲畫面
• 影片儲存：選擇最近 3–30 秒的片段儲存到相簿
• 片段庫：依日期瀏覽所有錄製記錄
• 慢動作回放：¼×、½×、1× 速度回看動作細節
• 雙指縮放即時視窗大小
```

#### 關鍵字（最多 100 字元，逗號分隔）
```
延遲,回放,訓練,高爾夫,棒球,舞蹈,動作分析,慢動作,體育,教練
```

#### 支援網址（必填）
可用 GitHub Pages、Notion 或任何公開頁面，需能正常開啟。

#### 隱私權政策網址（必填）
App 使用相機與相簿，**必須提供隱私權政策**。  
最簡單做法：在 GitHub 建立一個 `privacy-policy.md` 並透過 GitHub Pages 公開。

---

## 第四階段：截圖與預覽影片

### 8. 截圖規格（必填）

至少需要提供 **6.9 吋（iPhone 16 Pro Max）** 的截圖：

| 機型 | 尺寸 | 必填 |
|------|------|------|
| 6.9 吋（iPhone 16 Pro Max）| 1320×2868 px | ✅ |
| 6.5 吋（iPhone 14 Plus）| 1242×2688 px | 選填（若不填會自動縮放）|
| iPad Pro 13 吋 | 2064×2752 px | 若支援 iPad 則必填 |

**拍截圖的方式：**
1. Xcode → Simulator → 選擇對應機型
2. 執行 App → 操作到最佳畫面
3. `⌘ + S` 存截圖，或到 `File → Take Screenshot`

**建議截圖內容（5–10 張）：**
1. 主畫面（HomeView 深色卡片）
2. 延遲錄影中（倒數或延遲畫面全螢幕）
3. 即時小視窗 + 控制列
4. 日期記錄列表
5. 片段播放（含速度切換）

---

## 第五階段：Build 上傳

### 9. Archive & 上傳

```
1. Xcode → 選擇目標裝置為「Any iOS Device (arm64)」
2. Product → Archive
3. 等待完成後，Organizer 視窗會自動開啟
4. 選取剛建立的 Archive → Distribute App
5. App Store Connect → Upload → 下一步直到完成
```

> 上傳成功後約 15–30 分鐘會在 App Store Connect 的 TestFlight / 建置版本出現。

### 10. 選擇 Build
在 App Store Connect 的版本頁面：
- 「Build」欄位 → 選擇剛上傳的版本號

---

## 第六階段：審核前確認清單

在按下「提交審核」之前，逐項確認：

- [ ] App 在真實裝置（非模擬器）上測試無崩潰
- [ ] 所有權限在拒絕時 App 不會閃退
- [ ] 隱私權政策頁面可正常開啟
- [ ] 支援網址可正常開啟
- [ ] 截圖尺寸正確、內容清楚
- [ ] 描述沒有提及其他平台（Android / 競品）
- [ ] 版本號與 Build 號正確
- [ ] 內容分級問卷填寫完整
- [ ] 出口合規：若 App 有使用加密（HTTPS 算），勾選「僅使用豁免的加密」

### 常見退審原因（提前避免）
| 原因 | 對應守則 |
|------|---------|
| 權限說明不夠清楚 | 2.5.4 |
| 隱私權政策缺失或無法開啟 | 5.1.1 |
| 截圖與實際功能不符 | 2.3.3 |
| App 在特定情況崩潰 | 2.1 |
| 功能太少或像是「Demo」| 4.2 |

---

## 第七階段：提交與等待

### 11. 提交審核
App Store Connect → 版本 → 右上角「提交審核」

### 12. 審核時間
- 一般首次提審：**1–3 個工作天**
- 若有問題會收到 email，需在 App Store Connect 回覆或修改後重新提交

### 13. 上架設定
提交前選擇：
- **自動上架**：審核通過後立即發布
- **手動上架**：審核通過後你決定何時按「發布」
- **排程上架**：指定日期自動發布

---

## 第八階段：上線後

### 14. 版本更新流程
每次更新重複以下步驟：
1. 修改程式
2. 遞增 Build 號（每次上傳必須比前一個大）
3. 若有新功能，遞增 Version（1.0.0 → 1.1.0）
4. Archive → 上傳
5. App Store Connect 建立新版本 → 填寫「此版本的新功能」
6. 提交審核

### 15. 評分與回覆
- App Store Connect → 評分與評論
- 建議在 App 內適當時機請使用者評分：
  ```swift
  import StoreKit
  SKStoreReviewController.requestReview()
  ```

---

## 快速參考

| 資源 | 連結 |
|------|------|
| App Store Connect | https://appstoreconnect.apple.com |
| Apple Developer | https://developer.apple.com |
| App Store 審核指南 | https://developer.apple.com/app-store/review/guidelines/ |
| 截圖規格 | https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications |
| Human Interface Guidelines | https://developer.apple.com/design/human-interface-guidelines |
