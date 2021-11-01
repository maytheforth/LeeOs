; 主引导程序
;----------------------------------------------------
%include "boot.inc"
SECTION MBR vstart=0x7c00
    mov ax,cs
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov fs,ax
    mov sp,0x7c00
    mov ax,0xb800   ; 显卡内存段基址
    mov gs,ax

    mov ax, 0x600
    mov bx, 0x700
    mov cx,0
    mov dx,0x184f

    int 0x10

;---------------------------------------------- 输出字符串 MBR

    mov byte [gs:0x00], '1'
    mov byte [gs:0x01],0xA4

    mov byte [gs:0x02],' '
    mov byte [gs:0x03],0xA4

    mov byte [gs:0x04],'M'
    mov byte [gs:0x05],0xA4

    mov byte [gs:0x06],'B'
    mov byte [gs:0x07],0xA4

    mov byte [gs:0x08],'R'
    mov byte [gs:0x09],0xA4

    mov eax, LOADER_START_SECTOR     ; 起始扇区lba地址
    mov bx, LOADER_BASE_ADDR         ; 加载的内存地址
    mov cx,4                         ; 读取的扇区数
    call rd_disk_m_16

    jmp LOADER_START

;--------------------------------------
; 功能: 读取硬盘n个扇区
rd_disk_m_16:
    mov esi, eax     ;备份eax
    mov di, cx       ;备份cx

; 设置要读取的扇区数
    mov dx, 0x1f2
    mov al,cl
    out dx,al
    mov eax,esi

; 将LBA地址存入0x1f3 - 0x1f6
   mov dx,0x1f3
   out dx,al

   mov cl,8
   shr eax,cl
   mov dx,0x1f4
   out dx,al

   shr eax,cl
   mov dx,0x1f5
   out dx,al

   shr eax,cl
   and al,0x0f   ; lba第 24 - 27位
   or al,0xe0   
   mov dx,0x1f6
   out dx,al

   ; 读入写命令
   mov dx,0x1f7
   mov al,0x20
   out dx,al

.not_ready:
    ; 检测硬盘状态
    nop
    in al,dx
    and al,0x88
    cmp al,0x08
    jnz .not_ready

    mov ax, di        ; di为要读取的扇区数
    mov dx,256
    mul dx
    mov cx,ax      ; data寄存器为两个字节,所以 cx = di * 512/2 = di * 256    

    mov dx, 0x1f0

.go_on_read:
    in ax,dx
    mov [bx],ax
    add bx,2
    loop .go_on_read 
    ret

   times 510-($-$$) db 0
   db 0x55,0xaa
