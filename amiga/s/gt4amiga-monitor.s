
; gt4amiga-monitor: bridge de lectura/escritura de memoria + llamada
; generica a funciones de libreria, en tiempo real, via SER:
;
; Comando S: devuelve IntuitionBase->FirstScreen (offset 60, confirmado
; contra el header primario intuition/intuitionbase.h + graphics/view.h:
; sizeof(struct Library)=34 + sizeof(struct View)=18 + ActiveWindow(4)
; + ActiveScreen(4) = 60). Sustituye a LockPubScreen(), que es de V36
; (Kickstart 2.0) y no existe en la tabla de intuition.library de nuestro
; Kickstart 1.3 - saltar a su LVO (-510) en 1.3 ejecuta memoria fuera de
; la tabla real y provoca un Address Error. Confirmado via autodoc oficial
; (amigadev.elowar.com), que marca LockPubScreen explicitamente "(V36)".

        SECTION code,CODE

MODE_OLDFILE equ 1005

start:
        movem.l d2-d7/a2-a6,-(sp)

        move.l  4.w,a6
        lea     dosname,a1
        moveq   #0,d0
        jsr     -552(a6)
        tst.l   d0
        beq     quit_now
        move.l  d0,a2

        lea     intuitionname,a1
        moveq   #0,d0
        jsr     -552(a6)
        tst.l   d0
        beq     close_dos
        move.l  d0,a3

        lea     graphicsname,a1
        moveq   #0,d0
        jsr     -552(a6)
        tst.l   d0
        beq     close_intuition
        move.l  d0,a4

        move.l  a2,a6
        lea     sername,a1
        move.l  a1,d1
        move.l  #MODE_OLDFILE,d2
        jsr     -30(a6)
        move.l  d0,d6
        beq     close_graphics

mainloop:
        lea     opbyte,a5
        moveq   #1,d5
        bsr     read_n_bytes
        move.b  opbyte,d7

        cmp.b   #$52,d7
        beq     do_read
        cmp.b   #$57,d7
        beq     do_write
        cmp.b   #$43,d7
        beq     do_call
        cmp.b   #$53,d7             ; S = get Workbench screen pointer
        beq     do_getscreen
        cmp.b   #$51,d7
        beq     close_ser
        bra     mainloop

do_getscreen:
        move.l  60(a3),databuf      ; IntuitionBase->FirstScreen
        lea     databuf,a5
        moveq   #4,d5
        bsr     write_n_bytes
        bra     mainloop

do_read:
        lea     rwbuf,a5
        moveq   #6,d5
        bsr     read_n_bytes
        moveq   #0,d4               ; move.b only sets the LOW byte of d4 -
                                     ; without clearing it first, any garbage in
                                     ; the upper 24 bits becomes a gigantic
                                     ; byte count in read_n_bytes/write_n_bytes
                                     ; and the monitor blocks forever on SER:
        move.b  rwbuf,d4
        move.l  rwbuf+2,a0

        cmp.b   #4,d4
        beq     rd_long
        cmp.b   #2,d4
        beq     rd_word
        move.b  (a0),databuf
        bra     rd_send
rd_word:
        move.w  (a0),databuf
        bra     rd_send
rd_long:
        move.l  (a0),databuf
rd_send:
        lea     databuf,a5
        move.l  d4,d5
        bsr     write_n_bytes
        bra     mainloop

do_write:
        lea     rwbuf,a5
        moveq   #6,d5
        bsr     read_n_bytes
        moveq   #0,d4               ; clear before move.b - see do_read
        move.b  rwbuf,d4

        lea     databuf,a5
        move.l  d4,d5
        bsr     read_n_bytes

        move.l  rwbuf+2,a0          ; load the target address AFTER the last
                                     ; read_n_bytes: it calls dos.library Read()
                                     ; and a0 is a scratch register across any
                                     ; library call - loading it before (the
                                     ; previous code) made the store below hit
                                     ; a garbage address while still acking OK.
                                     ; do_read is safe: it dereferences a0
                                     ; before calling anything.

        cmp.b   #4,d4
        beq     wr_long
        cmp.b   #2,d4
        beq     wr_word
        move.b  databuf,(a0)
        bra     wr_ack
wr_word:
        move.w  databuf,(a0)
        bra     wr_ack
wr_long:
        move.l  databuf,(a0)
wr_ack:
        lea     ackbyte,a5
        moveq   #1,d5
        bsr     write_n_bytes
        bra     mainloop

do_call:
        lea     callbuf,a5
        moveq   #28,d5
        bsr     read_n_bytes

        moveq   #0,d0
        move.b  callbuf,d0
        cmp.b   #0,d0
        beq     lib_exec
        cmp.b   #1,d0
        beq     lib_dos
        cmp.b   #2,d0
        beq     lib_intuition
        move.l  a4,a6
        bra     have_base
lib_exec:
        move.l  4.w,a6
        bra     have_base
lib_dos:
        move.l  a2,a6
        bra     have_base
lib_intuition:
        move.l  a3,a6
have_base:
        move.w  callbuf+2,d7        ; d7.w = LVO, kept as an INDEX register so
                                     ; a6 itself is never altered - many library
                                     ; functions use a6 internally as their own
                                     ; base pointer during execution, not just to
                                     ; locate the entry point. Mutating a6 before
                                     ; the jsr (the previous approach) corrupts
                                     ; that reference and crashes inside the
                                     ; callee. (a6,d7.w) addressing computes
                                     ; a6+sign_extend(d7.w) without touching a6.

        move.l  callbuf+4,a0
        move.l  callbuf+8,a1
        move.l  callbuf+12,d0
        move.l  callbuf+16,d1
        move.l  callbuf+20,d2
        move.l  callbuf+24,d3

        jsr     0(a6,d7.w)

        move.l  d0,databuf
        lea     databuf,a5
        moveq   #4,d5
        bsr     write_n_bytes
        bra     mainloop

close_ser:
        move.l  a2,a6
        move.l  d6,d1
        jsr     -36(a6)
close_graphics:
        move.l  4.w,a6
        move.l  a4,a1
        jsr     -414(a6)
close_intuition:
        move.l  4.w,a6
        move.l  a3,a1
        jsr     -414(a6)
close_dos:
        move.l  4.w,a6
        move.l  a2,a1
        jsr     -414(a6)
quit_now:
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts

read_n_bytes:
        move.l  a2,a6
readloop:
        move.l  d6,d1
        move.l  a5,d2
        moveq   #1,d3
        jsr     -42(a6)
        tst.l   d0
        ble     close_ser
        addq.l  #1,a5
        subq.l  #1,d5
        bne.s   readloop
        rts

write_n_bytes:
        move.l  a2,a6
        move.l  d6,d1
        move.l  a5,d2
        move.l  d5,d3
        jsr     -48(a6)
        rts

        SECTION data,DATA

dosname:
        dc.b    "dos.library",0
        EVEN
intuitionname:
        dc.b    "intuition.library",0
        EVEN
graphicsname:
        dc.b    "graphics.library",0
        EVEN
sername:
        dc.b    "SER:",0
        EVEN
ackbyte:
        dc.b    "K"
        EVEN

        SECTION bss,BSS

opbyte:
        ds.b    2
rwbuf:
        ds.b    6
callbuf:
        ds.b    28
databuf:
        ds.b    4
