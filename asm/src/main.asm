; Compare-DirectoryTree — x86-64 NASM / Win32 implementation
;
; Conforms to the non-recursive base scope of
; ../../specs/Compare-DirectoryTree-Spec.md. See asm/README.md for the exact
; list of implemented and not-yet-implemented spec sections.
;
; Calling convention notes:
;   - Every internal procedure aligns RSP to 16 bytes on entry with
;     `and rsp, -16` after saving the incoming RSP in RBP, then reserves at
;     least 32 bytes of shadow space. This sidesteps having to hand-track
;     stack parity across pushes.
;   - Internal procedures avoid relying on the non-volatile registers
;     (RBX/RSI/RDI/R12-R15) surviving a CALL; state that must survive a
;     Win32 API call is kept in .bss globals rather than registers. This
;     program is single-threaded, so this is safe and keeps the hand-written
;     assembly easier to verify than ad hoc register-preservation bookkeeping.
;   - All memory operands reference symbols via `[rel label]` (RIP-relative)
;     because the default image base places sections outside the signed
;     32-bit displacement range that absolute addressing would need.

    section .text

    global start

    extern GetCommandLineW
    extern GetStdHandle
    extern WriteFile
    extern GetFileAttributesW
    extern FindFirstFileW
    extern FindNextFileW
    extern FindClose
    extern GetLastError
    extern ExitProcess

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
STD_OUTPUT_HANDLE       equ -11
STD_ERROR_HANDLE        equ -12
INVALID_HANDLE_VALUE    equ -1
FILE_ATTRIBUTE_DIRECTORY equ 0x10
INVALID_FILE_ATTRIBUTES equ 0xFFFFFFFF
ERROR_NO_MORE_FILES     equ 18

MAX_ENTRIES             equ 4096    ; per-side cap; see asm/README.md
MAX_NAME_CHARS          equ 260     ; WCHARs, matches Win32 MAX_PATH
FIND_DATA_SIZE          equ 600     ; WIN32_FIND_DATAW, rounded up

EXIT_MATCH              equ 0
EXIT_DIFFERENT          equ 1
EXIT_ERROR              equ 2

CLASS_LEFT_ONLY         equ 0
CLASS_RIGHT_ONLY        equ 1
CLASS_DIFFER            equ 2

; ---------------------------------------------------------------------------
; Entry point
; ---------------------------------------------------------------------------
start:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32

    call GetStdHandle_Init

    call ParseArgs
    test eax, eax
    jnz .usageError

    ; Validate LEFT then RIGHT are existing directories.
    lea rcx, [rel leftPathW]
    mov rdx, 0
    call ValidateDirectory
    test eax, eax
    jnz .badLeftDir

    lea rcx, [rel rightPathW]
    mov rdx, 1
    call ValidateDirectory
    test eax, eax
    jnz .badRightDir

    ; Enumerate both sides.
    lea rcx, [rel leftPathW]
    lea rdx, [rel leftNames]
    lea r8, [rel leftSizes]
    lea r9, [rel leftCount]
    call EnumerateDirectory
    test eax, eax
    jnz .enumFailedLeft

    lea rcx, [rel rightPathW]
    lea rdx, [rel rightNames]
    lea r8, [rel rightSizes]
    lea r9, [rel rightCount]
    call EnumerateDirectory
    test eax, eax
    jnz .enumFailedRight

    ; Sort each side (also required so the merge below is a simple
    ; two-pointer walk), then detect case-insensitive collisions.
    lea rcx, [rel leftNames]
    lea rdx, [rel leftSizes]
    mov r8d, [rel leftCount]
    call SortEntries

    lea rcx, [rel rightNames]
    lea rdx, [rel rightSizes]
    mov r8d, [rel rightCount]
    call SortEntries

    lea rcx, [rel leftNames]
    mov edx, [rel leftCount]
    call CheckCollisions
    test eax, eax
    jnz .collisionLeft

    lea rcx, [rel rightNames]
    mov edx, [rel rightCount]
    call CheckCollisions
    test eax, eax
    jnz .collisionRight

    call MergeAndClassify
    call RenderReport

    mov eax, [rel relevantDiffCount]
    test eax, eax
    jz .exitMatch
    mov ecx, EXIT_DIFFERENT
    call ExitProcess

.exitMatch:
    mov ecx, EXIT_MATCH
    call ExitProcess

.usageError:
    lea rcx, [rel msgUsage]
    mov edx, msgUsageLen
    call PrintErr
    mov ecx, EXIT_ERROR
    call ExitProcess

.badLeftDir:
    lea rcx, [rel msgBadLeft]
    mov edx, msgBadLeftLen
    call PrintErr
    mov ecx, EXIT_ERROR
    call ExitProcess

.badRightDir:
    lea rcx, [rel msgBadRight]
    mov edx, msgBadRightLen
    call PrintErr
    mov ecx, EXIT_ERROR
    call ExitProcess

.enumFailedLeft:
    lea rcx, [rel msgEnumLeft]
    mov edx, msgEnumLeftLen
    call PrintErr
    mov ecx, EXIT_ERROR
    call ExitProcess

.enumFailedRight:
    lea rcx, [rel msgEnumRight]
    mov edx, msgEnumRightLen
    call PrintErr
    mov ecx, EXIT_ERROR
    call ExitProcess

.collisionLeft:
    lea rcx, [rel msgCollisionLeft]
    mov edx, msgCollisionLeftLen
    call PrintErr
    mov ecx, EXIT_ERROR
    call ExitProcess

.collisionRight:
    lea rcx, [rel msgCollisionRight]
    mov edx, msgCollisionRightLen
    call PrintErr
    mov ecx, EXIT_ERROR
    call ExitProcess

; ---------------------------------------------------------------------------
; GetStdHandle_Init: caches stdout/stderr handles in .bss.
; ---------------------------------------------------------------------------
GetStdHandle_Init:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [rel stdOutHandle], rax
    mov ecx, STD_ERROR_HANDLE
    call GetStdHandle
    mov [rel stdErrHandle], rax
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; PrintOut / PrintErr: rcx=ptr (ASCII bytes), edx=len
; ---------------------------------------------------------------------------
PrintOut:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 48
    mov [rsp+40], rcx      ; ptr
    mov [rsp+36], edx      ; len
    mov rcx, [rel stdOutHandle]
    mov rdx, [rsp+40]
    mov r8d, [rsp+36]
    lea r9, [rsp+32]
    mov qword [rsp+32+8], 0   ; keep clear (unused OVERLAPPED slot beyond frame not required)
    mov qword [rsp+32], 0
    call WriteFile
    mov rsp, rbp
    pop rbp
    ret

PrintErr:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 48
    mov [rsp+40], rcx
    mov [rsp+36], edx
    mov rcx, [rel stdErrHandle]
    mov rdx, [rsp+40]
    mov r8d, [rsp+36]
    lea r9, [rsp+32]
    mov qword [rsp+32], 0
    call WriteFile
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; ParseArgs: tokenizes GetCommandLineW() in place, expects exactly two
; arguments after the program-name token. Sets leftPathW/rightPathW to
; point at NUL-terminated (in-place) substrings of the command line.
; Returns EAX=0 on success, 1 on usage error.
;
; Quoting support is intentionally minimal: a token starting with '"' runs
; to the next '"' (no escaped-quote handling). This covers the common case
; of a single path wrapped in quotes because it contains spaces; paths that
; themselves contain a literal '"' are not supported in this version.
; ---------------------------------------------------------------------------
ParseArgs:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    call GetCommandLineW
    mov [rel cmdLinePtr], rax
    mov rsi, rax            ; rsi = cursor (only used within this leaf-ish proc; no calls after this point except recursion-free helper)
    mov dword [rel parsedArgCount], 0

    ; token 0: program name (skip)
    mov rcx, rsi
    call SkipToken
    mov rsi, rax

    ; token 1: LEFT
    mov rcx, rsi
    call SkipSpaces
    mov rsi, rax
    movzx eax, word [rsi]
    test ax, ax
    jz .fail
    mov rcx, rsi
    call ReadToken           ; returns rax = pointer to start (NUL-terminated in place), rdx = pointer past token
    mov [rel leftPathW], rax
    mov rsi, rdx
    inc dword [rel parsedArgCount]

    ; token 2: RIGHT
    mov rcx, rsi
    call SkipSpaces
    mov rsi, rax
    movzx eax, word [rsi]
    test ax, ax
    jz .fail
    mov rcx, rsi
    call ReadToken
    mov [rel rightPathW], rax
    mov rsi, rdx
    inc dword [rel parsedArgCount]

    ; must be no further non-space tokens
    mov rcx, rsi
    call SkipSpaces
    mov rsi, rax
    movzx eax, word [rsi]
    test ax, ax
    jnz .fail

    cmp dword [rel parsedArgCount], 2
    jne .fail

    xor eax, eax
    jmp .done
.fail:
    mov eax, 1
.done:
    mov rsp, rbp
    pop rbp
    ret

; SkipSpaces: rcx=ptr -> rax=ptr past ASCII/UTF-16 spaces (0x20) and tabs (0x09)
SkipSpaces:
    mov rax, rcx
.loop:
    movzx edx, word [rax]
    cmp dx, 0x20
    je .adv
    cmp dx, 0x09
    je .adv
    ret
.adv:
    add rax, 2
    jmp .loop

; SkipToken: rcx=ptr -> rax=ptr past current whitespace-delimited token
; (used only to skip argv[0], which we never need to quote-parse precisely)
SkipToken:
    mov rax, rcx
    ; skip leading spaces
.skipsp:
    movzx edx, word [rax]
    cmp dx, 0x20
    je .adv1
    cmp dx, 0x09
    je .adv1
    jmp .body
.adv1:
    add rax, 2
    jmp .skipsp
.body:
    movzx edx, word [rax]
    test dx, dx
    jz .done
    cmp dx, 0x20
    je .done
    cmp dx, 0x09
    je .done
    add rax, 2
    jmp .body
.done:
    ret

; ReadToken: rcx=ptr (no leading spaces) -> rax=token start, rdx=ptr after
; token (token is NUL-terminated in place by overwriting its delimiter).
ReadToken:
    movzx eax, word [rcx]
    cmp ax, 0x22             ; '"'
    jne .plain
    ; quoted token: content starts right after the opening quote
    lea rax, [rcx + 2]
    mov rdx, rax
.qloop:
    movzx ecx, word [rdx]
    test cx, cx
    jz .qunterminated
    cmp cx, 0x22
    je .qterminated
    add rdx, 2
    jmp .qloop
.qterminated:
    mov word [rdx], 0        ; NUL-terminate token in place
    lea rdx, [rdx + 2]       ; resume scanning past the closing quote
    ret
.qunterminated:
    ; already NUL; leave rdx pointing at it so the next SkipSpaces call
    ; stops at end-of-string too
    ret
.plain:
    mov rax, rcx
    mov rdx, rax
.ploop:
    movzx ecx, word [rdx]
    test cx, cx
    jz .pend_nul
    cmp cx, 0x20
    je .pend_delim
    cmp cx, 0x09
    je .pend_delim
    add rdx, 2
    jmp .ploop
.pend_delim:
    ; overwrite the delimiter with NUL to terminate the token in place, then
    ; advance rdx past it so callers resume scanning after the delimiter
    ; (not at the NUL we just wrote).
    mov word [rdx], 0
    add rdx, 2
    ret
.pend_nul:
    ; already at end-of-string; nothing to overwrite or skip past.
    ret

; ---------------------------------------------------------------------------
; ValidateDirectory: rcx=pathW, rdx=which(0=left,1=right)
; Returns EAX=0 if path exists and is a directory, else 1.
; ---------------------------------------------------------------------------
ValidateDirectory:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov rcx, [rcx]           ; rcx was &pathW; dereference to the actual wide string pointer
    call GetFileAttributesW
    cmp eax, INVALID_FILE_ATTRIBUTES
    je .bad
    test eax, FILE_ATTRIBUTE_DIRECTORY
    jz .bad
    xor eax, eax
    jmp .done
.bad:
    mov eax, 1
.done:
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; EnumerateDirectory: rcx=dirPathW, rdx=namesBuf, r8=sizesBuf, r9=countPtr
; Builds "<dir>\*" pattern, walks FindFirstFileW/FindNextFileW, skips any
; entry with FILE_ATTRIBUTE_DIRECTORY set (this also skips "." and "..").
; Returns EAX=0 on success, 1 on enumeration failure or overflow.
; ---------------------------------------------------------------------------
EnumerateDirectory:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 64
    mov [rsp+56], rcx        ; dirPathW
    mov [rsp+48], rdx        ; namesBuf
    mov [rsp+40], r8         ; sizesBuf
    mov [rsp+32], r9         ; countPtr

    ; build pattern into scratch buffer: copy dir path then append "\*\0"
    ; patternBuf holds 512 WCHARs; reserve 3 for "\*\0" and bounds-check the
    ; copy so an overlong path (e.g. a maliciously long command line) fails
    ; cleanly instead of overflowing into adjacent .bss data.
    mov rax, [rsp+56]       ; rax = &pathW
    mov rsi, [rax]          ; rsi = pathW (actual wide string pointer)
    lea rdi, [rel patternBuf]
    xor r10d, r10d          ; r10 = WCHARs copied so far
.copyPath:
    cmp r10d, 509
    jae .pathOverflow
    movzx eax, word [rsi]
    test ax, ax
    jz .pathDone
    mov [rdi], ax
    add rsi, 2
    add rdi, 2
    inc r10d
    jmp .copyPath
.pathOverflow:
    mov eax, 1
    jmp .ret
.pathDone:
    mov word [rdi], 0x5C     ; '\'
    add rdi, 2
    mov word [rdi], 0x2A     ; '*'
    add rdi, 2
    mov word [rdi], 0
    mov dword [r9], 0

    lea rcx, [rel patternBuf]
    lea rdx, [rel findData]
    call FindFirstFileW
    mov [rel findHandle], rax
    cmp rax, INVALID_HANDLE_VALUE
    jne .haveFirst
    ; empty directory enumerations still call FindFirstFileW successfully in
    ; Win32 (they return "." and ".."); INVALID_HANDLE_VALUE here is a real
    ; enumeration failure.
    mov eax, 1
    jmp .ret
.haveFirst:
.loopEntry:
    mov r9, [rsp+32]         ; reload countPtr; r9 is volatile and may be
                              ; clobbered by the FindNextFileW call at .next
    ; skip directories (covers "." and "..")
    mov eax, [rel findData]
    test eax, FILE_ATTRIBUTE_DIRECTORY
    jnz .next

    mov eax, [r9]
    cmp eax, MAX_ENTRIES
    jae .overflow

    ; copy cFileName into namesBuf[count]
    mov r10, [rsp+48]
    mov eax, [r9]
    imul rax, rax, MAX_NAME_CHARS*2
    add r10, rax
    lea rsi, [rel findData]
    add rsi, 44               ; offsetof(cFileName)
    mov rdi, r10
.copyName:
    movzx eax, word [rsi]
    mov [rdi], ax
    test ax, ax
    jz .nameDone
    add rsi, 2
    add rdi, 2
    jmp .copyName
.nameDone:
    ; size = (nFileSizeHigh << 32) | nFileSizeLow
    mov r10, [rsp+40]
    mov eax, [r9]
    lea r10, [r10 + rax*8]
    mov eax, [rel findData + 32]     ; nFileSizeLow
    mov edx, [rel findData + 28]     ; nFileSizeHigh
    shl rdx, 32
    or rax, rdx
    mov [r10], rax

    inc dword [r9]
.next:
    mov rcx, [rel findHandle]
    lea rdx, [rel findData]
    call FindNextFileW
    test eax, eax
    jnz .loopEntry
    call GetLastError
    cmp eax, ERROR_NO_MORE_FILES
    je .success
    mov eax, 1
    jmp .close
.success:
    xor eax, eax
.close:
    mov [rsp+32], eax        ; stash return code across the call (offset
                              ; >=32 is safe from FindClose's shadow-space use)
    mov rcx, [rel findHandle]
    call FindClose
    mov eax, [rsp+32]
    jmp .ret
.overflow:
    mov rcx, [rel findHandle]
    call FindClose
    mov eax, 1
    jmp .ret
.ret:
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; CaseInsensitiveCompare: rcx=nameA, rdx=nameB (NUL-terminated UTF-16)
; Returns EAX: <0 if A<B, 0 if equal, >0 if A>B, using a simple ordinal
; per-code-unit comparison after ASCII upper-casing (A-Z/a-z only). This
; matches the catalog and acceptance-scenario names, all of which are ASCII;
; non-ASCII segments compare using their raw code unit values.
; ---------------------------------------------------------------------------
CaseInsensitiveCompare:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 48
    mov rsi, rcx
    mov rdi, rdx
.loop:
    movzx eax, word [rsi]
    movzx ecx, word [rdi]
    mov [rsp+32], ecx        ; stash charB across the UpperW(charA) call
    mov ecx, eax             ; ecx = charA
    call UpperW
    mov [rsp+36], eax        ; stash upperA across the UpperW(charB) call
    mov ecx, [rsp+32]        ; ecx = charB
    call UpperW               ; eax = upperB
    mov r9d, [rsp+36]        ; upperA
    mov r10d, eax            ; upperB
    cmp r9d, r10d
    jne .diff
    test r9d, r9d
    jz .equal
    add rsi, 2
    add rdi, 2
    jmp .loop
.diff:
    mov eax, r9d
    sub eax, r10d
    jmp .done
.equal:
    xor eax, eax
.done:
    mov rsp, rbp
    pop rbp
    ret

; UpperW: in ECX = wchar, out EAX = ascii-uppercased wchar
UpperW:
    mov eax, ecx
    cmp eax, 'a'
    jb .ret
    cmp eax, 'z'
    ja .ret
    sub eax, 0x20
.ret:
    ret

; ---------------------------------------------------------------------------
; SortEntries: rcx=namesBuf, rdx=sizesBuf, r8d=count
; Insertion sort in place on parallel arrays, ordered by
; CaseInsensitiveCompare over the name.
; ---------------------------------------------------------------------------
SortEntries:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 64
    mov [rsp+56], rcx      ; namesBuf
    mov [rsp+48], rdx      ; sizesBuf
    mov [rsp+44], r8d      ; count

    mov dword [rsp+40], 1  ; i = 1
.outer:
    mov eax, [rsp+40]
    cmp eax, [rsp+44]
    jge .outerDone

.innerInit:
    mov eax, [rsp+40]
    mov [rsp+36], eax      ; j = i
.inner:
    mov eax, [rsp+36]
    test eax, eax
    jz .innerDone

    ; compare entry[j-1] vs entry[j]
    mov r10, [rsp+56]
    mov eax, [rsp+36]
    dec eax
    imul rax, rax, MAX_NAME_CHARS*2
    add rax, r10
    mov rcx, rax           ; nameA = names[j-1]

    mov r10, [rsp+56]
    mov eax, [rsp+36]
    imul rax, rax, MAX_NAME_CHARS*2
    add rax, r10
    mov rdx, rax           ; nameB = names[j]

    call CaseInsensitiveCompare
    cmp eax, 0
    jle .innerDone         ; already in order

    ; swap names[j-1] <-> names[j]
    mov r10, [rsp+56]
    mov eax, [rsp+36]
    dec eax
    imul rax, rax, MAX_NAME_CHARS*2
    lea rsi, [r10 + rax]
    mov r10, [rsp+56]
    mov eax, [rsp+36]
    imul rax, rax, MAX_NAME_CHARS*2
    lea rdi, [r10 + rax]
    mov ecx, MAX_NAME_CHARS*2
    call SwapBytes

    ; swap sizes[j-1] <-> sizes[j]
    mov r10, [rsp+48]
    mov eax, [rsp+36]
    dec eax
    lea rsi, [r10 + rax*8]
    mov r10, [rsp+48]
    mov eax, [rsp+36]
    lea rdi, [r10 + rax*8]
    mov rax, [rsi]
    mov r11, [rdi]
    mov [rdi], rax
    mov [rsi], r11

    dec dword [rsp+36]
    jmp .inner
.innerDone:
    inc dword [rsp+40]
    jmp .outer
.outerDone:
    mov rsp, rbp
    pop rbp
    ret

; SwapBytes: rsi=ptrA, rdi=ptrB, ecx=byteCount (must be even, we swap words)
SwapBytes:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov r8d, ecx
    xor r9d, r9d
.loop:
    cmp r9d, r8d
    jge .done
    movzx eax, word [rsi + r9]
    movzx edx, word [rdi + r9]
    mov [rsi + r9], dx
    mov [rdi + r9], ax
    add r9d, 2
    jmp .loop
.done:
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; CheckCollisions: rcx=namesBuf (sorted), edx=count
; Returns EAX=1 if two adjacent (post-sort) entries compare equal
; case-insensitively (an ambiguous collision), else 0.
; ---------------------------------------------------------------------------
CheckCollisions:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 48
    mov [rsp+40], rcx
    mov [rsp+36], edx
    mov dword [rsp+32], 1
.loop:
    mov eax, [rsp+32]
    cmp eax, [rsp+36]
    jge .noCollision

    mov r10, [rsp+40]
    mov eax, [rsp+32]
    dec eax
    imul rax, rax, MAX_NAME_CHARS*2
    lea rcx, [r10 + rax]
    mov r10, [rsp+40]
    mov eax, [rsp+32]
    imul rax, rax, MAX_NAME_CHARS*2
    lea rdx, [r10 + rax]
    call CaseInsensitiveCompare
    test eax, eax
    jz .collision
    inc dword [rsp+32]
    jmp .loop
.collision:
    mov eax, 1
    jmp .ret
.noCollision:
    xor eax, eax
.ret:
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; IsIgnoredMetadata: rcx=nameW (NUL-terminated) -> EAX=1 if it matches the
; Appendix A.1 "ignored by default" catalog (exact, case-insensitive name
; match), else 0. Appendix A.2 (recognized-but-relevant, wildcard patterns)
; is not yet classified; see asm/README.md.
; ---------------------------------------------------------------------------
; IsIgnoredMetadata: rcx=nameW (NUL-terminated) -> EAX=1 if it matches the
; Appendix A.1 "ignored by default" catalog (exact, case-insensitive name
; match), else 0. Appendix A.2 (recognized-but-relevant, wildcard patterns)
; is out of scope for this version; see asm/README.md. When EAX=1, RDX is
; set to a pointer to the matched entry's ASCII "Note" text (Appendix A.1
; column 3) and R8D to its length, for the "Ignored: <note>" annotation.
IsIgnoredMetadata:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 48
    mov [rsp+32], rcx

    lea rdx, [rel catThumbs]
    mov rcx, [rsp+32]
    call CaseInsensitiveCompare
    test eax, eax
    jnz .n1
    lea rdx, [rel noteThumbs]
    mov r8d, noteThumbsLen
    jmp .yes
.n1:
    lea rdx, [rel catEhthumbs]
    mov rcx, [rsp+32]
    call CaseInsensitiveCompare
    test eax, eax
    jnz .n2
    lea rdx, [rel noteEhthumbs]
    mov r8d, noteEhthumbsLen
    jmp .yes
.n2:
    lea rdx, [rel catDesktopIni]
    mov rcx, [rsp+32]
    call CaseInsensitiveCompare
    test eax, eax
    jnz .n3
    lea rdx, [rel noteDesktopIni]
    mov r8d, noteDesktopIniLen
    jmp .yes
.n3:
    lea rdx, [rel catDsStore]
    mov rcx, [rsp+32]
    call CaseInsensitiveCompare
    test eax, eax
    jnz .n4
    lea rdx, [rel noteDsStore]
    mov r8d, noteDsStoreLen
    jmp .yes
.n4:
    lea rdx, [rel catDotDirectory]
    mov rcx, [rsp+32]
    call CaseInsensitiveCompare
    test eax, eax
    jnz .no
    lea rdx, [rel noteDotDirectory]
    mov r8d, noteDotDirectoryLen
    jmp .yes

.no:
    xor eax, eax
    jmp .ret
.yes:
    mov eax, 1
.ret:
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; MergeAndClassify: two-pointer merge of the sorted LEFT/RIGHT arrays into
; the combined diffRows table, and tallies the summary counters.
; ---------------------------------------------------------------------------
MergeAndClassify:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32

    mov dword [rel iLeft], 0
    mov dword [rel jRight], 0
    mov dword [rel diffCount], 0
    mov dword [rel sameCount], 0
    mov dword [rel diffSizeCount], 0
    mov dword [rel leftOnlyCount], 0
    mov dword [rel rightOnlyCount], 0
    mov dword [rel ignoredCount], 0

.loop:
    mov eax, [rel iLeft]
    mov ecx, [rel leftCount]
    cmp eax, ecx
    jge .drainRight
    mov eax, [rel jRight]
    mov ecx, [rel rightCount]
    cmp eax, ecx
    jge .drainLeft

    ; compare leftNames[i] vs rightNames[j]
    lea r10, [rel leftNames]
    mov eax, [rel iLeft]
    imul rax, rax, MAX_NAME_CHARS*2
    lea rcx, [r10 + rax]
    lea r10, [rel rightNames]
    mov eax, [rel jRight]
    imul rax, rax, MAX_NAME_CHARS*2
    lea rdx, [r10 + rax]
    call CaseInsensitiveCompare
    cmp eax, 0
    jl .emitLeftOnly
    jg .emitRightOnly

    ; equal names: compare sizes
    lea r10, [rel leftSizes]
    mov eax, [rel iLeft]
    mov r8, [r10 + rax*8]
    lea r10, [rel rightSizes]
    mov eax, [rel jRight]
    mov r9, [r10 + rax*8]
    cmp r8, r9
    jne .emitDiffer
    inc dword [rel sameCount]
    inc dword [rel iLeft]
    inc dword [rel jRight]
    jmp .loop

.emitDiffer:
    lea r10, [rel leftNames]
    mov eax, [rel iLeft]
    imul rax, rax, MAX_NAME_CHARS*2
    lea rcx, [r10 + rax]        ; name pointer (from LEFT side)
    mov edx, CLASS_DIFFER
    call StoreDiffRow
    inc dword [rel diffSizeCount]
    inc dword [rel iLeft]
    inc dword [rel jRight]
    jmp .loop

.emitLeftOnly:
    lea r10, [rel leftNames]
    mov eax, [rel iLeft]
    imul rax, rax, MAX_NAME_CHARS*2
    lea rcx, [r10 + rax]
    mov edx, CLASS_LEFT_ONLY
    call StoreDiffRow
    inc dword [rel leftOnlyCount]
    inc dword [rel iLeft]
    jmp .loop

.emitRightOnly:
    lea r10, [rel rightNames]
    mov eax, [rel jRight]
    imul rax, rax, MAX_NAME_CHARS*2
    lea rcx, [r10 + rax]
    mov edx, CLASS_RIGHT_ONLY
    call StoreDiffRow
    inc dword [rel rightOnlyCount]
    inc dword [rel jRight]
    jmp .loop

.drainRight:
    mov eax, [rel jRight]
    mov ecx, [rel rightCount]
    cmp eax, ecx
    jge .mergeDone
    lea r10, [rel rightNames]
    mov eax, [rel jRight]
    imul rax, rax, MAX_NAME_CHARS*2
    lea rcx, [r10 + rax]
    mov edx, CLASS_RIGHT_ONLY
    call StoreDiffRow
    inc dword [rel rightOnlyCount]
    inc dword [rel jRight]
    jmp .drainRight

.drainLeft:
    mov eax, [rel iLeft]
    mov ecx, [rel leftCount]
    cmp eax, ecx
    jge .mergeDone
    lea r10, [rel leftNames]
    mov eax, [rel iLeft]
    imul rax, rax, MAX_NAME_CHARS*2
    lea rcx, [r10 + rax]
    mov edx, CLASS_LEFT_ONLY
    call StoreDiffRow
    inc dword [rel leftOnlyCount]
    inc dword [rel iLeft]
    jmp .drainLeft

.mergeDone:
    mov eax, [rel diffSizeCount]
    add eax, [rel leftOnlyCount]
    add eax, [rel rightOnlyCount]
    mov [rel totalDiffCount], eax
    mov eax, [rel totalDiffCount]
    sub eax, [rel ignoredCount]
    mov [rel relevantDiffCount], eax

    mov rsp, rbp
    pop rbp
    ret

; StoreDiffRow: rcx=namePtr (into leftNames/rightNames, still valid), edx=class
; Reads the matching LEFT/RIGHT size(s) using the *current* iLeft/jRight
; indices (valid only for CLASS_DIFFER, where both sides advance together);
; for one-sided classes the missing side is marked with MISSING_SIZE.
MISSING_SIZE equ -1

StoreDiffRow:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 48
    mov r10d, [rel diffCount]
    mov [rsp+32], r10d       ; stash index; r10 is volatile across calls below
    ; namePtr
    lea r11, [rel diffNamePtr]
    mov [r11 + r10*8], rcx
    ; class
    lea r11, [rel diffClass]
    mov [r11 + r10], dl

    cmp edx, CLASS_LEFT_ONLY
    jne .notLeftOnly
    lea r11, [rel leftSizes]
    mov eax, [rel iLeft]
    mov rax, [r11 + rax*8]
    lea r11, [rel diffLeftSize]
    mov [r11 + r10*8], rax
    lea r11, [rel diffRightSize]
    mov qword [r11 + r10*8], MISSING_SIZE
    jmp .checkIgnored

.notLeftOnly:
    cmp edx, CLASS_RIGHT_ONLY
    jne .isDiffer
    lea r11, [rel diffLeftSize]
    mov qword [r11 + r10*8], MISSING_SIZE
    lea r11, [rel rightSizes]
    mov eax, [rel jRight]
    mov rax, [r11 + rax*8]
    lea r11, [rel diffRightSize]
    mov [r11 + r10*8], rax
    jmp .checkIgnored

.isDiffer:
    lea r11, [rel leftSizes]
    mov eax, [rel iLeft]
    mov rax, [r11 + rax*8]
    lea r11, [rel diffLeftSize]
    mov [r11 + r10*8], rax
    lea r11, [rel rightSizes]
    mov eax, [rel jRight]
    mov rax, [r11 + rax*8]
    lea r11, [rel diffRightSize]
    mov [r11 + r10*8], rax

.checkIgnored:
    lea r11, [rel diffNamePtr]
    mov rcx, [r11 + r10*8]
    call IsIgnoredMetadata     ; eax=flag, rdx=notePtr, r8d=noteLen (if flag)
    mov r10d, [rsp+32]        ; reload index (r10 is volatile across the call)
    lea r11, [rel diffIgnored]
    mov [r11 + r10], al
    test al, al
    jz .noIgnore
    inc dword [rel ignoredCount]
    lea r11, [rel diffNoteText]
    mov [r11 + r10*8], rdx
    lea r11, [rel diffNoteLen]
    mov [r11 + r10*4], r8d
.noIgnore:

    inc dword [rel diffCount]
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; RenderReport: prints the full report using the computed diff rows and
; counters. See asm/README.md for the exact subset of Section 5 covered.
; ---------------------------------------------------------------------------
RenderReport:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32

    lea rcx, [rel rptHeader]
    mov edx, rptHeaderLen
    call PrintOut

    lea rcx, [rel rptLeftLabel]
    mov edx, rptLeftLabelLen
    call PrintOut
    call PrintLeftPath
    lea rcx, [rel nl]
    mov edx, 1
    call PrintOut

    lea rcx, [rel rptRightLabel]
    mov edx, rptRightLabelLen
    call PrintOut
    call PrintRightPath
    lea rcx, [rel nl]
    mov edx, 1
    call PrintOut

    lea rcx, [rel rptRules]
    mov edx, rptRulesLen
    call PrintOut

    lea rcx, [rel rptSummaryHeader]
    mov edx, rptSummaryHeaderLen
    call PrintOut

    mov ecx, [rel leftCount]
    lea rdx, [rel lblLeftFiles]
    mov r8d, lblLeftFilesLen
    call PrintCountLine

    mov ecx, [rel rightCount]
    lea rdx, [rel lblRightFiles]
    mov r8d, lblRightFilesLen
    call PrintCountLine

    mov ecx, [rel sameCount]
    lea rdx, [rel lblSame]
    mov r8d, lblSameLen
    call PrintCountLine

    mov ecx, [rel diffSizeCount]
    lea rdx, [rel lblDiffSize]
    mov r8d, lblDiffSizeLen
    call PrintCountLine

    mov ecx, [rel leftOnlyCount]
    lea rdx, [rel lblLeftOnly]
    mov r8d, lblLeftOnlyLen
    call PrintCountLine

    mov ecx, [rel rightOnlyCount]
    lea rdx, [rel lblRightOnly]
    mov r8d, lblRightOnlyLen
    call PrintCountLine

    lea rcx, [rel nl]
    mov edx, 1
    call PrintOut

    mov ecx, [rel totalDiffCount]
    lea rdx, [rel lblTotalDiff]
    mov r8d, lblTotalDiffLen
    call PrintCountLine

    mov ecx, [rel ignoredCount]
    lea rdx, [rel lblIgnored]
    mov r8d, lblIgnoredLen
    call PrintCountLine

    mov ecx, [rel relevantDiffCount]
    lea rdx, [rel lblRelevant]
    mov r8d, lblRelevantLen
    call PrintCountLine

    mov eax, [rel diffCount]
    test eax, eax
    jz .skipDifferences

    lea rcx, [rel rptDiffHeaderTop]
    mov edx, rptDiffHeaderTopLen
    call PrintOut

    call ComputeColumnWidths

    ; column header line
    lea rcx, [rel rptDiffPrefixLabel]
    mov edx, rptDiffPrefixLabelLen
    call PrintOut
    lea rcx, [rel txtPathHeader]
    mov edx, txtPathHeaderLen
    mov r8d, [rel colPathWidth]
    call PrintLeftJustified
    lea rcx, [rel txtLeftHeader]
    mov edx, txtLeftHeaderLen
    mov r8d, [rel colLeftWidth]
    call PrintPadded
    lea rcx, [rel colGap]
    mov edx, colGapLen
    call PrintOut
    lea rcx, [rel txtRightHeader]
    mov edx, txtRightHeaderLen
    mov r8d, [rel colRightWidth]
    call PrintPadded
    lea rcx, [rel txtNoteHeader]
    mov edx, txtNoteHeaderLen
    call PrintOut

    ; column underline (dashes) line
    lea rcx, [rel rptDiffPrefixDash]
    mov edx, rptDiffPrefixDashLen
    call PrintOut
    lea rcx, [rel txtPathDash]
    mov edx, txtPathDashLen
    mov r8d, [rel colPathWidth]
    call PrintLeftJustified
    lea rcx, [rel txtLeftDash]
    mov edx, txtLeftDashLen
    mov r8d, [rel colLeftWidth]
    call PrintPadded
    lea rcx, [rel colGap]
    mov edx, colGapLen
    call PrintOut
    lea rcx, [rel txtRightDash]
    mov edx, txtRightDashLen
    mov r8d, [rel colRightWidth]
    call PrintPadded
    lea rcx, [rel txtNoteDash]
    mov edx, txtNoteDashLen
    call PrintOut

    mov ecx, CLASS_LEFT_ONLY
    call PrintClassRows
    mov ecx, CLASS_RIGHT_ONLY
    call PrintClassRows
    mov ecx, CLASS_DIFFER
    call PrintClassRows

    lea rcx, [rel rptLegend]
    mov edx, rptLegendLen
    call PrintOut

.skipDifferences:
    call PrintVerdict

    mov rsp, rbp
    pop rbp
    ret

; PrintLeftPath / PrintRightPath: best-effort ASCII rendering of the
; supplied (possibly non-ASCII) wide path, one code unit truncated to one
; byte. Non-ASCII input is out of scope for this version; see
; asm/README.md.
PrintLeftPath:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    lea rcx, [rel leftPathW]
    call PrintWideBestEffort
    mov rsp, rbp
    pop rbp
    ret

PrintRightPath:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    lea rcx, [rel rightPathW]
    call PrintWideBestEffort
    mov rsp, rbp
    pop rbp
    ret

; PrintWideBestEffort: rcx = pointer to a WCHAR* variable (i.e. *rcx is the
; string pointer)
PrintWideBestEffort:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov rsi, [rcx]
    lea rdi, [rel asciiScratch]
    xor r8d, r8d
.loop:
    movzx eax, word [rsi]
    test ax, ax
    jz .done
    mov [rdi + r8], al
    add rsi, 2
    inc r8d
    jmp .loop
.done:
    lea rcx, [rel asciiScratch]
    mov edx, r8d
    call PrintOut
    mov rsp, rbp
    pop rbp
    ret

; PrintPadded: rcx=ptr, edx=len, r8d=fieldWidth. Right-justifies [ptr,len)
; within fieldWidth by printing (fieldWidth-len) spaces, then the value.
; Keeps ptr/len in stack locals (not registers) across the padding loop's
; own calls to PrintOut, which would otherwise clobber volatile registers.
PrintPadded:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 64
    mov [rsp+56], rcx        ; ptr
    mov [rsp+48], edx        ; len
    mov eax, r8d
    sub eax, edx
    mov [rsp+40], eax        ; remaining pad count
    cmp dword [rsp+40], 0
    jle .noPad
.pad:
    lea rcx, [rel spaceChar]
    mov edx, 1
    call PrintOut
    dec dword [rsp+40]
    jnz .pad
.noPad:
    mov rcx, [rsp+56]
    mov edx, [rsp+48]
    call PrintOut
    mov rsp, rbp
    pop rbp
    ret

; PrintLeftJustified: rcx=ptr, edx=len, r8d=fieldWidth. Prints the text then
; pads with trailing spaces so the field occupies exactly fieldWidth columns
; (no padding if len >= fieldWidth).
PrintLeftJustified:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 64
    mov [rsp+56], rcx        ; ptr
    mov [rsp+48], edx        ; len
    mov eax, r8d
    sub eax, edx
    mov [rsp+40], eax        ; remaining pad count
    mov rcx, [rsp+56]
    mov edx, [rsp+48]
    call PrintOut
    cmp dword [rsp+40], 0
    jle .done
    mov ecx, [rsp+40]
    call PrintSpaces
.done:
    mov rsp, rbp
    pop rbp
    ret

; PrintCountLine: ecx=value, rdx=labelPtr, r8d=labelLen
; Prints "<label>" then the decimal value right-justified so the total
; label+value width is 33 columns (matches the Rust implementation's
; format_summary_line width), then newline.
PrintCountLine:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 64
    mov [rsp+56], ecx        ; value
    mov [rsp+48], rdx        ; label ptr
    mov [rsp+40], r8d        ; label len

    mov rcx, [rsp+48]
    mov edx, [rsp+40]
    call PrintOut

    mov ecx, [rsp+56]
    call FormatPlainDecimal   ; -> rax=ptr into numScratch, edx=len
    mov rcx, rax
    mov r8d, 33
    sub r8d, [rsp+40]        ; fieldWidth = 33 - labelLen
    call PrintPadded

    lea rcx, [rel nl]
    mov edx, 1
    call PrintOut

    mov rsp, rbp
    pop rbp
    ret

; FormatPlainDecimal: ecx = value (unsigned, 32-bit is enough for counts)
; Returns RAX = pointer to first digit in numScratch, EDX = length. No
; thousands separators (used for summary/verdict counts).
FormatPlainDecimal:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov eax, ecx
    lea rdi, [rel numScratch + 31]
    mov byte [rdi], 0
    mov ecx, 10
    test eax, eax
    jnz .conv
    dec rdi
    mov byte [rdi], '0'
    jmp .fin
.conv:
.loop:
    xor edx, edx
    div ecx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    test eax, eax
    jnz .loop
.fin:
    lea rax, [rel numScratch + 31]
    sub rax, rdi
    mov edx, eax
    mov rax, rdi
    mov rsp, rbp
    pop rbp
    ret

; FormatExactBytes: rcx = 64-bit value (or -1 for MISSING_SIZE), treated as
; unsigned unless it equals MISSING_SIZE. Returns RAX=ptr, EDX=len. Emits
; thousands separators per Section 5.3; emits "<missing>" for MISSING_SIZE.
FormatExactBytes:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    cmp rcx, MISSING_SIZE
    jne .haveValue
    lea rax, [rel txtMissing]
    mov edx, txtMissingLen
    jmp .ret
.haveValue:
    mov rax, rcx
    lea rdi, [rel numScratch + 63]
    mov byte [rdi], 0
    xor r8d, r8d              ; digit count since last comma
    mov r9, 10
.loop:
    xor rdx, rdx
    div r9
    add dl, '0'
    dec rdi
    mov [rdi], dl
    inc r8d
    test rax, rax
    jz .fin
    cmp r8d, 3
    jne .loop
    dec rdi
    mov byte [rdi], ','
    xor r8d, r8d
    jmp .loop
.fin:
    lea rax, [rel numScratch + 63]
    sub rax, rdi
    mov edx, eax
    mov rax, rdi
.ret:
    mov rsp, rbp
    pop rbp
    ret

; PrintSpaces: ecx=count. Prints `count` ASCII space characters.
PrintSpaces:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 48
    mov [rsp+32], ecx
.loop:
    cmp dword [rsp+32], 0
    jle .done
    lea rcx, [rel spaceChar]
    mov edx, 1
    call PrintOut
    dec dword [rsp+32]
    jmp .loop
.done:
    mov rsp, rbp
    pop rbp
    ret

; WideAsciiLen: rcx = pointer to NUL-terminated wide string. Returns EAX =
; number of UTF-16 code units before the NUL (the length the best-effort
; ASCII rendering in this version will occupy).
WideAsciiLen:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32
    mov rax, rcx
    xor edx, edx
.loop:
    movzx ecx, word [rax + rdx*2]
    test cx, cx
    jz .done
    inc edx
    jmp .loop
.done:
    mov eax, edx
    mov rsp, rbp
    pop rbp
    ret

; ComputeColumnWidths: no args. Scans all rows in diffNamePtr/diffLeftSize/
; diffRightSize and sets colPathWidth/colLeftWidth/colRightWidth to the
; widest content seen, floored at the Section 5.2 canonical minimums
; (38/17/18), matching the Rust reference implementation's dynamic sizing.
ComputeColumnWidths:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 48
    mov dword [rel colPathWidth], 38
    mov dword [rel colLeftWidth], 17
    mov dword [rel colRightWidth], 18
    mov dword [rsp+32], 0    ; index
.loop:
    mov eax, [rsp+32]
    cmp eax, [rel diffCount]
    jge .done

    lea r10, [rel diffNamePtr]
    mov rcx, [r10 + rax*8]
    call WideAsciiLen
    add eax, 2
    cmp eax, [rel colPathWidth]
    jle .afterPath
    mov [rel colPathWidth], eax
.afterPath:
    mov eax, [rsp+32]
    lea r10, [rel diffLeftSize]
    mov rcx, [r10 + rax*8]
    call FormatExactBytes
    cmp edx, [rel colLeftWidth]
    jle .afterLeft
    mov [rel colLeftWidth], edx
.afterLeft:
    mov eax, [rsp+32]
    lea r10, [rel diffRightSize]
    mov rcx, [r10 + rax*8]
    call FormatExactBytes
    cmp edx, [rel colRightWidth]
    jle .afterRight
    mov [rel colRightWidth], edx
.afterRight:
    inc dword [rsp+32]
    jmp .loop
.done:
    mov rsp, rbp
    pop rbp
    ret

; PrintClassRows: ecx = class id. Iterates diffRows in stored (already
; sorted-by-merge) order, printing rows whose class matches, followed by a
; single blank line if at least one row was printed.
PrintClassRows:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 64
    mov [rsp+56], ecx        ; wanted class
    mov dword [rsp+48], 0    ; index
    mov dword [rsp+40], 0    ; printedAny

.loop:
    mov eax, [rsp+48]
    cmp eax, [rel diffCount]
    jge .afterLoop

    lea r10, [rel diffClass]
    movzx edx, byte [r10 + rax]
    cmp edx, [rsp+56]
    jne .skip

    mov dword [rsp+40], 1

    ; marker
    mov ecx, [rsp+56]
    cmp ecx, CLASS_LEFT_ONLY
    jne .tryRight
    lea rcx, [rel markLeftOnly]
    jmp .haveMark
.tryRight:
    cmp ecx, CLASS_RIGHT_ONLY
    jne .tryDiffer
    lea rcx, [rel markRightOnly]
    jmp .haveMark
.tryDiffer:
    lea rcx, [rel markDiffer]
.haveMark:
    mov edx, 2
    call PrintOut
    lea rcx, [rel rowPrefixGap]
    mov edx, rowPrefixGapLen
    call PrintOut

    ; name (best-effort ASCII), left-justified padded to colPathWidth
    mov eax, [rsp+48]
    lea r10, [rel diffNamePtr]
    mov rsi, [r10 + rax*8]
    lea rdi, [rel asciiScratch]
    xor r9d, r9d
.copyNm:
    movzx edx, word [rsi]
    test dx, dx
    jz .nmDone
    mov [rdi + r9], dl
    add rsi, 2
    inc r9d
    jmp .copyNm
.nmDone:
    mov rcx, rdi
    mov edx, r9d
    mov r8d, [rel colPathWidth]
    call PrintLeftJustified

    ; LEFT size, right-justified to colLeftWidth (no gap before this column)
    mov eax, [rsp+48]
    lea r10, [rel diffLeftSize]
    mov rcx, [r10 + rax*8]
    call FormatExactBytes
    mov rcx, rax
    mov r8d, [rel colLeftWidth]
    call PrintPadded
    lea rcx, [rel colGap]
    mov edx, colGapLen
    call PrintOut

    ; RIGHT size, right-justified to colRightWidth
    mov eax, [rsp+48]
    lea r10, [rel diffRightSize]
    mov rcx, [r10 + rax*8]
    call FormatExactBytes
    mov rcx, rax
    mov r8d, [rel colRightWidth]
    call PrintPadded

    ; optional ignored-metadata note
    mov eax, [rsp+48]
    lea r10, [rel diffIgnored]
    movzx edx, byte [r10 + rax]
    test dl, dl
    jz .noNote
    lea rcx, [rel colGap]
    mov edx, colGapLen
    call PrintOut
    lea rcx, [rel noteIgnoredPrefix]
    mov edx, noteIgnoredPrefixLen
    call PrintOut
    mov eax, [rsp+48]
    lea r10, [rel diffNoteText]
    mov rcx, [r10 + rax*8]
    lea r10, [rel diffNoteLen]
    mov edx, [r10 + rax*4]
    call PrintOut
.noNote:
    lea rcx, [rel nl]
    mov edx, 1
    call PrintOut

.skip:
    inc dword [rsp+48]
    jmp .loop

.afterLoop:
    cmp dword [rsp+40], 0
    jz .done
    lea rcx, [rel nl]
    mov edx, 1
    call PrintOut
.done:
    mov rsp, rbp
    pop rbp
    ret

NAME_COL_WIDTH equ 24

; PrintVerdict: implements the Section 8.1 grammar for the subset in scope
; (no recursive structural segments/clauses in this version).
PrintVerdict:
    push rbp
    mov rbp, rsp
    and rsp, -16
    sub rsp, 32

    mov eax, [rel relevantDiffCount]
    test eax, eax
    jnz .different

    lea rcx, [rel vMatchPrefix]
    mov edx, vMatchPrefixLen
    call PrintOut

    mov eax, [rel ignoredCount]
    test eax, eax
    jnz .matchQualified

    lea rcx, [rel vMatchAllPrefix]
    mov edx, vMatchAllPrefixLen
    call PrintOut
    mov ecx, [rel sameCount]
    call FormatPlainDecimal
    mov r10, rax
    mov r11d, edx
    mov rcx, r10
    mov edx, r11d
    call PrintOut
    lea rcx, [rel vMatchAllSuffix]
    mov edx, vMatchAllSuffixLen
    mov eax, [rel sameCount]
    cmp eax, 1
    jne .allSuffixReady
    lea rcx, [rel vMatchAllSuffixSing]
    mov edx, vMatchAllSuffixSingLen
.allSuffixReady:
    call PrintOut
    jmp .doneNl

.matchQualified:
    lea rcx, [rel vQualifiedPrefix]
    mov edx, vQualifiedPrefixLen
    call PrintOut
    mov ecx, [rel ignoredCount]
    call FormatPlainDecimal
    mov r10, rax
    mov r11d, edx
    mov rcx, r10
    mov edx, r11d
    call PrintOut
    mov eax, [rel ignoredCount]
    cmp eax, 1
    jne .qPlural
    lea rcx, [rel vQualifiedSingular]
    mov edx, vQualifiedSingularLen
    call PrintOut
    jmp .doneNl
.qPlural:
    lea rcx, [rel vQualifiedPlural]
    mov edx, vQualifiedPluralLen
    call PrintOut
    jmp .doneNl

.different:
    lea rcx, [rel vDifferentPrefix]
    mov edx, vDifferentPrefixLen
    call PrintOut
    mov ecx, [rel relevantDiffCount]
    call FormatPlainDecimal
    mov r10, rax
    mov r11d, edx
    mov rcx, r10
    mov edx, r11d
    call PrintOut
    mov eax, [rel relevantDiffCount]
    cmp eax, 1
    jne .dPlural
    lea rcx, [rel vRelevantSingular]
    mov edx, vRelevantSingularLen
    call PrintOut
    jmp .checkIgnoredSeg
.dPlural:
    lea rcx, [rel vRelevantPlural]
    mov edx, vRelevantPluralLen
    call PrintOut

.checkIgnoredSeg:
    mov eax, [rel ignoredCount]
    test eax, eax
    jz .doneNl
    lea rcx, [rel vSegSep]
    mov edx, vSegSepLen
    call PrintOut
    mov ecx, [rel ignoredCount]
    call FormatPlainDecimal
    mov r10, rax
    mov r11d, edx
    mov rcx, r10
    mov edx, r11d
    call PrintOut
    mov eax, [rel ignoredCount]
    cmp eax, 1
    jne .iPlural
    lea rcx, [rel vIgnoredSingular]
    mov edx, vIgnoredSingularLen
    call PrintOut
    jmp .doneNl
.iPlural:
    lea rcx, [rel vIgnoredPlural]
    mov edx, vIgnoredPluralLen
    call PrintOut

.doneNl:
    lea rcx, [rel nl]
    mov edx, 1
    call PrintOut

    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
    section .data

nl:                 db 10
spaceChar:          db " "
colGap:             db "   "
colGapLen           equ $ - colGap
rowPrefixGap:       db "        "   ; marker is followed by 2+4+2 spaces
                                     ; (2 blank "  ", 4-char blank Type field,
                                     ; 2 blank "  "); see Section 5.2.
rowPrefixGapLen     equ $ - rowPrefixGap

msgUsage:           db "usage: compare-directorytree.exe <left-dir> <right-dir>", 10
msgUsageLen         equ $ - msgUsage
msgBadLeft:         db "error: LEFT path does not exist or is not a directory", 10
msgBadLeftLen       equ $ - msgBadLeft
msgBadRight:        db "error: RIGHT path does not exist or is not a directory", 10
msgBadRightLen      equ $ - msgBadRight
msgEnumLeft:        db "error: failed to fully enumerate LEFT directory", 10
msgEnumLeftLen      equ $ - msgEnumLeft
msgEnumRight:       db "error: failed to fully enumerate RIGHT directory", 10
msgEnumRightLen     equ $ - msgEnumRight
msgCollisionLeft:   db "error: case-insensitive filename collision within LEFT directory", 10
msgCollisionLeftLen equ $ - msgCollisionLeft
msgCollisionRight:  db "error: case-insensitive filename collision within RIGHT directory", 10
msgCollisionRightLen equ $ - msgCollisionRight

rptHeader:          db "FILE COMPARISON", 10, "===============", 10, 10
rptHeaderLen        equ $ - rptHeader
rptLeftLabel:       db "LEFT : "
rptLeftLabelLen     equ $ - rptLeftLabel
rptRightLabel:      db "RIGHT: "
rptRightLabelLen    equ $ - rptRightLabel
rptRules:
    db 10
    db "Scope : Files in these directories only; subdirectories are NOT searched.", 10
    db "        Hidden and system files ARE included.", 10
    db "Match : Filenames are compared case-insensitively.", 10
    db "Same  : Matching filename and exact size in bytes.", 10
    db "Ignore: Known disposable metadata/cache files are reported but do not", 10
    db "        affect the final comparison result.", 10
    db "Note  : Contents, hashes, timestamps, attributes, and other metadata are", 10
    db "        NOT compared.", 10
    db 10
rptRulesLen         equ $ - rptRules

rptSummaryHeader:   db "SUMMARY", 10, "-------", 10
rptSummaryHeaderLen equ $ - rptSummaryHeader

lblLeftFiles:       db "LEFT files:                   "
lblLeftFilesLen     equ $ - lblLeftFiles
lblRightFiles:      db "RIGHT files:                  "
lblRightFilesLen    equ $ - lblRightFiles
lblSame:            db "Same:                         "
lblSameLen          equ $ - lblSame
lblDiffSize:        db "Different size:               "
lblDiffSizeLen      equ $ - lblDiffSize
lblLeftOnly:        db "LEFT only:                     "
lblLeftOnlyLen      equ $ - lblLeftOnly
lblRightOnly:       db "RIGHT only:                    "
lblRightOnlyLen     equ $ - lblRightOnly
lblTotalDiff:       db "Total differences:             "
lblTotalDiffLen     equ $ - lblTotalDiff
lblIgnored:         db "Ignored metadata differences:  "
lblIgnoredLen       equ $ - lblIgnored
lblRelevant:        db "Relevant differences:          "
lblRelevantLen      equ $ - lblRelevant

rptDiffHeaderTop:
    db 10
    db "DIFFERENCES", 10, "-----------", 10, 10
rptDiffHeaderTopLen equ $ - rptDiffHeaderTop

rptDiffPrefixLabel: db "    Type  "
rptDiffPrefixLabelLen equ $ - rptDiffPrefixLabel
rptDiffPrefixDash:  db "    ----  "
rptDiffPrefixDashLen equ $ - rptDiffPrefixDash

txtPathHeader:      db "File / Directory"
txtPathHeaderLen    equ $ - txtPathHeader
txtPathDash:        db "----------------"
txtPathDashLen      equ $ - txtPathDash
txtLeftHeader:      db "LEFT size (bytes)"
txtLeftHeaderLen    equ $ - txtLeftHeader
txtLeftDash:        db "-----------------"
txtLeftDashLen      equ $ - txtLeftDash
txtRightHeader:     db "RIGHT size (bytes)"
txtRightHeaderLen   equ $ - txtRightHeader
txtRightDash:       db "------------------"
txtRightDashLen     equ $ - txtRightDash
txtNoteHeader:      db "   Note", 10
txtNoteHeaderLen    equ $ - txtNoteHeader
txtNoteDash:        db "   ----", 10
txtNoteDashLen      equ $ - txtNoteDash

rptLegend:
    db 10
    db "Legend:", 10
    db "  <<   Exists only on LEFT", 10
    db "  >>   Exists only on RIGHT", 10
    db "  <>   Same filename, different size", 10
    db 10
rptLegendLen        equ $ - rptLegend

markLeftOnly:       db "<<"
markRightOnly:      db ">>"
markDiffer:         db "<>"

noteIgnoredPrefix:  db "Ignored: "
noteIgnoredPrefixLen equ $ - noteIgnoredPrefix

txtMissing:         db "<missing>"
txtMissingLen       equ $ - txtMissing

vMatchPrefix:       db "RESULT: MATCH - "
vMatchPrefixLen     equ $ - vMatchPrefix
vMatchAllPrefix:    db "all "
vMatchAllPrefixLen  equ $ - vMatchAllPrefix
vMatchAllSuffix:    db " files match"
vMatchAllSuffixLen  equ $ - vMatchAllSuffix
vMatchAllSuffixSing: db " file matches"
vMatchAllSuffixSingLen equ $ - vMatchAllSuffixSing
vQualifiedPrefix:   db "qualified: differences limited to "
vQualifiedPrefixLen equ $ - vQualifiedPrefix
vQualifiedSingular: db " ignored metadata file"
vQualifiedSingularLen equ $ - vQualifiedSingular
vQualifiedPlural:   db " ignored metadata files"
vQualifiedPluralLen equ $ - vQualifiedPlural
vDifferentPrefix:   db "RESULT: DIFFERENT - "
vDifferentPrefixLen equ $ - vDifferentPrefix
vRelevantSingular:  db " relevant difference"
vRelevantSingularLen equ $ - vRelevantSingular
vRelevantPlural:    db " relevant differences"
vRelevantPluralLen  equ $ - vRelevantPlural
vSegSep:            db " | "
vSegSepLen          equ $ - vSegSep
vIgnoredSingular:   db " ignored metadata difference"
vIgnoredSingularLen equ $ - vIgnoredSingular
vIgnoredPlural:     db " ignored metadata differences"
vIgnoredPluralLen   equ $ - vIgnoredPlural

catThumbs:          dw __utf16__('Thumbs.db'), 0
catEhthumbs:        dw __utf16__('ehthumbs.db'), 0
catDesktopIni:      dw __utf16__('desktop.ini'), 0
catDsStore:         dw __utf16__('.DS_Store'), 0
catDotDirectory:    dw __utf16__('.directory'), 0

noteThumbs:         db "Windows thumbnail cache"
noteThumbsLen       equ $ - noteThumbs
noteEhthumbs:       db "Windows Media Center thumbnail cache"
noteEhthumbsLen     equ $ - noteEhthumbs
noteDesktopIni:     db "Windows folder presentation metadata"
noteDesktopIniLen   equ $ - noteDesktopIni
noteDsStore:        db "macOS Finder metadata"
noteDsStoreLen      equ $ - noteDsStore
noteDotDirectory:   db "KDE folder presentation metadata"
noteDotDirectoryLen equ $ - noteDotDirectory

; ---------------------------------------------------------------------------
; BSS
; ---------------------------------------------------------------------------
    section .bss

stdOutHandle:       resq 1
stdErrHandle:        resq 1

cmdLinePtr:         resq 1
parsedArgCount:     resd 1
leftPathW:          resq 1
rightPathW:         resq 1

patternBuf:         resw 512
findData:           resb FIND_DATA_SIZE
findHandle:         resq 1

leftNames:          resw MAX_ENTRIES*MAX_NAME_CHARS
leftSizes:          resq MAX_ENTRIES
leftCount:          resd 1
rightNames:         resw MAX_ENTRIES*MAX_NAME_CHARS
rightSizes:         resq MAX_ENTRIES
rightCount:         resd 1

iLeft:              resd 1
jRight:             resd 1

diffNamePtr:        resq MAX_ENTRIES*2
diffLeftSize:       resq MAX_ENTRIES*2
diffRightSize:      resq MAX_ENTRIES*2
diffClass:          resb MAX_ENTRIES*2
diffIgnored:        resb MAX_ENTRIES*2
diffNoteText:       resq MAX_ENTRIES*2
diffNoteLen:        resd MAX_ENTRIES*2
diffCount:          resd 1
colPathWidth:       resd 1
colLeftWidth:       resd 1
colRightWidth:      resd 1

sameCount:          resd 1
diffSizeCount:      resd 1
leftOnlyCount:      resd 1
rightOnlyCount:     resd 1
totalDiffCount:     resd 1
ignoredCount:       resd 1
relevantDiffCount:  resd 1

asciiScratch:       resb 2048
numScratch:         resb 64
