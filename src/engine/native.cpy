# Vortex engine - the C layer.
#
# Cpyte's text support stops at `+` on two strings and `len()`: there is no
# slicing, no char concatenation, and a character literal casts to a string
# pointer rather than a byte. All text handling therefore goes through this
# thin C layer, which is also the only place the engine touches raw bytes,
# because indexing a `char*` from Cpyte is not something the codecs should
# depend on - `vt_at` and `vt_put` cover it.
#
# This is the engine's only `ccode:` block; every other module calls these
# helpers. Rules that apply to it:
#   * nothing may sit between the body and the first Cpyte statement, because
#     the raw block only ends at a statement;
#   * <stdlib.h> and <string.h> must be included at the top, otherwise calloc
#     and size_t are undeclared; <stdio.h> breaks the mingw header chain;
#   * no `?:` ternaries - they crash the compiler;
#   * no `strdup` - it is not declared in the C dialect Cpyte emits.

ccode:
    #include <stdlib.h>
    #include <string.h>

    /* --- text ---------------------------------------------------------- */
    /* Cpyte hands a `str` to a `const char*` parameter directly, and a
     * NUL-terminated `char*` prints as text. */
    int vt_strlen(const char* s) { return (int)strlen(s); }
    int vt_at(const char* s, int i) { return (int)(unsigned char)s[i]; }
    int vt_eq(const char* a, const char* b) {
        if (strcmp(a, b) == 0) return 1;
        return 0;
    }
    int vt_cmp(const char* a, const char* b) { return strcmp(a, b); }
    int vt_starts(const char* s, const char* prefix) {
        size_t n = strlen(prefix);
        if (strncmp(s, prefix, n) == 0) return 1;
        return 0;
    }
    int vt_find_str(const char* hay, const char* needle) {
        if (needle[0] == 0) return 0;
        const char* p = strstr(hay, needle);
        if (p == 0) return -1;
        return (int)(p - hay);
    }
    int vt_find_code(const char* s, int from, int code) {
        const char* p = strchr(s + from, code);
        if (p == 0) return -1;
        return (int)(p - s);
    }
    int vt_count(const char* s, int code) {
        int n = 0;
        const char* p;
        for (p = s; *p; p++) { if (*p == code) n++; }
        return n;
    }
    char* vt_dup(const char* s) {
        int n = (int)strlen(s);
        char* out = (char*)calloc((size_t)n + 1, 1);
        if (out != 0) memcpy(out, s, (size_t)n);
        return out;
    }
    void vt_put(char* s, int i, int code) { s[i] = (char)code; }
    char* vt_slice(const char* s, int begin, int end) {
        int n = end - begin;
        if (n < 0) n = 0;
        char* out = (char*)calloc((size_t)n + 1, 1);
        if (out == 0) return 0;
        memcpy(out, s + begin, (size_t)n);
        return out;
    }
    char* vt_calloc_char(int count) { return (char*)calloc((size_t)count + 1, 1); }
    char* vt_trim(const char* s) {
        const char* a = s;
        const char* b;
        while (*a == ' ' || *a == '\t' || *a == '\r' || *a == '\n') a++;
        b = a + strlen(a);
        while (b > a) {
            char c = b[-1];
            if (c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
            b--;
        }
        return vt_slice(s, (int)(a - s), (int)(b - s));
    }
    /* Field `index` of `line` split on `code`; "" when the index is absent. */
    char* vt_field(const char* line, int code, int index) {
        int cur = 0;
        const char* start = line;
        const char* p = line;
        while (1) {
            if (*p == 0 || *p == code) {
                if (cur == index) {
                    return vt_slice(line, (int)(start - line), (int)(p - line));
                }
                if (*p == 0) {
                    return vt_calloc_char(0);
                }
                cur++;
                start = p + 1;
            }
            p++;
        }
    }

    /* --- numbers -------------------------------------------------------- */
    /* `strict` comes back 0 when the text is not a complete number. */
    long long vt_parse_int(const char* s, int* strict) {
        char* end = 0;
        long long v = strtoll(s, &end, 10);
        while (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n') end++;
        if (strict == 0) return v;
        if (*end == 0 && end != s) *strict = 1;
        else *strict = 0;
        return v;
    }
    double vt_parse_double(const char* s, int* strict) {
        char* end = 0;
        double v = strtod(s, &end);
        while (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n') end++;
        if (strict == 0) return v;
        if (*end == 0 && end != s) *strict = 1;
        else *strict = 0;
        return v;
    }
    unsigned long long vt_fnv1a(const char* s) {
        unsigned long long hash = 14695981039346656037ULL;
        while (*s) {
            hash ^= (unsigned long long)(unsigned char)*s++;
            hash *= 1099511628211ULL;
        }
        return hash;
    }

    /* --- buffers -------------------------------------------------------- */
    void vt_free(void* p) { free(p); }
    void vt_copy_bytes(char* dst, int dst_off, const char* src, int src_off, int n) {
        if (n > 0) memcpy(dst + dst_off, src + src_off, (size_t)n);
    }
    char* vt_realloc_char(char* p, int bytes) {
        /* realloc(0) is a plain free, and a zero length allocates nothing, so
         * the caller always asks for at least one byte. */
        if (bytes < 1) bytes = 1;
        return (char*)realloc(p, (size_t)bytes);
    }

    /* --- typed arrays --------------------------------------------------- */
    /* Cpyte never indexes these directly: the accessors keep every raw
     * subscript inside C, where the element widths are known. */
    int* vt_calloc_int(int count) {
        if (count < 1) count = 1;
        return (int*)calloc((size_t)count, sizeof(int));
    }
    int vt_iget(const int* arr, int i) { return arr[i]; }
    void vt_iset(int* arr, int i, int v) { arr[i] = v; }
    unsigned long long* vt_calloc_u64(int count) {
        if (count < 1) count = 1;
        return (unsigned long long*)calloc((size_t)count, sizeof(unsigned long long));
    }
    unsigned long long vt_uget(const unsigned long long* arr, int i) { return arr[i]; }
    void vt_uset(unsigned long long* arr, int i, unsigned long long v) { arr[i] = v; }
    char* vt_calloc_ptrs(int count) {
        if (count < 1) count = 1;
        return (char*)calloc((size_t)count, sizeof(void*));
    }
    void* vt_ptr_get(const char* arr, int i) {
        void* slot;
        memcpy(&slot, arr + ((size_t)i * sizeof(void*)), sizeof(void*));
        return slot;
    }
    void vt_ptr_set(char* arr, int i, void* p) {
        memcpy(arr + ((size_t)i * sizeof(void*)), &p, sizeof(void*));
    }
    int vt_ptr_size(void) { return (int)sizeof(void*); }

    /* --- variable length integers --------------------------------------- */
    /* The 7-bit group loops live here rather than in Cpyte: Cpyte compares a
     * uint64 relationally as a *signed* value, so `v < 128` is true for every
     * negative number and the encoder stops after one group. */
    int vt_write_varint_at(char* buf, int off, int value) {
        unsigned int v = (unsigned int)value;
        int i = 0;
        while (v >= 0x80U && i < 4) {
            buf[off + i] = (char)((v & 0x7FU) | 0x80U);
            v = v >> 7;
            i++;
        }
        buf[off + i] = (char)v;
        return i + 1;
    }
    int vt_write_varlong_at(char* buf, int off, long long value) {
        unsigned long long v = (unsigned long long)value;
        int i = 0;
        while (v >= 0x80ULL && i < 9) {
            buf[off + i] = (char)((v & 0x7FULL) | 0x80ULL);
            v = v >> 7;
            i++;
        }
        buf[off + i] = (char)v;
        return i + 1;
    }
    /* Reads from [off, end). Returns the offset after the last group, or -1
     * when the run is truncated or longer than the encoding allows. VarInt is
     * 32 bit, so its result is sign extended from the low four bytes; `wide`
     * selects the 64 bit VarLong rule instead. */
    int vt_read_varint(const char* buf, int off, int end, long long* out, int wide) {
        unsigned long long acc = 0;
        int limit = 5;
        int i = off;
        if (wide != 0) limit = 10;
        while (i < end && i - off < limit) {
            unsigned long long byte = (unsigned long long)((unsigned char)buf[i]);
            acc = acc | ((byte & 0x7FULL) << ((unsigned long long)(i - off) * 7ULL));
            i++;
            if ((byte & 0x80ULL) == 0) {
                if (wide != 0) *out = (long long)acc;
                else *out = (long long)(int)(unsigned int)(acc & 0xFFFFFFFFULL);
                return i;
            }
        }
        return -1;
    }
    /* Keeps the low 32 bits of `raw`, sign extended. */
    int vt_sign_extend_32(unsigned long long raw) {
        return (int)(unsigned int)(raw & 0xFFFFFFFFULL);
    }
    /* Block position: x 26 bits, z 26 bits, y 12 bits, each signed. */
    void vt_unpack_block_pos(long long packed, int* out) {
        out[0] = (int)(packed >> 38);
        out[1] = (int)((packed << 26) >> 52);
        out[2] = (int)((packed << 38) >> 38);
    }
    /* Section position: x 22 bits, z 22 bits, y 20 bits, each signed. */
    void vt_unpack_section_pos(long long packed, int* out) {
        out[0] = (int)(packed >> 42);
        out[1] = (int)((packed << 44) >> 44);
        out[2] = (int)((packed << 22) >> 42);
    }

    /* --- packed long arrays --------------------------------------------- */
    /* Section palettes use the community "padded" packing: a 64 bit word holds
     * floor(64 / bits) whole entries and the leftover high bits of each word
     * go unused, so an entry never straddles two words. The width arithmetic
     * is unsigned throughout, because Cpyte compares uint64 as signed. */
    int vt_values_per_long(int bits) {
        if (bits <= 0 || bits > 64) return 0;
        return (int)(64 / bits);
    }
    int vt_packed_words(int count, int bits) {
        int per = vt_values_per_long(bits);
        if (per <= 0 || count <= 0) return 0;
        return (count + per - 1) / per;
    }
    unsigned long long vt_packed_mask(int bits) {
        if (bits <= 0) return 0;
        if (bits >= 64) return 0xFFFFFFFFFFFFFFFFULL;
        return (1ULL << bits) - 1ULL;
    }
    unsigned long long vt_packed_get(const unsigned long long* words, int index, int bits) {
        int per = vt_values_per_long(bits);
        if (per <= 0 || words == 0) return 0;
        int word = index / per;
        int shift = (index % per) * bits;
        return (words[word] >> shift) & vt_packed_mask(bits);
    }
    void vt_packed_set(unsigned long long* words, int index, int bits, unsigned long long value) {
        int per = vt_values_per_long(bits);
        if (per <= 0 || words == 0) return;
        int word = index / per;
        int shift = (index % per) * bits;
        unsigned long long mask = vt_packed_mask(bits);
        words[word] = (words[word] & ~(mask << shift)) | ((value & mask) << shift);
    }

    /* --- straddling bit packing ----------------------------------------- */
    /* Heightmaps fill the long array end to end in little endian bit order, so
     * an entry may run across a word boundary - the opposite of the palette
     * packing above. */
    int vt_bits_words(int count, int bits) {
        if (count <= 0 || bits <= 0) return 0;
        long long total = (long long)count * (long long)bits;
        return (int)((total + 63LL) / 64LL);
    }
    unsigned long long vt_bits_get(const unsigned long long* words, int index, int bits) {
        if (bits <= 0 || bits > 64 || words == 0) return 0;
        long long bit = (long long)index * (long long)bits;
        int word = (int)(bit >> 6);
        int shift = (int)(bit & 63LL);
        unsigned long long mask = vt_packed_mask(bits);
        unsigned long long low = words[word] >> shift;
        if (shift == 0 || shift + bits <= 64) return low & mask;
        return (low | (words[word + 1] << (64 - shift))) & mask;
    }
    void vt_bits_set(unsigned long long* words, int index, int bits, unsigned long long value) {
        if (bits <= 0 || bits > 64 || words == 0) return;
        long long bit = (long long)index * (long long)bits;
        int word = (int)(bit >> 6);
        int shift = (int)(bit & 63LL);
        unsigned long long mask = vt_packed_mask(bits);
        value = value & mask;
        words[word] = (words[word] & ~(mask << shift)) | (value << shift);
        if (shift != 0 && shift + bits > 64) {
            int left = bits - (64 - shift);
            unsigned long long rmask = vt_packed_mask(left);
            unsigned long long rest = (value >> (64 - shift)) & rmask;
            words[word + 1] = (words[word + 1] & ~rmask) | rest;
        }
    }

    /* --- bit casts ------------------------------------------------------ */
    /* NBT stores floats and doubles as their IEEE bit patterns, so the codec
     * needs to move them to and from integers without Cpyte getting a say in
     * the conversion.
     *
     * Both helpers cross the boundary as a C `double`: Cpyte's `float` is
     * double width, and a `float` parameter here receives garbage. TAG_Float
     * therefore narrows to 32 bit IEEE bits on the way out and widens back on
     * the way in. */
    double vt_bits_to_float(int bits) {
        float f = (float)0;
        memcpy(&f, &bits, sizeof(f));
        return (double)f;
    }
    int vt_float_to_bits(double f) {
        float narrow = (float)f;
        int bits = 0;
        memcpy(&bits, &narrow, sizeof(bits));
        return bits;
    }
    double vt_bits_to_double(unsigned long long bits) {
        double d = (double)0;
        memcpy(&d, &bits, sizeof(d));
        return d;
    }
    unsigned long long vt_double_to_bits(double d) {
        unsigned long long bits = (unsigned long long)0;
        memcpy(&bits, &d, sizeof(bits));
        return bits;
    }

    /* --- first-launch block database setup ------------------------------ */
    /* tools/setup_blockdb.py discovers a local installation, runs the vanilla
     * data generator and writes generated/blockdb.bin. The client calls this
     * only when the database is missing, so normal launches do no work. The
     * command is fixed (no user input), and the tool falls back gracefully. */
    int vt_run_blockdb_setup(void) {
        int rc = 0;
    #ifdef _WIN32
        rc = system("py -3 tools/setup_blockdb.py --auto");
        if (rc == 0) return 0;
        rc = system("python tools/setup_blockdb.py --auto");
    #else
        rc = system("python3 tools/setup_blockdb.py --auto");
        if (rc == 0) return 0;
        rc = system("python tools/setup_blockdb.py --auto");
    #endif
        if (rc == 0) return 0;
        return 1;
    }
