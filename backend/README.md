# DueBite AI API

FlutterアプリにAPIキーを含めず、Cloudflare Worker経由でGeminiを利用します。

- `POST /analyze-expiry`: 写真から商品名・賞味期限・カテゴリーを抽出
- `POST /identify-product`: 会話しながら商品と期限を特定

## セットアップ

1. [Google AI Studio](https://aistudio.google.com/app/apikey) でGemini APIキーを作成します。
2. 初回だけ設定ファイルを作成します。

   ```powershell
   Copy-Item backend\wrangler.toml.example backend\wrangler.toml
   ```

3. WorkerへAPIキーをSecretとして登録します。

   ```powershell
   Set-Location backend
   npx wrangler secret put GEMINI_API_KEY
   ```

4. デプロイします。

   ```powershell
   npx wrangler deploy
   ```

5. Worker URLを指定してFlutterアプリを起動します。

   ```powershell
   Set-Location ..
   flutter run --dart-define=AI_API_BASE_URL=https://YOUR-WORKER.workers.dev/analyze-expiry
   ```

APIキーはFlutterアプリや`wrangler.toml`へ記載しないでください。`AI_API_BASE_URL`を指定しない場合は、UI確認用のデモ応答を返します。

## API形式

画像解析リクエスト:

```json
{
  "imageBase64": "...",
  "mimeType": "image/jpeg",
  "today": "2026-09-04",
  "locale": "ja-JP"
}
```

会話リクエスト:

```json
{
  "messages": [
    {"role": "user", "text": "冷蔵庫にある青いパックの牛乳です"},
    {"role": "assistant", "text": "印字された期限はいつですか？"},
    {"role": "user", "text": "2026年9月10日です"}
  ],
  "today": "2026-09-04",
  "locale": "ja-JP"
}
```

商品が特定できた場合のレスポンス:

```json
{
  "reply": "牛乳、賞味期限2026年9月10日として登録できます。",
  "ready": true,
  "name": "牛乳",
  "expiryDate": "2026-09-10",
  "category": "飲み物",
  "confidence": 0.96
}
```

本番公開時は、利用回数制限・アプリ認証・監視をWorkerへ追加してください。
