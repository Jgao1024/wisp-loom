use serde_json::{Value, json};
use std::{thread, time::Duration};
use wisp_backend::{Backend, Ctx, Error};

/// Streams the text back word by word, then returns it whole.
fn echo(params: Value, ctx: &Ctx) -> Result<Value, Error> {
    let text = params["text"].as_str().unwrap_or_default();
    for word in text.split_inclusive(' ') {
        if ctx.cancelled() {
            return Err(Error::cancelled());
        }
        ctx.emit(json!({"type": "text_delta", "delta": word}));
        thread::sleep(Duration::from_millis(40));
    }
    Ok(json!({ "text": text }))
}

fn main() {
    Backend::new().method("echo", echo).run();
}
