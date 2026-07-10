
; gt4amiga-monitor: bridge de lectura/escritura de memoria + llamada
; generica a funciones de libreria, en tiempo real, via SER:
;
; PROTOCOLO v2 (enmarcado). Cada comando llega como:
;       [$A5][opcode][payload][chk]
; donde chk = XOR de opcode y todos los bytes del payload. Cada
; respuesta se envia como:
;       [$5A][status][payload][chk]
; donde chk = XOR de status y payload. status 0 = OK (ejecutado),
; status 1 = NAK: checksum incorrecto, NO se ejecuto nada (el cliente
; puede reenviar con total seguridad, incluso un CALL).
;
; El bucle principal CAZA el byte de sincronia $A5: si una trama llega
; mutilada (el transporte serie de FS-UAE pierde bytes de forma
; intermitente en rafagas desde ciertos clientes), el parser descarta
; bytes hasta el siguiente $A5 y se realinea solo - nunca mas un monitor
; clavado a mitad de comando. Un $A5 dentro de un payload es inocuo en
; operacion normal (dentro de una trama se lee por longitud, no se
; interpreta); durante una recuperacion puede producir como mucho un
; intercambio fallido extra, que el checksum convierte en NAK/reintento.
;
; Comandos (opcode / payload / respuesta):
;   R $52  [size][pad][addr.l]            -> payload = size bytes leidos
;   W $57  [size][pad][addr.l][data...]   -> payload vacio (ack)
;   C $43  [lib][pad][lvo.w][a0.l][a1.l][d0.l][d1.l][d2.l][d3.l]
;                                         -> payload = d0 tras la llamada
;   S $53  (sin payload)                  -> payload = IntuitionBase->FirstScreen
;   Q $51  (sin payload)                  -> payload vacio; el monitor termina
;
; Comando S: IntuitionBase->FirstScreen esta en el offset 60 (confirmado
; contra headers primarios: sizeof(struct Library)=34 + sizeof(struct
; View)=18 + ActiveWindow(4) + ActiveScreen(4)). Sustituye a
; LockPubScreen(), que es V36+ y no existe en Kickstart 1.3.

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
hunt:
        lea     opbyte,a5           ; cazar el byte de sincronia $A5:
        moveq   #1,d5                ; descartar bytes hasta encontrarlo
        bsr     read_n_bytes
        cmp.b   #$A5,opbyte
        bne     hunt

        lea     opbyte,a5           ; opcode
        moveq   #1,d5
        bsr     read_n_bytes
        move.b  opbyte,d7           ; d7 = opcode (sobrevive a Read/Write:
                                     ; dos.library solo destruye d0/d1/a0/a1)

        cmp.b   #$52,d7
        beq     do_read
        cmp.b   #$57,d7
        beq     do_write
        cmp.b   #$43,d7
        beq     do_call
        cmp.b   #$53,d7
        beq     do_getscreen
        cmp.b   #$51,d7
        beq     do_quit
        bra     hunt                ; opcode desconocido tras $A5: realinear

do_getscreen:
        lea     rwbuf,a5            ; solo el byte de checksum
        moveq   #1,d5
        bsr     read_n_bytes
        cmp.b   rwbuf,d7            ; chk = XOR(opcode) = opcode
        bne     send_nak
        move.l  60(a3),respdata     ; IntuitionBase->FirstScreen
        moveq   #4,d5
        bra     send_ok

do_read:
        lea     rwbuf,a5
        moveq   #7,d5               ; 6 de payload + 1 chk
        bsr     read_n_bytes
        moveq   #0,d4
        move.b  d7,d4
        lea     rwbuf,a5
        moveq   #6,d5
        bsr     xor_buf
        cmp.b   rwbuf+6,d4
        bne     send_nak
        moveq   #0,d4
        move.b  rwbuf,d4            ; size (moveq antes: move.b solo toca
        move.l  rwbuf+2,a0          ;  el byte bajo)
        cmp.b   #4,d4
        beq.s   rd_long
        cmp.b   #2,d4
        beq.s   rd_word
        move.b  (a0),respdata
        moveq   #1,d5
        bra     send_ok
rd_word:
        move.w  (a0),respdata
        moveq   #2,d5
        bra     send_ok
rd_long:
        move.l  (a0),respdata
        moveq   #4,d5
        bra     send_ok

do_write:
        lea     rwbuf,a5
        moveq   #6,d5               ; [size][pad][addr.l]
        bsr     read_n_bytes
        moveq   #0,d4
        move.b  rwbuf,d4
        cmp.b   #1,d4               ; validar size ANTES de usarlo como
        beq.s   dw_szok              ; contador: un size corrupto no debe
        cmp.b   #2,d4                ; convertirse en una lectura gigante
        beq.s   dw_szok
        cmp.b   #4,d4
        bne     hunt
dw_szok:
        lea     databuf,a5
        move.l  d4,d5
        addq.l  #1,d5               ; data + chk
        bsr     read_n_bytes
        moveq   #0,d4               ; chk = opcode ^ rwbuf(6) ^ data(size)
        move.b  d7,d4
        lea     rwbuf,a5
        moveq   #6,d5
        bsr     xor_buf
        lea     databuf,a5
        moveq   #0,d5
        move.b  rwbuf,d5
        bsr     xor_buf
        lea     databuf,a5          ; chk esperado esta justo tras los datos
        moveq   #0,d5
        move.b  rwbuf,d5
        adda.l  d5,a5
        cmp.b   (a5),d4
        bne     send_nak
        move.l  rwbuf+2,a0          ; cargar a0 DESPUES del ultimo Read():
        moveq   #0,d4                ; a0 es scratch en cualquier llamada
        move.b  rwbuf,d4             ; de libreria
        cmp.b   #4,d4
        beq.s   wr_long
        cmp.b   #2,d4
        beq.s   wr_word
        move.b  databuf,(a0)
        bra.s   wr_done
wr_word:
        move.w  databuf,(a0)
        bra.s   wr_done
wr_long:
        move.l  databuf,(a0)
wr_done:
        moveq   #0,d5               ; respuesta OK sin payload
        bra     send_ok

do_call:
        lea     callbuf,a5
        moveq   #29,d5              ; 28 de payload + 1 chk
        bsr     read_n_bytes
        moveq   #0,d4
        move.b  d7,d4
        lea     callbuf,a5
        moveq   #28,d5
        bsr     xor_buf
        cmp.b   callbuf+28,d4
        bne     send_nak

        moveq   #0,d0
        move.b  callbuf,d0
        cmp.b   #0,d0
        beq.s   lib_exec
        cmp.b   #1,d0
        beq.s   lib_dos
        cmp.b   #2,d0
        beq.s   lib_intuition
        move.l  a4,a6
        bra.s   have_base
lib_exec:
        move.l  4.w,a6
        bra.s   have_base
lib_dos:
        move.l  a2,a6
        bra.s   have_base
lib_intuition:
        move.l  a3,a6
have_base:
        move.w  callbuf+2,d7        ; d7.w = LVO (el opcode ya no hace
                                     ; falta), como INDICE para no mutar
                                     ; a6: muchas funciones usan a6 como
                                     ; base de su propia libreria DURANTE
                                     ; la ejecucion. (a6,d7.w) calcula
                                     ; a6+sign_extend(d7.w) sin tocarlo.

        move.l  callbuf+4,a0
        move.l  callbuf+8,a1
        move.l  callbuf+12,d0
        move.l  callbuf+16,d1
        move.l  callbuf+20,d2
        move.l  callbuf+24,d3

        jsr     0(a6,d7.w)

        move.l  d0,respdata
        moveq   #4,d5
        bra     send_ok

do_quit:
        lea     rwbuf,a5
        moveq   #1,d5
        bsr     read_n_bytes
        cmp.b   rwbuf,d7
        bne     send_nak
        move.b  #$5A,respbuf        ; despedida: [5A][00][00]
        clr.b   respbuf+1
        clr.b   respdata
        lea     respbuf,a5
        moveq   #3,d5
        bsr     write_n_bytes
        bra     close_ser

; --- respuestas -------------------------------------------------------

send_ok:                            ; entrada: d5 = longitud del payload,
        move.b  #$5A,respbuf         ; que ya esta en respdata
        clr.b   respbuf+1
        move.l  d5,d2
        moveq   #0,d4
        tst.l   d5
        beq.s   so_chk
        lea     respdata,a5
        bsr     xor_buf
so_chk:
        lea     respdata,a5         ; chk (XOR de status=0 + payload)
        adda.l  d2,a5                ; justo tras el payload
        move.b  d4,(a5)
        lea     respbuf,a5
        move.l  d2,d5
        addq.l  #3,d5               ; sync + status + payload + chk
        bsr     write_n_bytes
        bra     mainloop

send_nak:
        move.b  #$5A,respbuf        ; [5A][01][01]: chk = XOR(status=1)
        move.b  #1,respbuf+1
        move.b  #1,respdata
        lea     respbuf,a5
        moveq   #3,d5
        bsr     write_n_bytes
        bra     mainloop

; --- cierre -----------------------------------------------------------

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

; --- utilidades -------------------------------------------------------

read_n_bytes:                       ; a5 = buffer, d5 = n
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

write_n_bytes:                      ; a5 = buffer, d5 = n
        move.l  a2,a6
        move.l  d6,d1
        move.l  a5,d2
        move.l  d5,d3
        jsr     -48(a6)
        rts

xor_buf:                            ; a5 = buffer, d5 = n; acumula en d4
xb_loop:
        move.b  (a5)+,d3
        eor.b   d3,d4
        subq.l  #1,d5
        bne.s   xb_loop
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

        SECTION bss,BSS

opbyte:
        ds.b    2
rwbuf:
        ds.b    8                   ; 6 payload + chk, redondeado a par
databuf:
        ds.b    6                   ; 4 datos + chk, redondeado a par
callbuf:
        ds.b    30                  ; 28 payload + chk, redondeado a par
respbuf:
        ds.b    2                   ; [sync][status] - respdata debe ir
respdata:                            ; CONTIGUO justo despues
        ds.b    6                   ; payload max 4 + chk, redondeado a par
