module misc::secure;

import std::os::process;
import std::core::env;
import std::io;

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
    String[] cmds;

    $if core::env::WIN32:
        cmds = (String[]) {"cmd.exe", "/c", "clip"};
    $endif
    $if core::env::os_is_darwin():
        cmds = (String[]) {"pbcopy"};
    $endif
    $if core::env::LINUX:
        char[4096] buf;

        String found = process::execute_stdout_to_buffer(
            buf[:4096],
            (String[]) {"sh", "-lc", "command -v wl-copy"}
        ) ?? "";
        if (found.len > 0) {
            cmds = (String[]) {"wl-copy"};
        } else {
            found = process::execute_stdout_to_buffer(
                buf[:4096],
                (String[]) {"sh", "-lc", "command -v xclip"}
            ) ?? "";
            if (found.len > 0) {
                cmds = (String[]) {"xclip"};
            }
        }

        if (!cmds) {
            io::eprintf("Please install xclip or wl-copy or edit the source code to use wtv tf you're using.\n");
            return;
        }
    $endif

    process::SubProcess p = process::create(cmds)!!;
    p.write_to_stdin((char[])s)!!;
    (void)p.join()!!;
    p.destroy();
}

fn void schedule_clipboard_clear() {
    // clear after 10 seconds via a background shell/PowerShell job.
    String[] cmds;

    $if core::env::WIN32:
        cmds = (String[]) {
            "powershell",
            "-NoLogo",
            "-Command",
            "Start-Job { Start-Sleep 10; Set-Clipboard '' } | Out-Null"
        };
    $endif
    $if core::env::os_is_darwin():
        cmds = (String[]) {"sh", "-c", "sleep 10; printf '' | pbcopy &"};
    $endif
    $if core::env::LINUX:
        cmds = (String[]) {
            "sh",
            "-c",
            "sleep 10; printf '' | wl-copy >/dev/null 2>&1 || printf '' | xclip >/dev/null 2>&1 &"
        };
    $endif

    if (!cmds) {
        return;
    }

    process::SubProcess p = process::create(cmds)!!;
    (void)p.join()!!;
    p.destroy();
}

// copies to clipboard, deletes after 10 seconds, implementation depends on OS.
fn void output_pw(String s) {
    copy_to_clipboard(s);
    schedule_clipboard_clear();
}
