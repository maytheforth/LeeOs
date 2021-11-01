%include "boot.inc"                ; ndisasm loader.bin
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP  equ LOADER_BASE_ADDR
; 构建 gdt 以及内部描述符
GDT_BASE:  dd  0x00000000
            dd  0x00000000
CODE_DESC:  dd  0x0000FFFF
            dd  DESC_CODE_HIGH4
DATA_DESC:  dd  0x0000FFFF
            dd  DESC_DATA_HIGH4
VIDEO_DESC:  dd 0x80000007
             dd DESC_VIDEO_HIGH4    
GDT_SIZE   equ  $ - GDT_BASE
GDT_LIMIT  equ  GDT_SIZE - 1
times 60 dq 0                      ; 预留60个描述符的空位
total_mem_bytes dd 0               ; total_mem_bytes的地址是0xb03
SELECTOR_CODE    equ   (0x0001 << 3) + TI_GDT + RPL0
SELECTOR_DATA    equ    (0x0002 << 3) + TI_GDT + RPL0
SELECTOR_VIDEO   equ    (0X0003 << 3) + TI_GDT + RPL0

gdt_ptr   dw GDT_LIMIT
          dd  GDT_BASE

ards_buf times 244 db 0 
ards_nr dw 0 

loader_start:                           ; 0c00
;  int 15h   , E820 获取内存布局
xor ebx,ebx
mov edx, 0x534d4150
mov di, ards_buf
.e820_mem_get_loop:
    mov eax, 0x0000e820      ;使用 int 0x15后， eax的值变为 0x534d4150
    mov ecx, 20
    int 0x15
    jc .e820_failed_so_try_e801

    add di,cx             ; 是di增加20字节指向新的ARDS结构位置
    inc word [ards_nr]    ; 记录ards的数量
    cmp ebx,0             ; 若ebx为0且cf不为1，说明 ards全部返回
    jnz .e820_mem_get_loop

    mov cx, [ards_nr]
    mov ebx, ards_buf
    xor edx,edx           ; edx 存储最大的内存容量

.find_max_mem_area:
    ; 无需判断type是否为1，最大的内存块一定是可以被使用的
    mov eax, [ebx]
    add eax, [ebx + 8]
    add ebx,20
    cmp edx, eax
    jge .next_ards
    mov edx,eax

.next_ards:
    loop .find_max_mem_area         ; loop是判断 while(cx != 0) { do_something;  cx--; }
    jmp .mem_get_ok

;----- int 15h ax = e801h  获取内存大小, 最大支持4g ----
.e820_failed_so_try_e801:
    mov ax,0xe801
    int 0x15
    jc .e801_failed_so_try88

    mov cx, 0x400                  ; ax是以KB为单位的内存数量，将其转换为字节为单位 
    mul cx
    shl edx,16                     ; 逻辑左移，乘法积高16位dx寄存器，低16位在ax寄存器
    and eax, 0x0000FFFF
    or edx,eax
    add edx, 0x100000              ; ax只是15MB,需要加入1MB
    mov esi,edx 

    xor eax,eax
    mov ax,bx
    mov ecx, 0x10000                ; 64kb 
    mul ecx                  

    add esi, eax                    ; 由于此方法只能检测4G以内的内存，所以32位eax足够了          
    mov edx, esi   
    jmp .mem_get_ok

; --- int 15h ah = 0x88  获取内存大小，只能获取 64MB以内
.e801_failed_so_try88:
    mov ah, 0x88
    int 0x15
   ; jc .error_hlt                                    
    and eax, 0x0000FFFF
    
    mov cx, 0x400
    mul cx
    shl edx, 16
    or edx,eax
    add edx,0x100000

.mem_get_ok:
    mov [total_mem_bytes], edx
    jmp $


; ----- 进入保护模式
; ---- 打开 A20 , 将端口0x92的第一位置置为1, 从第0位置开始计数 ----
in al,0x92
or al, 0000_0010B
out 0x92,al

;-------- 加载gdt  -------
lgdt [gdt_ptr]

;------ cr0 第0位置1 ------
mov eax, cr0
or eax, 0x00000001
mov cr0,eax

jmp dword SELECTOR_CODE:p_mode_start          ;刷新流水线

[bits 32]
p_mode_start:
mov ax, SELECTOR_DATA
mov ds, ax
mov es, ax
mov ss, ax
mov esp, LOADER_STACK_TOP
mov ax, SELECTOR_VIDEO
mov gs, ax

mov byte [gs:160] , 'P'
