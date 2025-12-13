module misc::secure;

fn void explicit_bzero(char *b, usz size) @noinline {
    for (usz i = 0; i < size; i++) {
        b[i] = 0;
    }
}

fn void wipe_string(String s) @noinline {
    if (!s) return;
    explicit_bzero(s.ptr, s.len);
}

