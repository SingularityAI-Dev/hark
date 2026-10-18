// Bakes the polish server into the binary. The values come from the environment at build
// time (see build.sh) and are never written to disk or printed.
fn main() {
    for name in ["HARK_POLISH_URL", "HARK_POLISH_KEY", "HARK_POLISH_MODEL"] {
        println!("cargo:rerun-if-env-changed={name}");
        if let Ok(value) = std::env::var(name) {
            println!("cargo:rustc-env={name}={value}");
        }
    }
}
