// Edge Function: ai-echo
// Deploy: supabase functions deploy ai-echo
// Secret:  supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//
// Gestisce due operazioni AI:
//   type: "caption" → genera didascalia poetica
//   type: "mood"    → suggerisce il mood dal testo

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

serve(async (req: Request) => {
  // Pre-flight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS });
  }

  try {
    const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
    if (!apiKey) {
      return json({ error: 'ANTHROPIC_API_KEY non configurata' }, 500);
    }

    const { type, text, mood, location } = await req.json();

    if (!text || typeof text !== 'string') {
      return json({ error: 'Campo "text" obbligatorio' }, 400);
    }

    const prompt =
      type === 'mood'
        ? buildMoodPrompt(text)
        : buildCaptionPrompt(text, mood ?? 'echo', location);

    const maxTokens = type === 'mood' ? 10 : 150;

    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: maxTokens,
        messages: [{ role: 'user', content: prompt }],
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      return json({ error: `Anthropic error: ${err}` }, 502);
    }

    const data = await response.json();
    const result = data?.content?.[0]?.text ?? '';

    if (type === 'mood') {
      const valid = new Set(['echo', 'love', 'secret', 'dream', 'lost']);
      const suggested = result.trim().toLowerCase();
      return json({ mood: valid.has(suggested) ? suggested : null });
    }

    return json({ caption: result.trim() });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function buildCaptionPrompt(
  text: string,
  mood: string,
  location?: string,
): string {
  return (
    `Sei un autore poetico per un'app di ricordi chiamata Echo. ` +
    `Un utente ha lasciato questo ricordo:\n` +
    `Testo: "${text}"\n` +
    `Mood: ${mood}\n` +
    (location ? `Luogo: ${location}\n` : '') +
    `Scrivi una didascalia poetica di 1-2 frasi (max 100 caratteri) ` +
    `che cattura l'essenza emotiva del ricordo con il mood "${mood}". ` +
    `Rispondi SOLO con la didascalia, senza virgolette né spiegazioni.`
  );
}

function buildMoodPrompt(text: string): string {
  return (
    `Analizza questo testo e rispondi con UNA SOLA parola tra: ` +
    `echo, love, secret, dream, lost.\n` +
    `Testo: "${text}"\n` +
    `Rispondi solo con una di queste parole, nient'altro.`
  );
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}
