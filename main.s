// main.s - GitHub Language SVG Generator (AArch64 Linux)
// Targets: Linux AArch64
// To compile: as -o main.o main.s && ld -o main main.o

// --- Constants ---
.equiv MAX_LANGUAGES,         100
.equiv LANG_STRUCT_SIZE,      24
.equiv BUFFER_SIZE,           8192
.equiv OUT_BUF_SIZE,          65536

// SVG Layout Constants
.equiv LEGEND_ROWS_PER_COL,   25
.equiv LEGEND_COL_WIDTH,      180
.equiv LEGEND_ROW_HEIGHT,     20
.equiv LEGEND_START_X,        30
.equiv LEGEND_START_Y,        100
.equiv MIN_SVG_WIDTH,         760
.equiv SVG_MARGIN_X,          40
.equiv SVG_BASE_HEIGHT,      130

// Animation Constants (scaled by 100)
.equiv BAR_ANIM_START_DELAY,   50   // 0.50s
.equiv BAR_ANIM_STEP_DELAY,    5    // 0.05s
.equiv LEGEND_ANIM_START_DELAY, 100 // 1.00s
.equiv LEGEND_ANIM_STEP_DELAY,  2   // 0.02s

// System Calls
.equiv SYS_READ,      63
.equiv SYS_WRITE,     64
.equiv SYS_OPENAT,    56
.equiv SYS_CLOSE,     57
.equiv SYS_EXIT,      93
.equiv AT_FDCWD,      -100

.section .data
    file_in:      .asciz "languages.dat"
    file_out:     .asciz "languages.svg"
    
    // SVG Templates
    svg_hdr_1:    .ascii "<svg width=\"\0"
    svg_hdr_2:    .ascii "\" height=\"\0"
    svg_hdr_3:    .ascii "\" viewBox=\"0 0 \0"
    svg_hdr_4:    .ascii " \0"
    svg_hdr_5:    .ascii "\" xmlns=\"http://www.w3.org/2000/svg\">\n\0"

    svg_hdr_body:
             .ascii "  <rect width=\"100%\" height=\"100%\" fill=\"#0d1117\" rx=\"10\"/>\n"
             .ascii "  <text x=\"20\" y=\"30\" fill=\"#f0f6fc\" font-family=\"sans-serif\" font-size=\"14\" font-weight=\"bold\">Language Distribution</text>\n"
             .ascii "  <rect x=\"20\" y=\"50\" width=\"720\" height=\"12\" rx=\"6\" fill=\"#21262d\"/>\n"
             .ascii "  <style>\n"
             .ascii "    @keyframes grow { from { width: 0; } }\n"
             .ascii "    .bar-rect { animation: grow 1s ease-out both; }\n"
             .ascii "    @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }\n"
             .ascii "    .legend-item { animation: fadeIn 0.8s ease-out both; }\n"
             .ascii "  </style>\n"
             .ascii "  <defs>\n"
             .ascii "    <clipPath id=\"bar-clip\">\n"
             .ascii "      <rect x=\"20\" y=\"50\" width=\"720\" height=\"12\" rx=\"6\"/>\n"
             .ascii "    </clipPath>\n"
             .ascii "  </defs>\n"
             .ascii "  <g clip-path=\"url(#bar-clip)\">\n"
             .ascii "    <svg x=\"20\" y=\"50\" width=\"720\" height=\"12\">\n\0"
    
    bar_ftr:      .ascii "    </svg>\n"
                  .ascii "  </g>\n\0"
    svg_ftr:      .ascii "</svg>\n\0"
    
    rect_part1:   .ascii "      <rect x=\"\0"
    rect_part2:   .ascii "%\" width=\"\0"
    rect_part3:   .ascii "%\" height=\"100%\" fill=\"\0"
    rect_part4:   .ascii "\" class=\"bar-rect\" style=\"animation-delay: \0"
    rect_part5:   .ascii "s\" />\n\0"

    legend_part1:  .ascii "  <circle class=\"legend-item\" style=\"animation-delay: \0"
    legend_part1a: .ascii "s\" cx=\"\0"
    legend_part2:  .ascii "\" cy=\"\0"
    legend_part3:  .ascii "\" r=\"5\" fill=\"\0"
    legend_part4:  .ascii "\" />\n\0"
    legend_part5:  .ascii "  <text class=\"legend-item\" style=\"animation-delay: \0"
    legend_part5a: .ascii "s\" x=\"\0"
    legend_part6:  .ascii "\" y=\"\0"
    legend_part7:  .ascii "\" fill=\"#c9d1d9\" font-family=\"sans-serif\" font-size=\"12\">\0"
    legend_part8:  .ascii " \0"
    legend_part_pct: .ascii "%</text>\n\0"

.section .bss
    .align 4
    buffer:       .skip BUFFER_SIZE
    out_buf:      .skip OUT_BUF_SIZE
    total_val:     .skip 8
    // {char* name, long value, char* color}
    parsed_data:   .skip MAX_LANGUAGES * LANG_STRUCT_SIZE

.section .text
.global _start

// --- Main Program Entry ---
_start:
    // x19: fd, x20: bytes_read/lang_count, x21: buf_ptr, x22: data_ptr, x23: total_sum
    // x24: svg_width, x25: out_ptr, x26: svg_height
    
    bl load_languages_data
    cbz x0, exit_error  // bytes_read == 0
    mov x20, x0         // x20 = bytes_read

    bl parse_languages_data
    mov x20, x0         // x20 = lang_count
    mov x23, x1         // x23 = total_sum
    cbz x20, exit_error

    bl calculate_svg_metrics
    mov x24, x0         // x24 = svg_width
    mov x26, x1         // x26 = svg_height

    ldr x25, =out_buf   // x25 = current write pointer
    
    // Generate SVG parts
    mov x0, x24
    mov x1, x26
    bl write_svg_header
    
    mov x0, x20
    mov x1, x23
    bl write_svg_bars
    
    mov x0, x20
    mov x1, x23
    bl write_svg_legend
    
    bl write_svg_footer

    bl save_svg_file

    // Exit success
    mov x8, SYS_EXIT
    mov x0, #0
    svc #0

exit_error:
    mov x8, SYS_EXIT
    mov x0, #1
    svc #0

// --- Subroutines ---

// load_languages_data() -> x0: bytes_read
load_languages_data:
    stp x29, x30, [sp, #-16]!
    mov x8, SYS_OPENAT
    mov x0, AT_FDCWD
    ldr x1, =file_in
    mov x2, #0          // O_RDONLY
    svc #0
    cmp x0, #0
    blt load_failed
    mov x19, x0

    mov x8, SYS_READ
    mov x0, x19
    ldr x1, =buffer
    mov x2, BUFFER_SIZE
    svc #0
    mov x20, x0

    mov x8, SYS_CLOSE
    mov x0, x19
    svc #0
    
    mov x0, x20
    ldp x29, x30, [sp], #16
    ret
load_failed:
    mov x0, #0
    ldp x29, x30, [sp], #16
    ret

// parse_languages_data() -> x0: lang_count, x1: total_sum
parse_languages_data:
    stp x29, x30, [sp, #-48]!
    stp x21, x22, [sp, #16]
    stp x23, x24, [sp, #32]
    
    ldr x21, =buffer
    ldr x22, =parsed_data
    mov x23, #0         // lang_count
    mov x24, #0         // total_sum

parse_loop:
    cmp x20, #0
    ble parse_done
    cmp x23, MAX_LANGUAGES
    bge parse_done

    // 1. Store name pointer
    str x21, [x22, #0]
find_tab1:
    ldrb w0, [x21], #1
    sub x20, x20, #1
    cmp w0, #'\t'
    beq found_tab1
    cmp x20, #0
    ble parse_done
    b find_tab1
found_tab1:
    mov w1, #0
    strb w1, [x21, #-1] // Null terminate

    // 2. Parse value (atoi)
    mov x0, #0
atoi_loop:
    ldrb w1, [x21], #1
    sub x20, x20, #1
    cmp w1, #'\t'
    beq atoi_done
    cmp x20, #0
    ble atoi_done
    sub w1, w1, #'0'
    mov x2, #10
    mul x0, x0, x2
    add x0, x0, x1
    b atoi_loop
atoi_done:
    str x0, [x22, #8]
    add x24, x24, x0

    // 3. Store color pointer
    str x21, [x22, #16]
find_nl:
    ldrb w0, [x21], #1
    sub x20, x20, #1
    cmp w0, #'\n'
    beq found_nl
    cmp w0, #'\r'
    beq found_nl
    cmp x20, #0
    ble found_nl
    b find_nl
found_nl:
    mov w1, #0
    strb w1, [x21, #-1]

skip_extra:
    cmp x20, #0
    ble next_entry
    ldrb w0, [x21]
    cmp w0, #'\n'
    beq skip_char
    cmp w0, #'\r'
    beq skip_char
    b next_entry
skip_char:
    add x21, x21, #1
    sub x20, x20, #1
    b skip_extra

next_entry:
    add x22, x22, LANG_STRUCT_SIZE
    add x23, x23, #1
    b parse_loop

parse_done:
    mov x0, x23
    mov x1, x24
    ldp x23, x24, [sp, #32]
    ldp x21, x22, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

// calculate_svg_metrics() -> x0: width, x1: height
calculate_svg_metrics:
    // x20: lang_count
    add x0, x20, #(LEGEND_ROWS_PER_COL - 1)
    mov x1, LEGEND_ROWS_PER_COL
    udiv x2, x0, x1      // x2 = num_cols
    
    mov x3, LEGEND_ROWS_PER_COL
    cmp x20, LEGEND_ROWS_PER_COL
    csel x3, x20, x3, lo // x3 = max_rows
    
    mov x0, LEGEND_COL_WIDTH
    mul x0, x2, x0
    add x0, x0, SVG_MARGIN_X
    mov x1, MIN_SVG_WIDTH
    cmp x0, x1
    csel x0, x0, x1, hi   // x0 = final_width
    
    mov x1, LEGEND_ROW_HEIGHT
    mul x1, x3, x1
    add x1, x1, SVG_BASE_HEIGHT // x1 = final_height
    ret

// write_svg_header(x0: width, x1: height)
write_svg_header:
    stp x29, x30, [sp, #-32]!
    stp x19, x20, [sp, #16]
    mov x19, x0
    mov x20, x1

    ldr x0, =svg_hdr_1
    bl append_str
    mov x0, x19
    bl append_int
    ldr x0, =svg_hdr_2
    bl append_str
    mov x0, x20
    bl append_int
    ldr x0, =svg_hdr_3
    bl append_str
    mov x0, x19
    bl append_int
    ldr x0, =svg_hdr_4
    bl append_str
    mov x0, x20
    bl append_int
    ldr x0, =svg_hdr_5
    bl append_str
    ldr x0, =svg_hdr_body
    bl append_str

    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// write_svg_bars(x0: lang_count, x1: total_sum)
write_svg_bars:
    stp x29, x30, [sp, #-64]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    
    mov x19, x0         // x19 = lang_count
    mov x20, x1         // x20 = total_sum
    mov x21, #0         // cumulative_pct (scaled by 100)
    ldr x22, =parsed_data
    mov x23, #0         // index

bars_loop:
    cmp x23, x19
    bge bars_done
    
    // width_pct = (value * 10000) / total_sum
    ldr x0, [x22, #8]
    mov x1, #10000
    mul x0, x0, x1
    udiv x24, x0, x20    // x24 = width_pct

    ldr x0, =rect_part1
    bl append_str
    mov x0, x21
    bl append_fixed_point
    ldr x0, =rect_part2
    bl append_str
    mov x0, x24
    bl append_fixed_point
    ldr x0, =rect_part3
    bl append_str
    ldr x0, [x22, #16]
    bl append_str
    ldr x0, =rect_part4
    bl append_str
    
    // delay = BAR_ANIM_START_DELAY + (index * BAR_ANIM_STEP_DELAY)
    mov x5, BAR_ANIM_STEP_DELAY
    mov x6, BAR_ANIM_START_DELAY
    madd x0, x23, x5, x6
    bl append_fixed_point
    
    ldr x0, =rect_part5
    bl append_str

    add x21, x21, x24
    add x22, x22, LANG_STRUCT_SIZE
    add x23, x23, #1
    b bars_loop

bars_done:
    ldr x0, =bar_ftr
    bl append_str
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

// write_svg_legend(x0: lang_count, x1: total_sum)
write_svg_legend:
    stp x29, x30, [sp, #-64]!
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    
    mov x19, x0         // x19 = lang_count
    mov x20, x1         // x20 = total_sum
    ldr x21, =parsed_data
    mov x22, #0         // index

legend_loop:
    cmp x22, x19
    bge legend_done

    // column = index / 25, row = index % 25
    mov x0, LEGEND_ROWS_PER_COL
    udiv x1, x22, x0
    msub x2, x1, x0, x22
    
    // cx = LEGEND_START_X + (column * LEGEND_COL_WIDTH)
    mov x4, LEGEND_COL_WIDTH
    mov x5, LEGEND_START_X
    madd x0, x1, x4, x5
    
    // cy = LEGEND_START_Y + (row * LEGEND_ROW_HEIGHT)
    mov x4, LEGEND_ROW_HEIGHT
    mov x5, LEGEND_START_Y
    madd x1, x2, x4, x5
    // x0=cx, x1=cy

    // delay = LEGEND_ANIM_START_DELAY + (index * LEGEND_ANIM_STEP_DELAY)
    mov x4, LEGEND_ANIM_STEP_DELAY
    mov x5, LEGEND_ANIM_START_DELAY
    madd x23, x22, x4, x5

    // Circle
    mov x5, x0         // store cx in x5 (preserve x25!)
    mov x6, x1         // store cy in x6 (preserve x25!)
    
    ldr x0, =legend_part1
    bl append_str
    mov x0, x23
    bl append_fixed_point
    ldr x0, =legend_part1a
    bl append_str
    mov x0, x5
    bl append_int
    ldr x0, =legend_part2
    bl append_str
    mov x0, x6
    bl append_int
    ldr x0, =legend_part3
    bl append_str
    ldr x0, [x21, #16]
    bl append_str
    ldr x0, =legend_part4
    bl append_str

    // Text (tx = cx + 15, ty = cy + 5)
    ldr x0, =legend_part5
    bl append_str
    mov x0, x23
    bl append_fixed_point
    ldr x0, =legend_part5a
    bl append_str
    add x0, x5, #15
    bl append_int
    ldr x0, =legend_part6
    bl append_str
    add x0, x6, #5
    bl append_int
    ldr x0, =legend_part7
    bl append_str
    ldr x0, [x21, #0]
    bl append_str
    ldr x0, =legend_part8
    bl append_str
    
    // Pct
    ldr x0, [x21, #8]
    mov x1, #10000
    mul x0, x0, x1
    udiv x0, x0, x20
    bl append_fixed_point
    ldr x0, =legend_part_pct
    bl append_str

    add x21, x21, LANG_STRUCT_SIZE
    add x22, x22, #1
    b legend_loop

legend_done:
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

// write_svg_footer()
write_svg_footer:
    stp x29, x30, [sp, #-16]!
    ldr x0, =svg_ftr
    bl append_str
    ldp x29, x30, [sp], #16
    ret

// save_svg_file()
save_svg_file:
    stp x29, x30, [sp, #-16]!
    mov x8, SYS_OPENAT
    mov x0, AT_FDCWD
    ldr x1, =file_out
    mov x2, #0x241      // O_WRONLY | O_CREAT | O_TRUNC
    mov x3, #0644
    svc #0
    mov x19, x0

    mov x8, SYS_WRITE
    mov x0, x19
    ldr x1, =out_buf
    mov x2, x25
    sub x2, x2, x1
    svc #0

    mov x8, SYS_CLOSE
    mov x0, x19
    svc #0
    ldp x29, x30, [sp], #16
    ret

// --- Utility Functions ---

append_str:
    ldrb w1, [x0], #1
    cbz w1, append_str_end
    strb w1, [x25], #1
    b append_str
append_str_end:
    ret

append_int:
    mov x1, x25
    mov x2, #10
    mov x3, #0
int_push:
    udiv x4, x0, x2
    msub x5, x4, x2, x0
    add x5, x5, #'0'
    strb w5, [sp, #-16]!
    add x3, x3, #1
    mov x0, x4
    cbnz x0, int_push
int_pop:
    ldrb w5, [sp], #16
    strb w5, [x25], #1
    sub x3, x3, #1
    cbnz x3, int_pop
    ret

append_fixed_point:
    stp x19, x20, [sp, #-32]!
    stp x29, x30, [sp, #16]
    mov x19, x0
    mov x1, #100
    udiv x0, x19, x1
    bl append_int
    mov w1, #'.'
    strb w1, [x25], #1
    mov x1, #100
    udiv x2, x19, x1
    msub x20, x2, x1, x19
    mov x1, #10
    udiv x10, x20, x1
    msub x11, x10, x1, x20
    add w10, w10, #'0'
    strb w10, [x25], #1
    add w11, w11, #'0'
    strb w11, [x25], #1
    ldp x29, x30, [sp, #16]
    ldp x19, x20, [sp], #32
    ret
