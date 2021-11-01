;--------------- loader和kernel ---------
LOADER_BASE_ADDR equ 0x900
LOADER_START_SECTOR equ 0x2
LOADER_START  equ 0xc00

; ---- gdt 描述符属性  ---------------
DESC_G_4K   equ       1_00000_00000_00000_00000_000b       ; _分隔符无实意，段界限的单位值
DESC_D_32   equ        1_00000_00000_00000_00000_00b      
DESC_L      equ        0_00000_00000_00000_00000_0b        ; 64位代码段, 还是32位代码段
DESC_AVL    equ        0_00000_00000_00000_00000b     
DESC_LIMIT_CODE2  equ    1111_0_00000_00000_00000b         ; 段界限的第二部分
DESC_LIMIT_DATA2  equ    DESC_LIMIT_CODE2
DESC_LIMIT_VIDEO2 equ    0000_00000_00000_00000b     
DESC_P      equ         1_00000_00000_00000b    
DESC_DPL_0   equ        00_000_00000_00000b
DESC_DPL_1   equ        01_000_00000_00000b
DESC_DPL_2   equ        10_000_00000_00000b 
DESC_DPL_3   equ        11_000_00000_00000b
DESC_S_CODE    equ        1_00_00000_00000b 
DESC_S_DATA    equ        DESC_S_CODE 
DESC_S_SYS   equ        0_00_00000_00000b
DESC_TYPE_CODE equ      1000_000_00000b                     ; 可执行,非一致性, 不可读
DESC_TYPE_DATA equ      0010_000_00000b      
DESC_CODE_HIGH4  equ    (0x00 << 24) + DESC_G_4K + DESC_D_32 + DESC_L + DESC_AVL + DESC_LIMIT_CODE2 + DESC_P + DESC_DPL_0 + DESC_S_CODE + DESC_TYPE_CODE + 0x00
DESC_DATA_HIGH4  equ    (0x00 << 24) + DESC_G_4K + DESC_D_32 + DESC_L + DESC_AVL + DESC_LIMIT_DATA2 + DESC_P + DESC_DPL_0 + DESC_S_DATA + DESC_TYPE_DATA + 0x00
DESC_VIDEO_HIGH4  equ    (0x00 << 24) + DESC_G_4K + DESC_D_32 + DESC_L + DESC_AVL + DESC_LIMIT_VIDEO2 + DESC_P + DESC_DPL_0 + DESC_S_DATA + DESC_TYPE_DATA + 0x0b




; --- 选择子属性 ----
RPL0    equ   00b
RPL1    equ   01b
RPL2    equ   10b
RPL3    equ   11b
TI_GDT  equ   000b
TI_LDT  equ   100b 