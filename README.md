# DueBite-Demo

賞味期限のアプリです（デモ版）
## 実装済み

- カメラ撮影／アルバム選択
- AI画像解析による商品名・賞味期限・カテゴリーの入力補助
- AIとの会話による商品・賞味期限の特定と登録
- 手入力とカレンダー入力
- 期限順の一覧、緊急度表示、食べきり済み管理
- 期限内の食べきりで10〜20ポイント付与
- ポイント履歴とレベル表示
- Androidの期限通知（3日前と当日、通知時刻を選択可能）
- SharedPreferencesによる端末内保存
- Android、iOS、Web対応のレスポンシブUI

Androidの期限通知は、スマートフォンやVMに設定されている現地時刻を使います。端末を再起動した後も通知予約を復元します。

## 起動

AI未設定でもデモ解析付きで動作します。

```powershell
flutter pub get
flutter run
```

実際のAI画像解析を使う場合は、先に [backend/README.md](backend/README.md) のWorkerをデプロイし、そのURLを渡します。

```powershell
flutter run --dart-define=AI_API_BASE_URL=https://YOUR-WORKER.workers.dev/analyze-expiry
```

APIキーはFlutterアプリへ記載しないでください。WorkerのSecretとして保持します。

## テスト

```powershell
flutter analyze
flutter test
```
