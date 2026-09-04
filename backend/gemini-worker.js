const allowedCategories = [
  '乳製品',
  '飲み物',
  '冷蔵品',
  '肉・魚',
  '野菜・果物',
  'お惣菜',
  'その他',
];

const foodSchema = {
  type: 'OBJECT',
  properties: {
    name: { type: 'STRING' },
    expiryDate: {
      type: 'STRING',
      description: 'YYYY-MM-DD。分からない場合は空文字',
    },
    category: { type: 'STRING', enum: allowedCategories },
    confidence: { type: 'NUMBER', minimum: 0, maximum: 1 },
  },
  required: ['name', 'expiryDate', 'category', 'confidence'],
};

const chatSchema = {
  type: 'OBJECT',
  properties: {
    reply: { type: 'STRING', description: 'ユーザーへ返す短い日本語メッセージ' },
    ready: {
      type: 'BOOLEAN',
      description: '商品名と賞味期限の両方が確定した場合のみtrue',
    },
    name: { type: 'STRING', description: '不明な場合は空文字' },
    expiryDate: {
      type: 'STRING',
      description: 'YYYY-MM-DD。不明な場合は空文字',
    },
    category: { type: 'STRING', enum: allowedCategories },
    confidence: { type: 'NUMBER', minimum: 0, maximum: 1 },
  },
  required: ['reply', 'ready', 'name', 'expiryDate', 'category', 'confidence'],
};

export default {
  async fetch(request, env) {
    const corsHeaders = {
      'Access-Control-Allow-Origin': env.APP_ORIGIN || '*',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    const url = new URL(request.url);
    if (request.method !== 'POST') {
      return json({ error: 'Not found' }, 404, corsHeaders);
    }
    if (!env.GEMINI_API_KEY) {
      return json({ error: 'GEMINI_API_KEY is not configured' }, 500, corsHeaders);
    }

    try {
      const body = await request.json();
      if (url.pathname === '/analyze-expiry') {
        return await analyzeImage(body, env, corsHeaders);
      }
      if (url.pathname === '/identify-product') {
        return await identifyProduct(body, env, corsHeaders);
      }
      return json({ error: 'Not found' }, 404, corsHeaders);
    } catch (error) {
      return json({ error: error.message || 'Unexpected error' }, 500, corsHeaders);
    }
  },
};

async function analyzeImage(body, env, corsHeaders) {
  const imageBase64 = body.imageBase64;
  const mimeType = body.mimeType || 'image/jpeg';
  const today = body.today || new Date().toISOString().slice(0, 10);
  if (typeof imageBase64 !== 'string' || imageBase64.length === 0) {
    return json({ error: 'imageBase64 is required' }, 400, corsHeaders);
  }
  if (imageBase64.length > 14_000_000) {
    return json({ error: 'Image is too large' }, 413, corsHeaders);
  }

  const prompt =
    `今日は${today}です。食品パッケージの写真から商品名と賞味期限を読み取ってください。` +
    '消費期限しかない場合はその日付を使ってください。年が省略されている場合は、今日以降で最も近い妥当な日付として解釈してください。' +
    '読めない値は推測せず、賞味期限は空文字、商品名は空文字にしてください。';
  const result = await callGemini({
    env,
    contents: [
      {
        role: 'user',
        parts: [
          { text: prompt },
          { inlineData: { mimeType, data: imageBase64 } },
        ],
      },
    ],
    schema: foodSchema,
  });
  return json(result, 200, corsHeaders);
}

async function identifyProduct(body, env, corsHeaders) {
  const today = body.today || new Date().toISOString().slice(0, 10);
  const messages = Array.isArray(body.messages) ? body.messages.slice(-16) : [];
  const contents = normalizeMessages(messages);
  if (contents.length === 0) {
    return json({ error: 'messages are required' }, 400, corsHeaders);
  }

  const systemInstruction =
    `あなたは賞味期限管理アプリの商品登録エージェントです。今日は${today}です。` +
    '会話から食品の商品名、カテゴリー、パッケージに書かれた賞味期限または消費期限を特定してください。' +
    '情報が足りない場合は、一度に一つだけ、答えやすい短い質問を日本語で返してください。' +
    '期限を一般的な保存日数から推測してはいけません。印字された日付をユーザーに確認してください。' +
    '商品名と期限がそろった場合だけreadyをtrueにし、replyで確認を促してください。' +
    '日付はYYYY-MM-DD、不明な文字列は空文字にしてください。';
  const result = await callGemini({
    env,
    contents,
    schema: chatSchema,
    systemInstruction,
  });
  return json(result, 200, corsHeaders);
}

function normalizeMessages(messages) {
  const contents = [];
  for (const message of messages) {
    const text = typeof message?.text === 'string' ? message.text.trim() : '';
    if (!text) continue;
    const role = message.role === 'assistant' ? 'model' : 'user';
    if (contents.length === 0 && role !== 'user') continue;
    const previous = contents.at(-1);
    if (previous?.role === role) {
      previous.parts[0].text += `\n${text}`;
    } else {
      contents.push({ role, parts: [{ text }] });
    }
  }
  return contents;
}

async function callGemini({ env, contents, schema, systemInstruction }) {
  const model = env.GEMINI_MODEL || 'gemini-2.5-flash-lite';
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
    {
      method: 'POST',
      headers: {
        'x-goog-api-key': env.GEMINI_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        ...(systemInstruction
          ? { systemInstruction: { parts: [{ text: systemInstruction }] } }
          : {}),
        contents,
        generationConfig: {
          temperature: 0.1,
          maxOutputTokens: 400,
          responseMimeType: 'application/json',
          responseSchema: schema,
        },
      }),
    },
  );

  const responseBody = await response.json();
  if (!response.ok) {
    throw new Error(responseBody.error?.message || 'Gemini request failed');
  }
  const outputText = responseBody.candidates?.[0]?.content?.parts
    ?.map((part) => part.text || '')
    .join('');
  if (!outputText) throw new Error('No structured result returned');
  return JSON.parse(outputText);
}

function json(body, status, corsHeaders) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  });
}
