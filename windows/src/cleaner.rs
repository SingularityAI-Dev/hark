//! Rule-based transcript cleanup and the guard on model output. A port of
//! `Sources/HarkCore/TextCleaner.swift`; keep the two in step.

use fancy_regex::{Captures, Regex};
use std::collections::HashSet;
use std::sync::LazyLock;

fn re(pattern: &str) -> Regex {
    Regex::new(&format!("(?i){pattern}")).expect("constant pattern")
}

static FILLERS: LazyLock<Regex> =
    LazyLock::new(|| re(r"(?<![\w'])(?:u+h+m*|u+m+|e+r+m*|h+m+|m+h+m+|a+h+)(?![\w'])[,.]?\s*"));
static REPEATED_PHRASES: LazyLock<Regex> = LazyLock::new(|| re(r"\b((?:[\w']+\s+){1,3}[\w']+)\s+\1\b"));
static YOU_KNOW_ASIDE: LazyLock<Regex> = LazyLock::new(|| re(r",\s*you know\s*,"));
static YOU_KNOW: LazyLock<Regex> = LazyLock::new(|| re(r"\byou know\b[,]?\s*"));
static STUTTERS: LazyLock<Regex> =
    LazyLock::new(|| re(r"\b(i|the|a|an|and|to|of|in|it|is|we|you|but|so|my|for|on)(?:\s+\1\b)+"));
static SPACE_BEFORE_PUNCTUATION: LazyLock<Regex> = LazyLock::new(|| re(r"\s+([,.!?;:])"));
static REPEATED_COMMAS: LazyLock<Regex> = LazyLock::new(|| re(r",(?:\s*,)+"));
static WHITESPACE_RUNS: LazyLock<Regex> = LazyLock::new(|| re(r"[ \t]+"));
static LEADING_JUNK: LazyLock<Regex> = LazyLock::new(|| re(r"^[\s,.;:]+"));
static SENTENCE_START: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(^|[.!?]\s+)([a-z])").unwrap());

const YOU_KNOW_KEPT_AFTER: [&str; 14] = [
    "do", "did", "don't", "didn't", "if", "as", "what", "how", "would", "will", "and", "that", "whether",
    "because",
];
const YOU_KNOW_KEPT_BEFORE: [&str; 24] = [
    "what", "how", "that", "if", "where", "when", "why", "who", "whether", "the", "a", "an", "him", "her",
    "them", "it", "about", "this", "those", "these", "me", "us", "everything", "nothing",
];
const CORRECTION_CUES: [&str; 8] = ["wait", "sorry", "no", "actually", "mean", "scratch", "rather", "correction"];

fn replace(expression: &Regex, text: &str, template: &str) -> String {
    expression.replace_all(text, template).into_owned()
}

pub fn clean(raw: &str) -> String {
    let mut text = replace(&FILLERS, raw, "");
    text = replace(&STUTTERS, &text, "$1");
    for _ in 0..3 {
        text = replace(&REPEATED_PHRASES, &text, "$1");
    }
    text = replace(&YOU_KNOW_ASIDE, &text, " ");
    text = remove_filler_you_know(&text);
    text = replace(&WHITESPACE_RUNS, &text, " ");
    text = replace(&SPACE_BEFORE_PUNCTUATION, &text, "$1");
    text = replace(&REPEATED_COMMAS, &text, ",");
    text = replace(&LEADING_JUNK, &text, "");
    text = capitalise_sentence_starts(&text);
    text.trim().to_string()
}

fn remove_filler_you_know(text: &str) -> String {
    let mut result = text.to_string();
    let spans: Vec<(usize, usize)> = YOU_KNOW
        .find_iter(&result)
        .filter_map(|m| m.ok())
        .map(|m| (m.start(), m.end()))
        .collect();
    for (start, end) in spans.into_iter().rev() {
        let before = result[..start].split_whitespace().last().map(|w| w.to_lowercase());
        let after = result[end..]
            .split_whitespace()
            .next()
            .map(|w| w.to_lowercase().trim_matches(|c: char| c.is_ascii_punctuation()).to_string());
        if let Some(b) = &before {
            if YOU_KNOW_KEPT_AFTER.contains(&b.as_str()) {
                continue;
            }
        }
        if let Some(a) = &after {
            if YOU_KNOW_KEPT_BEFORE.contains(&a.as_str()) {
                continue;
            }
        }
        if before.is_none() {
            continue; // "You know the..." opening a sentence is usually meant.
        }
        result.replace_range(start..end, "");
    }
    result
}

fn capitalise_sentence_starts(text: &str) -> String {
    SENTENCE_START
        .replace_all(text, |caps: &Captures| format!("{}{}", &caps[1], caps[2].to_uppercase()))
        .into_owned()
}

pub fn word_count(text: &str) -> usize {
    text.split_whitespace().count()
}

fn vocabulary(text: &str) -> Vec<String> {
    text.to_lowercase()
        .split(|c: char| !(c.is_alphanumeric() || c == '\''))
        .filter(|w| !w.is_empty())
        .map(str::to_string)
        .collect()
}

fn takes_something_back(text: &str) -> bool {
    vocabulary(text).iter().any(|w| CORRECTION_CUES.contains(&w.as_str()))
}

/// Guards against the model answering the dictation, summarising it away or padding it.
pub fn is_plausible_refinement(original: &str, refined: &str) -> bool {
    let before = word_count(original);
    let after = word_count(refined);
    if after == 0 {
        return false;
    }
    let shrink_limit = if takes_something_back(original) { 0.15 } else { 0.35 };
    if (after as f64) < (before as f64) * shrink_limit || after > before + 3.max(before / 4) {
        return false;
    }
    let spoken: HashSet<String> = vocabulary(original).into_iter().collect();
    let written = vocabulary(refined);
    if written.is_empty() {
        return false;
    }
    let kept = written.iter().filter(|w| spoken.contains(*w)).count();
    (kept as f64) / (written.len() as f64) >= 0.65
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn removes_fillers_and_stutters() {
        assert_eq!(clean("um hey the the shop opens uh tomorrow"), "Hey the shop opens tomorrow");
    }

    #[test]
    fn keeps_you_know_when_it_is_part_of_the_sentence() {
        assert_eq!(clean("do you know where it is"), "Do you know where it is");
    }

    #[test]
    fn accepts_a_misheard_word_repair() {
        assert!(is_plausible_refinement(
            "send the minuets from the call to john",
            "Send the minutes from the call to John."
        ));
    }

    #[test]
    fn rejects_an_answer_to_a_dictated_question() {
        assert!(!is_plausible_refinement(
            "what time does the shop open tomorrow",
            "The shop opens at nine in the morning on weekdays and ten on weekends."
        ));
    }

    #[test]
    fn rejects_a_summary() {
        assert!(!is_plausible_refinement(
            "so I went to the shop and then I bought milk and eggs and bread and came home again",
            "Shopping trip."
        ));
    }
}
