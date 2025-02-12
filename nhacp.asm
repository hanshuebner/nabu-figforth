
;;;  todo: error handling
        
#include "nabu-comms.asm"

;;; perform one NHCAP request/response interaction.  Requires six
;;; arguments on the stack:
;;; 
;;; ( req req-len buf buf-len )
;;;
;;; req/req-len is the static part of the request message.  It must be
;;; one of the statically allocated request message buffers.
;;; buf/buf-len is the buffer to send and/or receive returns a pointer
;;; to the response message received in HL.
;;;
;;; buf is used both for sending and receiving data.  When sending, if
;;; buf-len is not zero, it specifies how many bytes, starting at buf
;;; to send after the request message header.  When receiving, all
;;; bytes that did not go into the static response message header are
;;; received into buf.  The purpose of this scheme is to allow the
;;; application to specify the payload buffer address instead of
;;; requiring an intermediate buffer for the received data.  That way,
;;; it is possible to receive large chunks of data in one fell swoop.

;;; The response message is received into one of the statically
;;; allocated message buffers.  Any excess bytes in the response frame
;;; are put into buf, starting at index 0.

;;; The nhacp_request entry point sets up the in-memory variables and
;;; enables the HCCA interrupts.  The rest of the protocol handling is
;;; done inside of the interrupt routines
nhacp_request:
        ;; pop all parameters into static variables
        pop     hl
        ld      (nhacp_buf_len), hl
        pop     hl
        ld      (nhacp_buf), hl
        pop     hl
        ld      (nhacp_req_len), hl
        pop     hl
        ld      (nhacp_req), hl
        ;; calculate total length of frame
        push    bc
        ld      hl, (nhacp_req_len)
        ld      b, h
        ld      c, l
        ld      hl, (nhacp_buf_len)
        add     hl, bc
        ld      b, h
        ld      c, l
        ;; store in front of req
        ld      hl, (nhacp_req)
        dec     hl
        ld      (hl), b
        dec     hl
        ld      (hl), c
        pop     bc
        ;; set up transmit pointer and count
        ld      (hcca_transmit_pointer), hl
        ld      hl, (nhacp_req_len)
        inc     hl
        inc     hl
        ld      (hcca_transmit_count), hl
        ;; set up receive pointer and count
        ld      hl, nhacp_frame_length
        ld      (hcca_receive_pointer), hl
        ld      hl, 3
        ld      (hcca_receive_count), hl
        ld      a, RECEIVE_STATE_PREAMBLE
        ld      (nhacp_receive_state), a
        ;; set "busy" flag, enable interrupts and wait for transaction to complete
        ld      a, 1
        ld      (nhacp_busy), a
        ld      a, INT_MASK_HCCATINT + INT_MASK_HCCARINT
        call    enable_hcca_interrupts
nhacp_request_wait:
        ld      a, (nhacp_busy)
        cp      0
        jr      nz, nhacp_request_wait
        ld      hl, (nhacp_received_response)
        dec     hl                                          ; dispatch table points to first data byte, adjust
        ld      (nhacp_response), hl
        JNEXT

nhacp_response:
        .ds     2

enable_hcca_interrupts:
        di
        push    bc
        ld      b, a
        ld      a, PSG_REG_IO_A
        out     (PSG_ADDRESS), a
        in      a, (PSG_DATA)
        or      b
        out     (PSG_DATA), a
        pop     bc
        ei
        ret

nhacp_start:
        ;; set up receive pointers
        ld      hl, nhacp_adapter_id
        ld      (nhacp_buf), hl
        ld      hl, nhacp_frame_length
        ld      (hcca_receive_pointer), hl
        ld      hl, 3
        ld      (hcca_receive_count), hl
        ;; set "busy" flag, enable interrupts and wait for NA to send response
        ld      a, 1
        ld      (nhacp_busy), a
        ld      a, INT_MASK_HCCARINT
        call    enable_hcca_interrupts
        ld      a, NHACP_START
        out     (HCCA_REGISTER), a
        jr      nhacp_request_wait

;;; HCCA transmitter.  To transmit, the hcca_transmit_pointer needs to
;;; point to the start of the message, hcca_transmit_count needs to
;;; contain the number of bytes to transmit and the HCCA transmit
;;; interrupt needs to be enabled.
hccat_irq:
        push    af
        push    hl
        ld      hl, (hcca_transmit_pointer)
        ld      a, (hl)
        out     (HCCA_REGISTER), a
        inc     hl
        ld      (hcca_transmit_pointer), hl
        ld      hl, (hcca_transmit_count)
        dec     hl
        ld      a, h
        or      l
        jr      z, check_buf
        ld      (hcca_transmit_count), hl
        jr      z, check_buf
        jr      count_transmit
check_buf:
        ld      hl, (nhacp_buf_len)
        ld      a, h
        or      l
        jr      z, end_of_transmit
        ;; we've got data to send, re-point transmitter to buffer and
        ;; continue sending
        ld      (hcca_transmit_count), hl
        ld      hl, 0
        ld      (nhacp_buf_len), hl
        ld      hl, (nhacp_buf)
        ld      (hcca_transmit_pointer), hl
        jr      count_transmit
end_of_transmit:
        ;; end of message, switch off the HCCA TX interrupt
        ld      a, PSG_REG_IO_A
        out     (PSG_ADDRESS), a
        in      a, (PSG_DATA)
        and     ~INT_MASK_HCCATINT
        push    af
        ld      a, PSG_REG_IO_A
        out     (PSG_ADDRESS), a
        pop     af
        out     (PSG_DATA), a
        ld      a, 0
count_transmit:
        ld      hl, hccat_count
        jp      increment_counter


;;; HCCA receive interrupt.  This routine handles the receipt of the
;;; two or three segments that constitute a NHACP frame.  The first
;;; segment contains the frame length and the type tag.  Once it has
;;; been read, a lookup is performed to find the receive buffer for
;;; the request type - One buffer is statically allocated for each
;;; request message type.  When the message header was received and
;;; any bytes remain in the frame, they are read into the buffer
;;; supplied by the user.
hccar_irq:
        push    af
        push    hl
        push    bc
        ld      hl, (hcca_receive_pointer)
        in      a, (HCCA_REGISTER)
        ld      (hl), a
        inc     hl
        ld      (hcca_receive_pointer), hl
        ld      hl, (hcca_receive_count)
        dec     hl
        ld      (hcca_receive_count), hl
        ld      a, h
        or      l
        jr      nz, receive_irq_done
        ;; end of segment, see what we need to do next
        ld      a, (nhacp_receive_state)
        cp      RECEIVE_STATE_HEADER
        jr      z, maybe_receive_payload
        cp      RECEIVE_STATE_PAYLOAD
        jr      z, end_of_receive
        inc     a
        ld      (nhacp_receive_state), a
        ;; we've received the frame preamble, determine response
        ;; buffer to use
        ld      a, (nhacp_frame_type)                       ; frame type received
        bit     7, a
        jr      z, receive_error
        and     07fh
        cp      response_type_count
        jr      nc, receive_error
        sla     a
        sla     a
        ld      c, a
        ld      b, 0
        ld      hl, response_message_dispatch_table
        add     hl, bc
        ld      a, (hl) ; length of message, adjusted by 1 as the type byte was already received
        cp      0
        jr      z, end_of_receive
        ld      (hcca_receive_count), a
        inc     hl
        ld      c, (hl)
        inc     hl
        ld      b, (hl)
        ld      (nhacp_received_response), bc               ; points to response buffer found
        ld      (hcca_receive_pointer), bc
        ;; substract what we've already received from nhacp_frame_length
        ld      bc, (hcca_receive_count)
        inc     bc
        ld      hl, (nhacp_frame_length)
        sbc     hl, bc
        ld      (nhacp_frame_length), hl                    ; frame length contains bytes remaining to be read
        jr      receive_irq_done
maybe_receive_payload:
        inc     a
        ld      (nhacp_receive_state), a
        ld      hl, (nhacp_frame_length)
        ld      a, l
        or      h
        jr      z, end_of_receive                           ; no more data to receive
        ld      (hcca_receive_count), hl
        ld      hl, (nhacp_buf)
        ld      (hcca_receive_pointer), hl
        ld      hl, nhacp_frame_length
        ld      (hl), 0
        jr      receive_irq_done
receive_error:
        ld      a, CONTROL_ROMSEL | CONTROL_LED_ALERT | CONTROL_LED_CHECK
        out     (CONTROL_REGISTER), a
end_of_receive:
        ;; end of message, switch off the HCCA RX interrupt
        ld      a, PSG_REG_IO_A
        out     (PSG_ADDRESS), a
        in      a, (PSG_DATA)
        and     ~INT_MASK_HCCARINT
        push    af
        ld      a, PSG_REG_IO_A
        out     (PSG_ADDRESS), a
        pop     af
        out     (PSG_DATA), a
        ld      a, 0
        ld      (nhacp_busy), a
receive_irq_done:
        ld      hl, hccar_count
        pop     bc
        pop     hl
        pop     af
        ei
        reti

hcca_receive_pointer:
        .dw     0
hcca_receive_count:
        .dw     0

hcca_transmit_pointer:
        .dw     0
hcca_transmit_count:
        .dw     0

nhacp_adapter_id:
        .ds     50

RECEIVE_STATE_PREAMBLE: .equ    0
RECEIVE_STATE_HEADER:   .equ    1
RECEIVE_STATE_PAYLOAD:  .equ    2

nhacp_receive_state:
        .byte   0

;;; buffer for frame preamble
nhacp_frame_length:
        .dw     0
nhacp_frame_type:       
        .db     0
nhacp_frame_preamble_end:

;;; buffer pointers
nhacp_buf:
        .dw     0
nhacp_buf_len:
        .dw     0
nhacp_req:
        .dw     0
nhacp_req_len:
        .dw     0
nhacp_received_response:
        .dw     0
nhacp_busy:
        .byte   0
