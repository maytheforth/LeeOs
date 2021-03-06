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
mov esp, LOADER_STACK_TOP           ; 设置栈顶为 0x900
mov ax, SELECTOR_VIDEO
mov gs, ax

mov byte [gs:160] , 'P'

mov eax, KERNEL_START_SECTOR
mov ebx, KERNEL_BIN_BASE_ADDR
mov ecx, 200
call rd_disk_m_32

; 创建页表
call setup_page

; 将描述符导出到 gdt_ptr中
sgdt [gdt_ptr]

mov ebx, [gdt_ptr + 2]        ; 将段基址保存到 ebx中
or dword [ebx + 0x18 + 4], 0xc0000000

add dword [gdt_ptr + 2], 0xc0000000

add esp, 0xc0000000           ; 栈指针也映射到内核地址

; 把页目录地址赋给cr3
mov eax, PAGE_DIR_TABLE_POS
mov cr3, eax 

; 打开cr0的pg位
mov eax, cr0
or eax, 0x80000000
mov cr0, eax

; 打开分页后，重新加载
lgdt [gdt_ptr]

jmp SELECTOR_CODE:enter_kernel

enter_kernel:
    call kernel_init
    mov esp, 0xc009f000                              ;设置栈底
    jmp KERNEL_ENTRY_POINT

;-------------- 将kernel.bin中的segment 拷贝到编译的地址 ------------------------
kernel_init:
    xor eax,eax
    xor ebx,ebx       ; 记录程序头表位置
    xor ecx,ecx       ; 记录 program header数量
    xor edx,edx       ; 记录 program header尺寸，及 e_phentsize

    mov dx, [KERNEL_BIN_BASE_ADDR + 42]     ; e_phentsize
    mov ebx, [KERNEL_BIN_BASE_ADDR + 28]    ; e_phoff, 表示第一个program header在文件中的偏移量
    add ebx, KERNEL_BIN_BASE_ADDR
    mov cx, [KERNEL_BIN_BASE_ADDR + 44]     

.each_segment:
    cmp byte [ebx + 0], PT_NULL
    je .PTNULL

    push dword [ebx + 16]
    mov eax, [ebx + 4]
    add eax, KERNEL_BIN_BASE_ADDR
    push eax
    push dword [ebx + 8]
    call mem_cpy
    add esp,12                     ; 清空压栈的三个参数

.PTNULL:
    add ebx, edx                     ; 指向下一个program header
    loop .each_segment
    ret

; --------------------- 逐字节拷贝 (dst, src,size) -------- 
mem_cpy:
    cld
    push ebp
    mov ebp, esp
    push ecx                   ; rep指令用到了ecx

    mov edi, [ebp + 8]         ; dst
    mov esi, [ebp + 12]        ; src
    mov ecx, [ebp + 16]        ; size
    rep movsb

    pop ecx
    pop ebp
    ret 



; ------------------------------------ 分页 begin -------------------------------------------
setup_page:
    ; 先把页目录占用的空间清0
    mov ecx, 4096
    mov esi, 0
.clear_page_dir:
    mov byte [PAGE_DIR_TABLE_POS + esi], 0
    inc esi
    loop .clear_page_dir

; 创建页目录项 PDE
.create_pde:
    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x1000
    mov ebx, eax                 ; eax是第一个页表的地址

    or eax, PG_US_U | PG_RW_W | PG_P
    mov [PAGE_DIR_TABLE_POS + 0x0], eax
    mov [PAGE_DIR_TABLE_POS + 0xc00], eax        ; 0xc00表示第768个页表占用的目录项

    sub eax, 0x1000
    mov [PAGE_DIR_TABLE_POS + 4092], eax          ; 最后一个页表项是页表自己
 
; 创建页表项(PTE)
   mov ecx, 256
   mov esi, 0
   mov edx, PG_US_U | PG_RW_W | PG_P
.create_pte:
    mov [ebx + esi * 4], edx                      ; edx是物理地址 
    add edx, 4096
    inc esi
    loop .create_pte

;  创建内核其他页表的PDE
    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x2000
    or eax, PG_US_U | PG_RW_W | PG_P
    mov ebx, PAGE_DIR_TABLE_POS
    mov ecx, 254
    mov esi, 769
.create_kernel_pde:
    mov [ebx + esi * 4], eax
    inc esi
    add eax, 0x1000
    loop .create_kernel_pde
    ret

;-------------------------------------分页 end ----------------------------------------------------
rd_disk_m_32:
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
    mov [ebx],ax
    add ebx,2
    loop .go_on_read 
    ret
