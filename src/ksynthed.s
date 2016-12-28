******************************
* KsynthEd Editor for Ksynth *
* (c)2016 Dagen Brock        *
******************************

* TO DO:
*  X- play current note
*  - return to Edit note  \
*  - insert note           > note entry  - String Inputter - dialog / window?
*  - delete note          /
*  - virtual keyboard ?
*  - up/down note nudging ?  what about duration?
*  - load
*  - save
*  - new
*  - help
*  - MESSAGES
*    - on EOF note, "HIT RETURN TO ADD A NOTE HERE"
*    - on

* Note entry - virtual keyboard / tempo lengths



                       org      $2000

LAYOUT_CURRENT_NOTE_X  =        18                       ; col position of current note "##"
LAYOUT_NOTENUM_Y       =        07                       ; row position of current note "##"
LAYOUT_NOTESTR_Y       =        10                       ; the line on which note triplets are drawNote
LAYOUT_NOTEVAL_Y       =        11
LAYOUT_NOTEDUR_Y       =        13




* INITIALIZE PLAYER TO OUR SONG WORKING SPACE
                       lda      #SongSpace
                       ldy      #>SongSpace
                       jsr      ks_setsong
                       jsr      SetLatch





* PRESET SONG UNTIL PLAYER DISPLAY IS EVEN WORKING
                       jsr      SetSongKarateka

* MAIN RUN LOOP - REDRAWS SCREEN
MAIN
                       jsr      DrawMenuBackground
                       jsr      DrawNoteBoard
MAIN_DRAW_NOTES
                       jsr      DrawNotes
MAIN_NO_DRAW
:MAIN_KEY_LOOP         lda      $c000
                       bmi      :key_hit
                       jsr      FancyWait
                       jmp      :MAIN_KEY_LOOP
:key_hit               sta      $c010
                       sta      MAIN_KEY_HIT
                       ldx      #0
:scan_key_table_loop   lda      MAIN_KEY_TABLE,x
                       beq      :key_not_found
                       cmp      MAIN_KEY_HIT
                       beq      :key_found
                       inx
                       bne      :scan_key_table_loop     ; BRA
:key_found
                       txa                               ; index
                       asl                               ; 6502 jmp table routine
                       tax                               ; ...
                       lda      MAIN_KEY_JUMP_TABLE+1,X  ; ...
                       pha                               ; push it on stack
                       lda      MAIN_KEY_JUMP_TABLE,X    ; ...
                       pha                               ; push second byte of address(-1) on stack
                       rts                               ; and return (jmp)
:key_not_found         GOXY     #19;#1
                       lda      MAIN_KEY_HIT
                       jsr      $FDDA
                       jmp      :MAIN_KEY_LOOP

MAIN_KEY_HIT           db       0                        ; store last key hit in buffer
MAIN_KEY_TABLE         asc      90," ",#KEY_LTARROW,#KEY_RTARROW  ; 90 = CTRL-P
                       asc      "?","h","H"
                       asc      "b",00
MAIN_KEY_JUMP_TABLE    da       MAINKEY_PLAYSONG-1,MAINKEY_PLAYNOTE-1,MAINKEY_LEFT-1,MAINKEY_RIGHT-1
                       da       MAINKEY_HELP-1,MAINKEY_HELP-1,MAINKEY_HELP-1
                       da       SetSongBFlatScale-1


***************************************
** KEY HANDLER ROUTINES START

MAINKEY_PLAYSONG       jsr      ks_player_latched        ; included from ksynth_inc.s
                       jmp      MAIN_NO_DRAW


MAINKEY_LEFT           lda      _ks_current_note_idx
                       beq      :no_dec
                       dec
                       sta      _ks_current_note_idx
:no_dec                jmp      MAIN_DRAW_NOTES


MAINKEY_RIGHT          lda      _ks_current_note_idx     ;
                       asl
                       tax
                       jsr      ks_get_song_value        ; look at duration bytes
                       cmp      #0
                       beq      :no_inc                  ;  - if zero, last note of song
                       inc      _ks_current_note_idx
:no_inc                jmp      MAIN_DRAW_NOTES


MAINKEY_PLAYNOTE       lda      _ks_current_note_idx
                       ASL
                       TAX
                       jsr      ks_get_song_value
                       sta      SongOneNote              ; copy note duration
                       INX
                       jsr      ks_get_song_value
                       sta      SongOneNote+1            ; copy note value

                       jsr      ks_getsong
                       pha                               ; save A (address part)
                       tya
                       pha                               ; save Y (address part)
                       lda      #SongOneNote
                       ldy      #>SongOneNote
                       jsr      ks_setsong
                       jsr      ks_player
                       pla
                       tay                               ;restore Y (address part)
                       pla                               ;restore A (address part)
                       jsr      ks_setsong
                       jmp      MAIN_NO_DRAW
                       rts


MAINKEY_HELP           jsr      HOME
                       lda      #HelpScreen1Strs
                       ldy      #>HelpScreen1Strs
                       ldx      #00                      ; horiz pos
                       jsr      PrintStringsX
                       jsr      WaitKey
                       jmp      MAIN                     ; need redraw!




** END OF MAIN KEY HANDLERS
**********************************


SetLatch               lda      #LatchTest
                       ldy      #>LatchTest
                       jsr      ks_set_latch
                       rts

LatchDummy             rts

* NOTE: Be careful to preserve or restore A in your callback.  It is song index.
* NOTE: Be careful clear on return.  carry set = stop playback.
LatchTest
                       pha                               ; preserve A
                       lsr                               ; convert to ptr
                       sta      _ks_current_note_idx     ;save
                       jsr      DrawNotes
                       lda      $c000
                       bpl      :no_key
                       sta      $c010                    ; clear key
                       sec                               ; set return value (stop playback)
                       pla                               ;restore A
                       rts
:no_key                clc                               ; set return value (normal)
                       pla                               ;restore A
                       rts
_ks_current_note_idx   db       0                        ; actual index to note data, i.e. - Note #i out of #127 notes in song
                                                         ;



** THIS DRAWS THE NOTES WHEN EDITING OR PLAYING BACK **
**
** It is not very efficient code and can probably be refactored for
** greatly improved code re-use.  Have at it, suckers!  :P
*
* Player Vision Callback pseudocode
*
* centeroffset = 3 ; our "active" note
* For x = 0 to 10
*  noteToDraw = _drawing_note - _center_offset
*   if underflow draw blank
*   if eof draw eof?
*   if past eof draw blank
*  drawNote (x, noteToDraw)

_drawing_note          db       0                        ; the note box on screen we are actively drawing
_drawing_note_idx      db       0                        ;  - index of the note in song: N/255
_drawing_note_dur      db       0                        ;  - its duration
_drawing_note_val      db       0                        ;  - its value/frequency raw hex
_drawing_note_str      da       ks_asc_UNKNOWN           ;  - pointer to string representing note value
_drawing_note_xpos     db       0                        ;  - leftmost x position to draw its data
_drawing_note_type     db       0                        ;  - 0=non-note (negative/>eof), 1=note, 2=eof
_drawing_eof_hit       db       0                        ;  - !0 = we are at EOF, stop drawing notes
_center_offset         =        4                        ; it's the 5 box on the screen
_total_notes           =        9                        ; total board notes


DrawNotes
                       lda      #0
                       sta      _drawing_eof_hit
                       sta      _drawing_note

:draw_note_loop
                       asl
                       asl                               ; *4
                       clc
                       adc      #2                       ; +2 :  should have correct xpos now
                       sta      _drawing_note_xpos

                                                         ; NOW FIND OUT IF A REAL NOTE OR EMPTY BOX
                       lda      _ks_current_note_idx     ; actual song in note - starts at 0

                                                         ;  0      |1      |2      |3      |4
                       clc
                       adc      _drawing_note            ;  0  1  2|0  1  2|0  1  2|0  1  2|0  1  2
                                                         ;  0  1  2|1  2  3|2  3  4|3  4  5|4  5
                       sec                               ; ?
                       sbc      #_center_offset          ; -4 -4 -4|-4-4 -4|-4-4 -4|-4-4 -4|-4-4 -4
                                                         ; -4 -3 -2|-3-2 -1|-2-1  0|-1 0  1|0  1  2
                       bcs      :draw_me                 ; carry gets cleared when underflow, right?

:negative_note                                           ; no need to store A since we aren't working on a real note
                       jsr      DrawBlankNote            ; but draw a blank spot
                       bra      :next_note
:draw_me                                                 ; A should have note to draw
                                                         ;pha
                       jsr      DrawOneNote

:next_note
                       inc      _drawing_note
                       lda      _drawing_note
                       cmp      #_total_notes
                       bne      :draw_note_loop
                       rts


* Enter with A as index to song note to draw
DrawOneNote
                       sta      _drawing_note_idx
                       asl                               ;*2
                       tax
                       jsr      ks_get_song_value        ; get duration
                       beq      :eof_hit
                       sta      _drawing_note_dur
                       inx                               ; +1 for note (0 is get duration above)
                       jsr      ks_get_song_value
                       sta      _drawing_note_val
                       ldx      #0
:search_loop           lda      ks_valid_note_tbl,x
                       cmp      _drawing_note_val
                       beq      :found_note
:not_found
                       inx
                       cpx      #ks_valid_notes
                       bne      :search_loop
                       ldy      #>ks_asc_UNKNOWN
                       sty      _drawing_note_str+1
                       lda      #ks_asc_UNKNOWN
                       sta      _drawing_note_str

                       bra      :now_draw
:eof_hit               lda      _drawing_eof_hit
                       bne      :been_done               ; we already hit eof before, so we just need to draw a blank
                       inc      _drawing_eof_hit
                       ldy      #>ks_asc_END
                       sty      _drawing_note_str+1
                       lda      #ks_asc_END
                       sta      _drawing_note_str
                       stz      _drawing_note_dur
                       stz      _drawing_note_val
                       bra      :now_draw
:been_done             jmp      DrawBlankNote            ; THIS WILL POP OUT (RTS) directly from DrawBlankNote

:found_note
                       txa
                       asl                               ; *2 for str ptr into list
                       tax
                       lda      ks_note_str3_tbl+1,x
                       sta      _drawing_note_str+1
                       lda      ks_note_str3_tbl,x
                       sta      _drawing_note_str

:now_draw
                       ldx      _drawing_note_xpos       ; draw note num
                       ldy      #LAYOUT_NOTENUM_Y
                       jsr      GoXY
                       lda      _drawing_note_idx
                       jsr      $FDDA


                       ldx      _drawing_note_xpos       ; draw note str
                       ldy      #LAYOUT_NOTESTR_Y
                       jsr      GoXY
                       lda      _drawing_note_str
                       ldy      _drawing_note_str+1
                       jsr      PrintString


                       ldx      _drawing_note_xpos       ; draw note val
                       ldy      #LAYOUT_NOTEVAL_Y
                       jsr      GoXY
                       lda      _drawing_note_val
                       jsr      $FDDA


                       ldx      _drawing_note_xpos       ; draw note dur
                       ldy      #LAYOUT_NOTEDUR_Y
                       jsr      GoXY
                       lda      _drawing_note_dur
                       jsr      $FDDA

                       rts

DrawBlankNote
                       ldx      _drawing_note_xpos       ; clear note num
                       ldy      #LAYOUT_NOTENUM_Y
                       jsr      GoXY
                       lda      #ks_asc_BLANK
                       ldy      #>ks_asc_BLANK
                       jsr      PrintString


                       ldx      _drawing_note_xpos       ; clear note str
                       ldy      #LAYOUT_NOTESTR_Y
                       jsr      GoXY
                       lda      #ks_asc_BLANK
                       ldy      #>ks_asc_BLANK
                       jsr      PrintString


                       ldx      _drawing_note_xpos       ; clear note val
                       ldy      #LAYOUT_NOTEVAL_Y
                       jsr      GoXY
                       lda      #ks_asc_BLANK
                       ldy      #>ks_asc_BLANK
                       jsr      PrintString


                       ldx      _drawing_note_xpos       ; clear note dur
                       ldy      #LAYOUT_NOTEDUR_Y
                       jsr      GoXY
                       lda      #ks_asc_BLANK
                       ldy      #>ks_asc_BLANK
                       jsr      PrintString
                       rts

DrawNoteBoard
                       GOXY     #0;#8
                       lda      #NoteBoardStrs
                       ldy      #>NoteBoardStrs
                       ldx      #00                      ; horiz pos
                       jsr      PrintStringsX            ; someone should make a XY version ;)
                       rts

DrawMenuBackground     jsr      HOME
                       lda      #MainMenuStrs
                       ldy      #>MainMenuStrs
                       ldx      #00                      ; horiz pos
                       jsr      PrintStringsX

                       GOXY     #0;#18
                       lda      #CheatSheetStrs
                       ldy      #>CheatSheetStrs
                       ldx      #00                      ; horiz pos
                       jsr      PrintStringsX            ; someone should make a XY version ;)

                       rts

FancyWait              lda      _fw_status
                       bne      :check1
:got0                  PRINTXY  #14;#0;_fw_s0
                       PRINTXY  #25;#0;_fw_s0
                       jmp      :next
:check1                cmp      #1
                       bne      :check2
:got1                  PRINTXY  #14;#0;_fw_s1
                       PRINTXY  #25;#0;_fw_s1
                       jmp      :next
:check2                cmp      #2
                       bne      :check3
:got2                  PRINTXY  #14;#0;_fw_s2
                       PRINTXY  #25;#0;_fw_s2
                       jmp      :next
:check3                PRINTXY  #14;#0;_fw_s3
                       PRINTXY  #25;#0;_fw_s3

:next                  inc      _fw_status
                       lda      _fw_status
                       cmp      #$4
                       bne      :done
                       lda      #0
                       sta      _fw_status
:done                  rts

_fw_status             db       0
_fw_s0                 asc      "-",00
_fw_s1                 asc      "/",00
_fw_s2                 asc      "|",00
_fw_s3                 asc      "\",00




SetSongKarateka
                       ldx      #0
:copy_song             lda      SongKarateka,x
                       sta      SongSpace,x
                       inx
                       cpx      SongKaratekaEnd
                       bne      :copy_song
                       rts

SetSongBFlatScale
                       ldx      #0
:copy_song             lda      SongBFlatScale,x
                       sta      SongSpace,x
                       inx
                       cpx      SongBFlatScale
                       bne      :copy_song
                       JMP      MAIN

* This is used to play a single note
* It may seem overkill to play a note as a song, but this way we avoid making
* changes to the player and tone generator code, or using a priori knowledge of
* the engine internals.
* I.e. - This will work even if we completely change players as long as it respects our note format.
SongOneNote            asc      FF,FF,00,00
SongOneNoteEnd         =        *-SongOneNote
SongOneNoteStash       da       SongOneNote              ; for backup of real song we swap in/out


SongKarateka           asc      10,a8,20,FF,08,c7,05,FF,10,a8,15,FF,25,7e,20,FF,10,63,08,FF,80,63,00,00
SongKaratekaEnd        =        *-SongKarateka

SongBFlatScale         asc      20,A9,20,96,20,86,20,7E,20,71,20,64,20,59,20,54,20,59,20,64,20,71,20,7E,20,86,20,96,FF,A9,FF,FF,10,A9,10,86,10,71,10,54,10,71,10,86,FF,A9,00,00
SongBFlatScaleEnd      =        *-SongBFlatScale
SongSpace              ds       1024
                       dw       0000                     ; buffer



MainMenuStrs
                       asc      "                KSYNTHED  ",8D,8D,00
                       asc      " Song:                    Notes:   /127",00,00

CheatSheetStrs

                       asc      "   C  C# D  Eb E  F  F# G  G# A  Bb B ",8D,00
                       asc      "   -- -- -- -- -- -- -- -- -- -- -- --",8D,00
                       asc      "   25 23 21 1F 1E 1C 1A 19 17 16 15 13",8D,00
                       asc      "   4B 47 43 3F 3C 38 35 32 2F 2D 2A 27",8D,00
                       asc      "   96 8E 86 7E 77 71 6A 64 5E 59 54 4F",8D,00
                       asc      "            FC EF E1 D5 C9 BD B3 A9 9F",00
                       asc      00,00

NoteBoardStrs
                       asc      "  ___ ___ ___ ___ === ___ ___ ___ ___",8D,00
                       asc      " |   |   |   |   |   |   |   |   |   |`",8D,00
                       asc      " |   |   |   |   |   |   |   |   |   |`",8D,00
                       asc      " |   |   |   |   |   |   |   |   |   |`",8D,00
                       asc      " |   |   |   |   |   |   |   |   |   |`",8D,00
                       asc      " |   |   |   |   |   |   |   |   |   |`",8D,00
                       asc      " |___|___|___|___|___|___|___|___|___|`",8D,00
                       asc      "  ``` ``` ``` ``` \\\ ``` ``` ``` ```",8D,00,00


HelpScreen1Strs        asc      " _____________  KSYNTHED _____________",8D,00
                       asc      "|                                     |",8D,00
                       asc      "| SONG CONTROL KEYS                   |",8D,00
                       asc      "|                                     |",8D,00
                       asc      "|  CTRL-P  =  PLAY SONG               |",8D,00
                       asc      "|  CTRL-L  =  LOAD SONG               |",8D,00
                       asc      "|  CTRL-S  =  SAVE SONG               |",8D,00
                       asc      "|  CTRL-N  =  NEW SONG                |",8D,00
                       asc      "|                                     |",8D,00
                       asc      "| NOTE EDITOR KEYS                    |",8D,00
                       asc      "|  L/R ARROW  =  MOVE CURSOR          |",8D,00
                       asc      "|  SPACEBAR   =  PLAY NOTE            |",8D,00
                       asc      "|  RETURN     =  EDIT NOTE            |",8D,00
                       asc      "|  CTRL-I     =  INSERT NOTE          |",8D,00
                       asc      "|  CTRL-D     =  DELETE NOTE          |",8D,00
                       asc      "|                                     |",8D,00
                       asc      "|                                     |",8D,00
                       asc      "|  H or ?     = HELP SCREEN           |",8D,00
                       asc      "|_____________________________________|",8D,00,00




ks_valid_note_tbl
                       HEX      13,15,16,17,19,1A,1C,1E,1F,21,23,25
                       HEX      27,2A,2D,2F,32,35,38,3C,3F,43,47,4B
                       HEX      4F,54,59,5E,64,6A,71,77,7E,86,8E,96
                       HEX      9F,A9,B3,BD,C9,D5,E1,EF,FC,FF
ks_valid_notes         =        *-ks_valid_note_tbl

ks_note_str3_tbl
                       DA       ks_asc_13,ks_asc_15,ks_asc_16,ks_asc_17,ks_asc_19,ks_asc_1A
                       DA       ks_asc_1C,ks_asc_1E,ks_asc_1F,ks_asc_21,ks_asc_23,ks_asc_25
                       DA       ks_asc_27,ks_asc_2A,ks_asc_2D,ks_asc_2F,ks_asc_32,ks_asc_35
                       DA       ks_asc_38,ks_asc_3C,ks_asc_3F,ks_asc_43,ks_asc_47,ks_asc_4B
                       DA       ks_asc_4F,ks_asc_54,ks_asc_59,ks_asc_5E,ks_asc_64,ks_asc_6A
                       DA       ks_asc_71,ks_asc_77,ks_asc_7E,ks_asc_86,ks_asc_8E,ks_asc_96
                       DA       ks_asc_9F,ks_asc_A9,ks_asc_B3,ks_asc_BD,ks_asc_C9,ks_asc_D5
                       DA       ks_asc_E1,ks_asc_EF,ks_asc_FC,ks_asc_FF



ks_asc_13              asc      "B-4",00
ks_asc_15              asc      "Bb4",00
ks_asc_16              asc      "A-4",00
ks_asc_17              asc      "G#4",00
ks_asc_19              asc      "G-4",00
ks_asc_1A              asc      "F#4",00
ks_asc_1C              asc      "F-4",00
ks_asc_1E              asc      "E-4",00
ks_asc_1F              asc      "Eb4",00
ks_asc_21              asc      "D-4",00
ks_asc_23              asc      "C#4",00
ks_asc_25              asc      "C-4",00
ks_asc_27              asc      "B-3",00
ks_asc_2A              asc      "Bb3",00
ks_asc_2D              asc      "A-3",00
ks_asc_2F              asc      "G#3",00
ks_asc_32              asc      "G-3",00
ks_asc_35              asc      "F#3",00
ks_asc_38              asc      "F-3",00
ks_asc_3C              asc      "E-3",00
ks_asc_3F              asc      "Eb3",00
ks_asc_43              asc      "D-3",00
ks_asc_47              asc      "C#3",00
ks_asc_4B              asc      "C-3",00
ks_asc_4F              asc      "B-2",00
ks_asc_54              asc      "Bb2",00
ks_asc_59              asc      "A-2",00
ks_asc_5E              asc      "G#2",00
ks_asc_64              asc      "G-2",00
ks_asc_6A              asc      "F#2",00
ks_asc_71              asc      "F-2",00
ks_asc_77              asc      "E-2",00
ks_asc_7E              asc      "Eb2",00
ks_asc_86              asc      "D-2",00
ks_asc_8E              asc      "C#2",00
ks_asc_96              asc      "C-2",00
ks_asc_9F              asc      "B-1",00
ks_asc_A9              asc      "Bb1",00
ks_asc_B3              asc      "A-1",00
ks_asc_BD              asc      "G#1",00
ks_asc_C9              asc      "G-1",00
ks_asc_D5              asc      "F#1",00
ks_asc_E1              asc      "F-1",00
ks_asc_EF              asc      "E-1",00
ks_asc_FC              asc      "Eb1",00
ks_asc_FF              asc      "RST",00
ks_asc_END             asc      "END",00
ks_asc_UNKNOWN         asc      "-?-",00
ks_asc_NONOTE          asc      "XXX",00
ks_asc_NEGATIVE        asc      "***",00                 ; really just for debugging visibility
ks_asc_BLANK           asc      "   ",00



* Mostly for debugging, not intended for prod key handling
WaitKey                lda      $c000
                       bpl      WaitKey
                       sta      $c010
                       rts



                       put      strings
                       put      ksynth_inc
                       use      applerom
                       dsk      KSYNTHED.SYSTEM
