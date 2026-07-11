
; gt4amiga-monitor: bridge de lectura/escritura de memoria + llamada
; generica a funciones de libreria, en tiempo real, con DOS TRANSPORTES:
;
;   - TCP (bsdsocket.library): para hardware real con pila TCP/IP
;     (p.ej. A500 + PiStorm/Emu68 + wifipi + Roadshow). El monitor es un
;     servidor TCP en el puerto 2345; GT se conecta a <ip-amiga>:2345.
;     Si un cliente desconecta, se acepta al siguiente (resiliencia).
;   - SER: (dos.library): para FS-UAE, que puentea el puerto serie
;     emulado a un socket TCP del host (misma semantica que siempre).
;
; Seleccion automatica al arrancar: si bsdsocket.library existe (hay
; pila TCP corriendo) se usa TCP; si no (p.ej. Workbench 1.3 bajo
; FS-UAE), SER:. El protocolo que viaja es identico en ambos.
;
; LVOs de bsdsocket.library verificados contra el FD canonico de AmiTCP
; (bias 30, paso 6): socket -30 (d0/d1/d2), bind -36 (d0/a0/d1),
; listen -42 (d0/d1), accept -48 (d0/a0/a1), send -66 (d0/a0/d1/d2),
; recv -78 (d0/a0/d1/d2), setsockopt -90 (d0/d1/d2/a0/d3),
; CloseSocket -120 (d0). Convenciones contrastadas con el autodoc
; oficial (wiki.amigaos.net/amiga/autodocs/bsdsocket.doc.txt).
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
; mutilada, el parser descarta bytes hasta el siguiente $A5 y se
; realinea solo. Un $A5 dentro de un payload es inocuo en operacion
; normal (dentro de una trama se lee por longitud, no se interpreta).
;
; Comandos (opcode / payload / respuesta):
;   R $52  [size][pad][addr.l]            -> payload = size bytes leidos
;   W $57  [size][pad][addr.l][data...]   -> payload vacio (ack)
;   B $42  [addr.l][len.w]                -> payload = len bytes leidos
;          (1..BLK_MAX). La region se copia primero a un buffer interno:
;          datos y checksum salen de la misma foto coherente.
;   P $50  [addr.l][len.w][data...]       -> payload vacio (ack)
;          (1..BLK_MAX). Los datos se reciben EN EL BUFFER y solo se
;          copian al destino tras verificar el checksum: un frame
;          corrupto produce NAK sin haber tocado memoria.
;          B/P copian byte a byte: son para RAM (framebuffers, copper
;          lists, sprites). Los registros custom exigen accesos de
;          word: para ellos, R/W de toda la vida.
;   C $43  [lib][pad][lvo.w][a0.l][a1.l][d0.l][d1.l][d2.l][d3.l]
;                                         -> payload = d0 tras la llamada
;   S $53  (sin payload)                  -> payload = IntuitionBase->FirstScreen
;   X $58  (sin payload)                  -> payload = direccion del mailbox
;          de ejecucion, o 0 si no se lanzo nada (ya hay un programa en
;          marcha, o LoadSeg/CreateProc fallo). Carga GT4A:incoming/program
;          y lo lanza como PROCESO SEPARADO (CreateProc, dos V34): el
;          monitor sigue atendiendo R/W/C mientras el programa corre.
;          La salida del programa (Output/Write) va al fichero
;          GT4A:outgoing/output. Mailbox: [estado.b][pad(3)][rc.l]
;          estado: 0 nunca, 1 corriendo, 2 terminado, 3 error de lanzam.
;          NO enviar Q con estado=1: el hijo ejecuta codigo del seglist
;          del monitor y el CLI lo libera cuando el monitor termina.
;   Q $51  (sin payload)                  -> payload vacio; el monitor termina
;
; DISCIPLINA DE PILA: los saltos de error (p.ej. Read/recv fallido)
; ocurren DENTRO de subrutinas, con direcciones de retorno acumuladas
; en la pila. El SP se guarda al entrar (stacksave) y se restaura en
; cada punto de salida/reciclaje - sin esto, el movem.l (sp)+ final
; restauraba basura y el rts saltaba a cualquier parte (la "salida
; limpia" por error de lectura era en realidad un crash silencioso).

        SECTION code,CODE

MODE_OLDFILE equ 1005
MODE_NEWFILE equ 1006
TCP_PORT     equ 2345
EXEC_STACK   equ 4096               ; pila del proceso hijo (multiplo de 4)
BLK_MAX      equ 4096               ; maximo de una transferencia B/P:
                                    ; acota el buffer BSS y el coste de
                                    ; reintentar una trama corrupta (el
                                    ; cliente trocea cantidades mayores)
PR_COS       equ 160                ; offset de pr_COS en struct Process
                                    ; (dosextens.i: TC_SIZE=92 + MP_SIZE=34
                                    ;  + pad.w + 8 campos.l = 160)

start:
        movem.l d2-d7/a2-a6,-(sp)
        move.l  sp,stacksave

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

; --- seleccion de transporte -------------------------------------------

        move.l  4.w,a6              ; hay pila TCP? (bsdsocket.library
        lea     bsdname,a1           ; solo existe con la pila arrancada)
        moveq   #0,d0
        jsr     -552(a6)
        tst.l   d0
        beq     try_serial
        move.l  d0,sockbase

        move.l  d0,a6               ; socket(AF_INET=2, SOCK_STREAM=1, 0)
        moveq   #2,d0
        moveq   #1,d1
        moveq   #0,d2
        jsr     -30(a6)
        tst.l   d0
        bmi     tcp_fail_lib
        move.l  d0,listenfd

        move.l  #1,optval           ; setsockopt(fd, SOL_SOCKET=$FFFF,
        move.l  listenfd,d0          ;  SO_REUSEADDR=4, &1, 4): permite
        move.l  #$FFFF,d1            ;  relanzar el monitor sin esperar
        moveq   #4,d2                ;  el TIME_WAIT del puerto
        lea     optval,a0
        moveq   #4,d3
        jsr     -90(a6)

        move.b  #16,sockaddr        ; sockaddr_in (estilo BSD4.4):
        move.b  #2,sockaddr+1        ; [len][family=AF_INET][port.w][addr.l]
        move.w  #TCP_PORT,sockaddr+2 ; (BSS ya esta a cero: addr=INADDR_ANY)
        move.l  listenfd,d0
        lea     sockaddr,a0
        moveq   #16,d1
        jsr     -36(a6)             ; bind
        tst.l   d0
        bne     tcp_fail_close

        move.l  listenfd,d0         ; listen(fd, 1)
        moveq   #1,d1
        jsr     -42(a6)
        tst.l   d0
        bne     tcp_fail_close

        move.b  #1,transport
        bra     accept_client

tcp_fail_close:
        move.l  sockbase,a6
        move.l  listenfd,d0
        jsr     -120(a6)            ; CloseSocket
tcp_fail_lib:
        move.l  4.w,a6
        move.l  sockbase,a1
        jsr     -414(a6)            ; CloseLibrary
        clr.l   sockbase

try_serial:
        clr.b   transport
        move.l  a2,a6
        lea     sername,a1
        move.l  a1,d1
        move.l  #MODE_OLDFILE,d2
        jsr     -30(a6)
        move.l  d0,d6
        beq     close_graphics
        bra     mainloop

accept_client:
        move.l  stacksave,sp        ; se llega aqui desde cualquier
        move.l  sockbase,a6          ; profundidad tras perder un cliente
        move.l  #16,addrlen
        move.l  listenfd,d0
        lea     acceptaddr,a0
        lea     addrlen,a1
        jsr     -48(a6)             ; accept (bloquea hasta un cliente)
        tst.l   d0
        bmi     shutdown_tcp        ; error de accept: apagar limpio
        move.l  d0,clientfd

; --- bucle principal del protocolo (identico en ambos transportes) -----

mainloop:
hunt:
        lea     opbyte,a5           ; cazar el byte de sincronia $A5
        moveq   #1,d5
        bsr     read_n_bytes
        cmp.b   #$A5,opbyte
        bne     hunt

        lea     opbyte,a5           ; opcode
        moveq   #1,d5
        bsr     read_n_bytes
        move.b  opbyte,d7           ; d7 = opcode (los callees solo
                                     ; destruyen d0/d1/a0/a1)

        cmp.b   #$52,d7
        beq     do_read
        cmp.b   #$57,d7
        beq     do_write
        cmp.b   #$42,d7
        beq     do_blockread
        cmp.b   #$50,d7
        beq     do_blockwrite
        cmp.b   #$43,d7
        beq     do_call
        cmp.b   #$53,d7
        beq     do_getscreen
        cmp.b   #$58,d7
        beq     do_exec
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
        move.l  rwbuf+2,a0          ; cargar a0 DESPUES del ultimo read:
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

do_blockread:
        lea     rwbuf,a5            ; [addr.l][len.w] + chk
        moveq   #7,d5
        bsr     read_n_bytes
        moveq   #0,d4               ; chk = opcode ^ header(6)
        move.b  d7,d4
        lea     rwbuf,a5
        moveq   #6,d5
        bsr     xor_buf
        cmp.b   rwbuf+6,d4
        bne     send_nak
        moveq   #0,d7               ; d7 = len (el opcode ya no hace
        move.w  rwbuf+4,d7           ; falta; d2/d3 los pisan las
        beq     hunt                 ; rutinas de E/S)
        cmp.l   #BLK_MAX,d7
        bhi     hunt
        move.l  rwbuf,a0            ; snapshot coherente al buffer:
        lea     blkbuf,a1            ; datos y checksum de la misma foto
        move.l  d7,d5
brd_copy:
        move.b  (a0)+,(a1)+
        subq.l  #1,d5
        bne.s   brd_copy
        move.b  #$5A,respbuf        ; cabecera [5A][00]
        clr.b   respbuf+1
        lea     respbuf,a5
        moveq   #2,d5
        bsr     write_n_bytes
        lea     blkbuf,a5           ; datos
        move.l  d7,d5
        bsr     write_n_bytes
        moveq   #0,d4               ; chk = XOR(status=0 ^ datos)
        lea     blkbuf,a5
        move.l  d7,d5
        bsr     xor_buf
        move.b  d4,respbuf          ; un byte final
        lea     respbuf,a5
        moveq   #1,d5
        bsr     write_n_bytes
        bra     mainloop

do_blockwrite:
        lea     rwbuf,a5            ; [addr.l][len.w]
        moveq   #6,d5
        bsr     read_n_bytes
        moveq   #0,d7
        move.w  rwbuf+4,d7          ; validar len ANTES de usarlo como
        beq     hunt                 ; contador de lectura
        cmp.l   #BLK_MAX,d7
        bhi     hunt
        lea     blkbuf,a5           ; datos + chk AL BUFFER, nunca al
        move.l  d7,d5                ; destino: el NAK garantiza que un
        addq.l  #1,d5                ; frame corrupto no ejecuto nada
        bsr     read_n_bytes
        moveq   #0,d4               ; chk = opcode ^ header(6) ^ datos
        move.b  #$50,d4             ; (d7 ya es len, no el opcode)
        lea     rwbuf,a5
        moveq   #6,d5
        bsr     xor_buf
        lea     blkbuf,a5
        move.l  d7,d5
        bsr     xor_buf
        lea     blkbuf,a5           ; chk esperado justo tras los datos
        adda.l  d7,a5
        cmp.b   (a5),d4
        bne     send_nak
        move.l  rwbuf,a0            ; verificado: buffer -> destino
        lea     blkbuf,a1
        move.l  d7,d5
bwr_copy:
        move.b  (a1)+,(a0)+
        subq.l  #1,d5
        bne.s   bwr_copy
        moveq   #0,d5               ; ack vacio
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

do_exec:
        lea     rwbuf,a5            ; solo el byte de checksum
        moveq   #1,d5
        bsr     read_n_bytes
        cmp.b   rwbuf,d7            ; chk = XOR(opcode) = opcode
        bne     send_nak
        cmp.b   #1,exec_state       ; ya hay un programa corriendo?
        beq     ex_fail
        move.l  a2,a6               ; LoadSeg("GT4A:incoming/program")
        move.l  #progname,d1
        jsr     -150(a6)
        tst.l   d0
        beq     ex_fail
        move.l  d0,exec_seglist
        lsl.l   #2,d0               ; entrada = (BPTR a seglist)<<2 + 4
        addq.l  #4,d0                ; (salta el puntero al hunk siguiente)
        move.l  d0,exec_entry
        clr.l   exec_rc
        move.b  #1,exec_state       ; corriendo: ANTES de CreateProc (el
                                     ; hijo puede terminar y escribir 2
                                     ; antes de que volvamos aqui)
        move.l  a2,a6               ; CreateProc(nombre, pri=0, stub, pila)
        move.l  #procname,d1
        moveq   #0,d2
        lea     stubseg_next,a0     ; BPTR al fake seglist del stub (el
        move.l  a0,d3                ; patron oficial del autodoc: dc.l 16
        lsr.l   #2,d3                ; + dc.l 0 + codigo; nunca UnLoadSeg)
        move.l  #EXEC_STACK,d4
        jsr     -138(a6)
        tst.l   d0
        beq.s   ex_createfail
        move.l  #exec_mb,respdata   ; payload = direccion del mailbox,
        moveq   #4,d5                ; que el host sondea con R
        bra     send_ok
ex_createfail:
        move.l  a2,a6
        move.l  exec_seglist,d1
        jsr     -156(a6)            ; UnLoadSeg
        move.b  #3,exec_state
ex_fail:
        clr.l   respdata            ; payload = 0: no se lanzo nada
        moveq   #4,d5
        bra     send_ok

; --- stub del proceso hijo (lanzado por CreateProc desde do_exec) ------
;
; Corre como proceso independiente, compartiendo el espacio de
; direcciones del monitor (referencias absolutas via reloc normal).
; Un proceso de CreateProc no tiene contexto CLI: Output() devolveria 0
; y el Write del programa iria a una direccion basura. El stub abre el
; fichero de captura y lo instala como SU PROPIO pr_COS antes de saltar
; al programa, asi los ejemplos del libro usan Output()/Write() sin
; cambios. Cuenta con la convencion ya documentada: el programa preserva
; d2-d7/a2-a6 (aqui: a5=DOSBase, d5=fichero de captura).

        CNOP    0,4
stubseg_len:
        dc.l    16                  ; longitud fingida del segmento
stubseg_next:
        dc.l    0                   ; sin segmento siguiente
stub_entry:                         ; CreateProc entra aqui: (BPTR<<2)+4
        move.l  4.w,a6              ; el hijo abre SU dos.library
        lea     dosname,a1
        moveq   #0,d0
        jsr     -552(a6)
        tst.l   d0
        beq     stub_nodos
        move.l  d0,a5

        move.l  a5,a6               ; Open(fich. captura, MODE_NEWFILE)
        move.l  #outname,d1
        move.l  #MODE_NEWFILE,d2
        jsr     -30(a6)
        move.l  d0,d5
        beq     stub_noout

        move.l  4.w,a6              ; FindTask(0) = nuestro proceso
        suba.l  a1,a1
        jsr     -294(a6)
        move.l  d0,a0
        move.l  d5,PR_COS(a0)       ; pr_COS = fichero: Output() del
                                     ; programa apunta a la captura
        move.l  exec_entry,a1
        lea     stub_nl,a0          ; convencion CLI: a0 = linea de
        moveq   #1,d0                ; comandos, d0 = longitud ("\n")
        jsr     (a1)
        move.l  d0,exec_rc          ; codigo de retorno del programa

        move.l  4.w,a6              ; pr_COS = 0 antes de cerrar el
        suba.l  a1,a1                ; fichero (nada debe usarlo ya)
        jsr     -294(a6)
        move.l  d0,a0
        clr.l   PR_COS(a0)
        move.l  a5,a6               ; Close: vuelca la captura a disco
        move.l  d5,d1
        jsr     -36(a6)

        move.l  a5,a6               ; el programa ya no ejecuta: liberar
        move.l  exec_seglist,d1      ; su seglist (CreateProc no lo hace)
        jsr     -156(a6)
        clr.l   exec_seglist

        move.l  4.w,a6
        move.l  a5,a1
        jsr     -414(a6)            ; CloseLibrary(dos)
        move.b  #2,exec_state       ; terminado: SIEMPRE lo ultimo (rc y
        moveq   #0,d0                ; fichero completos al leer estado=2)
        rts

stub_noout:
        move.l  a5,a6               ; sin captura no se ejecuta nada:
        move.l  exec_seglist,d1      ; Write(Output()=0,...) del programa
        jsr     -156(a6)             ; seria un crash seguro
        clr.l   exec_seglist
        move.l  4.w,a6
        move.l  a5,a1
        jsr     -414(a6)
stub_nodos:
        move.b  #3,exec_state       ; error de lanzamiento
        moveq   #0,d0
        rts

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
        bra     shutdown_all

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

; --- E/S con despacho por transporte ----------------------------------

read_n_bytes:                       ; a5 = buffer, d5 = n
        tst.b   transport
        bne.s   rnb_tcp
        move.l  a2,a6               ; SER: via dos.library Read
rnb_serloop:
        move.l  d6,d1
        move.l  a5,d2
        move.l  d5,d3               ; pedir TODO lo que falta en un solo
        jsr     -42(a6)              ; Read (un Read por byte convertia
        tst.l   d0                   ; una trama P de 4 KB en 4097
        ble     serial_lost          ; round-trips a serial.device y el
        adda.l  d0,a5                ; monitor tardaba decenas de
        sub.l   d0,d5                ; segundos en contestar); avanzar
        bne.s   rnb_serloop          ; por lo realmente devuelto
        rts
rnb_tcp:
        move.l  sockbase,a6         ; TCP via bsdsocket recv
rnb_tcploop:
        move.l  clientfd,d0
        move.l  a5,a0
        move.l  d5,d1
        moveq   #0,d2
        jsr     -78(a6)             ; recv(fd, buf, len, 0)
        tst.l   d0
        ble     client_lost         ; 0 = cierre ordenado, <0 = error
        adda.l  d0,a5               ; recv puede devolver menos de lo
        sub.l   d0,d5                ; pedido: avanzar y repetir
        bne.s   rnb_tcploop
        rts

write_n_bytes:                      ; a5 = buffer, d5 = n
        tst.b   transport
        bne.s   wnb_tcp
        move.l  a2,a6               ; SER: via dos.library Write
        move.l  d6,d1
        move.l  a5,d2
        move.l  d5,d3
        jsr     -48(a6)
        rts
wnb_tcp:
        move.l  sockbase,a6
wnb_tcploop:
        move.l  clientfd,d0
        move.l  a5,a0
        move.l  d5,d1
        moveq   #0,d2
        jsr     -66(a6)             ; send(fd, buf, len, 0)
        tst.l   d0
        ble     client_lost
        adda.l  d0,a5
        sub.l   d0,d5
        bne.s   wnb_tcploop
        rts

xor_buf:                            ; a5 = buffer, d5 = n; acumula en d4
xb_loop:
        move.b  (a5)+,d3
        eor.b   d3,d4
        subq.l  #1,d5
        bne.s   xb_loop
        rts

; --- perdida de enlace y cierre ---------------------------------------

client_lost:                        ; TCP: el cliente se fue - cerrar su
        move.l  sockbase,a6          ; socket y aceptar al siguiente
        move.l  clientfd,d0          ; (accept_client restaura el SP)
        jsr     -120(a6)
        bra     accept_client

serial_lost:                        ; SER: error de lectura - salida
        move.l  stacksave,sp         ; ordenada (SP restaurado: podemos
        bra     shutdown_all         ; llegar desde cualquier profundidad)

shutdown_tcp:
        move.l  stacksave,sp
        bra     shutdown_all

shutdown_all:
        move.l  stacksave,sp
        tst.b   transport
        beq.s   sd_serial
        move.l  sockbase,a6         ; TCP: cerrar cliente + listener +
        move.l  clientfd,d0          ; liberar bsdsocket.library
        jsr     -120(a6)
        move.l  sockbase,a6
        move.l  listenfd,d0
        jsr     -120(a6)
        move.l  4.w,a6
        move.l  sockbase,a1
        jsr     -414(a6)
        bra.s   close_graphics
sd_serial:
        move.l  a2,a6               ; SER: cerrar el fichero
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
        move.l  stacksave,sp
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
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
bsdname:
        dc.b    "bsdsocket.library",0
        EVEN
sername:
        dc.b    "SER:",0
        EVEN
progname:
        dc.b    "GT4A:incoming/program",0
        EVEN
outname:
        dc.b    "GT4A:outgoing/output",0
        EVEN
procname:
        dc.b    "gt4amiga-exec",0
        EVEN
stub_nl:
        dc.b    10
        EVEN

        SECTION bss,BSS

stacksave:
        ds.l    1
transport:
        ds.b    2                   ; 0 = SER:, 1 = TCP
sockbase:
        ds.l    1
listenfd:
        ds.l    1
clientfd:
        ds.l    1
optval:
        ds.l    1
addrlen:
        ds.l    1
sockaddr:
        ds.b    16                  ; sockaddr_in del bind
acceptaddr:
        ds.b    16                  ; sockaddr_in del peer aceptado
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
exec_mb:                            ; mailbox de ejecucion (opcode X);
exec_state:                          ; el host lo sondea via R
        ds.b    1                   ; 0 nunca, 1 corriendo, 2 fin, 3 error
        ds.b    3                   ; pad: exec_rc alineado a longword
exec_rc:
        ds.l    1                   ; d0 del programa (valido con estado 2)
exec_seglist:
        ds.l    1                   ; BPTR del seglist cargado
exec_entry:
        ds.l    1                   ; APTR de entrada para el stub
blkbuf:
        ds.b    BLK_MAX+2           ; transferencias B/P: datos + chk,
                                    ; redondeado a par
