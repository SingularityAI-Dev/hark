//! The polish step: an OpenAI-compatible chat call to the server baked in at build time,
//! then the plausibility guard. Any failure returns the rule-cleaned text.

use crate::cleaner;
use std::time::Duration;

const PROMPT: &str = include_str!("../prompt.txt");
const URL: Option<&str> = option_env!("HARK_POLISH_URL");
const KEY: Option<&str> = option_env!("HARK_POLISH_KEY");
const MODEL: Option<&str> = option_env!("HARK_POLISH_MODEL");

/// Below this many words the rule-based pass is used on its own.
const MODEL_THRESHOLD: usize = 3;

pub fn refine(raw: &str, use_model: bool) -> String {
    let cleaned = cleaner::clean(raw);
    let Some(base) = URL.filter(|u| !u.is_empty()) else { return cleaned };
    if !use_model || cleaner::word_count(&cleaned) < MODEL_THRESHOLD {
        return cleaned;
    }
    match complete(base, &cleaned) {
        Ok(output) => {
            let refined = strip(&output);
            if cleaner::is_plausible_refinement(&cleaned, &refined) {
                refined
            } else {
                cleaned
            }
        }
        Err(_) => cleaned,
    }
}

fn complete(base: &str, cleaned: &str) -> Result<String, Box<dyn std::error::Error>> {
    let agent = ureq::AgentBuilder::new().timeout(Duration::from_secs(10)).build();
    let mut request = agent.post(&format!("{}/chat/completions", base.trim_end_matches('/')));
    if let Some(key) = KEY.filter(|k| !k.is_empty()) {
        request = request.set("Authorization", &format!("Bearer {key}"));
    }
    let body = serde_json::json!({
        "model": MODEL.filter(|m| !m.is_empty()).unwrap_or("auto"),
        "temperature": 0,
        "messages": [
            { "role": "system", "content": PROMPT },
            { "role": "user", "content": format!("<transcript>\n{cleaned}\n</transcript>") },
        ],
    });
    let reply: serde_json::Value = request.send_json(body)?.into_json()?;
    reply["choices"][0]["message"]["content"]
        .as_str()
        .map(str::to_string)
        .ok_or_else(|| "no message in reply".into())
}

/// Drops transcript tags and wrapping quotes the model sometimes adds.
fn strip(output: &str) -> String {
    let mut text = output.trim().to_string();
    for tag in ["<transcript>", "</transcript>"] {
        text = text.replace(tag, "");
    }
    let text = text.trim();
    let text = text
        .strip_prefix('"')
        .and_then(|t| t.strip_suffix('"'))
        .unwrap_or(text);
    text.trim().to_string()
}
