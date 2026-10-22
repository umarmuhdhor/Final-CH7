// Generic chat-completions client (OpenAI-compatible request shape, which most providers offer).
// Model, base URL and key come from config. It returns the model's text or null; it never throws and never
// forwards anything the provider said about an error (SECURITY A10).

/**
 * @param {{ config: object, fetch: typeof fetch }} deps
 * @returns {(messages: object[], signal: AbortSignal) => Promise<string | null>}
 */
export function createProvider({ config, fetch }) {
    return async (messages, signal) => {
        try {
            const res = await fetch(`${config.baseUrl}/chat/completions`, {
                method: "POST",
                headers: { "content-type": "application/json", authorization: `Bearer ${config.apiKey}` },
                body: JSON.stringify({
                    model: config.model,
                    messages,
                    temperature: 0, // A13: repeatable answers
                    max_tokens: 200,
                    response_format: { type: "json_object" },
                }),
                signal,
                redirect: "error", // the key must not follow a redirect to another host
            });
            if (!res.ok) return null;
            const body = await res.json();
            const content = body?.choices?.[0]?.message?.content;
            return typeof content === "string" ? content : null;
        } catch {
            return null;
        }
    };
}
