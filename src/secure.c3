module misc::secure;

import std::os::process;
import std::core::env;

fn void explicit_bzero(char *b, usz size) @noinline {
    for (usz i = 0; i < size; i++) {
        b[i] = 0;
    }
}

fn void wipe_string(String s) @noinline {
    if (!s) return;
    explicit_bzero(s.ptr, s.len);
}

fn void copy_to_clipboard(String s) {
    
    String cpg;

    $if core::env::WIN32:
        //TODO: implement for windows;
    $endif
    $if core::env::os_is_darwin():
        cpg = "pbcopy";
    $endif
    $if core::env::LINUX:
        cpg = "xclip"
    $endif

    process::SubProcess p = process::create((String[]) {"pbcopy"})!!;

    // Write exactly what you want copied (no extra newline unless you add one).
    p.write_to_stdin((char[])s)!!;

    // join() closes stdin first, so pbcopy sees EOF and exits.
    (void)p.join()!!;
    p.destroy();
}

// copies to clipboard, deletes after 15 seconds, implementation depends on OS.
fn void output_pw(String s) {
    $if core::env::WIN32:
        //TODO: implement for windows.
    $endif
    $if env::os_is_darwin():
        copy_to_clipboard(s);
    $endif
    $if core::env::LINUX:
        //TODO: implement for linux.
    $endif
}

