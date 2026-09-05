import assert from 'node:assert/strict';
import test from 'node:test';

import worker from './gemini-worker.js';

const request = () =>
  new Request('https://worker.test/identify-product', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages: [
        { role: 'user', text: 'りんごジュース、期限は2026-10-21です' },
      ],
      today: '2026-09-05',
      locale: 'ja-JP',
    }),
  });

test('high demand時は次のGeminiモデルへ切り替える', async () => {
  const originalFetch = globalThis.fetch;
  const urls = [];
  globalThis.fetch = async (url) => {
    urls.push(String(url));
    if (urls.length === 1) {
      return Response.json(
        { error: { message: 'This model is currently experiencing high demand.' } },
        { status: 503 },
      );
    }
    return Response.json({
      candidates: [
        {
          content: {
            parts: [
              {
                text: JSON.stringify({
                  reply: '確認できました。',
                  ready: true,
                  name: 'りんごジュース',
                  expiryDate: '2026-10-21',
                  category: '飲み物',
                  confidence: 0.95,
                }),
              },
            ],
          },
        },
      ],
    });
  };

  try {
    const response = await worker.fetch(request(), {
      GEMINI_API_KEY: 'test-key',
      GEMINI_MODEL: 'gemini-3.8-flash',
      GEMINI_FALLBACK_MODELS: 'gemini-3.5-flash,gemini-3.5-flash-lite',
    });
    const body = await response.json();

    assert.equal(response.status, 200);
    assert.equal(body.modelUsed, 'gemini-3.5-flash');
    assert.equal(urls.length, 2);
    assert.match(urls[0], /gemini-3\.8-flash/);
    assert.match(urls[1], /gemini-3\.5-flash/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('修正が必要な400エラーでは別モデルへ切り替えない', async () => {
  const originalFetch = globalThis.fetch;
  let requestCount = 0;
  globalThis.fetch = async () => {
    requestCount += 1;
    return Response.json(
      { error: { message: 'Invalid request payload' } },
      { status: 400 },
    );
  };

  try {
    const response = await worker.fetch(request(), {
      GEMINI_API_KEY: 'test-key',
      GEMINI_MODEL: 'gemini-3.8-flash',
      GEMINI_FALLBACK_MODELS: 'gemini-3.5-flash',
    });
    const body = await response.json();

    assert.equal(response.status, 500);
    assert.equal(body.error, 'Invalid request payload');
    assert.equal(requestCount, 1);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('全モデルが混雑中なら日本語の再試行メッセージを返す', async () => {
  const originalFetch = globalThis.fetch;
  let requestCount = 0;
  globalThis.fetch = async () => {
    requestCount += 1;
    return Response.json(
      { error: { message: 'This model is currently experiencing high demand.' } },
      { status: 503 },
    );
  };

  try {
    const response = await worker.fetch(request(), {
      GEMINI_API_KEY: 'test-key',
      GEMINI_MODEL: 'gemini-3.8-flash',
      GEMINI_FALLBACK_MODELS: 'gemini-3.5-flash,gemini-3.5-flash-lite',
    });
    const body = await response.json();

    assert.equal(response.status, 503);
    assert.equal(
      body.error,
      'AIが混み合っています。少し待ってからもう一度お試しください。',
    );
    assert.equal(requestCount, 3);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
