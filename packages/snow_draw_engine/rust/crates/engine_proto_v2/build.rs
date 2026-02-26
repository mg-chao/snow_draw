fn main() {
    let protoc = protoc_bin_vendored::protoc_bin_path().expect("vendored protoc path");
    // SAFETY: build script process-local mutation is expected by prost-build.
    unsafe {
        std::env::set_var("PROTOC", protoc);
    }

    let proto_root = std::path::PathBuf::from("../../proto");
    let proto_file = proto_root.join("engine_v2.proto");

    println!("cargo:rerun-if-changed={}", proto_file.display());

    prost_build::Config::new()
        .compile_protos(&[proto_file], &[proto_root])
        .expect("compile engine_v2.proto");
}
